// WorkoutBlocks.swift
// A plan workout as the steps a watch runs: a warm-up, blocks of work and
// recovery repeated some number of times, and a cool-down, each with its
// distance and, where it has one, its pace band. The shape follows
// WorkoutKit's custom workouts, but nothing here imports it, so the
// structure is tested on its own and F-12b only translates it.
//
// Quality sessions follow their notes: the plan's peak session cut to the
// workout's distance (`QualitySession.scaled(toKm:)`), so the watch runs
// what the plan detail describes. Every other run is one work step at its
// pace band.

import Foundation

public struct WorkoutStep: Equatable, Sendable {

    public enum Purpose: String, Sendable {
        case warmUp
        case work
        case recovery
        case coolDown
    }

    public let purpose: Purpose
    public let distanceMeters: Double
    /// Pace band in seconds per km, nil for a step run by feel (a recovery
    /// jog, or a warm-up when the plan has no easy band).
    public let paceMinSecPerKm: Double?
    public let paceMaxSecPerKm: Double?

    public init(purpose: Purpose, distanceMeters: Double,
                paceMinSecPerKm: Double? = nil, paceMaxSecPerKm: Double? = nil) {
        self.purpose = purpose
        self.distanceMeters = distanceMeters
        self.paceMinSecPerKm = paceMinSecPerKm
        self.paceMaxSecPerKm = paceMaxSecPerKm
    }
}

public struct WorkoutBlock: Equatable, Sendable {
    /// How many times the steps run, in order.
    public let iterations: Int
    public let steps: [WorkoutStep]

    public init(iterations: Int, steps: [WorkoutStep]) {
        self.iterations = iterations
        self.steps = steps
    }

    public var distanceMeters: Double {
        Double(iterations) * steps.reduce(0) { $0 + $1.distanceMeters }
    }
}

public struct WorkoutBlocks: Equatable, Sendable {

    public let kind: WorkoutKind
    public let warmUp: WorkoutStep?
    public let blocks: [WorkoutBlock]
    public let coolDown: WorkoutStep?

    public init(kind: WorkoutKind, warmUp: WorkoutStep?, blocks: [WorkoutBlock], coolDown: WorkoutStep?) {
        self.kind = kind
        self.warmUp = warmUp
        self.blocks = blocks
        self.coolDown = coolDown
    }

    /// The whole workout.
    public var distanceMeters: Double {
        (warmUp?.distanceMeters ?? 0) + blocks.reduce(0) { $0 + $1.distanceMeters } + (coolDown?.distanceMeters ?? 0)
    }

    /// The steps of `workout`, or nil for a rest day and the race, which
    /// aren't sent to the watch.
    ///
    /// - Parameters:
    ///   - goal, tier: the plan's, which set a quality session's structure.
    ///   - easyPace: the plan's easy band, for a quality session's warm-up
    ///     and cool-down (`DayPrescription.easyPaceBand`).
    public static func make(_ workout: Workout, goal: RunningGoal, tier: PlanTier,
                            easyPace: ClosedRange<Double>?) -> WorkoutBlocks? {
        guard workout.kind != .rest, workout.kind != .race, workout.distanceMeters > 0 else { return nil }
        let band = (min: workout.paceMinSecPerKm > 0 ? workout.paceMinSecPerKm : nil,
                    max: workout.paceMaxSecPerKm > 0 ? workout.paceMaxSecPerKm : nil)

        guard let peak = TrainingPlanGenerator().peakSession(for: workout.kind, tier: tier, goal: goal) else {
            // One step at the run's band: easy, long, marathon pace, strides.
            let work = WorkoutStep(purpose: .work, distanceMeters: workout.distanceMeters.rounded(),
                                   paceMinSecPerKm: band.min, paceMaxSecPerKm: band.max)
            return WorkoutBlocks(kind: workout.kind, warmUp: nil,
                                 blocks: [WorkoutBlock(iterations: 1, steps: [work])], coolDown: nil)
        }

        let session = peak.scaled(toKm: workout.distanceKm)
        func meters(_ km: Double) -> Double { (km * 1000).rounded() }
        func easy(_ purpose: WorkoutStep.Purpose, _ km: Double) -> WorkoutStep? {
            guard km > 0 else { return nil }
            return WorkoutStep(purpose: purpose, distanceMeters: meters(km),
                               paceMinSecPerKm: easyPace?.lowerBound, paceMaxSecPerKm: easyPace?.upperBound)
        }
        let rep = WorkoutStep(purpose: .work, distanceMeters: meters(session.repKm),
                              paceMinSecPerKm: band.min, paceMaxSecPerKm: band.max)
        // A jog between reps, none after the last: the reps but one with
        // their jog, then the last rep on its own, so the steps add up to
        // the session as its notes give it.
        var blocks: [WorkoutBlock] = []
        if session.reps > 1, session.jogKm > 0 {
            let jog = WorkoutStep(purpose: .recovery, distanceMeters: meters(session.jogKm))
            blocks.append(WorkoutBlock(iterations: session.reps - 1, steps: [rep, jog]))
            blocks.append(WorkoutBlock(iterations: 1, steps: [rep]))
        } else {
            blocks.append(WorkoutBlock(iterations: max(1, session.reps), steps: [rep]))
        }
        return WorkoutBlocks(kind: workout.kind, warmUp: easy(.warmUp, session.warmUpKm),
                             blocks: blocks, coolDown: easy(.coolDown, session.coolDownKm))
    }
}
