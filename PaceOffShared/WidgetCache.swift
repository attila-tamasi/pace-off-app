// WidgetCache.swift
// The day's state the app hands the widget through App Group defaults, and
// how the widget reads it back at the moment it draws.

import Foundation

public struct WidgetCache: Equatable, Sendable {
    public var target: RunTarget?
    public var voiceLine: String?
    public var runCompletedToday: Bool
    /// Today's plan workout headline ("8.0 km · 5:25–5:45/km", "Rest").
    /// Nil when no plan is active.
    public var planSummary: String?
    /// Whether a recorded run already covered today's plan workout.
    public var planCompletedToday: Bool

    public init(target: RunTarget? = nil,
                voiceLine: String? = nil,
                runCompletedToday: Bool = false,
                planSummary: String? = nil,
                planCompletedToday: Bool = false) {
        self.target = target
        self.voiceLine = voiceLine
        self.runCompletedToday = runCompletedToday
        self.planSummary = planSummary
        self.planCompletedToday = planCompletedToday
    }

    public static let empty = WidgetCache()

    public var isPlanRestDay: Bool { planSummary == Workout.rest.summary }

    // MARK: - Reading it at a moment

    /// The cache as the widget should draw it at `now`. Everything is
    /// written together with the target, so a target computed on an earlier
    /// day dates the lot: it all goes, and the widget asks the runner to
    /// open the app instead of passing yesterday off as today.
    public func asOf(_ now: Date, calendar: Calendar = .current) -> WidgetCache {
        guard let target, calendar.isDate(target.computedAt, inSameDayAs: now) else { return .empty }
        return self
    }

    public enum Dot: Equatable, Sendable {
        /// No target for today.
        case neutral
        /// Today's run or plan workout is done, or it's a planned rest day.
        case green
        /// Still to run, before noon.
        case orange
        /// Still to run, from noon on.
        case red
    }

    public func dot(at now: Date, calendar: Calendar = .current) -> Dot {
        let today = asOf(now, calendar: calendar)
        guard today.target != nil else { return .neutral }
        if today.runCompletedToday || today.planCompletedToday || today.isPlanRestDay { return .green }
        return calendar.component(.hour, from: now) >= 12 ? .red : .orange
    }

    /// The moments from `now` on where the widget's look changes with no new
    /// data: `now`, noon (the dot turns red) while it's still ahead, and
    /// midnight (today's cache goes stale).
    public static func timelineDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now), noon > now {
            dates.append(noon)
        }
        if let midnight = calendar.dateInterval(of: .day, for: now)?.end {
            dates.append(midnight)
        }
        return dates
    }

    // MARK: - App Group defaults

    /// Writes every field, so the widget never mixes two refreshes.
    public func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        if let target, let data = try? JSONEncoder().encode(target) {
            defaults.set(data, forKey: AppGroup.Keys.lastTodayTarget)
        } else {
            defaults.removeObject(forKey: AppGroup.Keys.lastTodayTarget)
        }
        if let voiceLine {
            defaults.set(voiceLine, forKey: AppGroup.Keys.lastTodayVoiceLine)
        } else {
            defaults.removeObject(forKey: AppGroup.Keys.lastTodayVoiceLine)
        }
        defaults.set(runCompletedToday, forKey: AppGroup.Keys.runCompletedToday)
        if let planSummary {
            defaults.set(planSummary, forKey: AppGroup.Keys.lastPlanWorkoutSummary)
        } else {
            defaults.removeObject(forKey: AppGroup.Keys.lastPlanWorkoutSummary)
        }
        defaults.set(planCompletedToday, forKey: AppGroup.Keys.planWorkoutCompletedToday)
    }

    public static func load(from defaults: UserDefaults?) -> WidgetCache {
        guard let defaults else { return .empty }
        let target = defaults.data(forKey: AppGroup.Keys.lastTodayTarget)
            .flatMap { try? JSONDecoder().decode(RunTarget.self, from: $0) }
        return WidgetCache(
            target: target,
            voiceLine: defaults.string(forKey: AppGroup.Keys.lastTodayVoiceLine),
            runCompletedToday: defaults.bool(forKey: AppGroup.Keys.runCompletedToday),
            planSummary: defaults.string(forKey: AppGroup.Keys.lastPlanWorkoutSummary),
            planCompletedToday: defaults.bool(forKey: AppGroup.Keys.planWorkoutCompletedToday)
        )
    }
}
