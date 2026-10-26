// TodayView.swift
// Home screen, laid out like the Health app's Summary:
//   • Large "Today" title, the date and race countdown under it, and the
//     profile avatar top-right (it opens Profile as a sheet)
//   • The one hero surface: today's target on the icon's blue, with the
//     icon's running track in the corner
//   • "Recovery" and "Running" sections of Health-style metric cards with
//     mini charts
//
// Liquid Glass stays on the navigation layer (toolbar, tab bar, the tone
// pill on the hero), as in Health; the data cards are solid grouped
// surfaces so the numbers stay crisp.

import SwiftUI
import MapKit
import CoreLocation

struct TodayView: View {

    @Environment(TodayViewModel.self) private var todayVM
    @Environment(ProfileStore.self) private var profileStore
    @Environment(TrainingPlanStore.self) private var planStore

    @State private var profilePresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dateLine
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)

                heroCard

                recoverySection
                runningSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background { ambientBackground }
        .refreshable { await todayVM.refresh() }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { profilePresented = true } label: {
                    ProfileAvatar(photo: profileStore.photo, name: profileStore.profile?.displayName)
                }
                .accessibilityLabel("Profile")
            }
        }
        .sheet(isPresented: $profilePresented) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { profilePresented = false }
                        }
                    }
            }
        }
        .navigationDestination(for: TodayDestination.self) { dest in
            switch dest {
            case .vo2Max: VO2MaxDetailView()
            }
        }
    }

    // MARK: - Backdrop

    /// The grouped system background with a soft wash of the icon's blue
    /// behind the title, like the tinted top of Health's Summary.
    private var ambientBackground: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: - Date line

    /// "Monday, 26 October · Race in 9 weeks". The countdown keeps the
    /// reason for the push on screen whenever a race date is set.
    private var dateLine: some View {
        HStack(spacing: 0) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .foregroundStyle(.secondary)
            if let countdown = goalCountdownLabel {
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text(countdown)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandPalette.track)
            }
        }
        .font(.system(.subheadline, weight: .medium))
    }

    /// "Race in 12 weeks" / "Race in 4 days", or nil if no goal date is set.
    private var goalCountdownLabel: String? {
        guard let goalDate = profileStore.profile?.goalDate, goalDate > Date() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: goalDate).day ?? 0
        if days <= 0 { return nil }
        if days < 14 {
            return "Race in \(days) day\(days == 1 ? "" : "s")"
        }
        let weeks = days / 7
        return "Race in \(weeks) week\(weeks == 1 ? "" : "s")"
    }

    // MARK: - Hero (today's target)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S TARGET")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(.white.opacity(0.85))
                    if let goal = profileStore.profile?.goal {
                        Text("Toward \(goal.displayName)")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                if let tone = todayVM.target?.tone {
                    Text(tone.displayName.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.tint(.white.opacity(0.12)), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(todayVM.target.map { "\($0.displayedDistanceKm)" } ?? "—")
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("km")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            // The trailing inset keeps the copy clear of the track.
            Text(todayVM.voiceLine)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 96)

            if let planLine {
                HStack(spacing: 7) {
                    Circle()
                        .fill(BrandPalette.trackLight)
                        .frame(width: 7, height: 7)
                        .shadow(color: BrandPalette.trackLight, radius: 4)
                    Text(planLine)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.top, 4)
                .padding(.trailing, 96)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                BrandPalette.cardGradient
                TrackBend(radius: 0.75, width: 0.27)
                    .frame(width: 150, height: 150)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: BrandPalette.deepBlue.opacity(0.25), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }

    /// "Half Marathon plan · Tempo", or "Rest day in your plan". Nil when
    /// no plan is active today.
    private var planLine: String? {
        guard let plan = planStore.activePlan, let workout = plan.todayWorkout() else { return nil }
        if workout.kind == .rest { return "Rest day in your plan" }
        return "\(plan.goal.displayName) plan · \(workout.kind.displayName)"
    }

    // MARK: - Recovery

    @ViewBuilder
    private var recoverySection: some View {
        MetricSectionHeader(title: "Recovery")

        VStack(spacing: 10) {
            if let readiness = todayVM.readiness {
                readinessCard(readiness)
            }
            HStack(alignment: .top, spacing: 10) {
                MetricCard(
                    title: "HRV",
                    systemImage: "heart.fill",
                    tint: .pink,
                    value: todayVM.yesterdayHRV.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "ms",
                    note: "Yesterday",
                    layout: .compact
                ) {
                    if todayVM.hrvTrend.count > 1 {
                        Sparkline(points: todayVM.hrvTrend, tint: .pink)
                            .frame(height: 30)
                    }
                }
                MetricCard(
                    title: "Resting HR",
                    systemImage: "heart.fill",
                    tint: .pink,
                    value: todayVM.latestRestingHeartRate.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    note: todayVM.yesterdayAvgHeartRate.map { "Avg yesterday \(Int($0.rounded())) bpm" },
                    layout: .compact
                ) {
                    if todayVM.restingHRTrend.count > 1 {
                        Sparkline(points: todayVM.restingHRTrend, tint: .pink)
                            .frame(height: 30)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Green / yellow / red verdict on today's recovery. Hidden entirely
    /// while there isn't enough HRV/RHR history for a trustworthy baseline.
    private func readinessCard(_ readiness: DailyReadiness) -> some View {
        MetricCard(
            title: "Readiness",
            systemImage: readinessSymbol(readiness.level),
            tint: readinessTint(readiness.level),
            detail: readiness.computedAt.formatted(date: .omitted, time: .shortened),
            value: readinessLabel(readiness.level),
            note: readiness.sentence
        ) {
            HStack(spacing: 6) {
                ForEach([ReadinessLevel.green, .yellow, .red], id: \.self) { level in
                    Circle()
                        .fill(level == readiness.level ? readinessDot(level) : Color(.tertiarySystemFill))
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)
        }
    }

    private func readinessLabel(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "Ready"
        case .yellow: return "Ease off"
        case .red: return "Rest"
        }
    }

    private func readinessSymbol(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.circle.fill"
        case .red: return "moon.zzz.fill"
        }
    }

    /// Text tint for the card header. Yellow text is unreadable on a light
    /// card, so the yellow day reads in orange; the dot stays yellow.
    private func readinessTint(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }

    private func readinessDot(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    // MARK: - Running

    @ViewBuilder
    private var runningSection: some View {
        MetricSectionHeader(title: "Running")

        VStack(spacing: 10) {
            if let run = todayVM.todayRun {
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    todayRunCard(run)
                }
                .buttonStyle(.plain)
            }

            MetricCard(
                title: "Last 7 days",
                systemImage: "figure.run",
                tint: BrandPalette.track,
                detail: streakLabel,
                value: String(format: "%.1f", todayVM.weekTotalKm),
                unit: "km"
            ) {
                DailyDistanceBars(days: todayVM.weekDistances)
                    .frame(width: 150, height: 64)
            }

            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: TodayDestination.vo2Max) {
                    MetricCard(
                        title: "VO₂ max",
                        systemImage: "lungs.fill",
                        tint: .accentColor,
                        showsChevron: true,
                        value: todayVM.currentVO2Max.map { String(format: "%.1f", $0) } ?? "—",
                        layout: .compact
                    ) {
                        if todayVM.vo2Trend.count > 1 {
                            Sparkline(points: todayVM.vo2Trend, tint: .accentColor)
                                .frame(height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)

                MetricCard(
                    title: "Last run",
                    systemImage: "calendar",
                    tint: .accentColor,
                    value: lastRunValue,
                    note: todayVM.yesterday.map { String(format: "%.1f km", $0.distanceKm) },
                    layout: .compact
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "5-day streak", or nil before the first day of a streak.
    private var streakLabel: String? {
        let streak = todayVM.currentStreak
        guard streak > 0 else { return nil }
        return "\(streak)-day streak"
    }

    /// How long ago the most recent run before today was: "Yesterday",
    /// "3 days ago".
    private var lastRunValue: String {
        guard let run = todayVM.yesterday else { return "—" }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: run.startDate),
            to: cal.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    // MARK: - Today's run

    private func todayRunCard(_ run: RunRecord) -> some View {
        // Compare against the displayed (rounded-up) target, not the precise
        // engine value, so the "Target hit" badge matches what the user saw.
        let askedKm = Double(todayVM.target?.displayedDistanceKm ?? 0)
        let actualKm = run.distanceKm
        let hit = askedKm > 0 && actualKm >= askedKm * 0.95
        let label: String
        let color: Color
        if hit {
            label = "Target hit"; color = .green
        } else if askedKm == 0 {
            label = "Logged"; color = .accentColor
        } else {
            label = "Short by \(String(format: "%.1f km", askedKm - actualKm))"
            color = .orange
        }

        var stats = "\(run.formattedDuration) · \(run.formattedPace)"
        if let hr = run.averageHeartRate {
            stats += " · \(Int(hr.rounded())) bpm"
        }

        return VStack(alignment: .leading, spacing: 12) {
            MetricCard(
                title: "Today's run",
                systemImage: "figure.run",
                tint: BrandPalette.track,
                detail: run.startDate.formatted(date: .omitted, time: .shortened),
                showsChevron: true,
                value: String(format: "%.2f", actualKm),
                unit: "km",
                note: stats
            ) {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
                    .padding(.bottom, 2)
            }

            if !todayVM.todayRouteCoordinates.isEmpty {
                RouteMapPreview(coordinates: todayVM.todayRouteCoordinates)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

// MARK: - Route preview

/// Static map of a route, fitted to the line. Not interactive: it sits
/// inside a card that is itself a link to the run's detail.
private struct RouteMapPreview: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    BrandPalette.track,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityHidden(true)
    }

    private var region: MKCoordinateRegion {
        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude
        var minLng = coordinates[0].longitude, maxLng = coordinates[0].longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.005),
                                   longitudeDelta: max((maxLng - minLng) * 1.5, 0.005))
        )
    }
}

// MARK: - Avatar

/// The profile photo in a circle, or the runner's initials on the track's
/// orange when there's no photo.
private struct ProfileAvatar: View {
    let photo: UIImage?
    let name: String?

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else if let initials {
                Text(initials)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrandPalette.trackFill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private var initials: String? {
        let letters = (name ?? "")
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}

private enum TodayDestination: Hashable {
    case vo2Max
}

#if DEBUG
#Preview("Today (populated)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview())
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
}

#Preview("Today (ran today)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(todayRun: .sample, streak: 5))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
}

#Preview("Today (rest day)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(readiness: .sampleRed))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
}

#Preview("Today (empty)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel())
        .environment(PreviewProfileStore.empty)
        .environment(TrainingPlanStore.shared)
}
#endif
