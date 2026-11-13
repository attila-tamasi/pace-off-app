// SiriAnswer.swift
// What Siri and Shortcuts say for "What's my run today?" and "How ready am
// I?", from the day the app cached for the widget (`WidgetCache`). No
// HealthKit and no app launch: a day cached on an earlier date asks the
// runner to open the app, as the widget does. Pure and Sendable.

import Foundation

public enum SiriAnswer {

    public static let openApp = "Open Pace Off to get today's target."

    /// "Today's run: 8.0 km · 5:25–5:45/km.", "Rest day today.", "Today's
    /// run is done: 6 km."
    public static func runToday(_ cache: WidgetCache, units: UnitFormatter = .metric,
                                now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = cache.asOf(now, calendar: calendar)
        guard today.target != nil else { return openApp }
        if today.isStrengthOnlyDay, let strength = today.strengthSummary {
            return today.isPlanDayDone
                ? "Strength day, and the session is done."
                : "Strength day: \(strength). No run today."
        }
        if today.isPlanRestDay { return "Rest day today." }
        let run = today.planSummary ?? today.distanceText(in: units).map { "\($0) \(units.unit.symbol)" } ?? ""
        if today.runCompletedToday && (today.planSummary == nil || today.planCompletedToday) {
            return "Today's run is done: \(run)."
        }
        return "Today's run: \(run)."
    }

    /// "Ease off: HRV below your baseline — easy day."
    public static func readiness(_ cache: WidgetCache, now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = cache.asOf(now, calendar: calendar)
        guard today.target != nil else { return openApp }
        guard let level = today.readinessLevel, let sentence = today.readinessSentence else {
            return "No readiness today yet: it needs a reading from Apple Watch."
        }
        let label: String
        switch level {
        case .green: label = "Ready"
        case .yellow: label = "Ease off"
        case .red: label = "Rest"
        }
        return "\(label): \(sentence)"
    }
}
