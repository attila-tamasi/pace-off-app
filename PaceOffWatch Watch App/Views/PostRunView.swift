// PostRunView.swift
// Brief post-run summary. Surfaces in PaceOffWatchApp after the session ends.

import SwiftUI

struct PostRunView: View {
    let run: RunRecord
    let target: RunTarget?

    private var hitTarget: Bool {
        guard let t = target else { return false }
        // Compare against the displayed (rounded-up) target so the "DONE" /
        // "SHORT" badge matches the integer the user saw before the run.
        return run.distanceMeters >= t.displayedDistanceMeters * 0.95
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(hitTarget ? "DONE" : "SHORT")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(hitTarget ? .green : .red)

                Text(String(format: "%.2f km", run.distanceKm))
                    .font(.system(size: 44, weight: .bold, design: .rounded))

                if let t = target {
                    Text("Target was \(t.displayedDistanceKm) km")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 4)

                Text(run.formattedPace)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(run.formattedDuration)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Post-run — done") {
    NavigationStack {
        PostRunView(
            run: RunRecord(
                startDate: Date().addingTimeInterval(-3600),
                endDate: Date().addingTimeInterval(-300),
                distanceMeters: 8_120,
                durationSeconds: 45 * 60 + 22,
                averageHeartRate: 154,
                averagePace: 335
            ),
            target: RunTarget(
                distanceMeters: 7_700,
                tone: .firm,
                daysSinceLastRun: 1,
                vo2MaxSlope: -0.05,
                baselineMeters: 7_200,
                ceilingClamped: false,
                fatigueGuardActive: false
            )
        )
    }
}

#Preview("Post-run — short") {
    NavigationStack {
        PostRunView(
            run: RunRecord(
                startDate: Date().addingTimeInterval(-1800),
                endDate: Date().addingTimeInterval(-100),
                distanceMeters: 3_200,
                durationSeconds: 18 * 60 + 4,
                averageHeartRate: 148,
                averagePace: 340
            ),
            target: RunTarget(
                distanceMeters: 7_000,
                tone: .firm,
                daysSinceLastRun: 1,
                vo2MaxSlope: 0,
                baselineMeters: 6_800,
                ceilingClamped: false,
                fatigueGuardActive: false
            )
        )
    }
}
#endif
