// RunDetailView.swift
// Everything Health holds for one run: the GPS route, a summary of every
// recorded figure (time, pace, speed, heart rate, energy, elevation, steps,
// weather), heart rate over time, the elevation profile, per-km splits and
// running dynamics. A figure Health didn't record is left out.

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

    /// Heart rate across the run, the elevation along it, and what Health
    /// keeps on the workout itself. Nil until loaded, or when not recorded.
    @State private var heartRate: WorkoutHeartRate?
    @State private var elevation: WorkoutElevation?
    @State private var extras: WorkoutExtras?

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
                        summaryGrid
                        if let heartRate, heartRate.points.count >= 2 {
                            heartRateCard(heartRate)
                        }
                        if let elevation, elevation.high - elevation.low >= 1 {
                            elevationCard(elevation)
                        }
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
                        BrandPalette.track,
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
        heartRate = nil
        elevation = nil
        extras = nil
        // Read alongside the route and heart rate, not after them.
        let run = self.run
        let workoutExtras = Task { await HealthKitService.shared.fetchWorkoutExtras(for: run) }

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

        heartRate = WorkoutHeartRate(samples: hrRaw, start: run.startDate, end: run.endDate)
        // Distances along the whole route; a negative vertical accuracy
        // marks a point without a valid altitude, which the profile skips.
        elevation = WorkoutElevation(samples: zip(locations, locationSamples)
            .filter { $0.0.verticalAccuracy >= 0 }
            .map { (meters: $0.1.cumulativeMeters, altitude: $0.0.altitude) })
        extras = await workoutExtras.value
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
            Text("\(run.startDate.formatted(date: .omitted, time: .shortened))–\(run.endDate.formatted(date: .omitted, time: .shortened))")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One tile per figure Health recorded for this run, in a fixed order.
    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(summaryItems) { item in
                metric(item.label, value: item.value, icon: item.icon)
            }
        }
    }

    private struct SummaryItem: Identifiable {
        let label: String
        let value: String
        let icon: String
        var id: String { label }
    }

    private var summaryItems: [SummaryItem] {
        var items = [SummaryItem(label: "DURATION", value: run.formattedDuration, icon: "stopwatch")]
        if run.distanceMeters > 0 {
            items.append(SummaryItem(label: "AVG PACE", value: run.formattedPace, icon: "speedometer"))
        }
        if run.distanceMeters > 0, run.durationSeconds > 0 {
            let kmh = run.distanceKm / (run.durationSeconds / 3600)
            items.append(SummaryItem(label: "AVG SPEED", value: String(format: "%.1f km/h", kmh), icon: "gauge.with.dots.needle.33percent"))
        }
        if let avg = run.averageHeartRate ?? heartRate?.average {
            items.append(SummaryItem(label: "AVG HEART RATE", value: "\(Int(avg.rounded())) bpm", icon: "heart.fill"))
        }
        if let heartRate {
            items.append(SummaryItem(label: "MAX HEART RATE", value: "\(Int(heartRate.high.rounded())) bpm", icon: "arrow.up.heart.fill"))
            items.append(SummaryItem(label: "MIN HEART RATE", value: "\(Int(heartRate.low.rounded())) bpm", icon: "arrow.down.heart.fill"))
        }
        if let kcal = run.activeEnergyKcal {
            items.append(SummaryItem(label: "ACTIVE ENERGY", value: "\(Int(kcal.rounded())) kcal", icon: "flame.fill"))
        }
        // Gain and loss from one source: Health's own figures when it has
        // them, else the route's. Indoors there's no elevation to speak of.
        if extras?.indoor != true {
            let fromHealth = extras?.elevationGainMeters != nil
            let gain = fromHealth ? extras?.elevationGainMeters : elevation?.gain
            let loss = fromHealth ? extras?.elevationLossMeters : elevation?.loss
            if let gain {
                items.append(SummaryItem(label: "ELEVATION GAIN", value: "\(Int(gain.rounded())) m", icon: "arrow.up.right"))
            }
            if let loss {
                items.append(SummaryItem(label: "ELEVATION LOSS", value: "\(Int(loss.rounded())) m", icon: "arrow.down.right"))
            }
        }
        if let steps = extras?.steps {
            items.append(SummaryItem(label: "STEPS", value: Int(steps.rounded()).formatted(), icon: "shoeprints.fill"))
        }
        if let temperature = extras?.temperatureCelsius {
            let humidity = extras?.humidityPercent.map { " · \(Int($0.rounded()))%" } ?? ""
            items.append(SummaryItem(label: "WEATHER", value: "\(Int(temperature.rounded())) °C\(humidity)", icon: "thermometer.medium"))
        }
        if let indoor = extras?.indoor {
            items.append(SummaryItem(label: "LOCATION", value: indoor ? "Indoor" : "Outdoor", icon: indoor ? "house.fill" : "tree.fill"))
        }
        if let mets = extras?.averageMETs {
            items.append(SummaryItem(label: "INTENSITY", value: String(format: "%.1f METs", mets), icon: "bolt.heart.fill"))
        }
        return items
    }

    // MARK: - Heart rate over time

    private func heartRateCard(_ heartRate: WorkoutHeartRate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("HEART RATE")
            Text("\(Int(heartRate.low.rounded()))–\(Int(heartRate.high.rounded())) bpm, \(Int(heartRate.average.rounded())) on average")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            Chart {
                ForEach(heartRate.points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("bpm", point.bpm)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.pink)
                }
                RuleMark(y: .value("Average", heartRate.average))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: max(0, heartRate.low - 10)...(heartRate.high + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: Date.FormatStyle.dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Elevation profile

    private func elevationCard(_ elevation: WorkoutElevation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ELEVATION")
            Text("\(Int(elevation.low.rounded()))–\(Int(elevation.high.rounded())) m above sea level")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            Chart {
                ForEach(elevation.points) { point in
                    AreaMark(
                        x: .value("km", point.meters / 1000),
                        yStart: .value("Base", elevation.low - 5),
                        yEnd: .value("m", point.altitude)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(BrandPalette.trackFill.opacity(0.35))
                    LineMark(
                        x: .value("km", point.meters / 1000),
                        y: .value("m", point.altitude)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(BrandPalette.track)
                }
            }
            .chartYScale(domain: (elevation.low - 5)...(elevation.high + 5))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: km == km.rounded() ? "%.0f km" : "%.1f km", km))
                                .font(.system(.caption2, design: .rounded))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 150)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    .foregroundStyle(BrandPalette.trackFill)
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

            splitsTable(showsHR: hasHR)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// One row per km: its pace, its average heart rate (when recorded,
    /// red above the run's median) and the elapsed time at its end.
    private func splitsTable(showsHR: Bool) -> some View {
        VStack(spacing: 0) {
            splitRow(km: "KM", pace: "PACE", hr: showsHR ? "HR" : nil, time: "TIME", isHeader: true)
            ForEach(splits) { split in
                Divider()
                splitRow(
                    km: "\(split.index)",
                    pace: split.formattedPace,
                    hr: showsHR ? (split.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—") : nil,
                    hrColor: hrColor(for: split.averageHeartRate),
                    time: formatElapsed(split.cumulativeSeconds),
                    isHeader: false
                )
            }
        }
    }

    private func splitRow(km: String, pace: String, hr: String?, hrColor: Color = .secondary,
                          time: String, isHeader: Bool) -> some View {
        HStack {
            Text(km).frame(width: 36, alignment: .leading)
            Text(pace).frame(maxWidth: .infinity, alignment: .leading)
            if let hr {
                Text(hr)
                    .foregroundStyle(isHeader ? Color.secondary : hrColor)
                    .frame(width: 56, alignment: .trailing)
            }
            Text(time).frame(width: 64, alignment: .trailing)
        }
        .font(isHeader
              ? Font.system(.caption2, design: .rounded, weight: .semibold)
              : Font.system(.subheadline, design: .rounded, weight: .medium))
        .foregroundStyle(isHeader ? Color.secondary : Color.primary)
        .monospacedDigit()
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// "27:41", or "1:02:05" past the hour.
    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
