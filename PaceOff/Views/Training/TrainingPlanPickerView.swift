// TrainingPlanPickerView.swift
// First screen of the Training Plan flow. Surfaces the goal race up top so
// the runner can lock in distance + race day before picking an intensity
// tier — the three cards (Easy / Medium / Aggressive) drive plan generation
// from that goal. Tapping a card pushes a detail view that shows the full
// plan and offers a "Select this plan" CTA.

import SwiftUI

struct TrainingPlanPickerView: View {

    @Environment(ProfileStore.self) private var profileStore
    @Environment(HealthKitService.self) private var health

    @State private var longRunDay: Weekday = .sunday
    @State private var planForDetail: TrainingPlan?
    @State private var detailPresented: Bool = false
    @State private var vo2Max: Double?

    private let generator = TrainingPlanGenerator()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                goalCard
                longRunDayPicker
                ForEach(PlanTier.allCases) { tier in
                    tierCard(tier)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVO2Max() }
        .navigationDestination(isPresented: $detailPresented) {
            if let plan = planForDetail {
                TrainingPlanDetailView(plan: plan)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick a plan")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Lock in your goal race, then choose an intensity. Paces are tailored to your current fitness using Daniels' VDOT method.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Goal card (distance + race day)

    /// Editing the goal here writes straight back to `ProfileStore` — the
    /// profile is the single source of truth for race goal and date (the
    /// prediction card on Profile, plan generation, and the Today screen all
    /// read from it). Plan-local override would create silent divergence.
    private var goalCard: some View {
        // We need a Binding<RunningGoal> and Binding<Date?> backed by the
        // store. SwiftUI's @Environment(ProfileStore.self) wrapper supplies
        // an `@Bindable` `profileStore` accessor; we synthesise property-
        // shaped bindings around the store's mutator.
        let goalBinding = Binding<RunningGoal>(
            get: { profileStore.profile?.goal ?? .tenK },
            set: { newGoal in
                profileStore.update { $0.goal = newGoal }
            }
        )
        let dateBinding = Binding<Date?>(
            get: { profileStore.profile?.goalDate },
            set: { newDate in
                profileStore.update { $0.goalDate = newDate }
            }
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(.caption, weight: .semibold))
                Text("YOUR RACE")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .kerning(1.1)
            }
            .foregroundStyle(.secondary)

            GoalGridPicker(selection: goalBinding)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(.caption, weight: .semibold))
                    Text("RACE DAY")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .kerning(1.1)
                }
                .foregroundStyle(.secondary)
                GoalDatePicker(goalDate: dateBinding)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    // MARK: - Long-run day picker

    private var longRunDayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LONG RUN DAY")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.secondary)
            Picker("Long run day", selection: $longRunDay) {
                ForEach(Weekday.allCases) { d in
                    Text(d.shortName).tag(d)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Tier card

    private func tierCard(_ tier: PlanTier) -> some View {
        Button {
            planForDetail = generator.generate(inputs(for: tier))
            detailPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tier.displayName)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                summaryLine(tier)
                Text(tier.blurb)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func summaryLine(_ tier: PlanTier) -> some View {
        HStack(spacing: 14) {
            chip("\(tier.runsPerWeek) runs/wk", icon: "figure.run")
            chip("\(weeksFor(goal)) weeks", icon: "calendar")
        }
    }

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(.caption2, weight: .semibold))
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Helpers

    private var goal: RunningGoal { profileStore.profile?.goal ?? .tenK }
    private var goalDate: Date? { profileStore.profile?.goalDate }
    private var personalBest: PersonalBest? { profileStore.profile?.personalBest }

    private func inputs(for tier: PlanTier) -> TrainingPlanInputs {
        TrainingPlanInputs(
            goal: goal,
            tier: tier,
            longRunDay: longRunDay,
            vo2Max: vo2Max,
            personalBest: personalBest,
            goalDate: goalDate
        )
    }

    private func weeksFor(_ goal: RunningGoal) -> Int {
        generator.planWeeks(for: goal, goalDate: goalDate)
    }

    private func loadVO2Max() async {
        let cached = await HealthDataCache.shared.load()
        vo2Max = cached?.vo2Max.last?.value
    }
}

#if DEBUG
#Preview("Plan picker") {
    NavigationStack {
        TrainingPlanPickerView()
    }
    .environment(PreviewProfileStore.populated)
    .environment(HealthKitService.shared)
    .environment(TrainingPlanStore.shared)
}

#Preview("Plan picker — marathon w/ race day") {
    NavigationStack {
        TrainingPlanPickerView()
    }
    .environment(PreviewProfileStore.marathonWithRaceDay)
    .environment(HealthKitService.shared)
    .environment(TrainingPlanStore.shared)
}
#endif
