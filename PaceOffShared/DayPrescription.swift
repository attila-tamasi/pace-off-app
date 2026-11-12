// DayPrescription.swift
// The one prescription for today. On a day the training plan has a run,
// the plan's workout is the day's run, and readiness changes that workout
// instead of adding a second number beside it. A plan rest day is rest.
// Without a plan workout (no plan, a plan that hasn't started or has
// ended), the daily target from PushTargetEngine is the day's run.
//
// Pure and Sendable: Today, the pushes, the widget and Siri read the same
// value, so they can't disagree.

import Foundation

public struct DayPrescription: Sendable, Equatable {

    public enum Kind: String, Sendable {
        case run
        case rest
        /// A plan rest day for running with a strength session.
        case strength
        case race
    }

    /// Where the day's run comes from.
    public enum Source: String, Sendable {
        case plan
        case dailyTarget
    }

    /// What readiness did to the plan's workout.
    public enum Adjustment: String, Sendable {
        /// Yellow: a quality session run at easy pace, same distance.
        case easedForYellow
        /// Red: an easy run of at most 60% of the plan's distance.
        case cutForRed
    }

    public let kind: Kind
    public let source: Source
    /// The kind of run to do: the plan's, or `.easy` once readiness eased
    /// it. Nil on rest and strength days and for the daily target.
    public let workoutKind: WorkoutKind?
    /// The distance to run. Nil on rest and strength days.
    public let distanceMeters: Double?
    /// Pace band in seconds per km, nil when there's none to show: the
    /// daily target, a race, or an eased run on a plan without an easy band.
    public let paceMinSecPerKm: Double?
    public let paceMaxSecPerKm: Double?
    /// Set when readiness changed the plan's workout.
    public let adjustment: Adjustment?
    /// The plan's own workout, as written, on a plan day.
    public let planWorkout: Workout?
    /// Today's strength session, still to do or done.
    public let strength: StrengthSession?

    /// Red readiness keeps at most this share of the plan's distance, the
    /// factor a red day already caps the daily target at.
    public static let redDistanceFactor = PushTargetEngine.redReadinessCapFactor

    /// A plan run counts as done at this share of its distance, as in
    /// `TrainingPlanReconciler`.
    public static let planCompletionFraction = 0.85
    /// The daily target counts as hit at this share of its whole km, as
    /// Today's badge has always judged it.
    public static let targetCompletionFraction = 0.95

    public var distanceKm: Double? { distanceMeters.map { $0 / 1000 } }

    /// Whether a run of `meters` (the longest today) meets the day.
    public func isMet(byRunMeters meters: Double) -> Bool {
        guard let distanceMeters, distanceMeters > 0 else { return false }
        let share = source == .plan ? Self.planCompletionFraction : Self.targetCompletionFraction
        return meters >= distanceMeters * share
    }

    // MARK: - Building it

    /// Today's prescription, or nil when there's nothing to prescribe (no
    /// plan workout and no daily target, as before a first run).
    ///
    /// - Parameters:
    ///   - planStatus: today's plan status, nil without an active plan.
    ///   - readiness: today's readiness level, nil when unknown.
    ///   - target: the daily target, used when the plan has no workout today.
    ///   - easyPace: the plan's easy band this week (`easyPaceBand(in:today:)`),
    ///     for a run readiness eases.
    public static func make(planStatus: PlanDayStatus?,
                            readiness: ReadinessLevel?,
                            target: RunTarget?,
                            easyPace: ClosedRange<Double>?) -> DayPrescription? {
        if let status = planStatus, let workout = status.workout {
            return fromPlan(workout, strength: status.strength, readiness: readiness, easyPace: easyPace)
        }
        guard let target else { return nil }
        return DayPrescription(kind: .run, source: .dailyTarget, workoutKind: nil,
                               distanceMeters: target.displayedDistanceMeters,
                               paceMinSecPerKm: nil, paceMaxSecPerKm: nil,
                               adjustment: nil, planWorkout: nil, strength: nil)
    }

    private static func fromPlan(_ workout: Workout, strength: StrengthSession?,
                                 readiness: ReadinessLevel?,
                                 easyPace: ClosedRange<Double>?) -> DayPrescription {
        switch workout.kind {
        case .rest:
            return DayPrescription(kind: strength == nil ? .rest : .strength, source: .plan,
                                   workoutKind: nil, distanceMeters: nil,
                                   paceMinSecPerKm: nil, paceMaxSecPerKm: nil,
                                   adjustment: nil, planWorkout: workout, strength: strength)
        case .race:
            // Readiness never changes the race.
            return DayPrescription(kind: .race, source: .plan, workoutKind: .race,
                                   distanceMeters: workout.distanceMeters,
                                   paceMinSecPerKm: nil, paceMaxSecPerKm: nil,
                                   adjustment: nil, planWorkout: workout, strength: strength)
        default:
            break
        }

        let asWritten = DayPrescription(
            kind: .run, source: .plan, workoutKind: workout.kind,
            distanceMeters: workout.distanceMeters,
            paceMinSecPerKm: workout.paceMinSecPerKm > 0 ? workout.paceMinSecPerKm : nil,
            paceMaxSecPerKm: workout.paceMaxSecPerKm > 0 ? workout.paceMaxSecPerKm : nil,
            adjustment: nil, planWorkout: workout, strength: strength)

        switch readiness {
        case .red:
            // Rounded down to the tenth of a km the plan shows, so the
            // shown distance stays within the cut.
            let cut = (workout.distanceMeters * redDistanceFactor / 100).rounded(.down) * 100
            return eased(workout, to: cut, adjustment: .cutForRed, strength: strength, easyPace: easyPace)
        case .yellow where workout.kind.isQuality:
            return eased(workout, to: workout.distanceMeters, adjustment: .easedForYellow,
                         strength: strength, easyPace: easyPace)
        default:
            // Green, unknown, or yellow on a run that's already easy.
            return asWritten
        }
    }

    private static func eased(_ workout: Workout, to meters: Double, adjustment: Adjustment,
                              strength: StrengthSession?,
                              easyPace: ClosedRange<Double>?) -> DayPrescription {
        DayPrescription(kind: .run, source: .plan, workoutKind: .easy,
                        distanceMeters: meters,
                        paceMinSecPerKm: easyPace?.lowerBound, paceMaxSecPerKm: easyPace?.upperBound,
                        adjustment: adjustment, planWorkout: workout, strength: strength)
    }

    /// The plan's easy pace band in the week of `today`, else in its first
    /// week with an easy run. Nil when the plan has none.
    public static func easyPaceBand(in plan: TrainingPlan, today: Date = Date()) -> ClosedRange<Double>? {
        let weeks: [TrainingWeek]
        if let index = plan.currentWeekIndex(today: today), plan.weeks.indices.contains(index) {
            weeks = [plan.weeks[index]] + plan.weeks
        } else {
            weeks = plan.weeks
        }
        for week in weeks {
            if let easy = week.days.map(\.workout).first(where: {
                $0.kind == .easy && $0.paceMinSecPerKm > 0 && $0.paceMaxSecPerKm >= $0.paceMinSecPerKm
            }) {
                return easy.paceMinSecPerKm...easy.paceMaxSecPerKm
            }
        }
        return nil
    }
}
