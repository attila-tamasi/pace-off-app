// TodayViewModel.swift
// State container for the Today screen. Owns the latest computed RunTarget.

import Foundation
import SwiftUI

@MainActor
public final class TodayViewModel: ObservableObject {

    @Published public private(set) var target: RunTarget?
    @Published public private(set) var voiceLine: String = "Sync with Apple Health to compute your push."
    @Published public private(set) var notificationLine: String = ""
    @Published public private(set) var yesterday: RunRecord?
    @Published public private(set) var todayRun: RunRecord?
    @Published public private(set) var currentVO2Max: Double?
    @Published public private(set) var currentStreak: Int = 0
    @Published public private(set) var userAge: Int?
    @Published public private(set) var isRefreshing: Bool = false

    private let engine = PushTargetEngine()
    private let voice = VoiceCopy()

    public init() {}

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let runs = await HealthKitService.shared.fetchRuns(daysBack: 90)
        let vo2 = await HealthKitService.shared.fetchVO2Max(daysBack: 90)
        let rhr = await HealthKitService.shared.fetchRestingHeartRate(daysBack: 14)

        let inputs = PushTargetEngine.Inputs(
            today: Date(),
            runs: runs,
            vo2Max: vo2,
            restingHeartRate: rhr
        )
        let computed = engine.compute(inputs)
        self.target = computed
        self.yesterday = mostRecentRunBefore(today: Date(), in: runs)
        self.todayRun = mostRecentRunOn(day: Date(), in: runs)
        self.currentVO2Max = vo2.last?.value
        self.currentStreak = computeStreak(runs)
        self.userAge = HealthKitService.shared.userAge()

        // Mark "ran today" so the notification scheduler can suppress the evening push.
        AppGroup.sharedDefaults?.set(self.todayRun != nil, forKey: AppGroup.Keys.runCompletedToday)

        let state = VoiceState(target: computed, yesterday: yesterday, currentStreak: currentStreak)
        self.voiceLine = voice.todayCard(for: state)
        self.notificationLine = voice.notification(for: state)

        // Cache for the widget
        if let data = try? JSONEncoder().encode(computed) {
            AppGroup.sharedDefaults?.set(data, forKey: AppGroup.Keys.lastTodayTarget)
        }
        AppGroup.sharedDefaults?.set(self.voiceLine, forKey: AppGroup.Keys.lastTodayVoiceLine)

        // Schedule today's notifications
        NotificationScheduler.shared.scheduleDailyPushes(
            target: computed,
            yesterday: yesterday,
            currentStreak: currentStreak
        )
    }

    private func mostRecentRunBefore(today: Date, in runs: [RunRecord]) -> RunRecord? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        return runs
            .filter { $0.startDate < startOfToday }
            .max(by: { $0.startDate < $1.startDate })
    }

    /// Most recent run that started on the given calendar day (or nil).
    /// If the user did multiple runs today, returns the longest one — that's what
    /// the user is most likely thinking about when they open the app.
    private func mostRecentRunOn(day: Date, in runs: [RunRecord]) -> RunRecord? {
        let cal = Calendar.current
        return runs
            .filter { cal.isDate($0.startDate, inSameDayAs: day) }
            .max(by: { $0.distanceMeters < $1.distanceMeters })
    }

    private func computeStreak(_ runs: [RunRecord]) -> Int {
        let cal = Calendar.current
        let dates = Set(runs.map { cal.startOfDay(for: $0.startDate) })
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        while dates.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
