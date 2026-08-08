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

    /// Schedules today's three pushes based on the computed target. Replaces any prior daily notifications.
    /// `overrideBody` lets the caller substitute an AI-rewritten line for the canned VoiceCopy text.
    ///
    /// `planStatus` makes the pushes plan-aware. The scheduling is refreshed
    /// several times a day (foreground refresh + BGAppRefreshTask), so the
    /// decisions below always reflect the latest Health sync:
    /// - active plan day → the morning/afternoon bodies lead with the
    ///   prescribed workout, not just the push-target line
    /// - planned rest day → no afternoon reminder, no evening "last call" —
    ///   the plan told the runner to sit down, so we don't nag
    /// - plan workout already completed → reminder + last call are dropped
    ///   for the rest of the day
    public func scheduleDailyPushes(
        target: RunTarget,
        yesterday: RunRecord?,
        currentStreak: Int,
        planStatus: PlanDayStatus? = nil,
        overrideBody: String? = nil
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningId, Self.afternoonId, Self.eveningId])

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: currentStreak)
        var body = overrideBody ?? voice.notification(for: state)

        let isPlanRestDay = planStatus?.isRestDay ?? false
        let planDone = planStatus?.isCompleted ?? false
        if let workout = planStatus?.workout, !isPlanRestDay {
            body = "Today's plan: \(workout.summary). \(body)"
        }

        let defaults = AppGroup.sharedDefaults
        let morningHour = defaults?.integer(forKey: AppGroup.Keys.notificationMorningHour) ?? 0
        let afternoonHour = defaults?.integer(forKey: AppGroup.Keys.notificationAfternoonHour) ?? 0
        let eveningHour = defaults?.integer(forKey: AppGroup.Keys.notificationEveningHour) ?? 0

        let morning = morningHour > 0 ? morningHour : 8
        let afternoon = afternoonHour > 0 ? afternoonHour : 17
        let evening = eveningHour > 0 ? eveningHour : 21

        // 08:00 — today's target (or the plan's rest-day note)
        let morningBody = isPlanRestDay
            ? "Rest day on your plan. Recovery is training too."
            : body
        schedule(id: Self.morningId, hour: morning, minute: 0, title: "Pace Off", body: morningBody)

        // 17:30 — reminder if not started. Skipped on planned rest days and
        // once the plan workout is in the books.
        if !isPlanRestDay && !planDone {
            schedule(id: Self.afternoonId, hour: afternoon, minute: 30, title: "Pace Off", body: "Reminder: \(body)")
        }

        // 21:00 — last call (only if 1+ days already skipped this week)
        if target.daysSinceLastRun >= 1 && !isPlanRestDay && !planDone {
            schedule(id: Self.eveningId, hour: evening, minute: 0, title: "Pace Off", body: "Last call. \(body)")
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

    private func schedule(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "paceoff.daily"

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private static let morningId = "paceoff.notification.morning"
    private static let afternoonId = "paceoff.notification.afternoon"
    private static let eveningId = "paceoff.notification.evening"
    private static let planRetunedId = "paceoff.notification.planRetuned"
}
