// WatchTodayView.swift
// Watch home: today's target distance, voice line, big Start button.

import SwiftUI

struct WatchTodayView: View {

    @Environment(WorkoutSessionManager.self) private var session

    private var cachedTarget: RunTarget? {
        guard let data = AppGroup.sharedDefaults?.data(forKey: AppGroup.Keys.lastTodayTarget) else { return nil }
        return try? JSONDecoder().decode(RunTarget.self, from: data)
    }
    private var cachedVoice: String {
        AppGroup.sharedDefaults?.string(forKey: AppGroup.Keys.lastTodayVoiceLine) ?? "Open Pace Off on iPhone."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("TARGET")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(cachedTarget.map { "\($0.displayedDistanceKm)" } ?? "—")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text("km")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(cachedVoice)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .padding(.bottom, 8)

                Button(action: start) {
                    Label("Start Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Pace Off")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.requestAuthorization() }
    }

    private func start() { session.start() }
}

#if DEBUG
#Preview("Watch Today") {
    NavigationStack {
        WatchTodayView()
            .environment(WorkoutSessionManager())
    }
}
#endif
