// WatchSchedulePlanner.swift
// Which of the plan's runs go to Apple Watch, and as what: the next seven
// days' runs, today's as the day's prescription has it (readiness and the
// single-run cap included), later days as the plan wrote them. Rest days,
// strength-only days and the race stay off the watch. Pure: the WorkoutKit
// side (`WatchWorkoutScheduler`) only translates the result.

import Foundation

public struct ScheduledRun: Equatable, Sendable {
    /// The start of the run's day.
    public let day: Date
    /// "Threshold · 9 km", the name the watch shows.
    public let displayName: String
    public let blocks: WorkoutBlocks

    public init(day: Date, displayName: String, blocks: WorkoutBlocks) {
        self.day = day
        self.displayName = displayName
        self.blocks = blocks
    }
}

public enum WatchSchedulePlanner {

    /// Today and the six days after it.
    public static let days = 7

    /// The runs to schedule from `today` on, at most `limit` of them.
    ///
    /// - Parameter prescription: today's `DayPrescription`; when it comes
    ///   from the plan, today's entry is its run. Nil uses the plan as written.
    public static func runs(plan: TrainingPlan, today: Date, prescription: DayPrescription?,
                            limit: Int, calendar: Calendar = .current) -> [ScheduledRun] {
        guard limit > 0 else { return [] }
        let start = calendar.startOfDay(for: today)
        var result: [ScheduledRun] = []
        for offset in 0..<days {
            guard result.count < limit,
                  let day = calendar.date(byAdding: .day, value: offset, to: start),
                  // Midday, so the plan's own calendar lands on the same day.
                  let midday = calendar.date(byAdding: .hour, value: 12, to: day)
            else { continue }
            let workout: Workout?
            if offset == 0, let prescription, prescription.source == .plan {
                workout = prescription.runWorkout
            } else {
                workout = plan.todayDay(today: midday)?.workout
            }
            guard let workout,
                  let blocks = WorkoutBlocks.make(workout, goal: plan.goal, tier: plan.tier,
                                                  easyPace: DayPrescription.easyPaceBand(in: plan, today: midday))
            else { continue }
            result.append(ScheduledRun(day: day, displayName: displayName(workout), blocks: blocks))
        }
        return result
    }

    /// "Threshold · 9 km", "Long · 18.5 km".
    public static func displayName(_ workout: Workout) -> String {
        "\(workout.kind.displayName) · \(DayPrescription.formatKm(workout.distanceKm)) km"
    }
}
