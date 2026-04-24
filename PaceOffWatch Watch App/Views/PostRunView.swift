// PostRunView.swift
// Brief post-run summary. Surfaces in PaceOffWatchApp after the session ends.

import SwiftUI

struct PostRunView: View {
    let run: RunRecord
    let target: RunTarget?

    private var hitTarget: Bool {
        guard let t = target else { return false }
        return run.distanceMeters >= t.distanceMeters * 0.95
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
                    Text("Target was \(String(format: "%.1f", t.distanceKm)) km")
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
