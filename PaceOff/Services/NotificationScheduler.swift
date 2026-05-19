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
    public func scheduleDailyPushes(
        target: RunTarget,
        yesterday: RunRecord?,
        currentStreak: Int,
        overrideBody: String? = nil
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningId, Self.afternoonId, Self.eveningId])

        let state = VoiceState(target: target, yesterday: yesterday, currentStreak: currentStreak)
        let body = overrideBody ?? voice.notification(for: state)

        let defaults = AppGroup.sharedDefaults
        let morningHour = defaults?.integer(forKey: AppGroup.Keys.notificationMorningHour) ?? 0
        let afternoonHour = defaults?.integer(forKey: AppGroup.Keys.notificationAfternoonHour) ?? 0
        let eveningHour = defaults?.integer(forKey: AppGroup.Keys.notificationEveningHour) ?? 0

        let morning = morningHour > 0 ? morningHour : 8
        let afternoon = afternoonHour > 0 ? afternoonHour : 17
        let evening = eveningHour > 0 ? eveningHour : 21

        // 08:00 — today's target
        schedule(id: Self.morningId, hour: morning, minute: 0, title: "Pace Off", body: body)

        // 17:30 — reminder if not started
        schedule(id: Self.afternoonId, hour: afternoon, minute: 30, title: "Pace Off", body: "Reminder: \(body)")

        // 21:00 — last call (only if 1+ days already skipped this week)
        if target.daysSinceLastRun >= 1 {
            schedule(id: Self.eveningId, hour: evening, minute: 0, title: "Pace Off", body: "Last call. \(body)")
        }
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
}
