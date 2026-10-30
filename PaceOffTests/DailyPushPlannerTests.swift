// DailyPushPlannerTests.swift
// Covers the daily push rules: one-shot times on today's date, passed slots
// left out, the evening "last call" only in a week with a skipped day,
// planned rest days not counting as skips, and the plan-aware bodies.

import XCTest
@testable import PaceOff

final class DailyPushPlannerTests: XCTestCase {

    private let cal = Calendar.current
    private lazy var planner = DailyPushPlanner(calendar: cal)

    /// 2026-01-05 is a Monday; dates are built from local components so the
    /// weekday is the same in any timezone.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    private func run(day: Int, km: Double = 6) -> RunRecord {
        let start = date(day: day, hour: 7)
        return RunRecord(
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            distanceMeters: km * 1000,
            durationSeconds: 1_800
        )
    }

    /// One week from Monday 2026-01-05: Mon rest, Tue easy, Wed easy,
    /// Thu rest, Fri easy, Sat easy, Sun long.
    private func plan() -> TrainingPlan {
        let kinds: [WorkoutKind] = [.rest, .easy, .easy, .rest, .easy, .easy, .long]
        let days = zip(Weekday.allCases, kinds).map { weekday, kind in
            TrainingDay(
                weekday: weekday,
                workout: kind == .rest
                    ? Workout(kind: .rest, distanceMeters: 0, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
                    : Workout(kind: kind, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
            )
        }
        return TrainingPlan(
            goal: .tenK,
            tier: .medium,
            longRunDay: .sunday,
            weeks: [TrainingWeek(index: 1, days: days)],
            vdot: 45,
            usedBeginnerDefault: false,
            createdAt: date(day: 5, hour: 12)
        )
    }

    private func pushes(now: Date,
                        runs: [RunRecord],
                        plan: TrainingPlan? = nil,
                        planStatus: PlanDayStatus? = nil,
                        schedule: DailyPushPlanner.Schedule = .standard) -> [DailyPush] {
        planner.pushes(for: DailyPushPlanner.Inputs(
            now: now,
            body: "Run 8 km.",
            runs: runs,
            plan: plan,
            planStatus: planStatus,
            schedule: schedule
        ))
    }

    // MARK: - Times

    func test_allThreeSlots_fireTodayAtTheirTimes() {
        // Wednesday 06:00; ran Monday, skipped Tuesday.
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5)])

        XCTAssertEqual(result.map(\.slot), [.morning, .afternoon, .evening])
        XCTAssertEqual(result.map(\.fireDate), [
            date(day: 7, hour: 8),
            date(day: 7, hour: 17, minute: 30),
            date(day: 7, hour: 21),
        ])
    }

    func test_slotsThatHavePassed_areLeftOut() {
        let result = pushes(now: date(day: 7, hour: 18), runs: [run(day: 5)])
        XCTAssertEqual(result.map(\.slot), [.evening])
    }

    func test_afterTheEveningSlot_nothingIsScheduled() {
        XCTAssertTrue(pushes(now: date(day: 7, hour: 22), runs: [run(day: 5)]).isEmpty)
    }

    func test_customHours_areUsed() {
        let schedule = DailyPushPlanner.Schedule(morningHour: 7, afternoonHour: 16, eveningHour: 20)
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5)], schedule: schedule)
        XCTAssertEqual(result.map(\.fireDate), [
            date(day: 7, hour: 7),
            date(day: 7, hour: 16, minute: 30),
            date(day: 7, hour: 20),
        ])
    }

    func test_unsetHours_fallBackToDefaults() {
        XCTAssertEqual(DailyPushPlanner.Schedule(morningHour: 0, afternoonHour: 0, eveningHour: 0), .standard)
        XCTAssertEqual(DailyPushPlanner.Schedule(morningHour: 24, afternoonHour: -1, eveningHour: 99), .standard)
    }

    // MARK: - Last call

    func test_noLastCall_whenNoDayWasSkippedThisWeek() {
        // Ran Monday and Tuesday.
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5), run(day: 6)])
        XCTAssertEqual(result.map(\.slot), [.morning, .afternoon])
    }

    func test_noLastCall_onMonday_evenAfterSkippingLastWeek() {
        // Last run the previous Wednesday; the new week has no skipped day yet.
        let lastWeek = run(day: 5).startDate.addingTimeInterval(-5 * 86_400)
        let result = pushes(
            now: date(day: 5, hour: 6),
            runs: [RunRecord(startDate: lastWeek, endDate: lastWeek.addingTimeInterval(1_800),
                             distanceMeters: 6_000, durationSeconds: 1_800)]
        )
        XCTAssertEqual(result.map(\.slot), [.morning, .afternoon])
    }

    func test_plannedRestDays_areNotSkips() {
        // Thursday: Monday is a planned rest day, ran Tuesday and Wednesday.
        let withPlan = planner.skippedDaysThisWeek(runs: [run(day: 6), run(day: 7)], plan: plan(), now: date(day: 8, hour: 6))
        XCTAssertEqual(withPlan, 0)

        // Without a plan, the same Monday is a skip.
        let withoutPlan = planner.skippedDaysThisWeek(runs: [run(day: 6), run(day: 7)], plan: nil, now: date(day: 8, hour: 6))
        XCTAssertEqual(withoutPlan, 1)
    }

    // MARK: - Already ran, or the plan says stop

    func test_ranToday_dropsReminderAndLastCall() {
        // Skipped Tuesday, ran Wednesday at 07:00; it's now 07:45.
        let result = pushes(now: date(day: 7, hour: 7, minute: 45), runs: [run(day: 5), run(day: 7)])
        XCTAssertEqual(result.map(\.slot), [.morning])
    }

    func test_planRestDay_onlyMorning_withRestNote() {
        let rest = PlanDayStatus(
            workout: Workout(kind: .rest, distanceMeters: 0, paceMinSecPerKm: 0, paceMaxSecPerKm: 0),
            isCompleted: false
        )
        let result = pushes(now: date(day: 8, hour: 6), runs: [run(day: 5)], plan: plan(), planStatus: rest)
        XCTAssertEqual(result.map(\.slot), [.morning])
        XCTAssertEqual(result.first?.body, "Rest day on your plan. Recovery is training too.")
    }

    func test_planWorkoutDone_onlyMorning() {
        let workout = Workout(kind: .easy, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
        let done = PlanDayStatus(workout: workout, isCompleted: true)
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5)], plan: plan(), planStatus: done)
        XCTAssertEqual(result.map(\.slot), [.morning])
    }

    // MARK: - Bodies

    func test_bodies_leadWithThePlanWorkout() {
        let workout = Workout(kind: .easy, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
        let pending = PlanDayStatus(workout: workout, isCompleted: false)
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5)], plan: plan(), planStatus: pending)

        // Monday is a planned rest day, Tuesday was skipped: all three go out.
        let line = "Today's plan: \(workout.summary). Run 8 km."
        XCTAssertEqual(result.map(\.body), [line, "Reminder: \(line)", "Last call. \(line)"])
    }

    func test_bodies_withoutAPlan() {
        let result = pushes(now: date(day: 7, hour: 6), runs: [run(day: 5)])
        XCTAssertEqual(result.map(\.body), ["Run 8 km.", "Reminder: Run 8 km.", "Last call. Run 8 km."])
    }
}
