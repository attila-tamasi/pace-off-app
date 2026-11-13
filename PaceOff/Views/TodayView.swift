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
    /// The answer's buttons are open again after "Change".
    @State private var changingFeeling = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dateLine
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)

                if todayVM.needsFirstRun {
                    firstRunCard
                } else {
                    heroCard
                }

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
            case .hrv: HeartTrendDetailView(metric: .hrv)
            case .restingHeartRate: HeartTrendDetailView(metric: .restingHeartRate)
            case .week: WeekDetailView()
            case .readiness: ReadinessDetailView()
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
                Text(heroDistance ?? (isPlanRestDay ? "Rest" : "—"))
                    .scaledFont(size: 76, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if heroDistance != nil {
                    Text(units.unit.symbol)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // The trailing inset keeps the copy clear of the track.
            Text(todayVM.voiceLine)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 96)

            if let planLine {
                planLineRow(planLine)
            }
            if let capNote = todayVM.prescription?.capNote(in: units) {
                Text("\(capNote).")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 96)
            }
        }
        .heroSurface(trackSize: 150)
        .accessibilityElement(children: .combine)
    }

    // MARK: - First run

    /// In the hero's place while Health holds no run: what Pace Off needs,
    /// how to log a run, and where to check its access. HealthKit never
    /// says whether read access was denied, so the access hint is always
    /// there.
    private var firstRunCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GET STARTED")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.white.opacity(0.85))

            Text("Log your first run")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)

            Text("Pace Off sets each day's target from your runs in Apple Health. Record a run with Apple Watch, the Fitness app or any app that saves workouts to Health, and your first target appears here.")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Already running but nothing shows? Pace Off may not be allowed to read your workouts. In the Health app, open your profile, then Apps, then Pace Off, and turn on Workouts.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 72)

            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Label("Open Health", systemImage: "heart.text.square")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glass)
            .padding(.top, 2)

            if let planLine {
                planLineRow(planLine)
            }
        }
        .heroSurface(trackSize: 120)
    }

    /// The day's distance: the prescription's ("8", "10.8"), else the
    /// target's whole km. Nil on a plan rest day and before any target.
    private var heroDistance: String? {
        if let prescription = todayVM.prescription { return prescription.distanceText(in: units) }
        return todayVM.target.map { "\(units.wholeUnits($0.distanceMeters, capMeters: $0.capMeters))" }
    }

    /// The runner's unit (kilometres or miles).
    private var units: UnitFormatter { .runner }

    private var isPlanRestDay: Bool {
        guard let kind = todayVM.prescription?.kind else { return false }
        return kind == .rest || kind == .strength
    }

    /// Today's plan workout under the hero's copy, on a glowing track dot.
    private func planLineRow(_ line: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(BrandPalette.trackLight)
                .frame(width: 7, height: 7)
                .shadow(color: BrandPalette.trackLight, radius: 4)
            Text(line)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.top, 4)
        .padding(.trailing, 96)
    }

    /// "Half Marathon plan · Tempo", "… · Tempo + strength", "Strength day
    /// in your plan · Kettlebell" or "Rest day in your plan". Nil when no
    /// plan is active today.
    private var planLine: String? {
        guard let plan = planStore.activePlan, let day = plan.todayDay() else { return nil }
        let tick = todayVM.strengthDoneToday ? " ✓" : ""
        if day.workout.kind == .rest {
            return day.strength.map { "Strength day in your plan · \($0.equipment.displayName)\(tick)" }
                ?? "Rest day in your plan"
        }
        var line = "\(plan.goal.displayName) plan · \(day.workout.kind.displayName)"
        switch todayVM.prescription?.adjustment {
        case .easedForYellow?: line += ", run easy today"
        case .cutForRed?: line += ", cut to an easy run"
        case .restForUnwell?: line += ", rest today: you're unwell"
        case nil: break
        }
        if todayVM.prescription?.cappedAtMeters != nil {
            line += " (plan: \(units.distanceOneDecimal(day.workout.distanceMeters)))"
        }
        return day.strength == nil ? line : "\(line) + strength\(tick)"
    }

    // MARK: - Recovery

    @ViewBuilder
    private var recoverySection: some View {
        MetricSectionHeader(title: "Recovery")

        VStack(spacing: 10) {
            if !todayVM.needsFirstRun { checkInCard }
            if let readiness = todayVM.readiness {
                NavigationLink(value: TodayDestination.readiness) {
                    readinessCard(readiness)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: TodayDestination.hrv) {
                    MetricCard(
                        title: "HRV",
                        systemImage: "heart.fill",
                        tint: .pink,
                        showsChevron: true,
                        value: todayVM.yesterdayHRV.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: "ms",
                        note: todayVM.yesterdayValuesDayName?.localizedCapitalized,
                        layout: .compact
                    ) {
                        if todayVM.hrvTrend.count > 1 {
                            Sparkline(points: todayVM.hrvTrend, tint: .pink)
                                .frame(height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)

                NavigationLink(value: TodayDestination.restingHeartRate) {
                    MetricCard(
                        title: "Resting HR",
                        systemImage: "heart.fill",
                        tint: .pink,
                        showsChevron: true,
                        value: todayVM.latestRestingHeartRate.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: "bpm",
                        note: todayVM.yesterdayAvgHeartRate.flatMap { avg in
                            todayVM.yesterdayValuesDayName.map { "Avg \($0) \(Int(avg.rounded())) bpm" }
                        },
                        layout: .compact
                    ) {
                        if todayVM.restingHRTrend.count > 1 {
                            Sparkline(points: todayVM.restingHRTrend, tint: .pink)
                                .frame(height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "How do you feel?": one optional tap, Fresh to Unwell, that joins
    /// readiness (`CheckIn`). Once answered it folds to one line with a
    /// way to change it. Skipping it changes nothing.
    @ViewBuilder
    private var checkInCard: some View {
        if let feeling = todayVM.feeling, !changingFeeling {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(BrandPalette.track)
                    .accessibilityHidden(true)
                Text("You feel \(feeling.displayName.lowercased()) today")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer()
                Button("Change") { changingFeeling = true }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .accessibilityLabel("Change how you feel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("How do you feel?", systemImage: "hand.raised.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(BrandPalette.track)
                    Spacer()
                    if todayVM.feeling != nil {
                        Button("Clear") {
                            changingFeeling = false
                            Task { await todayVM.answer(nil) }
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .accessibilityLabel("Clear today's answer")
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(CheckInFeeling.allCases, id: \.self) { option in
                        Button {
                            changingFeeling = false
                            Task { await todayVM.answer(option) }
                        } label: {
                            Text(option.displayName)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(todayVM.feeling == option ? BrandPalette.track : .secondary)
                        .accessibilityAddTraits(todayVM.feeling == option ? .isSelected : [])
                    }
                }
                Text("Optional. It joins today's readiness with the watch.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            showsChevron: true,
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

            NavigationLink(value: TodayDestination.week) {
                MetricCard(
                    title: "Last 7 days",
                    systemImage: "figure.run",
                    tint: BrandPalette.track,
                    detail: streakLabel,
                    showsChevron: true,
                    value: String(format: "%.1f", todayVM.weekTotalKm),
                    unit: "km"
                ) {
                    DailyDistanceBars(days: todayVM.weekDistances)
                        .frame(width: 150, height: 64)
                }
            }
            .buttonStyle(.plain)

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

                if let lastRun = todayVM.yesterday {
                    NavigationLink {
                        RunDetailView(run: lastRun)
                    } label: {
                        lastRunCard(showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    lastRunCard(showsChevron: false)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The most recent run before today: how long ago and how far.
    private func lastRunCard(showsChevron: Bool) -> some View {
        MetricCard(
            title: "Last run",
            systemImage: "calendar",
            tint: .accentColor,
            showsChevron: showsChevron,
            value: lastRunValue,
            note: todayVM.yesterday.map { String(format: "%.1f km", $0.distanceKm) },
            layout: .compact
        )
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
        // Judged against the day's prescription as the hero showed it: the
        // plan's run (85% of it counts), else the target's whole km (95%).
        let askedKm: Double
        if let prescription = todayVM.prescription {
            askedKm = prescription.distanceKm ?? 0
        } else {
            askedKm = Double(todayVM.target?.displayedDistanceKm ?? 0)
        }
        let actualKm = run.distanceKm
        let hit = askedKm > 0 && (todayVM.prescription?.isMet(byRunMeters: run.distanceMeters)
                                  ?? (actualKm >= askedKm * 0.95))
        let label: String
        let color: Color
        if hit {
            label = "Target hit"; color = .green
        } else if askedKm == 0 {
            label = "Logged"; color = .accentColor
        } else {
            label = "Short by \(units.distanceOneDecimal((askedKm - actualKm) * 1000))"
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
    case hrv
    case restingHeartRate
    case week
    case readiness
}

private extension View {
    /// The hero's surface: the icon's blue gradient with its running track
    /// in the corner, rounded and lifted, as on Today's target card.
    func heroSurface(trackSize: CGFloat) -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    BrandPalette.cardGradient
                    TrackBend(radius: 0.75, width: 0.27)
                        .frame(width: trackSize, height: trackSize)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: BrandPalette.deepBlue.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

#if DEBUG
#Preview("Today (populated)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview())
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}

#Preview("Today (ran today)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(todayRun: .sample, streak: 5))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}

#Preview("Today (rest day)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(readiness: .sampleRed))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}

#Preview("Today (first run)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(
            target: nil, voiceLine: "", yesterday: nil, vo2Max: nil, streak: 0,
            hrv: nil, avgHR: nil, restingHR: nil, readiness: nil, trends: false,
            needsFirstRun: true
        ))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}

#Preview("Today (cache from Thursday)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview(yesterdayDayName: "Thursday"))
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}

#Preview("Today (largest text)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel.preview())
        .environment(PreviewProfileStore.populated)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today (empty)") {
    NavigationStack { TodayView() }
        .environment(TodayViewModel())
        .environment(PreviewProfileStore.empty)
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}
#endif
