// WeekDetailView.swift
// The last seven days, opened from Today's "Last 7 days" card: the week's
// distance and streak, a bar per day against the plan's distance, how the
// week stands against the plan (with a way to the Plan tab), and each day
// with its plan workout and its runs, which open their detail.

import SwiftUI
import Charts

struct WeekDetailView: View {

    @Environment(TodayViewModel.self) private var todayVM
    @Environment(TrainingPlanStore.self) private var planStore
    @Environment(AppNavigation.self) private var navigation

    /// The runner's unit (kilometres or miles).
    private var units: UnitFormatter { .runner }

    /// The week's time in zones 1–2 across its runs, and the notes for runs
    /// meant easy that weren't. Nil until worked out, or without heart rate.
    @State private var balance: (easyShare: Double, notes: [String])?

    var body: some View {
        let week = WeekReview(runs: todayVM.recentRuns, plan: planStore.activePlan)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(week)
                chartCard(week)
                if week.hasPlan {
                    planCard(week)
                }
                if let balance {
                    balanceCard(balance.easyShare, notes: balance.notes)
                }
                MetricSectionHeader(title: "Day by day")
                VStack(spacing: 10) {
                    ForEach(week.days.reversed()) { day in
                        dayCard(day)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .task(id: todayVM.recentRuns.map(\.id)) { await loadBalance(week) }
        .navigationTitle("Last 7 Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private func summary(_ week: WeekReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(units.numberOneDecimal(week.totalKm * 1000))
                    .scaledFont(size: 64, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(units.unit.symbol)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(summaryLine(week))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "4 runs · 3-day streak".
    private func summaryLine(_ week: WeekReview) -> String {
        var parts = ["\(week.runCount) run\(week.runCount == 1 ? "" : "s")"]
        if week.streak > 0 {
            parts.append("\(week.streak)-day streak")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Easy and hard

    /// Reads each run's heart rate, adds up its time in zones, and finds
    /// the runs meant easy (by the day's ledger row) that weren't.
    private func loadBalance(_ week: WeekReview) async {
        let snapshot = await HealthDataCache.shared.load()
        guard let maxHR = HeartRateZones.maxHR(observed: snapshot?.maxHeartRate,
                                               age: snapshot?.userAge ?? HealthKitService.shared.userAge())
        else { return }
        let zones = HeartRateZones(maxHR: maxHR)
        let ledger = await RunLedger.shared.load()
        var perRun: [[TimeInterval]] = []
        var notes: [String] = []
        for run in week.days.flatMap(\.runs) {
            let samples = await HealthKitService.shared.fetchHeartRateSamples(from: run.startDate, to: run.endDate)
            let seconds = zones.timeInZones(samples: samples, start: run.startDate, end: run.endDate)
            guard seconds.reduce(0, +) > 0 else { continue }
            perRun.append(seconds)
            if let note = EasyRunCheck.note(timeInZones: seconds,
                                            meantEasy: EasyRunCheck.isMeantEasy(ledger.day(run.startDate))) {
                notes.append("\(run.startDate.formatted(.dateTime.weekday(.wide))): \(note)")
            }
        }
        balance = EasyRunCheck.easyShare(perRun).map { (easyShare: $0, notes: notes) }
    }

    /// "78% easy · 22% hard": time in zones 1–2 against zone 3 and above.
    private func balanceCard(_ easyShare: Double, notes: [String]) -> some View {
        let easy = Int((easyShare * 100).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            Label("Easy and hard", systemImage: "heart.fill")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.pink)
            Text("\(easy)% easy · \(100 - easy)% hard")
                .font(.system(.title3, design: .rounded, weight: .bold))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.blue).frame(width: max(2, (geo.size.width - 2) * easyShare))
                    Rectangle().fill(Color.orange)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            Text("Time in heart-rate zones 1–2 against zone 3 and above, across this week's runs.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "tortoise.fill")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(BrandPalette.track)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Chart

    /// A bar per day in the track's orange; with a plan, a dashed line
    /// across each day at the plan's distance.
    private func chartCard(_ week: WeekReview) -> some View {
        Chart {
            ForEach(week.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(units.unit.symbol, units.value(day.distanceKm * 1000))
                )
                .foregroundStyle(BrandPalette.trackFill)
                .cornerRadius(5)
                if let workout = day.plan?.workout, workout.kind != .rest {
                    RuleMark(
                        xStart: .value("Start", day.date.addingTimeInterval(3 * 3600)),
                        xEnd: .value("End", day.date.addingTimeInterval(21 * 3600)),
                        y: .value("Plan", units.value(workout.distanceMeters))
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Distance per day for the last seven days")
    }

    // MARK: - Against the plan

    private func planCard(_ week: WeekReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(planStore.activePlan?.displayName ?? "Training plan", systemImage: "list.bullet.rectangle.portrait")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                stat(value: "\(week.completedSessions) of \(week.plannedSessions)", label: "sessions done")
                stat(value: "\(units.numberOneDecimal(week.kmOnPlanDays * 1000)) of \(units.numberOneDecimal(week.plannedKm * 1000))", label: "\(units.unit.symbol) on plan days")
            }

            if week.plannedKm > 0 {
                ProgressView(value: min(week.kmOnPlanDays, week.plannedKm), total: week.plannedKm)
                    .tint(Color.accentColor)
            }

            Button {
                navigation.tab = .plan
            } label: {
                Label("Open training plan", systemImage: "arrow.right.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Days

    private func dayCard(_ day: WeekReview.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(dayTitle(day))
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 8)
                if day.distanceKm > 0 {
                    Text(units.distanceOneDecimal(day.distanceKm * 1000))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(BrandPalette.track)
                }
                if let mark = day.planMark {
                    markIcon(mark)
                }
            }

            if let workout = day.plan?.workout {
                Text(planLine(workout))
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if day.runs.isEmpty {
                if day.planMark != .rest {
                    Text(day.isToday ? "No run yet" : "No run")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ForEach(day.runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "Today", "Yesterday", or "Wednesday, 4 Nov".
    private func dayTitle(_ day: WeekReview.Day) -> String {
        if day.isToday { return "Today" }
        if Calendar.current.isDateInYesterday(day.date) { return "Yesterday" }
        return day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// "Plan: Easy · 8.0 km · 5:25–5:45/km", or "Plan: rest day".
    private func planLine(_ workout: Workout) -> String {
        if workout.kind == .rest { return "Plan: rest day" }
        if workout.kind == .race { return "Plan: \(workout.headline(in: units))" }
        return "Plan: \(workout.kind.displayName) · \(workout.summary(in: units))"
    }

    private func markIcon(_ mark: WeekReview.PlanMark) -> some View {
        let symbol: String
        let color: Color
        let label: String
        switch mark {
        case .done:
            symbol = "checkmark.circle.fill"; color = .green; label = "Plan workout done"
        case .pending:
            symbol = "clock.fill"; color = .accentColor; label = "Plan workout still to do"
        case .missed:
            // Neutral grey: orange means running on these screens.
            symbol = "xmark.circle.fill"; color = .secondary; label = "Plan workout missed"
        case .rest:
            symbol = "moon.zzz.fill"; color = .secondary; label = "Planned rest day"
        }
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private func runRow(_ run: RunRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run")
                .foregroundStyle(BrandPalette.track)
            VStack(alignment: .leading, spacing: 2) {
                Text(units.distanceTwoDecimals(run.distanceMeters))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("\(run.formattedPace(in: units)) · \(run.formattedDuration) · \(run.startDate.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Last 7 days") {
    NavigationStack { WeekDetailView() }
        .environment(TodayViewModel.preview())
        .environment(TrainingPlanStore.shared)
        .environment(AppNavigation())
}
#endif
