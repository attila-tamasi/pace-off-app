// TodayViewModel.swift
// State container for the Today screen. Owns the latest computed RunTarget.

import Foundation
import SwiftUI
import CoreLocation
import Observation

@MainActor
@Observable
public final class TodayViewModel {

    public private(set) var target: RunTarget?
    public private(set) var voiceLine: String = "Sync with Apple Health to compute your push."
    public private(set) var notificationLine: String = ""
    public private(set) var yesterday: RunRecord?
    public private(set) var todayRun: RunRecord?
    public private(set) var currentVO2Max: Double?
    public private(set) var currentStreak: Int = 0
    public private(set) var userAge: Int?
    public private(set) var todayRouteCoordinates: [CLLocationCoordinate2D] = []
    public private(set) var isRefreshing: Bool = false

    // Yesterday's recovery snapshot — surfaced as the morning check-in card
    // at the top of the Today screen.
    public private(set) var yesterdayHRV: Double?
    public private(set) var yesterdayAvgHeartRate: Double?
    public private(set) var latestRestingHeartRate: Double?

    // Daily traffic light. Nil until there's enough HRV/RHR history to
    // trust a baseline — the card stays hidden rather than guessing.
    public private(set) var readiness: DailyReadiness?

    @ObservationIgnored private let engine = PushTargetEngine()
    @ObservationIgnored private let readinessEngine = ReadinessEngine()
    @ObservationIgnored private let voice = VoiceCopy()

    public init() {}

    /// Hydrate from the persisted `HealthDataCache` so the UI has something
    /// to render before the slow HealthKit reads return. No-op when no
    /// cache file exists yet (first launch).
    public func hydrateFromCache() async {
        guard let snapshot = await HealthDataCache.shared.load(),
              !snapshot.isEmpty
        else { return }
        applySnapshot(snapshot)
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Fire one parallel sync that writes the cache. Apply the result.
        let snapshot = await HealthKitService.shared.syncAll()
        applySnapshot(snapshot)

        // Today's GPS route — kept out of the cache because it's bulky and
        // only consumed by this view. Re-pulled on every refresh.
        self.todayRouteCoordinates = (self.todayRun != nil)
            ? await HealthKitService.shared.fetchTodayRunRoute()
            : []

        // applySnapshot always produces a non-nil target; this guard keeps the
        // compiler happy without changing the public type.
        guard let target else { return }
        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: currentStreak)
        let cannedCard = voice.todayCard(for: state)
        let cannedNotif = voice.notification(for: state)
        self.voiceLine = cannedCard
        self.notificationLine = cannedNotif

        // Try Apple Intelligence for a creative rewrite. Returns nil on
        // unsupported devices or when the model is busy — fall back silently.
        if let aiCard = await AppleIntelligenceCopy.shared.rewrite(cannedCard, kind: .todayCard) {
            self.voiceLine = aiCard
        }
        let notificationBody: String
        if let aiNotif = await AppleIntelligenceCopy.shared.rewrite(cannedNotif, kind: .notification) {
            self.notificationLine = aiNotif
            notificationBody = aiNotif
        } else {
            notificationBody = cannedNotif
        }

        // Cache for the widget
        if let data = try? JSONEncoder().encode(target) {
            AppGroup.sharedDefaults?.set(data, forKey: AppGroup.Keys.lastTodayTarget)
        }
        AppGroup.sharedDefaults?.set(self.voiceLine, forKey: AppGroup.Keys.lastTodayVoiceLine)

        // Plan-aware scheduling — the same reconciliation the background
        // refresh does, so foreground and background never disagree about
        // today's pushes. The in-memory plan is authoritative here; only
        // the background task re-reads disk.
        let planStatus = TrainingPlanStore.shared.activePlan.map {
            TrainingPlanReconciler().todayStatus(plan: $0, runs: snapshot.runs)
        }

        // Schedule today's notifications using the (possibly AI-rewritten) body.
        NotificationScheduler.shared.scheduleDailyPushes(
            target: target,
            yesterday: yesterday,
            currentStreak: currentStreak,
            planStatus: planStatus,
            overrideBody: notificationBody
        )
    }

    /// Recompute every derived property from a cached or freshly-synced
    /// snapshot. Shared by `hydrateFromCache` and `refresh`.
    private func applySnapshot(_ snapshot: HealthDataSnapshot) {
        let runs = snapshot.runs
        let vo2 = snapshot.vo2Max
        let rhr = snapshot.restingHR
        let now = Date()

        let inputs = PushTargetEngine.Inputs(
            today: now,
            runs: runs,
            vo2Max: vo2,
            restingHeartRate: rhr
        )
        let computed = engine.compute(inputs)
        self.target = computed
        self.readiness = readinessEngine.compute(
            ReadinessEngine.Inputs(today: now, hrv: snapshot.hrv, restingHeartRate: rhr)
        )
        self.yesterday = mostRecentRunBefore(today: now, in: runs)
        self.todayRun = mostRecentRunOn(day: now, in: runs)
        self.currentVO2Max = vo2.last?.value
        self.currentStreak = computeStreak(runs)
        self.userAge = snapshot.userAge ?? HealthKitService.shared.userAge()
        self.yesterdayHRV = snapshot.yesterdayHRV
        self.yesterdayAvgHeartRate = snapshot.yesterdayAvgHeartRate
        self.latestRestingHeartRate = snapshot.latestRestingHeartRate

        AppGroup.sharedDefaults?.set(self.todayRun != nil, forKey: AppGroup.Keys.runCompletedToday)
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

    #if DEBUG
    /// Factory for SwiftUI previews. Populates the view-model with sample
    /// state so the Today screen renders meaningful content in the canvas
    /// without hitting HealthKit or the push-target engine.
    static func preview(
        target: RunTarget? = .sample,
        voiceLine: String = "Easy 6K. Keep the pace conversational.",
        yesterday: RunRecord? = .sample,
        todayRun: RunRecord? = nil,
        vo2Max: Double? = 49.2,
        streak: Int = 3,
        age: Int? = 33,
        hrv: Double? = 62,
        avgHR: Double? = 68,
        restingHR: Double? = 51,
        readiness: DailyReadiness? = .sample
    ) -> TodayViewModel {
        let vm = TodayViewModel()
        vm.target = target
        vm.voiceLine = voiceLine
        vm.yesterday = yesterday
        vm.todayRun = todayRun
        vm.currentVO2Max = vo2Max
        vm.currentStreak = streak
        vm.userAge = age
        vm.yesterdayHRV = hrv
        vm.yesterdayAvgHeartRate = avgHR
        vm.latestRestingHeartRate = restingHR
        vm.readiness = readiness
        return vm
    }
    #endif
}
