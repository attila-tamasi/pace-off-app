// PlanTabView.swift
// The Plan tab. With an active plan: today's workout on the brand hero,
// this week's days with today marked, and the whole plan one tap away. A
// plan built for a far-off race that hasn't started yet says when it
// starts and previews its first week instead.
// Without one: the plan picker, which flips this tab to the active plan
// as soon as a plan is selected.

import SwiftUI

struct PlanTabView: View {
    /// The runner's unit (kilometres or miles).
    private var units: UnitFormatter { .runner }

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
    @State private var watch = WatchWorkoutScheduler.shared

    /// One clock read per render, so every part of the screen agrees on
    /// the day, even across midnight.
    let now = Date()
    private var weekIndex: Int? { plan.currentWeekIndex(today: now) }
    private var startsLater: Bool { plan.startsLater(today: now) }
    private var today: Weekday { Weekday(date: now) }

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
                    weekCard(plan.weeks[weekIndex], marksToday: true)
                } else if startsLater, let first = plan.weeks.first {
                    MetricSectionHeader(title: "First week")
                    weekCard(first, marksToday: false)
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

    /// "Medium Half Marathon Plan · Week 3 of 12", or "· Starts 3 Mar"
    /// before it begins.
    private var subtitle: String {
        if startsLater {
            return "\(plan.displayName) · Starts \(plan.firstDayText(today: now))"
        }
        guard let weekIndex else { return plan.displayName }
        return "\(plan.displayName) · Week \(weekIndex + 1) of \(plan.weekCount)"
    }

    // MARK: - Today

    private var todayHero: some View {
        let day = plan.todayDay(today: now)
        let workout = day?.workout
        let strength = startsLater ? nil : day?.strength

        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.white.opacity(0.85))

            Text(heroTitle(workout, strength: strength))
                .scaledFont(size: 40, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(heroDetail(workout, strength: strength))
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 96)

            if let notes = workout?.notes(in: .runner), workout?.kind != .rest {
                Text(notes)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 96)
            }

            if let strength {
                // After the run on a run day; the day's whole session on a
                // strength-only day.
                Text(workout?.kind == .rest ? strength.notes : "Then strength, \(strength.summary): \(strength.notes)")
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

    private func heroTitle(_ workout: Workout?, strength: StrengthSession?) -> String {
        if startsLater { return "Starts \(plan.firstDayText(today: now))" }
        guard let workout else { return "No session" }
        if workout.kind == .rest { return strength == nil ? "Rest day" : "Strength" }
        return workout.kind.displayName
    }

    private func heroDetail(_ workout: Workout?, strength: StrengthSession?) -> String {
        if startsLater {
            return "Week 1 of \(plan.weekCount) begins on \(plan.firstDayText(long: true, today: now)), so the plan ends on race day. Until then, Today's target keeps you running."
        }
        guard let workout else {
            return weekIndex == nil
                ? "This plan isn't running this week."
                : "Nothing planned today."
        }
        if workout.kind == .rest {
            return strength.map { "\($0.summary). No run today." } ?? "Recovery is part of the plan."
        }
        return workout.summary(in: .runner)
    }

    // MARK: - This week

    private func weekCard(_ week: TrainingWeek, marksToday: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(week.days) { day in
                dayRow(day, marksToday: marksToday)
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

    private func dayRow(_ day: TrainingDay, marksToday: Bool) -> some View {
        let isToday = marksToday && day.weekday == today
        let isRest = day.workout.kind == .rest && day.strength == nil

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
                Text(day.isStrengthOnly ? "Strength" : day.workout.kind.displayName)
                    .font(.system(.subheadline, weight: isRest ? .regular : .semibold))
                    .foregroundStyle(isRest ? .secondary : .primary)
                if day.workout.kind != .rest {
                    Text(day.workout.summary(in: .runner))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let strength = day.strength {
                    Label(day.isStrengthOnly ? strength.summary : "Then \(strength.summary)",
                          systemImage: "dumbbell.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if day.workout.kind.isKeySession {
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
            if startsLater {
                planRow("Starts", value: plan.firstDayText(today: now))
            } else {
                planRow("Weeks left", value: "\(plan.weeksRemaining(today: now))")
            }
            Divider().padding(.leading, 16)
            planRow("Runs per week", value: "\(plan.tier.runsPerWeek)")
            Divider().padding(.leading, 16)
            planRow("Long run", value: plan.longRunDay.displayName)
            if let kit = plan.crossTraining {
                Divider().padding(.leading, 16)
                planRow("Strength per week",
                        value: "\(TrainingPlanGenerator.strengthSessionsPerWeek(tier: plan.tier)) · \(kit.displayName)")
            }
            if watch.isSupported {
                Divider().padding(.leading, 16)
                watchRow
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    /// "Send workouts to Apple Watch": the next seven days' runs go to the
    /// Workout app on the watch, with pace alerts.
    private var watchRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Send workouts to Apple Watch", isOn: Binding(
                get: { watch.isEnabled },
                set: { on in Task { await watch.setEnabled(on) } }
            ))
            Text(watch.isDenied
                 ? "Pace Off isn't allowed to schedule workouts. You can allow it in Settings."
                 : "The next seven days' runs appear in the Workout app on your watch, with pace alerts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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

#Preview("Plan tab — starts later") {
    let store = TrainingPlanStore.shared
    store.setActive(
        TrainingPlanGenerator().generate(
            TrainingPlanInputs(
                goal: .marathon,
                tier: .medium,
                longRunDay: .sunday,
                vo2Max: 49.2,
                goalDate: Date().addingTimeInterval(26 * 7 * 86_400)
            )
        )
    )
    return NavigationStack { PlanTabView() }
        .environment(store)
        .environment(PreviewProfileStore.populated)
        .environment(HealthKitService.shared)
}
#endif
