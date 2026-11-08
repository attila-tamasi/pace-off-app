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

    var body: some View {
        let week = WeekReview(runs: todayVM.recentRuns, plan: planStore.activePlan)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(week)
                chartCard(week)
                if week.hasPlan {
                    planCard(week)
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
        .navigationTitle("Last 7 Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private func summary(_ week: WeekReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", week.totalKm))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("km")
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

    // MARK: - Chart

    /// A bar per day in the track's orange; with a plan, a dashed line
    /// across each day at the plan's distance.
    private func chartCard(_ week: WeekReview) -> some View {
        Chart {
            ForEach(week.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("km", day.distanceKm)
                )
                .foregroundStyle(BrandPalette.trackFill)
                .cornerRadius(5)
                if let workout = day.plan?.workout, workout.kind != .rest {
                    RuleMark(
                        xStart: .value("Start", day.date.addingTimeInterval(3 * 3600)),
                        xEnd: .value("End", day.date.addingTimeInterval(21 * 3600)),
                        y: .value("Plan", workout.distanceKm)
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
                stat(value: String(format: "%.1f of %.1f", week.totalKm, week.plannedKm), label: "km against the plan")
            }

            if week.plannedKm > 0 {
                ProgressView(value: min(week.totalKm, week.plannedKm), total: week.plannedKm)
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
                    Text(String(format: "%.1f km", day.distanceKm))
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
        if workout.kind == .race { return "Plan: \(workout.headline)" }
        return "Plan: \(workout.kind.displayName) · \(workout.summary)"
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
            symbol = "xmark.circle.fill"; color = .orange; label = "Plan workout missed"
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
                Text(String(format: "%.2f km", run.distanceKm))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("\(run.formattedPace) · \(run.formattedDuration) · \(run.startDate.formatted(date: .omitted, time: .shortened))")
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
