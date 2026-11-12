import XCTest

final class SingleRunCapTests: XCTestCase {

    private let cal = Calendar.current
    private let engine = PushTargetEngine()
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 9))!

    private func run(daysAgo: Int, km: Double) -> RunRecord {
        let start = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        return RunRecord(startDate: start, endDate: start.addingTimeInterval(km * 360),
                         distanceMeters: km * 1000, durationSeconds: km * 360)
    }

    // MARK: - The cap

    func testCapIsTenPercentPastTheLongestRunOfTheLast30Days() throws {
        let runs = [run(daysAgo: 2, km: 5), run(daysAgo: 9, km: 8), run(daysAgo: 30, km: 9)]
        XCTAssertEqual(try XCTUnwrap(SingleRunCap.capMeters(runs: runs, today: today, calendar: cal)),
                       9_900, accuracy: 0.001)
    }

    func testTodaysRunAndOlderRunsDontCount() throws {
        let runs = [run(daysAgo: 0, km: 20), run(daysAgo: 31, km: 30), run(daysAgo: 3, km: 6)]
        XCTAssertEqual(try XCTUnwrap(SingleRunCap.capMeters(runs: runs, today: today, calendar: cal)),
                       6_600, accuracy: 0.001)
    }

    func testNoCapWithoutARunInTheLast30Days() {
        XCTAssertNil(SingleRunCap.capMeters(runs: [run(daysAgo: 31, km: 10)], today: today, calendar: cal))
        XCTAssertNil(SingleRunCap.capMeters(runs: [], today: today, calendar: cal))
    }

    // MARK: - The daily target

    func testRunnerWhoseRunsAreAllFiveKmIsKeptToFive() throws {
        // The PRD's worked example: 5 km runs, two days skipped, VO₂ max
        // falling. The PRD rules ask for 6.4 km; the cap is 5.5 km.
        let runs = (2...11).map { run(daysAgo: $0, km: 5) }
        let vo2 = (0..<14).map { i in
            VO2MaxSnapshot(date: cal.date(byAdding: .day, value: -(i * 2), to: today)!,
                           value: 50.0 - (Double(28 - i * 2) * 0.4 / 28))
        }
        let inputs = PushTargetEngine.Inputs(today: today, runs: runs, vo2Max: vo2, restingHeartRate: [])
        XCTAssertEqual(engine.compute(inputs).displayedDistanceKm, 7)

        let target = try XCTUnwrap(engine.target(inputs))
        XCTAssertEqual(target.displayedDistanceKm, 5)
        XCTAssertLessThanOrEqual(target.distanceMeters, 5_500)
        XCTAssertEqual(try XCTUnwrap(target.singleRunCapMeters), 5_500, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(target.capMeters), 5_500, accuracy: 0.001)
    }

    func testTargetWellUnderTheCapIsUnchanged() throws {
        var runs = (1...10).map { run(daysAgo: $0, km: 5) }
        runs.append(run(daysAgo: 12, km: 14))
        let inputs = PushTargetEngine.Inputs(today: today, runs: runs, vo2Max: [], restingHeartRate: [])
        let target = try XCTUnwrap(engine.target(inputs))
        XCTAssertEqual(target.displayedDistanceKm, engine.compute(inputs).displayedDistanceKm)
        XCTAssertNil(target.singleRunCapMeters)
    }

    func testRunnerBackAfter31DaysGetsTheRestartAsBefore() throws {
        let inputs = PushTargetEngine.Inputs(today: today, runs: [run(daysAgo: 31, km: 10)],
                                             vo2Max: [], restingHeartRate: [])
        let target = try XCTUnwrap(engine.target(inputs))
        XCTAssertEqual(target, engine.compute(inputs))
        XCTAssertEqual(target.tone, .restart)
    }

    func testCappedTargetSaysSoInTheDaysPrescription() throws {
        let runs = (2...11).map { run(daysAgo: $0, km: 5) }
        let target = try XCTUnwrap(engine.target(PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: [], restingHeartRate: [])))
        // Two days skipped: 5.6 km asked, shown as 5 under the 5.5 km cap.
        XCTAssertNotNil(target.singleRunCapMeters)
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil, target: target, easyPace: nil))
        XCTAssertEqual(day.capNote, "Kept to 5 km: 10% past your longest run of the last 30 days")
    }

    // MARK: - Today's plan run

    private let longRun = Workout(kind: .long, distanceMeters: 18_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)

    func testLongRunAfterThreeMissedWeeksIsKeptToTheCap() throws {
        let runs = [run(daysAgo: 22, km: 10), run(daysAgo: 25, km: 8)]
        let cap = SingleRunCap.capMeters(runs: runs, today: today, calendar: cal)
        let day = try XCTUnwrap(DayPrescription.make(
            planStatus: PlanDayStatus(workout: longRun, isCompleted: false),
            readiness: .green, target: nil, easyPace: 330...350, singleRunCapMeters: cap))
        XCTAssertEqual(try XCTUnwrap(day.distanceMeters), 11_000, accuracy: 0.001)
        XCTAssertEqual(day.summary, "11.0 km · 5:30–5:50/km")
        XCTAssertEqual(day.capNote, "Kept to 11 km: 10% past your longest run of the last 30 days")
        XCTAssertEqual(day.planWorkout?.distanceMeters, 18_000)
        XCTAssertEqual(day.workoutKind, .long)
    }

    func testPlanRunUnderTheCapIsUntouched() throws {
        let day = try XCTUnwrap(DayPrescription.make(
            planStatus: PlanDayStatus(workout: longRun, isCompleted: false),
            readiness: .green, target: nil, easyPace: nil, singleRunCapMeters: 19_800))
        XCTAssertEqual(day.distanceMeters, 18_000)
        XCTAssertNil(day.capNote)
    }

    func testRaceDayIsNeverCut() throws {
        let race = Workout(kind: .race, distanceMeters: 42_195, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        let day = try XCTUnwrap(DayPrescription.make(
            planStatus: PlanDayStatus(workout: race, isCompleted: false),
            readiness: .green, target: nil, easyPace: nil, singleRunCapMeters: 35_200))
        XCTAssertEqual(day.distanceMeters, 42_195)
        XCTAssertNil(day.capNote)
    }

    func testRedCutUnderTheCapCarriesNoCapNote() throws {
        let day = try XCTUnwrap(DayPrescription.make(
            planStatus: PlanDayStatus(workout: longRun, isCompleted: false),
            readiness: .red, target: nil, easyPace: 330...350, singleRunCapMeters: 11_000))
        XCTAssertEqual(try XCTUnwrap(day.distanceMeters), 10_800, accuracy: 0.001)
        XCTAssertNil(day.capNote)
    }

    func testPushNamesTheCappedRunAndWhy() throws {
        let cap = SingleRunCap.capMeters(runs: [run(daysAgo: 22, km: 10)], today: today, calendar: cal)
        let day = try XCTUnwrap(DayPrescription.make(
            planStatus: PlanDayStatus(workout: longRun, isCompleted: false),
            readiness: .green, target: nil, easyPace: nil, singleRunCapMeters: cap))
        let morning = cal.date(bySettingHour: 6, minute: 0, second: 0, of: today)!
        let body = DailyPushPlanner(calendar: cal).pushes(for: DailyPushPlanner.Inputs(
            now: morning, body: "x", runs: [], plan: nil,
            planStatus: PlanDayStatus(workout: longRun, isCompleted: false), prescription: day
        )).first { $0.slot == .morning }?.body
        XCTAssertEqual(body, "Today's plan: 11.0 km · 5:30–5:50/km. Kept to 11 km: 10% past your longest run of the last 30 days.")
    }
}
