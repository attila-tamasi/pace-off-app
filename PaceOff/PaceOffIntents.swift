// PaceOffIntents.swift
// Siri and Shortcuts: "What's my run today?" and "How ready am I?",
// answered from the day cached for the widget (`SiriAnswer`), without
// opening the app and without HealthKit.

import AppIntents
import Foundation

struct RunTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "Today's Run" }
    static var description: IntentDescription { IntentDescription("Says today's run from Pace Off: the plan's workout or the daily target.") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = SiriAnswer.runToday(WidgetCache.load(from: AppGroup.sharedDefaults))
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct ReadinessIntent: AppIntent {
    static var title: LocalizedStringResource { "Today's Readiness" }
    static var description: IntentDescription { IntentDescription("Says today's readiness from Pace Off and why.") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = SiriAnswer.readiness(WidgetCache.load(from: AppGroup.sharedDefaults))
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct PaceOffShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunTodayIntent(),
            phrases: [
                "What's my run today in \(.applicationName)",
                "What should I run today in \(.applicationName)",
                "\(.applicationName) today's run",
            ],
            shortTitle: "Today's Run",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: ReadinessIntent(),
            phrases: [
                "How ready am I in \(.applicationName)",
                "\(.applicationName) readiness",
            ],
            shortTitle: "Readiness",
            systemImageName: "heart.fill"
        )
    }
}
