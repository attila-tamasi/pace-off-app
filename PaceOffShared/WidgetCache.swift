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
    /// Today's strength session ("Kettlebell · 35 min"), nil without one.
    public var strengthSummary: String?
    /// Whether a strength workout in Health already covered it.
    public var strengthCompletedToday: Bool
    /// The day's prescribed distance in km (`DayPrescription`): the plan's
    /// run as readiness left it, or the daily target. Nil on a rest day,
    /// and in a cache written before it existed, where the target's whole
    /// km stand in.
    public var dayDistanceKm: Double?

    public init(target: RunTarget? = nil,
                voiceLine: String? = nil,
                runCompletedToday: Bool = false,
                planSummary: String? = nil,
                planCompletedToday: Bool = false,
                strengthSummary: String? = nil,
                strengthCompletedToday: Bool = false,
                dayDistanceKm: Double? = nil) {
        self.target = target
        self.voiceLine = voiceLine
        self.runCompletedToday = runCompletedToday
        self.planSummary = planSummary
        self.planCompletedToday = planCompletedToday
        self.strengthSummary = strengthSummary
        self.strengthCompletedToday = strengthSummary != nil && strengthCompletedToday
        self.dayDistanceKm = dayDistanceKm
    }

    /// The day as a refresh computed it, with today's plan status (nil
    /// when no plan is active).
    ///
    /// With the day's `prescription`, the plan line names the plan's run as
    /// readiness changed it, the plan counts as done once that run is, and
    /// the widget shows the prescription's distance.
    public init(target: RunTarget,
                voiceLine: String,
                runCompletedToday: Bool,
                planStatus: PlanDayStatus?,
                prescription: DayPrescription? = nil) {
        let planDay = prescription?.source == .plan ? prescription : nil
        let planRun = planDay?.kind == .run ? planDay : nil
        // Unwell: the widget shows rest, with or without a plan.
        let unwell = prescription?.adjustment == .restForUnwell
        self.init(target: target,
                  voiceLine: voiceLine,
                  runCompletedToday: runCompletedToday,
                  planSummary: unwell ? Workout.rest.summary : planRun?.summary ?? planStatus?.workout?.headline,
                  planCompletedToday: unwell ? false : planRun?.isDone ?? planStatus?.isCompleted ?? false,
                  strengthSummary: unwell ? nil : planStatus?.strength?.summary,
                  strengthCompletedToday: planStatus?.isStrengthCompleted ?? false,
                  dayDistanceKm: prescription?.distanceKm)
    }

    public static let empty = WidgetCache()

    public var isPlanRestDay: Bool { planSummary == Workout.rest.summary }

    /// The distance the widget shows: "8", "10.8". Nil on a plan rest day
    /// and with no target.
    public var distanceText: String? {
        guard let target, !isPlanRestDay else { return nil }
        return dayDistanceKm.map(DayPrescription.formatKm) ?? "\(target.displayedDistanceKm)"
    }

    /// A planned day without a run but with a strength session.
    public var isStrengthOnlyDay: Bool { isPlanRestDay && strengthSummary != nil }

    /// The plan's day is done: its run, or on a strength-only day its
    /// session (or a run the runner did instead). False without a plan.
    public var isPlanDayDone: Bool {
        isStrengthOnlyDay ? strengthCompletedToday || runCompletedToday : planCompletedToday
    }

    /// The widget's plan line: "Plan: 8.0 km · 5:25–5:45/km", with " ✓"
    /// once a run covered it and " + strength" when a session follows;
    /// "Strength: Kettlebell · 35 min" on a strength-only day; "Rest day"
    /// on planned rest. Nil when no plan is active.
    public var planLine: String? {
        guard let planSummary else { return nil }
        let tick = strengthCompletedToday ? " ✓" : ""
        if isPlanRestDay {
            return strengthSummary.map { "Strength: \($0)\(tick)" } ?? "Rest day"
        }
        let line = planCompletedToday ? "Plan: \(planSummary) ✓" : "Plan: \(planSummary)"
        return strengthSummary == nil ? line : "\(line) + strength\(tick)"
    }

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
        /// Today's run or plan workout is done, it's a planned rest day, or
        /// a strength-only day's session is logged.
        case green
        /// Still to run, before noon.
        case orange
        /// Still to run, from noon on.
        case red
    }

    public func dot(at now: Date, calendar: Calendar = .current) -> Dot {
        let today = asOf(now, calendar: calendar)
        guard today.target != nil else { return .neutral }
        if today.isStrengthOnlyDay {
            if today.isPlanDayDone { return .green }
        } else if today.runCompletedToday || today.planCompletedToday || today.isPlanRestDay {
            return .green
        }
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

    /// Writes every field, so the widget never mixes two refreshes. A day
    /// computed later than this one, already stored by a refresh that
    /// finished first, is kept: nothing is written and the result is false.
    /// A stored day stamped after `now` (the clock was set back) doesn't
    /// count as later.
    @discardableResult
    public func save(to defaults: UserDefaults?, now: Date = Date()) -> Bool {
        guard let defaults else { return false }
        if let target,
           let stored = Self.load(from: defaults).target,
           stored.computedAt > target.computedAt,
           stored.computedAt <= now {
            return false
        }
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
        if let strengthSummary {
            defaults.set(strengthSummary, forKey: AppGroup.Keys.lastPlanStrengthSummary)
        } else {
            defaults.removeObject(forKey: AppGroup.Keys.lastPlanStrengthSummary)
        }
        defaults.set(strengthCompletedToday, forKey: AppGroup.Keys.strengthCompletedToday)
        if let dayDistanceKm {
            defaults.set(dayDistanceKm, forKey: AppGroup.Keys.lastDayDistanceKm)
        } else {
            defaults.removeObject(forKey: AppGroup.Keys.lastDayDistanceKm)
        }
        return true
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
            planCompletedToday: defaults.bool(forKey: AppGroup.Keys.planWorkoutCompletedToday),
            strengthSummary: defaults.string(forKey: AppGroup.Keys.lastPlanStrengthSummary),
            strengthCompletedToday: defaults.bool(forKey: AppGroup.Keys.strengthCompletedToday),
            dayDistanceKm: defaults.object(forKey: AppGroup.Keys.lastDayDistanceKm) as? Double
        )
    }
}
