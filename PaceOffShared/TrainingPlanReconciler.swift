// TrainingPlanReconciler.swift
// Keeps the active training plan honest against fresh Apple Health data.
// Two jobs, both pure so the background task and the foreground refresh
// share one implementation:
//
//   1. `todayStatus` — what does the plan prescribe today, and did the
//      runner already do it? Drives plan-aware notification scheduling
//      and the cached state the widget reads.
//   2. `retunedPlan` — when the runner's fitness (VDOT) has drifted from
//      the anchor the plan's paces were computed against, rebuild the
//      pace bands of the *remaining* weeks. Structure, distances, and
//      completed weeks are never touched — only the sec/km targets move.
//
// No I/O, no HealthKit — callers hand in runs and a resolved VDOT.

import Foundation

// MARK: - Today's plan status

public struct PlanDayStatus: Sendable, Equatable {
    /// Today's prescribed workout, or nil when the plan doesn't cover today
    /// (before start, after the final week).
    public let workout: Workout?
    /// True when a run recorded today covers the prescription (within
    /// `TrainingPlanReconciler.completionFraction` of the distance).
    public let isCompleted: Bool

    public var isRestDay: Bool { workout?.kind == .rest }

    public init(workout: Workout?, isCompleted: Bool) {
        self.workout = workout
        self.isCompleted = isCompleted
    }
}

// MARK: - Reconciler

public struct TrainingPlanReconciler: Sendable {

    /// A run counts as "did the planned workout" at ≥85% of the prescribed
    /// distance — close enough that nagging the runner would be noise.
    static let completionFraction = 0.85

    /// VDOT points of drift before a plan's paces are considered stale.
    /// Below this the difference is inside the pace bands' tolerance anyway.
    static let vdotDriftThreshold = 1.0

    private let vdotCalc = VDOTCalculator()

    public init() {}

    // MARK: Today

    /// What the plan asks for today and whether the day's runs satisfied it.
    /// The longest run of the day is the one measured against the plan —
    /// same disambiguation TodayViewModel uses for the "you ran today" card.
    public func todayStatus(plan: TrainingPlan,
                            runs: [RunRecord],
                            today: Date = Date()) -> PlanDayStatus {
        guard let workout = plan.todayWorkout(today: today) else {
            return PlanDayStatus(workout: nil, isCompleted: false)
        }
        guard workout.kind != .rest, workout.distanceMeters > 0 else {
            return PlanDayStatus(workout: workout, isCompleted: false)
        }
        let cal = Calendar.current
        let longestToday = runs
            .filter { cal.isDate($0.startDate, inSameDayAs: today) }
            .map(\.distanceMeters)
            .max() ?? 0
        let done = longestToday >= workout.distanceMeters * Self.completionFraction
        return PlanDayStatus(workout: workout, isCompleted: done)
    }

    // MARK: Retune

    /// Rebuild the remaining weeks' pace bands around `newVDOT`. Returns nil
    /// when there's nothing to do: the plan is over, or the drift from the
    /// plan's anchor VDOT is inside `vdotDriftThreshold`. A plan that was
    /// generated from the beginner-default fallback retunes on any real
    /// VDOT, drift regardless — its paces were never the runner's to begin
    /// with.
    ///
    /// Weeks strictly before the current one keep their original workouts —
    /// history shouldn't rewrite itself. `id` and `createdAt` are preserved
    /// so week indexing and identity stay stable.
    public func retunedPlan(_ plan: TrainingPlan,
                            toVDOT newVDOT: Double,
                            today: Date = Date()) -> TrainingPlan? {
        guard let currentWeek = plan.currentWeekIndex(today: today) else { return nil }
        let drift = abs(newVDOT - plan.vdot)
        guard plan.usedBeginnerDefault || drift >= Self.vdotDriftThreshold else { return nil }

        let weeks = plan.weeks.map { week -> TrainingWeek in
            guard week.index - 1 >= currentWeek else { return week }
            let days = week.days.map { day in
                TrainingDay(weekday: day.weekday,
                            workout: retuned(day.workout, vdot: newVDOT))
            }
            return TrainingWeek(index: week.index, days: days)
        }

        return TrainingPlan(
            id: plan.id,
            goal: plan.goal,
            tier: plan.tier,
            longRunDay: plan.longRunDay,
            weeks: weeks,
            vdot: newVDOT,
            usedBeginnerDefault: false,
            createdAt: plan.createdAt
        )
    }

    /// Recompute one workout's pace band from a new VDOT. Kind, distance,
    /// and notes are untouched. The intensity/tolerance mapping mirrors
    /// `TrainingPlanGenerator.materialise` exactly (strides are paced at
    /// easy effort there, not at `TrainingIntensity.forKind`'s interval),
    /// so a retuned plan is indistinguishable from one freshly generated
    /// at the new VDOT.
    func retuned(_ workout: Workout, vdot: Double) -> Workout {
        let fraction: Double
        let tolerance: Double
        switch workout.kind {
        case .rest:
            return workout
        case .easy, .long, .strides:
            fraction = TrainingIntensity.easy.fractionOfVDOT
            tolerance = TrainingIntensity.easy.paceToleranceSec
        case .marathonPace:
            fraction = TrainingIntensity.marathon.fractionOfVDOT
            tolerance = TrainingIntensity.marathon.paceToleranceSec
        case .tempo, .threshold:
            fraction = TrainingIntensity.threshold.fractionOfVDOT
            tolerance = TrainingIntensity.threshold.paceToleranceSec
        case .interval:
            fraction = TrainingIntensity.interval.fractionOfVDOT
            tolerance = TrainingIntensity.interval.paceToleranceSec
        }
        let pace = vdotCalc.paceSecPerKm(vdot: vdot, fractionOfVDOT: fraction)
        return Workout(
            kind: workout.kind,
            distanceMeters: workout.distanceMeters,
            paceMinSecPerKm: pace - tolerance,
            paceMaxSecPerKm: pace + tolerance,
            notes: workout.notes
        )
    }
}
