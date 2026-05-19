// TodayView.swift
// Home screen — single ScrollView:
//   • Map at the top (today's route, or empty placeholder centered on Berlin)
//   • Content below it (date, hero target, today's run card, supporting grid)
//   • Scroll up and the map naturally disappears above the content.

import SwiftUI
import MapKit
import CoreLocation

struct TodayView: View {

    @Environment(TodayViewModel.self) private var todayVM
    @Environment(ProfileStore.self) private var profileStore
    @State private var cameraPosition: MapCameraPosition = .region(TodayView.berlinRegion)

    /// Map height as a fraction of the available screen height.
    private let mapHeightFraction: CGFloat = 0.46

    /// Default region used when there's no run today — centered on Berlin.
    private static let berlinRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    mapLayer
                        .frame(height: geo.size.height * mapHeightFraction)
                        .clipped()

                    contentSection
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Pace Off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await todayVM.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(10)
                }
                .disabled(todayVM.isRefreshing)
            }
        }
        .navigationDestination(for: TodayDestination.self) { dest in
            switch dest {
            case .vo2Max: VO2MaxDetailView()
            }
        }
        .onChange(of: routeCoordinateSnapshot) { _, _ in
            updateCamera(for: todayVM.todayRouteCoordinates)
        }
        .onAppear { updateCamera(for: todayVM.todayRouteCoordinates) }
    }

    private var routeCoordinateSnapshot: [RouteCoordinateSnapshot] {
        todayVM.todayRouteCoordinates.map(RouteCoordinateSnapshot.init)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapLayer: some View {
        if todayVM.todayRouteCoordinates.isEmpty {
            emptyMapPlaceholder
        } else {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                MapPolyline(coordinates: todayVM.todayRouteCoordinates)
                    .stroke(
                        .blue.gradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                if let start = todayVM.todayRouteCoordinates.first {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let end = todayVM.todayRouteCoordinates.last,
                   todayVM.todayRouteCoordinates.count > 1 {
                    Annotation("Finish", coordinate: end) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        }
    }

    /// Stylized placeholder shown when there's no recorded run today — the map
    /// itself is rendered, but parked over Berlin so the user always sees a
    /// real-looking map instead of an empty grey rectangle.
    private var emptyMapPlaceholder: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom])
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))

            VStack(spacing: 10) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.primary)
                Text("No run today")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Your route will appear here once you run.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    /// Fit the camera to the full route plus a little padding. When the route is
    /// empty (no run today), fall back to the Berlin region so the map still
    /// shows something recognizable.
    private func updateCamera(for coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else {
            cameraPosition = .region(TodayView.berlinRegion)
            return
        }
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

    // MARK: - Content section (scrolls below the map)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            dateRibbon

            recoveryCard

            heroCard

            if let run = todayVM.todayRun {
                todayRunCard(run)
            }

            supportingGrid
        }
    }

    /// Date line. When the user has a goal date set, also shows a countdown
    /// chip ("RACE IN 12 WEEKS") so the home screen always reminds them why
    /// they're being pushed.
    private var dateRibbon: some View {
        let date = Date().formatted(.dateTime.weekday(.wide).month().day()).uppercased()
        return HStack(spacing: 10) {
            Text(date)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(1.2)
            if let countdown = goalCountdownLabel {
                Text("·")
                    .foregroundStyle(.tertiary)
                    .font(.system(.caption, weight: .semibold))
                Text(countdown)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// "RACE IN 12 WEEKS" / "RACE IN 4 DAYS", or nil if no goal date is set.
    private var goalCountdownLabel: String? {
        guard let goalDate = profileStore.profile?.goalDate, goalDate > Date() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: goalDate).day ?? 0
        if days <= 0 { return nil }
        if days < 14 {
            return "RACE IN \(days) DAY\(days == 1 ? "" : "S")"
        }
        let weeks = days / 7
        return "RACE IN \(weeks) WEEK\(weeks == 1 ? "" : "S")"
    }

    // MARK: - Yesterday's recovery (morning check-in)

    /// Shown at the top of the home screen so it's the first thing the user
    /// reads when they open the app. Three numbers from yesterday/overnight:
    /// HRV (SDNN), average heart rate, and most-recent resting heart rate.
    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YESTERDAY'S RECOVERY")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.pink)
            }

            HStack(alignment: .top, spacing: 0) {
                recoveryStat(
                    label: "HRV",
                    value: todayVM.yesterdayHRV.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "ms"
                )
                divider
                recoveryStat(
                    label: "AVG HR",
                    value: todayVM.yesterdayAvgHeartRate.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm"
                )
                divider
                recoveryStat(
                    label: "RESTING",
                    value: todayVM.latestRestingHeartRate.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm"
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        }
    }

    private func recoveryStat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: - Hero card (today's target)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row: label on the left, tone pill on the right — no
            // overlap, balanced visual weight, easier to scan.
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S TARGET")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(1.2)
                    if let goalLine {
                        Text(goalLine)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if let tone = todayVM.target?.tone {
                    Text(tone.displayName.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .kerning(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(toneColor(tone).opacity(0.15), in: Capsule())
                        .foregroundStyle(toneColor(tone))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(todayVM.target?.formattedDistance.replacingOccurrences(of: " km", with: "") ?? "—")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("km")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(todayVM.voiceLine)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        }
    }

    /// "Toward Half Marathon" — only when a profile goal is set. The home
    /// screen now reflects the user's stated goal, not just a daily number.
    private var goalLine: String? {
        guard let goal = profileStore.profile?.goal else { return nil }
        return "Toward \(goal.displayName)"
    }

    private func toneColor(_ tone: Tone) -> Color {
        switch tone {
        case .neutral, .firm: return .accentColor
        case .aggressive, .restart: return .red
        case .recovery: return .orange
        case .victory: return .green
        case .shortfall: return .yellow
        }
    }

    // MARK: - Today's run card

    private func todayRunCard(_ run: RunRecord) -> some View {
        // Compare against the displayed (rounded-up) target, not the precise
        // engine value, so the "TARGET HIT" badge matches what the user saw.
        let askedKm = Double(todayVM.target?.displayedDistanceKm ?? 0)
        let actualKm = run.distanceKm
        let hit = askedKm > 0 && actualKm >= askedKm * 0.95
        let label: String
        let color: Color
        if hit {
            label = "TARGET HIT"; color = .green
        } else if askedKm == 0 {
            label = "LOGGED"; color = .accentColor
        } else {
            label = "SHORT BY \(String(format: "%.1f km", askedKm - actualKm))"
            color = .orange
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOU RAN TODAY")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .kerning(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", actualKm))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("km")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                runStat(label: "TIME", value: run.formattedDuration)
                runStat(label: "PACE", value: run.formattedPace)
                if let hr = run.averageHeartRate {
                    runStat(label: "AVG HR", value: "\(Int(hr.rounded())) bpm")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        }
    }

    private func runStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
        }
    }

    // MARK: - Supporting stat grid

    private var supportingGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(
                    label: "YESTERDAY",
                    value: todayVM.yesterday.map { String(format: "%.1f km", $0.distanceKm) } ?? "—",
                    icon: "calendar"
                )
                NavigationLink(value: TodayDestination.vo2Max) {
                    statCard(
                        label: "VO₂ MAX",
                        value: todayVM.currentVO2Max.map { String(format: "%.1f", $0) } ?? "—",
                        icon: "lungs.fill",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                statCard(
                    label: "STREAK",
                    value: todayVM.currentStreak == 0 ? "0" : "\(todayVM.currentStreak) day\(todayVM.currentStreak == 1 ? "" : "s")",
                    icon: "flame.fill"
                )
                statCard(
                    label: "DAYS SKIPPED",
                    value: todayVM.target.map { "\($0.daysSinceLastRun)" } ?? "—",
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func statCard(label: String, value: String, icon: String, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum TodayDestination: Hashable {
    case vo2Max
}

private struct RouteCoordinateSnapshot: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

#if DEBUG
#Preview("Today (populated)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview())
        .environment(PreviewProfileStore.populated)
}

#Preview("Today (ran today)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(todayRun: .sample, streak: 5))
        .environment(PreviewProfileStore.populated)
}

#Preview("Today (empty)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel())
        .environment(PreviewProfileStore.empty)
}
#endif
