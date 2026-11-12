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
import WidgetKit
import UIKit
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

        // iOS gives us a hard deadline. When it hits, cancel the work and
        // report the task done right there, failed, so iOS can back off;
        // the work may not notice the cancellation before the deadline.
        // Whichever finishes first reports, once.
        let report = TaskReport(task)
        task.expirationHandler = {
            work.cancel()
            report.complete(success: false)
        }

        let success = await work.value
        report.complete(success: success)
    }

    /// Reports a background task complete exactly once, from whichever of
    /// the work and the expiration handler gets there first.
    private final class TaskReport: @unchecked Sendable {
        private let task: BGTask
        private let once = OnceFlag()

        init(_ task: BGTask) {
            self.task = task
        }

        func complete(success: Bool) {
            if once.claim() { task.setTaskCompleted(success: success) }
        }
    }

    // MARK: - Health observers

    private var observerRefresh: Task<Void, Never>?
    /// Set when a delivery arrives during a refresh that may already have
    /// read Health: the running refresh goes round once more.
    private var refreshAgain = false
    /// Whether the last refresh found Health locked (the phone was), so
    /// it read nothing.
    private var lastReadWasLocked = false

    /// Starts the workout and VO₂ max observers. A new run or reading
    /// re-syncs Health, recomputes the target, reschedules today's pushes
    /// and reloads the widget, the same as a scheduled background refresh,
    /// so a finished run stops the afternoon reminder without the app
    /// being opened. Changes that arrive during a refresh share it.
    public func startHealthObservers() {
        HealthKitService.shared.startObservingHealthUpdates { done in
            Task { @MainActor in
                await BackgroundRefreshService.shared.handleDelivery(done)
            }
        }
    }

    /// One observer delivery. In the foreground there's nothing to do: the
    /// app refreshes whenever it becomes active. In the background, run the
    /// refresh under a background-time assertion. A delivery that found
    /// the phone locked read nothing, so it isn't acknowledged: HealthKit
    /// then delivers it again, with backoff, until a read gets through.
    private func handleDelivery(_ done: HealthUpdateCompletion) async {
        guard UIApplication.shared.applicationState == .background else {
            done()
            return
        }
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Health update")
        await refreshForObserver()
        if !lastReadWasLocked { done() }
        if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
    }

    private func refreshForObserver() async {
        if let running = observerRefresh {
            // The running refresh may have read Health before this change.
            refreshAgain = true
            await running.value
            return
        }
        let refresh = Task { @MainActor in
            repeat {
                self.refreshAgain = false
                _ = await self.refreshHealthData()
            } while self.refreshAgain
        }
        observerRefresh = refresh
        await refresh.value
        observerRefresh = nil
    }

    /// The actual refresh. Returns true on success, false on cancellation/error.
    /// Reused by `runOnceNow()` for "manual" foreground refreshes.
    @discardableResult
    public func refreshHealthData() async -> Bool {
        // Signed out or not yet set up: nothing to compute, push or show.
        guard AppGroup.isRunnerSetUp else {
            lastReadWasLocked = false
            return true
        }

        // syncAll writes the snapshot to HealthDataCache as a side effect,
        // so the next foreground launch picks it up instantly.
        let sync = await HealthKitService.shared.syncAll()
        lastReadWasLocked = sync.decision == .keepCache(.protectedDataUnavailable)
        if Task.isCancelled { return false }
        // Deleted or signed out while the read ran.
        guard AppGroup.isRunnerSetUp else { return true }

        // On a locked phone, or when the read failed or came back empty,
        // the cache was kept and this run learned nothing new. Change
        // nothing: no target, no plan retune, no rescheduled pushes. Redoing
        // them from the kept cache after midnight would call yesterday a
        // skip whenever the cache predates yesterday's run; the next-morning
        // push already covers a night without a refresh.
        guard sync.isFresh, let snapshot = sync.snapshot else {
            if case .keepCache(let reason) = sync.decision {
                log.info("Health read not used (\(reason.rawValue, privacy: .public)); cache, widget and pushes left as they were")
            }
            return true
        }

        let runs = snapshot.runs
        let vo2 = snapshot.vo2Max
        let rhr = snapshot.restingHR
        // One clock reading, so a refresh across midnight can't mix two days.
        let now = Date()

        // Same readiness → target pipeline the foreground refresh uses.
        let readiness = ReadinessEngine().compute(
            ReadinessEngine.Inputs(today: now, hrv: snapshot.hrv, restingHeartRate: rhr, sleep: snapshot.sleepOrEmpty)
        )

        let inputs = PushTargetEngine.Inputs(
            today: now,
            runs: runs,
            vo2Max: vo2,
            restingHeartRate: rhr,
            readiness: readiness?.level
        )
        // A runner never seen to run: nothing to target or push. Clear any
        // pushes left from an earlier day; Today shows how to log a first run.
        let defaults = AppGroup.sharedDefaults
        if !runs.isEmpty { defaults?.set(true, forKey: AppGroup.Keys.hasSeenRun) }
        guard let target = PushTargetEngine().target(
            inputs, hasRunBefore: defaults?.bool(forKey: AppGroup.Keys.hasSeenRun) ?? false
        ) else {
            NotificationScheduler.shared.clearToday()
            log.info("Background refresh completed — no runs yet, no target")
            return true
        }

        let yesterday = mostRecentRunBefore(today: now, in: runs)
        let todayRun = mostRecentRunOn(day: now, in: runs)
        let streak = RunStreak.current(runs: runs, today: now)

        // Training plan: reconcile today's workout and retune stale paces
        // against the data we just pulled. The voice line needs today's
        // status too.
        if Task.isCancelled { return false }
        let planStatus = reconcileTrainingPlan(runs: runs, strengthWorkouts: snapshot.strengthWorkoutsOrEmpty,
                                               vo2Max: vo2, now: now)

        let activePlan = TrainingPlanStore.shared.activePlan
        let prescription = DayPrescription.make(
            planStatus: planStatus,
            readiness: readiness?.level,
            target: target,
            easyPace: activePlan.flatMap { DayPrescription.easyPaceBand(in: $0, today: now) },
            longestRunTodayMeters: DayPrescription.longestRun(on: now, in: runs),
            singleRunCapMeters: SingleRunCap.capMeters(runs: runs, today: now)
        )

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: streak,
                               planStatus: planStatus, prescription: prescription)
        let voice = VoiceCopy()
        // The canned lines: the system rate-limits the on-device model in
        // the background, so the Apple Intelligence rewrite happens only in
        // the foreground refresh.
        let voiceLine = voice.todayCard(for: state)
        let notificationLine = voice.notification(for: state)

        if Task.isCancelled { return false }

        // Hand the day to the widget in one write, and have it redraw.
        let day = WidgetCache(target: target, voiceLine: voiceLine,
                              runCompletedToday: todayRun != nil, planStatus: planStatus,
                              prescription: prescription)
        if day.save(to: AppGroup.sharedDefaults) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        await RunLedger.shared.record(prescription: prescription, readiness: readiness?.level, runs: runs)

        // Reschedule today's notifications with the freshly enriched body so
        // the user gets the updated copy on the next push.
        NotificationScheduler.shared.scheduleDailyPushes(
            target: target,
            yesterday: yesterday,
            currentStreak: streak,
            runs: runs,
            plan: activePlan,
            planStatus: planStatus,
            prescription: prescription,
            overrideBody: notificationLine
        )
        await WatchWorkoutScheduler.shared.sync(prescription: prescription)

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
    /// beginner-default fallback VDOT never overwrites a real anchor. A plan
    /// that hasn't started yet is rebuilt instead, without a push. Only
    /// called with a fresh Health read, so a locked-phone read never retunes.
    private func reconcileTrainingPlan(runs: [RunRecord], strengthWorkouts: [StrengthWorkout],
                                       vo2Max: [VO2MaxSnapshot], now: Date) -> PlanDayStatus? {
        let store = TrainingPlanStore.shared
        store.load() // re-read disk — the app may have written since our launch
        guard let plan = store.activePlan else { return nil }

        let reconciler = TrainingPlanReconciler()
        let status = reconciler.todayStatus(plan: plan, runs: runs, strengthWorkouts: strengthWorkouts, today: now)

        // Resolve the runner's current VDOT the same way the picker does.
        // The PB counts whatever its distance: its VDOT is distance-free.
        let pb = ProfileStore.shared.profile?.personalBest
        let bests = BestEffortLog.load(from: AppGroup.sharedDefaults).bests

        // A plan that hasn't started is rebuilt from today's data, quietly:
        // there's nothing the runner has to change yet.
        if plan.startsLater(today: now) {
            if let rebuilt = reconciler.rebuiltBeforeStart(
                plan,
                vo2Max: vo2Max.last?.value,
                personalBest: pb,
                bestEfforts: bests,
                recentLongestRunMeters: TrainingPlanGenerator.longestRecentRunMeters(in: runs, today: now),
                today: now
            ) {
                store.setActive(rebuilt)
                log.info("Rebuilt the training plan before its start")
            }
            return status
        }

        let inputs = TrainingPlanInputs(
            goal: plan.goal,
            tier: plan.tier,
            longRunDay: plan.longRunDay,
            vo2Max: vo2Max.last?.value,
            personalBest: pb,
            bestEfforts: bests,
            today: now
        )
        let resolution = TrainingPlanGenerator().resolvePaces(inputs)
        guard !resolution.usedFallback else { return status }
        let currentVDOT = resolution.vdot

        if let retuned = reconciler.retunedPlan(plan, toVDOT: currentVDOT, source: resolution.source, today: now) {
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
}
