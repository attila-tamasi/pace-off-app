// TrainingPlanReconcilerTests.swift
// Covers today-status reconciliation (rest / pending / completed) and the
// VDOT-drift retune: threshold gating, past-week preservation, and
// equivalence with a freshly generated plan at the new VDOT.

import XCTest
@testable import PaceOff

final class TrainingPlanReconcilerTests: XCTestCase {

    private let reconciler = TrainingPlanReconciler()
    private let generator = TrainingPlanGenerator()
    private let cal = Calendar.current

    /// A fixed Monday at local noon so weekday mapping is deterministic in
    /// any timezone: 2026-01-05 is a Monday everywhere when built from
    /// local calendar components.
    private var monday: Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: monday)!
    }

    /// Medium-tier 10K plan created on the fixed Monday, anchored to VDOT 50.
    /// Week 1 layout (long-run Sunday): Mon rest, Tue interval, Wed rest,
    /// Thu easy, Fri rest, Sat easy, Sun long.
    private func makePlan(vo2Max: Double? = 50, personalBest: PersonalBest? = nil) -> TrainingPlan {
        generator.generate(TrainingPlanInputs(
            goal: .tenK,
            tier: .medium,
            longRunDay: .sunday,
            vo2Max: vo2Max,
            personalBest: personalBest,
            goalDate: nil,
            today: monday
        ))
    }

    private func run(on date: Date, km: Double) -> RunRecord {
        RunRecord(
            startDate: date,
            endDate: date.addingTimeInterval(km * 360),
            distanceMeters: km * 1000,
            durationSeconds: km * 360
        )
    }

    // MARK: - Today status

    func test_todayStatus_nilWorkout_whenPlanOver() {
        let plan = makePlan()
        let afterEnd = day(plan.weekCount * 7)
        let status = reconciler.todayStatus(plan: plan, runs: [], today: afterEnd)
        XCTAssertNil(status.workout)
        XCTAssertFalse(status.isCompleted)
    }

    func test_todayStatus_restDay() {
        let plan = makePlan()
        let status = reconciler.todayStatus(plan: plan, runs: [], today: monday)
        XCTAssertEqual(status.workout?.kind, .rest)
        XCTAssertTrue(status.isRestDay)
        XCTAssertFalse(status.isCompleted)
    }

    func test_todayStatus_pending_whenNoRunYet() {
        let plan = makePlan()
        let tuesday = day(1)
        let status = reconciler.todayStatus(plan: plan, runs: [], today: tuesday)
        XCTAssertNotNil(status.workout)
        XCTAssertNotEqual(status.workout?.kind, .rest)
        XCTAssertFalse(status.isCompleted)
    }

    func test_todayStatus_completed_whenRunCoversPrescription() {
        let plan = makePlan()
        let tuesday = day(1)
        let prescribed = plan.todayWorkout(today: tuesday)!
        let runs = [run(on: tuesday, km: prescribed.distanceKm)]
        let status = reconciler.todayStatus(plan: plan, runs: runs, today: tuesday)
        XCTAssertTrue(status.isCompleted)
    }

    func test_todayStatus_notCompleted_whenRunTooShort() {
        let plan = makePlan()
        let tuesday = day(1)
        let prescribed = plan.todayWorkout(today: tuesday)!
        let runs = [run(on: tuesday, km: prescribed.distanceKm * 0.5)]
        let status = reconciler.todayStatus(plan: plan, runs: runs, today: tuesday)
        XCTAssertFalse(status.isCompleted)
    }

    func test_todayStatus_ignoresRunsFromOtherDays() {
        let plan = makePlan()
        let tuesday = day(1)
        let prescribed = plan.todayWorkout(today: tuesday)!
        let runs = [run(on: day(-1), km: prescribed.distanceKm + 5)]
        let status = reconciler.todayStatus(plan: plan, runs: runs, today: tuesday)
        XCTAssertFalse(status.isCompleted)
    }

    // MARK: - Retune gating

    func test_retune_nil_whenDriftBelowThreshold() {
        let plan = makePlan() // vdot 50
        XCTAssertNil(reconciler.retunedPlan(plan, toVDOT: 50.6, today: monday))
    }

    func test_retune_nil_whenPlanOver() {
        let plan = makePlan()
        let afterEnd = day(plan.weekCount * 7)
        XCTAssertNil(reconciler.retunedPlan(plan, toVDOT: 55, today: afterEnd))
    }

    func test_retune_fires_whenDriftAtThreshold() {
        let plan = makePlan()
        XCTAssertNotNil(reconciler.retunedPlan(plan, toVDOT: 51.0, today: monday))
    }

    func test_retune_beginnerDefaultPlan_retunesOnAnyRealVDOT() {
        // No VO₂ max, no PB → plan anchored to the beginner fallback (38).
        let plan = makePlan(vo2Max: nil)
        XCTAssertTrue(plan.usedBeginnerDefault)
        let retuned = reconciler.retunedPlan(plan, toVDOT: 38.5, today: monday)
        XCTAssertNotNil(retuned)
        XCTAssertEqual(retuned?.usedBeginnerDefault, false)
    }

    // MARK: - Retune contents

    func test_retune_matchesFreshlyGeneratedPlan() {
        // Retuning from week 0 must be indistinguishable from generating the
        // plan at the new VDOT in the first place: same structure, same
        // distances, same paces.
        let planAt50 = makePlan(vo2Max: 50)
        let planAt54 = generator.generate(TrainingPlanInputs(
            goal: .tenK, tier: .medium, longRunDay: .sunday,
            vo2Max: 54, personalBest: nil, goalDate: nil, today: monday
        ))
        let retuned = reconciler.retunedPlan(planAt50, toVDOT: 54, today: monday)
        XCTAssertEqual(retuned?.weeks, planAt54.weeks)
        XCTAssertEqual(retuned?.vdot, 54)
    }

    func test_retune_preservesIdentityAndSchedule() {
        let plan = makePlan()
        let retuned = reconciler.retunedPlan(plan, toVDOT: 54, today: monday)
        XCTAssertEqual(retuned?.id, plan.id)
        XCTAssertEqual(retuned?.createdAt, plan.createdAt)
        XCTAssertEqual(retuned?.goal, plan.goal)
        XCTAssertEqual(retuned?.tier, plan.tier)
        XCTAssertEqual(retuned?.longRunDay, plan.longRunDay)
        XCTAssertEqual(retuned?.weekCount, plan.weekCount)
    }

    func test_retune_preservesPastWeeks_repacesRemaining() {
        let plan = makePlan()
        let inWeekTwo = day(8) // week index 1
        let retuned = reconciler.retunedPlan(plan, toVDOT: 54, today: inWeekTwo)!

        // Week 1 is history — byte-for-byte identical.
        XCTAssertEqual(retuned.weeks[0], plan.weeks[0])

        // Remaining weeks carry new paces on every running day.
        for (old, new) in zip(plan.weeks[1...], retuned.weeks[1...]) {
            for (oldDay, newDay) in zip(old.days, new.days) {
                XCTAssertEqual(newDay.workout.kind, oldDay.workout.kind)
                XCTAssertEqual(newDay.workout.distanceMeters, oldDay.workout.distanceMeters)
                if oldDay.workout.kind != .rest {
                    XCTAssertNotEqual(newDay.workout.paceMinSecPerKm,
                                      oldDay.workout.paceMinSecPerKm,
                                      "VDOT 50→54 must move every pace band")
                }
            }
        }
    }

    func test_retune_fasterVDOT_meansFasterPaces() {
        let plan = makePlan()
        let retuned = reconciler.retunedPlan(plan, toVDOT: 54, today: monday)!
        let tuesday = day(1)
        let oldPace = plan.todayWorkout(today: tuesday)!.paceMinSecPerKm
        let newPace = retuned.todayWorkout(today: tuesday)!.paceMinSecPerKm
        XCTAssertLessThan(newPace, oldPace, "Higher VDOT → fewer seconds per km")
    }

    func test_retunedWorkout_restIsUntouched() {
        let rest = Workout(kind: .rest, distanceMeters: 0, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        XCTAssertEqual(reconciler.retuned(rest, vdot: 60), rest)
    }
}
