// OpenTodayIntent.swift
// Opens Pace Off on Today. Compiled into the app and the widget extension:
// the Control Center control runs it, and the app switches to Today.

import AppIntents
import Foundation

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Today" }
    static var description: IntentDescription { IntentDescription("Opens Pace Off on Today.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .paceOffOpenToday, object: nil)
        return .result()
    }
}

extension Notification.Name {
    /// Posted when the runner asks for Today from outside the app.
    static let paceOffOpenToday = Notification.Name("PaceOffOpenToday")
}
