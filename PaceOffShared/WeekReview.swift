// WeekReview.swift
// The last seven days, day by day, behind Today's "Last 7 days" card:
// each day's runs and, with a plan active, its plan workout and whether a
// run covered it. Completion is TrainingPlanReconciler's own rule, so this
// screen, Today, the widget and the pushes always agree.

import Foundation

public struct WeekReview: Equatable, Sendable {

    /// How a day stands against its plan workout.
    public enum PlanMark: Equatable, Sendable {
        /// A run covered the workout.
        case done
        /// Today's workout, not done yet.
        case pending
        /// An earlier day's workout that no run covered.
        case missed
        /// A planned rest day.
        case rest
    }

    public struct Day: Equatable, Identifiable, Sendable {
        /// Start of the calendar day.
        public let date: Date
        public let isToday: Bool
        /// The day's runs, earliest first.
        public let runs: [RunRecord]
        /// The plan's workout that day and whether it was done; nil when
        /// no plan is active or the plan doesn't cover the day.
        public let plan: PlanDayStatus?

        public var id: Date { date }
        public var distanceKm: Double { runs.reduce(0) { $0 + $1.distanceKm } }

        public var planMark: PlanMark? {
            guard let plan, let workout = plan.workout else { return nil }
            if workout.kind == .rest { return .rest }
            if plan.isCompleted { return .done }
            return isToday ? .pending : .missed
        }
    }

    /// The last `dayCount` days, oldest first, today last.
    public let days: [Day]
    /// Consecutive running days up to today (or yesterday, before today's
    /// run), as Today's card counts them.
    public let streak: Int

    public init(runs: [RunRecord],
                plan: TrainingPlan?,
                today: Date = Date(),
                dayCount: Int = 7) {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        let reconciler = TrainingPlanReconciler()
        days = (0..<max(1, dayCount)).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            let dayRuns = runs
                .filter { cal.isDate($0.startDate, inSameDayAs: date) }
                .sorted { $0.startDate < $1.startDate }
            // Midday, so the plan lookup lands on the day whatever the time zone does at midnight.
            let noon = cal.date(byAdding: .hour, value: 12, to: date) ?? date
            let status = plan.map { reconciler.todayStatus(plan: $0, runs: dayRuns, today: noon) }
            return Day(date: date,
                       isToday: offset == 0,
                       runs: dayRuns,
                       plan: status?.workout == nil ? nil : status)
        }
        streak = RunStreak.current(runs: runs, today: today, calendar: cal)
    }

    // MARK: - The week in numbers

    public var totalKm: Double { days.reduce(0) { $0 + $1.distanceKm } }
    public var runCount: Int { days.reduce(0) { $0 + $1.runs.count } }

    /// Whether any day of the week has a plan workout.
    public var hasPlan: Bool { days.contains { $0.plan != nil } }

    /// The plan's distance over the week, rest days counting zero.
    public var plannedKm: Double {
        days.reduce(0) { total, day in
            guard let workout = day.plan?.workout, workout.kind != .rest else { return total }
            return total + workout.distanceKm
        }
    }

    /// Plan workouts that ask for a run, and how many a run covered.
    public var plannedSessions: Int {
        days.filter { $0.planMark != nil && $0.planMark != .rest }.count
    }
    public var completedSessions: Int {
        days.filter { $0.planMark == .done }.count
    }
}
