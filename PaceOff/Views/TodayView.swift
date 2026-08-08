// TodayView.swift
// Home screen — single ScrollView:
//   • Compact route strip at the top (today's route when there is one)
//   • Content below (date, recovery, readiness, target hero, today's run
//     card, supporting grid)
//   • With no run today, the map is replaced by a lightweight graphic hero
//     so we don't burn half the screen on a stock map region.
//
// Chrome is iOS 26 Liquid Glass: every card is a `.glassEffect` shape
// inside one `GlassEffectContainer`, sampling a quiet brand backdrop
// (soft orbs over the system background). No manual materials, no
// blur/opacity fakes — per the project design rules.

import SwiftUI
import MapKit
import CoreLocation

struct TodayView: View {

    @Environment(TodayViewModel.self) private var todayVM
    @Environment(ProfileStore.self) private var profileStore
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Map height as a fraction of available screen height. Compact on
    /// purpose — the map is a preview, not the point of the screen.
    private let mapHeightFraction: CGFloat = 0.28

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
            .scrollEdgeEffectStyle(.soft, for: .top)
            .ignoresSafeArea(edges: .top)
            .background { ambientBackground }
        }
        .navigationTitle("Pace Off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await todayVM.refresh() }
                } label: {
                    // iOS 26 toolbars give items their own Liquid Glass
                    // treatment — no manual padding or backdrop needed.
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
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
            noRunHero
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

    /// Lightweight non-map hero shown when there's no run today. Replaces the
    /// previous "stock map parked over Berlin" — that ate a lot of pixels for
    /// something the user didn't relate to. The glyph and headline follow
    /// today's readiness; the detailed sentence stays on the readiness card
    /// below so the two surfaces don't repeat each other.
    private var noRunHero: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            BrandPalette.driftingOrb(color: Color.accentColor.opacity(0.35), size: 220)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 60, y: -40)
            // Glass chip over the gradient — the one spot on this screen
            // where the material has something colourful to refract even
            // before the user has any data.
            VStack(spacing: 10) {
                Image(systemName: noRunGlyph)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(todayVM.readiness.map { readinessColor($0.level) } ?? .secondary)
                    .padding(.bottom, 2)
                Text(noRunHeadline)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Your route will appear here once you run.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private var noRunGlyph: String {
        switch todayVM.readiness?.level {
        case .green:   return "checkmark.circle.fill"
        case .yellow:  return "exclamationmark.circle.fill"
        case .red:     return "moon.zzz.fill"
        case nil:      return "figure.run.circle"
        }
    }

    private var noRunHeadline: String {
        switch todayVM.readiness?.level {
        case .green:   return "Ready when you are"
        case .yellow:  return "Ease into today"
        case .red:     return "Rest is the workout"
        case nil:      return "No run today"
        }
    }

    /// Fit the camera to the full route plus a little padding. Called only
    /// when there IS a route — no-op otherwise, since the map isn't in the
    /// view tree without one.
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

    // MARK: - Content section (scrolls below the map)

    /// One container for every glass shape on the screen so the system
    /// samples the backdrop consistently and can blend neighbouring shapes
    /// during transitions.
    private var contentSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 22) {
                dateRibbon

                recoveryCard

                if let readiness = todayVM.readiness {
                    readinessCard(readiness)
                }

                heroCard

                if let run = todayVM.todayRun {
                    todayRunCard(run)
                }

                supportingGrid
            }
        }
    }

    /// Quiet backdrop the Liquid Glass cards sample from: the grouped
    /// system background with two soft brand orbs parked in the corners.
    /// Static on purpose — the home screen is a dashboard, not the splash.
    private var ambientBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
            BrandPalette.driftingOrb(color: Color.accentColor.opacity(0.22), size: 340)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -80, y: 40)
            BrandPalette.driftingOrb(color: .pink.opacity(0.14), size: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 90, y: 60)
        }
        .ignoresSafeArea()
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect()
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    // MARK: - Readiness traffic light

    /// Green / yellow / red verdict on today's recovery, sitting between the
    /// raw numbers above and the prescription below. Hidden entirely while
    /// there isn't enough HRV/RHR history for a trustworthy baseline.
    private func readinessCard(_ readiness: DailyReadiness) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY'S READINESS")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(readinessColor(readiness.level))
                        .frame(width: 8, height: 8)
                    Text(readinessLabel(readiness.level))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .kerning(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(readinessColor(readiness.level).opacity(0.15), in: Capsule())
                .foregroundStyle(readinessColor(readiness.level))
            }

            Text(readiness.sentence)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The traffic-light state tints the material itself — legible at a
        // glance without adding another colored view on top.
        .glassEffect(.regular.tint(readinessColor(readiness.level).opacity(0.10)),
                     in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's readiness: \(readinessLabel(readiness.level)). \(readiness.sentence)")
    }

    private func readinessLabel(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "READY"
        case .yellow: return "EASE OFF"
        case .red: return "REST"
        }
    }

    private func readinessColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
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
        // Brand-tinted glass marks this as the screen's one hero surface.
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.12)),
                     in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                        showsChevron: true,
                        interactive: true
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

    /// `interactive` opts the glass into touch response (scale/shimmer on
    /// press) — only the tappable VO₂ MAX card wants that.
    private func statCard(label: String,
                          value: String,
                          icon: String,
                          showsChevron: Bool = false,
                          interactive: Bool = false) -> some View {
        let glass: Glass = interactive ? .regular.interactive() : .regular
        return VStack(alignment: .leading, spacing: 6) {
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
        .glassEffect(glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

#Preview("Today (rest day)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(readiness: .sampleRed))
        .environment(PreviewProfileStore.populated)
}

#Preview("Today (empty)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel())
        .environment(PreviewProfileStore.empty)
}
#endif
