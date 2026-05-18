// TrainingPlanSettingsView.swift
// Mini settings sheet for the currently-active training plan. Lets the user
// see the long-run day, the VDOT used, and end the plan. To switch tier or
// long-run day mid-plan, end this plan and pick a new one — that's simpler
// than partial regeneration and avoids surprising progress loss.

import SwiftUI

struct TrainingPlanSettingsView: View {

    @EnvironmentObject private var planStore: TrainingPlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingEnd = false

    var body: some View {
        NavigationStack {
            Form {
                if let plan = planStore.activePlan {
                    Section("Active plan") {
                        LabeledContent("Name", value: plan.displayName)
                        LabeledContent("Weeks", value: "\(plan.weekCount)")
                        LabeledContent("Long-run day", value: plan.longRunDay.displayName)
                        LabeledContent("VDOT", value: String(format: "%.0f", plan.vdot))
                        LabeledContent(
                            "Started",
                            value: plan.createdAt.formatted(.dateTime.month().day().year())
                        )
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmingEnd = true
                        } label: {
                            Label("End this plan", systemImage: "stop.circle")
                        }
                    } footer: {
                        Text("To change the long-run day or intensity, end this plan and pick a new one. Your run history is untouched.")
                    }
                } else {
                    Text("No active plan.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("End this training plan?",
                                isPresented: $confirmingEnd,
                                titleVisibility: .visible) {
                Button("End Plan", role: .destructive) {
                    planStore.clear()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#if DEBUG
#Preview("Plan settings — active") {
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
    return TrainingPlanSettingsView()
        .environmentObject(store)
}
#endif
