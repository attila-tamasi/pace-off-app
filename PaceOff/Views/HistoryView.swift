// HistoryView.swift
// Chronological list of all running workouts from HealthKit.

import SwiftUI

struct HistoryView: View {

    @State private var runs: [RunRecord] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading && runs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if runs.isEmpty {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "figure.run",
                    description: Text("Once you log a run, it'll appear here from Apple Health.")
                )
            } else {
                ForEach(grouped(), id: \.month) { group in
                    Section(header: Text(group.month)) {
                        ForEach(group.runs) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                RunRow(run: run)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched = await HealthKitService.shared.fetchRuns(daysBack: 365)
        self.runs = fetched.sorted { $0.startDate > $1.startDate }
    }

    private func grouped() -> [(month: String, runs: [RunRecord])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let grouped = Dictionary(grouping: runs) { formatter.string(from: $0.startDate) }
        return grouped
            .sorted { ($0.value.first?.startDate ?? .distantPast) > ($1.value.first?.startDate ?? .distantPast) }
            .map { (month: $0.key, runs: $0.value) }
    }
}

private struct RunRow: View {
    let run: RunRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(run.startDate.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text("\(String(format: "%.2f", run.distanceKm)) km · \(run.formattedPace) · \(run.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let hit = run.hitTarget {
                Image(systemName: hit ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(hit ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}
