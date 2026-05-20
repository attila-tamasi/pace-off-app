// TrainingPlanDetailView.swift
// Week-by-week preview of a generated TrainingPlan. The "Select this plan"
// button at the bottom commits the plan to TrainingPlanStore and pops back
// to the picker (and from there, the Profile tab).

import SwiftUI

struct TrainingPlanDetailView: View {

    let plan: TrainingPlan

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
                selectButton
                    .padding(.top, 8)
                    .padding(.bottom, 32)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .fill(.background)
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
                                      weight: day.workout.kind.isQuality || day.workout.kind == .long
                                            ? .semibold : .regular))
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
                personalBest: PersonalBest(durationSeconds: 5_482, year: 2024)
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
#endif
