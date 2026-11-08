// TrainingPlanDetailView.swift
// Week-by-week view of a TrainingPlan. From the picker it's a preview: the
// "Select this plan" button at the bottom commits the plan to
// TrainingPlanStore and pops back. From the Plan tab it shows the active
// plan, without the button.

import SwiftUI

struct TrainingPlanDetailView: View {

    let plan: TrainingPlan
    /// False when showing the plan that's already active.
    var showsSelectButton = true

    @Environment(TrainingPlanStore.self) private var planStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                ForEach(plan.weeks) { week in
                    weekCard(week)
                }
                if showsSelectButton {
                    selectButton
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plan.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Activate this plan?", isPresented: $confirming) {
            Button("Activate", role: .none) {
                planStore.setActive(plan)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces any plan you already have running.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip("\(plan.weekCount) weeks", icon: "calendar")
                chip("\(plan.tier.runsPerWeek) runs/wk", icon: "figure.run")
                chip("Long: \(plan.longRunDay.shortName)", icon: "flame.fill")
            }
            HStack(spacing: 6) {
                Image(systemName: plan.usedBeginnerDefault ? "info.circle" : "speedometer")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(plan.usedBeginnerDefault
                     ? "Paces use a beginner-baseline VDOT (\(Int(plan.vdot.rounded()))). Add a VO₂ max reading or PB to refine."
                     : "Paces tailored to VDOT \(Int(plan.vdot.rounded())).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if plan.startsLater() {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Starts \(plan.firstDayText(long: true)), so it ends on race day.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            if plan.isUnderBuilt {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(underBuiltText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Why the plan's longest run is short, and, when a race date cut its
    /// weeks, what would help.
    private var underBuiltText: String {
        let longest = String(format: "%.0f km", plan.longestLongRunMeters / 1000)
        let full = String(format: "%.0f km", plan.fullBuildLongRunMeters / 1000)
        if plan.isShortened {
            return "Too few weeks to build up from your recent runs: the longest run here is \(longest), "
                + "where a full plan reaches \(full). A later race date gives it room."
        }
        return "Built up from your recent runs, 10% a week, the longest run here is \(longest), "
            + "where a full build reaches \(full)."
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

    // MARK: - Week card

    private func weekCard(_ week: TrainingWeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Week \(week.index)")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f km", week.totalDistanceKm))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                ForEach(week.days) { day in
                    dayRow(day)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private func dayRow(_ day: TrainingDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(day.weekday.shortName)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.workout.kind.displayName)
                        .font(.system(.subheadline, design: .rounded,
                                      weight: day.workout.kind.isKeySession ? .semibold : .regular))
                        .foregroundStyle(day.workout.kind == .rest ? .secondary : .primary)
                    if day.workout.kind != .rest {
                        Text("· \(day.workout.summary)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let notes = day.workout.notes {
                    Text(notes)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - CTA

    private var selectButton: some View {
        Button {
            confirming = true
        } label: {
            Label("Select this plan", systemImage: "checkmark.circle.fill")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

#if DEBUG
private extension TrainingPlan {
    static var preview: TrainingPlan {
        TrainingPlanGenerator().generate(
            TrainingPlanInputs(
                goal: .halfMarathon,
                tier: .medium,
                longRunDay: .sunday,
                vo2Max: 49.2,
                personalBest: PersonalBest(durationSeconds: 5_482, year: 2024, distance: .halfMarathon)
            )
        )
    }
}

#Preview("Plan detail — Medium half") {
    NavigationStack {
        TrainingPlanDetailView(plan: .preview)
    }
    .environment(TrainingPlanStore.shared)
}

#Preview("Plan detail — beginner's marathon, 8 weeks") {
    NavigationStack {
        TrainingPlanDetailView(plan: TrainingPlanGenerator().generate(TrainingPlanInputs(
            goal: .marathon, tier: .easy,
            goalDate: Calendar.current.date(byAdding: .day, value: 49, to: Date()),
            recentLongestRunMeters: 0
        )))
    }
    .environment(TrainingPlanStore.shared)
}
#endif
