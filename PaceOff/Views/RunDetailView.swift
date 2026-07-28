// RunDetailView.swift
// Full breakdown of a single run including the GPS route map, per-km
// pace-decay chart, and running dynamics.

import SwiftUI
import MapKit
import CoreLocation
import Charts

struct RunDetailView: View {
    let run: RunRecord

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingRoute: Bool = true
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Per-kilometre splits derived from the route locations + HR samples.
    /// Populated after the route loads; empty for indoor / short runs.
    @State private var splits: [KilometerSplit] = []
    @State private var isLoadingSplits: Bool = true

    /// Map height as a fraction of the available screen height. Matches the
    /// proportion used on the Today screen so the experience feels consistent.
    private let mapHeightFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    mapSection
                        .frame(height: geo.size.height * mapHeightFraction)
                        .clipped()

                    VStack(alignment: .leading, spacing: 24) {
                        header
                        metricsGrid
                        splitsSection
                        if hasDynamics { dynamicsSection }
                    }
                    .padding(20)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(run.startDate.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: run.id) { await loadRouteAndSplits() }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if !routeCoordinates.isEmpty {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(
                        .blue.gradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                if let start = routeCoordinates.first {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let end = routeCoordinates.last, routeCoordinates.count > 1 {
                    Annotation("Finish", coordinate: end) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        } else {
            ZStack {
                Color(.systemGray6)
                VStack(spacing: 10) {
                    if isLoadingRoute {
                        ProgressView()
                        Text("Loading route…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No route recorded")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("This run was indoors, on a treadmill,\nor location wasn't shared.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func loadRouteAndSplits() async {
        isLoadingRoute = true
        isLoadingSplits = true

        // Fetch the full CLLocation stream (with timestamps) so we can
        // both draw the map polyline AND compute pace-decay splits from
        // it — one HealthKit round-trip instead of two.
        let locations = await HealthKitService.shared.fetchRunLocations(for: run)
        routeCoordinates = locations.map(\.coordinate)
        isLoadingRoute = false
        updateCamera(for: routeCoordinates)

        // Splits: convert (date, lat, lon) → cumulative-metres samples
        // and pull HR samples across the workout window.
        let stream = locations.map {
            (date: $0.timestamp,
             lat: $0.coordinate.latitude,
             lon: $0.coordinate.longitude)
        }
        let locationSamples = PaceDecayAnalyser.locationSamples(from: stream)
        let hrRaw = await HealthKitService.shared.fetchHeartRateSamples(
            from: run.startDate, to: run.endDate
        )
        let hrSamples = hrRaw.map {
            PaceDecayAnalyser.HeartRateSample(date: $0.date, bpm: $0.bpm)
        }
        splits = PaceDecayAnalyser().splits(
            locations: locationSamples,
            heartRates: hrSamples
        )
        isLoadingSplits = false
    }

    private func updateCamera(for coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLng = coords[0].longitude, maxLng = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.005)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Header & metrics

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(run.startDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f km", run.distanceKm))
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("\(run.formattedPace) · \(run.formattedDuration)")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("HEART RATE", value: run.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—", icon: "heart.fill")
            metric("ENERGY", value: run.activeEnergyKcal.map { "\(Int($0)) kcal" } ?? "—", icon: "flame.fill")
        }
    }

    // MARK: - Pace-decay chart

    /// Nothing to render when the run had no route (indoor, permission
    /// denied) or was shorter than 1 km. Otherwise: bar chart of per-km
    /// pace + a HR line overlay when we have HR data, and a headline
    /// naming any big shift ("Pace slowed 22 s/km after km 4").
    @ViewBuilder
    private var splitsSection: some View {
        if isLoadingSplits {
            splitsLoading
        } else if splits.count >= 2 {
            splitsCard
        } else {
            EmptyView()
        }
    }

    private var splitsLoading: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PACE PER KM")
            HStack {
                ProgressView()
                Text("Computing splits…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var splitsCard: some View {
        // Pace domain: pad by 15 s each side so the tallest bar isn't jammed
        // against the axis. Bigger sec/km (slower) sits UP on the axis by
        // default — the intuitive read is "taller = slower".
        let minPace = (splits.map(\.secondsPerKm).min() ?? 0) - 15
        let maxPace = (splits.map(\.secondsPerKm).max() ?? 0) + 15
        let hasHR = splits.contains { $0.averageHeartRate != nil }

        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PACE PER KM")
            if let headline = decayHeadline {
                Text(headline)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Chart {
                ForEach(splits) { split in
                    BarMark(
                        x: .value("Km", split.index),
                        y: .value("sec/km", split.secondsPerKm)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        Text(split.formattedPace)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: minPace...maxPace)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let sec = value.as(Double.self) {
                            Text(formatPace(sec))
                                .font(.system(.caption2, design: .rounded))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(splits.count, 8))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let km = value.as(Int.self) {
                            Text("\(km)")
                                .font(.system(.caption2, design: .rounded))
                        }
                    }
                }
            }
            .frame(height: 200)

            if hasHR {
                // A compact HR row — one small stat per km, wrapping — so
                // the user can still see "km 4 spiked to 168" without
                // buying into the dual-axis complexity of an overlaid line.
                heartRateRow
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var heartRateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVG HR PER KM")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(splits) { split in
                    VStack(spacing: 1) {
                        Text("\(split.index)")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(split.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(hrColor(for: split.averageHeartRate))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    /// Redden HR values that sit above the run's own median — a cheap way
    /// to flag effort spikes without needing a personal max HR baseline.
    private func hrColor(for bpm: Double?) -> Color {
        guard let bpm else { return .secondary }
        let hrValues = splits.compactMap(\.averageHeartRate).sorted()
        guard !hrValues.isEmpty else { return .primary }
        let median = hrValues[hrValues.count / 2]
        return bpm > median + 5 ? .red : .primary
    }

    /// Headline sentence: names where the run's pace drifted meaningfully.
    /// Uses the tercile split (first vs last third) so a single slow km
    /// doesn't trigger noise on longer runs.
    private var decayHeadline: String? {
        guard splits.count >= 4 else { return nil }
        let thirdSize = max(1, splits.count / 3)
        let firstAvg = averagePace(splits.prefix(thirdSize))
        let lastAvg = averagePace(splits.suffix(thirdSize))
        let delta = lastAvg - firstAvg  // positive = slower at the end
        if delta > 12 {
            return String(
                format: "Slowed %d s/km in the final third — likely fatigue or effort dip.",
                Int(delta.rounded())
            )
        } else if delta < -8 {
            return String(
                format: "Sped up %d s/km toward the end — strong finish.",
                Int(-delta.rounded())
            )
        } else {
            return "Pace held steady across the run — well-judged effort."
        }
    }

    private func averagePace(_ slice: ArraySlice<KilometerSplit>) -> Double {
        let vals = slice.map(\.secondsPerKm)
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(.secondary)
    }

    private var hasDynamics: Bool {
        run.averagePowerWatts != nil
            || run.averageStrideLengthMeters != nil
            || run.averageVerticalOscillationCm != nil
            || run.averageGroundContactMs != nil
            || run.averageCadenceSpm != nil
    }

    private var dynamicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUNNING DYNAMICS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let p = run.averagePowerWatts {
                    metric("POWER", value: "\(Int(p)) W", icon: "bolt.fill")
                }
                if let s = run.averageStrideLengthMeters {
                    metric("STRIDE", value: String(format: "%.2f m", s), icon: "ruler")
                }
                if let v = run.averageVerticalOscillationCm {
                    metric("VERTICAL OSC.", value: String(format: "%.1f cm", v), icon: "arrow.up.and.down")
                }
                if let g = run.averageGroundContactMs {
                    metric("GROUND CONTACT", value: "\(Int(g)) ms", icon: "shoe")
                }
                if let c = run.averageCadenceSpm {
                    metric("CADENCE", value: "\(Int(c)) spm", icon: "metronome")
                }
            }
        }
    }

    private func metric(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#if DEBUG
private let sampleSplits: [KilometerSplit] = [
    KilometerSplit(index: 1, secondsPerKm: 335, averageHeartRate: 150, cumulativeSeconds: 335),
    KilometerSplit(index: 2, secondsPerKm: 328, averageHeartRate: 154, cumulativeSeconds: 663),
    KilometerSplit(index: 3, secondsPerKm: 330, averageHeartRate: 157, cumulativeSeconds: 993),
    KilometerSplit(index: 4, secondsPerKm: 344, averageHeartRate: 163, cumulativeSeconds: 1_337),
    KilometerSplit(index: 5, secondsPerKm: 352, averageHeartRate: 168, cumulativeSeconds: 1_689),
    KilometerSplit(index: 6, secondsPerKm: 358, averageHeartRate: 171, cumulativeSeconds: 2_047),
    KilometerSplit(index: 7, secondsPerKm: 363, averageHeartRate: 172, cumulativeSeconds: 2_410),
    KilometerSplit(index: 8, secondsPerKm: 349, averageHeartRate: 168, cumulativeSeconds: 2_759),
]

/// Wrapper used only in previews so we can seed the split state without
/// touching HealthKit. Keeps the production `RunDetailView` init clean.
private struct PaceDecayPreviewHost: View {
    let run: RunRecord
    let splits: [KilometerSplit]
    var body: some View {
        NavigationStack {
            RunDetailView.previewWithSplits(run: run, splits: splits)
        }
    }
}

extension RunDetailView {
    /// Build a preview-only variant that pre-populates the splits state.
    /// Kept behind an extension so the production initializer stays a
    /// simple `RunDetailView(run:)`.
    fileprivate static func previewWithSplits(run: RunRecord, splits: [KilometerSplit]) -> some View {
        var view = RunDetailView(run: run)
        view._splits = State(initialValue: splits)
        view._isLoadingSplits = State(initialValue: false)
        view._isLoadingRoute = State(initialValue: false)
        return view
    }
}

#Preview("Run detail") {
    NavigationStack {
        RunDetailView(run: .sample)
    }
}

#Preview("Run detail — with pace decay") {
    PaceDecayPreviewHost(run: .sample, splits: sampleSplits)
}
#endif
