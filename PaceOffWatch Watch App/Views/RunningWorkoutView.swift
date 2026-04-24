// RunningWorkoutView.swift
// Live in-run screen. Pace, distance, time. Crown rotates secondary metric.

import SwiftUI

struct RunningWorkoutView: View {

    @EnvironmentObject private var session: WorkoutSessionManager
    @State private var secondaryMetric: SecondaryMetric = .heartRate
    @State private var showStopConfirm = false

    enum SecondaryMetric: String, CaseIterable {
        case heartRate, power, stride, cadence
        var label: String {
            switch self {
            case .heartRate: return "BPM"
            case .power:     return "WATTS"
            case .stride:    return "STRIDE"
            case .cadence:   return "SPM"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formattedPace)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("PACE")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            HStack {
                VStack(alignment: .leading) {
                    Text(String(format: "%.2f", session.distanceMeters / 1000))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("KM").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(formattedTime)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("TIME").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text(secondaryValue)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Text(secondaryMetric.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .focusable()
            .digitalCrownRotation(
                .init(get: { Double(SecondaryMetric.allCases.firstIndex(of: secondaryMetric) ?? 0) },
                      set: { newValue in
                          let idx = max(0, min(SecondaryMetric.allCases.count - 1, Int(newValue.rounded())))
                          secondaryMetric = SecondaryMetric.allCases[idx]
                      }),
                from: 0,
                through: Double(SecondaryMetric.allCases.count - 1),
                by: 1,
                sensitivity: .low,
                isContinuous: false
            )

            Spacer()

            Button(role: .destructive) {
                showStopConfirm = true
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 4)
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("End run?", isPresented: $showStopConfirm) {
            Button("End Run", role: .destructive) { session.stop() }
        }
    }

    private var formattedTime: String {
        let total = Int(session.elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private var formattedPace: String {
        guard let pace = session.currentPace, pace > 0, pace < 1800 else { return "—:—" }
        let m = Int(pace) / 60
        let s = Int(pace) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var secondaryValue: String {
        switch secondaryMetric {
        case .heartRate: return session.currentHeartRate.map { "\(Int($0))" } ?? "—"
        case .power:     return session.currentPower.map { "\(Int($0))" } ?? "—"
        case .stride:    return session.currentStride.map { String(format: "%.2f m", $0) } ?? "—"
        case .cadence:   return session.currentCadence.map { "\(Int($0))" } ?? "—"
        }
    }
}
