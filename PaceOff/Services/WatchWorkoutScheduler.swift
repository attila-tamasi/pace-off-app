// WatchWorkoutScheduler.swift
// Sends the plan's next runs to Apple Watch through WorkoutKit: each one
// is scheduled into Apple's own Workout app as a custom workout under Pace
// Off's name, with a pace alert on every step that has a band. No watch
// app of ours is involved. Which runs, and their steps, come from
// `WatchSchedulePlanner` and `WorkoutBlocks`; this class only translates
// and schedules them.
//
// Off until the runner turns on "Send workouts to Apple Watch" on the Plan
// tab. Then every refresh (foreground, background) and every plan change
// schedules the next seven days again; turning it off, ending the plan or
// deleting the runner's data removes them.

import Foundation
import Observation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

@MainActor
@Observable
public final class WatchWorkoutScheduler {

    public static let shared = WatchWorkoutScheduler()

    /// The Plan tab switch, stored in App Group defaults.
    public private(set) var isEnabled: Bool
    /// The runner refused scheduling when the switch asked.
    public private(set) var isDenied = false

    /// What the last sync scheduled, so a refresh that changes nothing
    /// doesn't remove and add the same workouts again.
    @ObservationIgnored private var lastScheduled: [ScheduledRun]?

    private init() {
        isEnabled = AppGroup.sharedDefaults?.bool(forKey: AppGroup.Keys.sendWorkoutsToWatch) ?? false
    }

    /// Whether this iPhone can schedule workouts on a watch at all.
    public var isSupported: Bool {
        #if canImport(WorkoutKit)
        return WorkoutScheduler.isSupported
        #else
        return false
        #endif
    }

    /// The Plan tab switch. Turning it on asks for permission first and
    /// stays off when it's refused.
    public func setEnabled(_ on: Bool) async {
        #if canImport(WorkoutKit)
        if on {
            let state = await WorkoutScheduler.shared.requestAuthorization()
            guard state == .authorized else {
                isDenied = true
                store(false)
                return
            }
            isDenied = false
            store(true)
            await sync(prescription: nil)
        } else {
            store(false)
            await removeAll()
        }
        #endif
    }

    /// Schedules the next seven days of the active plan again, today's run
    /// as `prescription` has it. Removes everything when the plan has
    /// ended. Does nothing while the switch is off.
    public func sync(prescription: DayPrescription?, now: Date = Date()) async {
        #if canImport(WorkoutKit)
        guard isEnabled else { return }
        let scheduler = WorkoutScheduler.shared
        guard await scheduler.authorizationState == .authorized else { return }
        let runs = TrainingPlanStore.shared.activePlan.map {
            WatchSchedulePlanner.runs(plan: $0, today: now, prescription: prescription,
                                      limit: WorkoutScheduler.maxAllowedScheduledWorkoutCount)
        } ?? []
        guard runs != lastScheduled else { return }
        await scheduler.removeAllWorkouts()
        for run in runs {
            var date = Calendar.current.dateComponents([.year, .month, .day], from: run.day)
            date.hour = 7
            date.minute = 0
            await scheduler.schedule(WorkoutPlan(.custom(Self.customWorkout(run))), at: date)
        }
        lastScheduled = runs
        #endif
    }

    /// Removes every workout Pace Off scheduled.
    public func removeAll() async {
        #if canImport(WorkoutKit)
        await WorkoutScheduler.shared.removeAllWorkouts()
        lastScheduled = []
        #endif
    }

    /// For "Delete my data" and sign-out: the switch goes off with the
    /// runner's other settings, and the workouts go too.
    public func eraseAll() async {
        isEnabled = false
        isDenied = false
        await removeAll()
    }

    private func store(_ on: Bool) {
        isEnabled = on
        AppGroup.sharedDefaults?.set(on, forKey: AppGroup.Keys.sendWorkoutsToWatch)
        if !on { lastScheduled = nil }
    }

    #if canImport(WorkoutKit)
    private static func customWorkout(_ run: ScheduledRun) -> CustomWorkout {
        CustomWorkout(activity: .running,
                      location: .outdoor,
                      displayName: run.displayName,
                      warmup: run.blocks.warmUp.map(step),
                      blocks: run.blocks.blocks.map { block in
                          IntervalBlock(steps: block.steps.map(intervalStep), iterations: block.iterations)
                      },
                      cooldown: run.blocks.coolDown.map(step))
    }

    private static func step(_ step: PaceOff.WorkoutStep) -> WorkoutKit.WorkoutStep {
        WorkoutKit.WorkoutStep(goal: .distance(step.distanceMeters, .meters), alert: alert(step))
    }

    private static func intervalStep(_ step: PaceOff.WorkoutStep) -> IntervalStep {
        var interval = IntervalStep(step.purpose == .recovery ? .recovery : .work)
        interval.step.goal = .distance(step.distanceMeters, .meters)
        interval.step.alert = alert(step)
        return interval
    }

    /// A current-pace alert over the step's band: the faster end is the
    /// higher speed.
    private static func alert(_ step: PaceOff.WorkoutStep) -> SpeedRangeAlert? {
        guard let fast = step.paceMinSecPerKm, let slow = step.paceMaxSecPerKm,
              fast > 0, slow >= fast else { return nil }
        let low = Measurement(value: 1000 / slow, unit: UnitSpeed.metersPerSecond)
        let high = Measurement(value: 1000 / fast, unit: UnitSpeed.metersPerSecond)
        return SpeedRangeAlert(target: low...high, metric: .current)
    }
    #endif
}
