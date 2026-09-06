// BackgroundRefreshService.swift
// Periodic Apple-Health → today-target refresh while the app is suspended.
//
// We register a single BGAppRefreshTask identifier (`com.paceoff.app.refresh`,
// declared in Info.plist's `BGTaskSchedulerPermittedIdentifiers`) and ask iOS
// to run it every ~6 hours. iOS doesn't honor exact times — it bundles the
// request with other system refresh windows and tries to fire it 3–4× per day
// based on user habits, charging state, and network conditions.
//
// Each run:
//   1. Pulls fresh runs / VO₂ max / RHR / HRV from HealthKit
//   2. Recomputes the RunTarget and voice copy
//   3. Reconciles the active training plan: marks today's planned workout
//      done/pending and retunes remaining pace bands when the runner's
//      VDOT has drifted from the plan's anchor
//   4. Persists everything to App Group UserDefaults so the widget and the
//      next app launch see it instantly
//   5. Reschedules the daily notifications (plan-aware) and the next
//      BGAppRefreshTask
//
// We intentionally use BGAppRefreshTask (not BGProcessingTask): app-refresh
// has a ~30s wall-clock budget and runs frequently, which matches "fetch a
// few HealthKit summaries and update a cache" perfectly.

import Foundation
import BackgroundTasks
import os

@MainActor
public final class BackgroundRefreshService {

    public static let shared = BackgroundRefreshService()

    /// Must match the identifier in Info.plist → BGTaskSchedulerPermittedIdentifiers.
    /// `nonisolated` because `register()` runs before any actor exists and
    /// must read it from a non-MainActor context.
    public nonisolated static let taskIdentifier = "com.paceoff.app.refresh"

    /// Earliest moment iOS may run the next refresh. ~6 hours gives the system
    /// ~4 wake-up opportunities per day; iOS picks the actual moment.
    nonisolated private static let refreshInterval: TimeInterval = 6 * 60 * 60

    private let log = Logger(subsystem: "com.paceoff.app", category: "BackgroundRefresh")

    private init() {}

    // MARK: - Registration

    /// Register the BGTask handler. Must be called from `App.init()` —
    /// BGTaskScheduler refuses registrations after the app finishes launching.
    public nonisolated func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // BGAppRefreshTask is an Obj-C class and not Sendable, but
            // BGTask is documented to be thread-safe — Apple's whole design
            // is that you hop off the system handler queue to do work.
            // `nonisolated(unsafe)` is the right bridge here.
            nonisolated(unsafe) let captured = refreshTask
            Task { @MainActor in
                await Self.shared.handle(captured)
            }
        }
    }

    // MARK: - Scheduling

    /// Ask iOS to run our refresh task again after `refreshInterval` has
    /// elapsed. Safe to call multiple times — iOS coalesces requests.
    public func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("Scheduled next background refresh ≥ \(Self.refreshInterval/3600, privacy: .public)h from now")
        } catch {
            // Most common cause: running in the simulator (BGTaskScheduler is
            // a no-op there) or BGTaskScheduler entitlement missing.
            log.error("Failed to schedule background refresh: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Handler

    private func handle(_ task: BGAppRefreshTask) async {
        // Always queue the next refresh first — if our work overruns the
        // wall-clock budget and gets killed, we still want another wake-up.
        scheduleNext()

        let work = Task { @MainActor in
            await refreshHealthData()
        }

        // iOS gives us a hard deadline; if we get cancelled mid-flight, kill
        // the work cleanly and report failure so iOS can back off.
        task.expirationHandler = {
            work.cancel()
        }

        let success = await work.value
        task.setTaskCompleted(success: success)
    }

    /// The actual refresh. Returns true on success, false on cancellation/error.
    /// Reused by `runOnceNow()` for "manual" foreground refreshes.
    @discardableResult
    public func refreshHealthData() async -> Bool {
        // syncAll writes the snapshot to HealthDataCache as a side effect,
        // so the next foreground launch picks it up instantly.
        let snapshot = await HealthKitService.shared.syncAll()
        if Task.isCancelled { return false }

        let runs = snapshot.runs
        let vo2 = snapshot.vo2Max
        let rhr = snapshot.restingHR

        // Same readiness → target pipeline the foreground refresh uses.
        let readiness = ReadinessEngine().compute(
            ReadinessEngine.Inputs(today: Date(), hrv: snapshot.hrv, restingHeartRate: rhr)
        )

        let inputs = PushTargetEngine.Inputs(
            today: Date(),
            runs: runs,
            vo2Max: vo2,
            restingHeartRate: rhr,
            readiness: readiness?.level
        )
        let target = PushTargetEngine().compute(inputs)

        let yesterday = mostRecentRunBefore(today: Date(), in: runs)
        let todayRun = mostRecentRunOn(day: Date(), in: runs)
        let streak = computeStreak(runs)

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: streak)
        let voice = VoiceCopy()
        var voiceLine = voice.todayCard(for: state)
        var notificationLine = voice.notification(for: state)

        // Optional Apple Intelligence pass — rewrites the canned line in a
        // more creative voice on devices that support it. Time-boxed so we
        // never blow our 30s budget.
        if let aiCard = await AppleIntelligenceCopy.shared.rewrite(voiceLine, kind: .todayCard) {
            voiceLine = aiCard
        }
        if let aiNotif = await AppleIntelligenceCopy.shared.rewrite(notificationLine, kind: .notification) {
            notificationLine = aiNotif
        }

        // Cache for the widget + next app launch.
        if let data = try? JSONEncoder().encode(target) {
            AppGroup.sharedDefaults?.set(data, forKey: AppGroup.Keys.lastTodayTarget)
        }
        AppGroup.sharedDefaults?.set(voiceLine, forKey: AppGroup.Keys.lastTodayVoiceLine)
        AppGroup.sharedDefaults?.set(todayRun != nil, forKey: AppGroup.Keys.runCompletedToday)

        // Training plan: reconcile today's workout and retune stale paces
        // against the data we just pulled.
        let planStatus = reconcileTrainingPlan(runs: runs, vo2Max: vo2)

        // Reschedule today's notifications with the freshly enriched body so
        // the user gets the updated copy on the next push.
        NotificationScheduler.shared.scheduleDailyPushes(
            target: target,
            yesterday: yesterday,
            currentStreak: streak,
            planStatus: planStatus,
            overrideBody: notificationLine
        )

        log.info("Background refresh completed — target=\(target.displayedDistanceKm)km")
        return true
    }

    // MARK: - Training plan reconciliation

    /// Sync the active plan with fresh Health data. Returns today's plan
    /// status (nil when no plan is active) so notification scheduling can
    /// be plan-aware.
    ///
    /// Retuning: the plan's paces were anchored to a VDOT captured at
    /// generation time. When the runner's current VDOT (fresh VO₂ max, or
    /// their PB) has drifted past the reconciler's threshold, the remaining
    /// weeks are re-paced and the user gets a one-shot notification. The
    /// beginner-default fallback VDOT never overwrites a real anchor.
    private func reconcileTrainingPlan(runs: [RunRecord], vo2Max: [VO2MaxSnapshot]) -> PlanDayStatus? {
        let store = TrainingPlanStore.shared
        store.load() // re-read disk — the app may have written since our launch
        guard let plan = store.activePlan else {
            AppGroup.sharedDefaults?.removeObject(forKey: AppGroup.Keys.lastPlanWorkoutSummary)
            AppGroup.sharedDefaults?.set(false, forKey: AppGroup.Keys.planWorkoutCompletedToday)
            return nil
        }

        let reconciler = TrainingPlanReconciler()
        let status = reconciler.todayStatus(plan: plan, runs: runs, today: Date())

        // Cache for the widget / next cold launch.
        if let summary = status.workout?.summary {
            AppGroup.sharedDefaults?.set(summary, forKey: AppGroup.Keys.lastPlanWorkoutSummary)
        } else {
            AppGroup.sharedDefaults?.removeObject(forKey: AppGroup.Keys.lastPlanWorkoutSummary)
        }
        AppGroup.sharedDefaults?.set(status.isCompleted, forKey: AppGroup.Keys.planWorkoutCompletedToday)

        // Resolve the runner's current VDOT the same way the picker does.
        // The profile's PB only applies when it's for the plan's distance.
        let profile = ProfileStore.shared.profile
        let pb = (profile?.goal == plan.goal) ? profile?.personalBest : nil
        let inputs = TrainingPlanInputs(
            goal: plan.goal,
            tier: plan.tier,
            longRunDay: plan.longRunDay,
            vo2Max: vo2Max.last?.value,
            personalBest: pb
        )
        let (currentVDOT, usedFallback) = TrainingPlanGenerator().resolveVDOT(inputs)
        guard !usedFallback else { return status }

        if let retuned = reconciler.retunedPlan(plan, toVDOT: currentVDOT, today: Date()) {
            store.setActive(retuned)
            if abs(currentVDOT - plan.vdot) >= TrainingPlanReconciler.vdotDriftThreshold {
                NotificationScheduler.shared.notifyPlanRetuned(fromVDOT: plan.vdot, toVDOT: currentVDOT)
            }
            log.info("Retuned training plan paces: VDOT \(plan.vdot, privacy: .public) → \(currentVDOT, privacy: .public)")
        }
        return status
    }

    // MARK: - Helpers (mirror TodayViewModel)

    private func mostRecentRunBefore(today: Date, in runs: [RunRecord]) -> RunRecord? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        return runs
            .filter { $0.startDate < startOfToday }
            .max(by: { $0.startDate < $1.startDate })
    }

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
