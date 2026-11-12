import XCTest

final class WatchSchedulePlannerTests: XCTestCase {

    private let cal = Calendar.current

    /// 2026-01-05 is a Monday.
    private func date(day: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private let easy = Workout(kind: .easy, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
    private let threshold = Workout(kind: .threshold, distanceMeters: 9_000, paceMinSecPerKm: 280, paceMaxSecPerKm: 295)
    private let long = Workout(kind: .long, distanceMeters: 16_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
    private let kettlebell = StrengthSession(equipment: .kettlebell, minutes: 35, notes: "Swings")

    /// Two weeks from Monday 2026-01-05: Mon rest, Tue threshold, Wed easy,
    /// Thu rest with strength, Fri easy, Sat easy, Sun long.
    private func plan(weeks: Int = 2) -> TrainingPlan {
        let days: [TrainingDay] = [
            TrainingDay(weekday: .monday, workout: .rest),
            TrainingDay(weekday: .tuesday, workout: threshold),
            TrainingDay(weekday: .wednesday, workout: easy),
            TrainingDay(weekday: .thursday, workout: .rest, strength: kettlebell),
            TrainingDay(weekday: .friday, workout: easy),
            TrainingDay(weekday: .saturday, workout: easy),
            TrainingDay(weekday: .sunday, workout: long),
        ]
        return TrainingPlan(goal: .halfMarathon, tier: .medium, longRunDay: .sunday,
                            weeks: (1...weeks).map { TrainingWeek(index: $0, days: days) },
                            vdot: 45, usedBeginnerDefault: false, createdAt: date(day: 5, hour: 8))
    }

    func testNextSevenDaysRunsOnly() {
        let runs = WatchSchedulePlanner.runs(plan: plan(), today: date(day: 5), prescription: nil,
                                             limit: 50, calendar: cal)
        // Mon rest, Thu strength-only and the following Mon are left out.
        XCTAssertEqual(runs.map { cal.component(.day, from: $0.day) }, [6, 7, 9, 10, 11])
        XCTAssertEqual(runs.map(\.displayName),
                       ["Threshold · 9 km", "Easy · 8 km", "Easy · 8 km", "Easy · 8 km", "Long · 16 km"])
        XCTAssertEqual(runs.first?.blocks.distanceMeters, 9_000)
    }

    func testNeverMoreThanTheLimit() {
        let runs = WatchSchedulePlanner.runs(plan: plan(), today: date(day: 5), prescription: nil,
                                             limit: 2, calendar: cal)
        XCTAssertEqual(runs.count, 2)
        XCTAssertTrue(WatchSchedulePlanner.runs(plan: plan(), today: date(day: 5), prescription: nil,
                                                limit: 0, calendar: cal).isEmpty)
    }

    func testTodayFollowsThePrescription() throws {
        let status = PlanDayStatus(workout: threshold, isCompleted: false)
        let red = try XCTUnwrap(DayPrescription.make(planStatus: status, readiness: .red, target: nil,
                                                     easyPace: 330...350))
        let runs = WatchSchedulePlanner.runs(plan: plan(), today: date(day: 6), prescription: red,
                                             limit: 50, calendar: cal)
        XCTAssertEqual(runs.first?.displayName, "Easy · 5.4 km")
        XCTAssertEqual(runs.first?.blocks.kind, .easy)
        // Later days stay as the plan wrote them.
        XCTAssertEqual(runs.dropFirst().first?.displayName, "Easy · 8 km")
    }

    func testDailyTargetPrescriptionLeavesThePlanAsWritten() throws {
        let target = RunTarget(distanceMeters: 5_000, tone: .neutral, daysSinceLastRun: 1, vo2MaxSlope: nil,
                               baselineMeters: 5_000, ceilingClamped: false, fatigueGuardActive: false)
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil, target: target, easyPace: nil))
        let runs = WatchSchedulePlanner.runs(plan: plan(), today: date(day: 6), prescription: day,
                                             limit: 50, calendar: cal)
        XCTAssertEqual(runs.first?.displayName, "Threshold · 9 km")
    }

    func testPlanEndingStopsTheSchedule() {
        // One week only: from Saturday the 10th, Sunday is the last plan day.
        let runs = WatchSchedulePlanner.runs(plan: plan(weeks: 1), today: date(day: 10), prescription: nil,
                                             limit: 50, calendar: cal)
        XCTAssertEqual(runs.map { cal.component(.day, from: $0.day) }, [10, 11])
    }
}
