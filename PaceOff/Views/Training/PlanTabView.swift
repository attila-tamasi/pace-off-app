// PlanTabView.swift
// The Plan tab. With an active plan: today's workout on the brand hero,
// this week's days with today marked, and the whole plan one tap away.
// Without one: the plan picker, which flips this tab to the active plan
// as soon as a plan is selected.

import SwiftUI

struct PlanTabView: View {

    @Environment(TrainingPlanStore.self) private var planStore

    var body: some View {
        if let plan = planStore.activePlan {
            ActivePlanView(plan: plan)
        } else {
            TrainingPlanPickerView()
        }
    }
}

private struct ActivePlanView: View {

    let plan: TrainingPlan

    @State private var settingsPresented = false

    private var weekIndex: Int? { plan.currentWeekIndex() }
    private var today: Weekday { Weekday(date: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(subtitle)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 14)

                todayHero

                if let weekIndex {
                    MetricSectionHeader(title: "This week")
                    weekCard(plan.weeks[weekIndex])
                }

                MetricSectionHeader(title: "Plan")
                planCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settingsPresented = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Plan settings")
            }
        }
        .sheet(isPresented: $settingsPresented) {
            TrainingPlanSettingsView()
        }
    }

    /// "Medium Half Marathon Plan · Week 3 of 12".
    private var subtitle: String {
        guard let weekIndex else { return plan.displayName }
        return "\(plan.displayName) · Week \(weekIndex + 1) of \(plan.weekCount)"
    }

    // MARK: - Today

    private var todayHero: some View {
        let workout = plan.todayWorkout()

        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.white.opacity(0.85))

            Text(heroTitle(workout))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(heroDetail(workout))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 96)

            if let notes = workout?.notes, workout?.kind != .rest {
                Text(notes)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 96)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
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

    private func heroTitle(_ workout: Workout?) -> String {
        guard let workout else { return "No session" }
        return workout.kind == .rest ? "Rest day" : workout.kind.displayName
    }

    private func heroDetail(_ workout: Workout?) -> String {
        guard let workout else {
            return weekIndex == nil
                ? "This plan isn't running this week."
                : "Nothing planned today."
        }
        return workout.kind == .rest ? "Recovery is part of the plan." : workout.summary
    }

    // MARK: - This week

    private func weekCard(_ week: TrainingWeek) -> some View {
        VStack(spacing: 0) {
            ForEach(week.days) { day in
                dayRow(day)
                if day.id != week.days.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func dayRow(_ day: TrainingDay) -> some View {
        let isToday = day.weekday == today
        let isRest = day.workout.kind == .rest

        return HStack(spacing: 12) {
            Text(day.weekday.shortName)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(isToday ? Color.white : Color.secondary)
                .frame(width: 40, height: 28)
                .background {
                    if isToday {
                        Capsule().fill(Color.accentColor)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(day.workout.kind.displayName)
                    .font(.system(.subheadline, weight: isRest ? .regular : .semibold))
                    .foregroundStyle(isRest ? .secondary : .primary)
                if !isRest {
                    Text(day.workout.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if day.workout.kind.isQuality || day.workout.kind == .long {
                Circle()
                    .fill(BrandPalette.track)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }

    // MARK: - Plan

    private var planCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                TrainingPlanDetailView(plan: plan, showsSelectButton: false)
            } label: {
                planRow("All weeks", value: "\(plan.weekCount)", showsChevron: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 16)
            planRow("Weeks left", value: "\(plan.weeksRemaining())")
            Divider().padding(.leading, 16)
            planRow("Runs per week", value: "\(plan.tier.runsPerWeek)")
            Divider().padding(.leading, 16)
            planRow("Long run", value: plan.longRunDay.displayName)
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func planRow(_ title: String, value: String, showsChevron: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Plan tab — active") {
    let store = TrainingPlanStore.shared
    store.setActive(
        TrainingPlanGenerator().generate(
            TrainingPlanInputs(
                goal: .halfMarathon,
                tier: .medium,
                longRunDay: .sunday,
                vo2Max: 49.2
            )
        )
    )
    return NavigationStack { PlanTabView() }
        .environment(store)
        .environment(PreviewProfileStore.populated)
        .environment(HealthKitService.shared)
}
#endif
