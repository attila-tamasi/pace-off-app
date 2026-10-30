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

    private init() {}

    public func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            permissionGranted = granted
        } catch {
            permissionGranted = false
        }
    }

    /// Schedules today's pushes and drops any earlier ones. Which pushes go
    /// out, when and with what text is `DailyPushPlanner`'s call; this only
    /// turns its answer into one-shot requests for today's date, so a day's
    /// text never repeats on the next. The foreground refresh and the
    /// background task call this several times a day, so the pushes always
    /// reflect the latest Health sync.
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
        overrideBody: String? = nil
    ) {
        center.removePendingNotificationRequests(withIdentifiers: Self.dailyIds)

        let defaults = AppGroup.sharedDefaults
        guard defaults?.bool(forKey: AppGroup.Keys.onboardingComplete) == true else { return }

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: currentStreak)
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
            schedule: times
        ))

        for push in pushes {
            schedule(push)
        }
    }

    /// One-shot notice that the background sync retuned the active plan's
    /// paces to the runner's current fitness. Fired at most once per retune
    /// (the caller gates on the drift threshold).
    public func notifyPlanRetuned(fromVDOT old: Double, toVDOT new: Double) {
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
