// NotificationScheduler.swift
// Schedules the three daily pushes per PRD §9.

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
public final class NotificationScheduler {

    public static let shared = NotificationScheduler()

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let voice = VoiceCopy()

    public private(set) var permissionGranted: Bool = false

    /// What the last scheduling call was given, so a settings change can
    /// reschedule today at once instead of waiting for the next refresh.
    private struct DayInputs {
        /// The calendar day these inputs were for; they're never replayed
        /// on another.
        let day: Date
        let target: RunTarget
        let yesterday: RunRecord?
        let currentStreak: Int
        let runs: [RunRecord]
        let plan: TrainingPlan?
        let planStatus: PlanDayStatus?
        let prescription: DayPrescription?
        let overrideBody: String?
    }
    @ObservationIgnored private var lastDay: DayInputs?

    private init() {}

    public func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            permissionGranted = granted
        } catch {
            permissionGranted = false
        }
    }

    /// Schedules today's pushes, plus tomorrow's morning fallback, and drops
    /// any earlier ones. Which pushes go out, when and with what text is
    /// `DailyPushPlanner`'s call; this only turns its answer into one-shot
    /// requests for their exact date, so a day's text never repeats on the
    /// next. The foreground refresh and the background task call this
    /// several times a day, so the pushes always reflect the latest Health
    /// sync.
    ///
    /// `overrideBody` lets the caller substitute an AI-rewritten line for the
    /// canned VoiceCopy text. Nothing is scheduled until onboarding is
    /// complete, so a signed-out user gets no pushes.
    public func scheduleDailyPushes(
        target: RunTarget,
        yesterday: RunRecord?,
        currentStreak: Int,
        runs: [RunRecord],
        plan: TrainingPlan?,
        planStatus: PlanDayStatus?,
        prescription: DayPrescription? = nil,
        overrideBody: String? = nil
    ) {
        lastDay = DayInputs(day: Calendar.current.startOfDay(for: Date()),
                            target: target, yesterday: yesterday, currentStreak: currentStreak,
                            runs: runs, plan: plan, planStatus: planStatus, prescription: prescription,
                            overrideBody: overrideBody)
        cancelDailyPushes()

        let defaults = AppGroup.sharedDefaults
        guard defaults?.bool(forKey: AppGroup.Keys.onboardingComplete) == true,
              DailyPushPlanner.pushesEnabled(in: defaults)
        else { return }

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: currentStreak,
                               planStatus: planStatus, prescription: prescription)
        let times = DailyPushPlanner.Schedule(
            morningHour: defaults?.integer(forKey: AppGroup.Keys.notificationMorningHour) ?? 0,
            afternoonHour: defaults?.integer(forKey: AppGroup.Keys.notificationAfternoonHour) ?? 0,
            eveningHour: defaults?.integer(forKey: AppGroup.Keys.notificationEveningHour) ?? 0
        )
        let pushes = DailyPushPlanner().pushes(for: DailyPushPlanner.Inputs(
            now: Date(),
            body: overrideBody ?? voice.notification(for: state),
            runs: runs,
            plan: plan,
            planStatus: planStatus,
            prescription: prescription,
            schedule: times
        ))

        for push in pushes {
            schedule(push)
        }
    }

    /// Reschedules today after a push time or the on/off switch changed:
    /// from the last scheduling call's inputs when they're today's, or
    /// else from a fresh refresh, so pushes are never rebuilt from another
    /// day's target and are never left at the old times.
    public func rescheduleToday() async {
        if let day = lastDay, Calendar.current.isDateInToday(day.day) {
            scheduleDailyPushes(target: day.target, yesterday: day.yesterday,
                                currentStreak: day.currentStreak, runs: day.runs,
                                plan: day.plan, planStatus: day.planStatus,
                                prescription: day.prescription, overrideBody: day.overrideBody)
        } else {
            await BackgroundRefreshService.shared.refreshHealthData()
        }
    }

    /// Today has no target (no run in Health yet): clear its pushes and
    /// forget its inputs, so a settings change can't bring them back.
    public func clearToday() {
        lastDay = nil
        cancelDailyPushes()
    }

    /// The Profile switch moved (it's already stored). Turning it on when
    /// iOS was never asked, after "Not now" in onboarding, asks now; then
    /// today's pushes follow the switch. Off clears every pending Pace Off
    /// notice, the plan-retune one included.
    public func pushesSwitched(on: Bool) async {
        if on {
            if await permission() == .notAsked { await requestAuthorization() }
            await rescheduleToday()
        } else {
            cancelDailyPushes()
            center.removePendingNotificationRequests(withIdentifiers: [Self.planRetunedId])
        }
    }

    /// Whether iOS lets Pace Off notify.
    public enum Permission: Sendable {
        case notAsked, allowed, denied
    }

    public func permission() async -> Permission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied:        return .denied
        default:             return .allowed
        }
    }

    /// One-shot notice that the background sync retuned the active plan's
    /// paces to the runner's current fitness. Fired at most once per retune
    /// (the caller gates on the drift threshold), and not with the pushes off.
    public func notifyPlanRetuned(fromVDOT old: Double, toVDOT new: Double) {
        guard DailyPushPlanner.pushesEnabled(in: AppGroup.sharedDefaults) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Training plan retuned"
        let direction = new > old ? "up" : "down"
        content.body = String(
            format: "Your fitness moved %@ (VDOT %.0f → %.0f). Remaining workouts now target your current paces.",
            direction, old, new
        )
        content.sound = .default
        content.threadIdentifier = "paceoff.plan"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: Self.planRetunedId, content: content, trigger: trigger)
        center.add(request)
    }

    private func schedule(_ push: DailyPush) {
        let content = UNMutableNotificationContent()
        content.title = "Pace Off"
        content.body = push.body
        content.sound = .default
        content.threadIdentifier = "paceoff.daily"

        // The full date, not just the time of day, and no repeat: the push
        // belongs to today only.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: push.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: Self.id(for: push.slot), content: content, trigger: trigger)
        center.add(request)
    }

    /// Removes today's scheduled pushes and leaves everything else. Called
    /// when there's no target to push for: no runs in Health yet.
    public func cancelDailyPushes() {
        center.removePendingNotificationRequests(withIdentifiers: Self.dailyIds)
    }

    /// Removes every scheduled and delivered Pace Off notification. Called
    /// on sign-out.
    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private static func id(for slot: DailyPush.Slot) -> String {
        "paceoff.notification.\(slot.rawValue)"
    }

    private static let dailyIds = DailyPush.Slot.allCases.map { NotificationScheduler.id(for: $0) }
    private static let planRetunedId = "paceoff.notification.planRetuned"
}
