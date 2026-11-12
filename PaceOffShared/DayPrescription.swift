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
    /// Whether today's run already meets the prescription
    /// (`isMet(byRunMeters:)` on the longest run today). False on rest and
    /// strength days.
    public internal(set) var isDone: Bool = false
    /// The distance the single-run cap (`SingleRunCap`) kept today's run
    /// to, when it cut it. Nil when it didn't.
    public internal(set) var cappedAtMeters: Double? = nil

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

    /// The distance as Today's hero shows it: "8", "10.8". Nil on rest and
    /// strength days.
    public var distanceText: String? { distanceKm.map(Self.formatKm) }

    /// The plan run to do, as written or eased, with its pace band. Nil for
    /// the daily target and on rest and strength days.
    public var runWorkout: Workout? {
        guard source == .plan, kind == .run || kind == .race, let distanceMeters else { return nil }
        return Workout(kind: workoutKind ?? .easy, distanceMeters: distanceMeters,
                       paceMinSecPerKm: paceMinSecPerKm ?? 0, paceMaxSecPerKm: paceMaxSecPerKm ?? 0,
                       notes: adjustment == nil ? planWorkout?.notes : nil)
    }

    /// The day on one line, for pushes and the widget: "8.0 km ·
    /// 5:25–5:45/km", "Race day · 21.1 km", "6 km" for the daily target.
    /// Nil on rest and strength days.
    public var summary: String? {
        switch kind {
        case .rest, .strength: return nil
        case .race: return runWorkout?.headline
        case .run: return runWorkout?.summary ?? distanceText.map { "\($0) km" }
        }
    }

    /// Why the plan's workout changed today, nil when it didn't.
    public var adjustmentNote: String? {
        switch adjustment {
        case .easedForYellow:
            let kind = planWorkout?.kind.displayName.lowercased() ?? "session"
            return "Readiness is yellow, so today's \(kind) runs easy"
        case .cutForRed:
            return "Readiness is red, so today's run is cut to an easy one"
        case nil:
            return nil
        }
    }

    /// "Kept to 11 km: 10% past your longest run of the last 30 days", when
    /// the single-run cap cut today's run.
    public var capNote: String? {
        cappedAtMeters.map { SingleRunCap.note(keptToKm: Self.formatKm($0 / 1000)) }
    }

    /// Whole km without a decimal ("8"), else one decimal ("10.8").
    public static func formatKm(_ km: Double) -> String {
        let tenths = (km * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(format: "%.0f", tenths) : String(format: "%.1f", tenths)
    }

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
    ///   - longestRunTodayMeters: the longest run recorded today, which sets
    ///     `isDone`.
    ///   - singleRunCapMeters: `SingleRunCap.capMeters` for today. A plan run
    ///     over it is kept to it; the race never is. The daily target comes
    ///     already capped.
    public static func make(planStatus: PlanDayStatus?,
                            readiness: ReadinessLevel?,
                            target: RunTarget?,
                            easyPace: ClosedRange<Double>?,
                            longestRunTodayMeters: Double = 0,
                            singleRunCapMeters: Double? = nil) -> DayPrescription? {
        var day: DayPrescription
        if let status = planStatus, let workout = status.workout {
            day = fromPlan(workout, strength: status.strength, readiness: readiness, easyPace: easyPace)
            if day.kind == .run, let cap = singleRunCapMeters, let distance = day.distanceMeters,
               distance > cap + 1e-6 {
                // Rounded down to the tenth of a km the plan shows.
                let kept = ((cap + 1e-6) / 100).rounded(.down) * 100
                day = DayPrescription(kind: day.kind, source: day.source, workoutKind: day.workoutKind,
                                      distanceMeters: kept,
                                      paceMinSecPerKm: day.paceMinSecPerKm, paceMaxSecPerKm: day.paceMaxSecPerKm,
                                      adjustment: day.adjustment, planWorkout: day.planWorkout,
                                      strength: day.strength)
                day.cappedAtMeters = kept
            }
        } else if let target {
            day = DayPrescription(kind: .run, source: .dailyTarget, workoutKind: nil,
                                  distanceMeters: target.displayedDistanceMeters,
                                  paceMinSecPerKm: nil, paceMaxSecPerKm: nil,
                                  adjustment: nil, planWorkout: nil, strength: nil)
            if target.singleRunCapMeters != nil { day.cappedAtMeters = target.displayedDistanceMeters }
        } else {
            return nil
        }
        day.isDone = day.isMet(byRunMeters: longestRunTodayMeters)
        return day
    }

    /// The longest run that started on `now`'s day.
    public static func longestRun(on now: Date, in runs: [RunRecord], calendar: Calendar = .current) -> Double {
        runs.filter { calendar.isDate($0.startDate, inSameDayAs: now) }.map(\.distanceMeters).max() ?? 0
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
