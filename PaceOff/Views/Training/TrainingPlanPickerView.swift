// TrainingPlanPickerView.swift
// First screen of the Training Plan flow. Three tier cards (Easy / Medium /
// Aggressive). Tapping one pushes a detail view that shows the full plan
// and offers a "Select this plan" CTA.

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
            Text("Three intensities for your \(goal.displayName). Paces are tailored to your current fitness using Daniels' VDOT method.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private var personalBest: PersonalBest? { profileStore.profile?.personalBest }

    private func inputs(for tier: PlanTier) -> TrainingPlanInputs {
        TrainingPlanInputs(
            goal: goal,
            tier: tier,
            longRunDay: longRunDay,
            vo2Max: vo2Max,
            personalBest: personalBest
        )
    }

    private func weeksFor(_ goal: RunningGoal) -> Int {
        generator.planWeeks(for: goal)
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
#endif
