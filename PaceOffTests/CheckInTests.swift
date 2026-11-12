// CheckInTests.swift
// The runner's morning answer as a readiness signal, its storage for today
// only, and its row in the run ledger.

import XCTest

final class CheckInTests: XCTestCase {

    private let engine = ReadinessEngine()
    private let cal = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!

    private func at(_ daysAgo: Int) -> Date {
        cal.startOfDay(for: today).addingTimeInterval(Double(-daysAgo) * 86_400 + 6 * 3600)
    }

    private func hrv(today value: Double) -> [HRVSnapshot] {
        (1...10).map { HRVSnapshot(date: at($0), sdnnMs: 60) } + [HRVSnapshot(date: at(0), sdnnMs: value)]
    }

    private func readiness(_ feeling: CheckInFeeling?, hrv: [HRVSnapshot] = []) -> DailyReadiness? {
        engine.compute(ReadinessEngine.Inputs(today: today, hrv: hrv, restingHeartRate: [], feeling: feeling))
    }

    // MARK: - Readiness

    func testTiredOrSoreAloneIsYellow() {
        XCTAssertEqual(readiness(.tired)?.level, .yellow)
        XCTAssertEqual(readiness(.tired)?.sentence, "You said you're tired — keep it easy.")
        XCTAssertEqual(readiness(.sore)?.level, .yellow)
        XCTAssertEqual(readiness(.sore)?.sentence, "You said you're sore — keep it easy.")
    }

    func testTiredWithAnotherSignalOffIsRedAndNamesBoth() {
        let r = readiness(.tired, hrv: hrv(today: 53))
        XCTAssertEqual(r?.level, .red)
        XCTAssertEqual(r?.sentence, "HRV down and you feel tired — your body is asking for rest.")
    }

    func testUnwellIsRedAndRest() {
        let r = readiness(.unwell, hrv: hrv(today: 60))
        XCTAssertEqual(r?.level, .red)
        XCTAssertEqual(r?.sentence, "You said you're unwell — rest today.")
        XCTAssertEqual(r?.feeling, .unwell)
    }

    func testFreshNeverLiftsTheWatch() {
        XCTAssertEqual(readiness(.fresh, hrv: hrv(today: 53))?.level, .yellow)
        XCTAssertEqual(readiness(.fresh, hrv: hrv(today: 45))?.level, .red)
        XCTAssertEqual(readiness(.fresh, hrv: hrv(today: 60))?.level, .green)
        XCTAssertEqual(readiness(.normal)?.level, .green)
    }

    func testSkippingChangesNothing() {
        XCTAssertNil(readiness(nil))
        XCTAssertEqual(readiness(nil, hrv: hrv(today: 53))?.sentence, "HRV below your baseline — easy day.")
    }

    // MARK: - Storage

    func testTheAnswerIsTodaysOnly() {
        let defaults = UserDefaults(suiteName: "CheckInTests")!
        defaults.removePersistentDomain(forName: "CheckInTests")
        XCTAssertNil(CheckIn.todayFeeling(in: defaults, now: today))
        CheckIn.save(.sore, in: defaults, now: today)
        XCTAssertEqual(CheckIn.todayFeeling(in: defaults, now: today.addingTimeInterval(3 * 3600)), .sore)
        XCTAssertNil(CheckIn.todayFeeling(in: defaults, now: today.addingTimeInterval(86_400)))
        CheckIn.save(.fresh, in: defaults, now: today)
        XCTAssertEqual(CheckIn.todayFeeling(in: defaults, now: today), .fresh)
        CheckIn.save(nil, in: defaults, now: today)
        XCTAssertNil(CheckIn.todayFeeling(in: defaults, now: today))
        defaults.removePersistentDomain(forName: "CheckInTests")
    }

    func testTheLedgerKeepsItWithTheDay() {
        let file = RunLedgerFile().recording(prescription: nil, readiness: .yellow, feeling: .tired,
                                             runs: [], now: today, calendar: cal)
        XCTAssertEqual(file.day(today, calendar: cal)?.feeling, .tired)
    }
}

// MARK: - Unwell means rest

final class UnwellRestTests: XCTestCase {

    private let cal = Calendar.current

    private func date(hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: hour))!
    }

    private func target(km: Double) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .neutral, daysSinceLastRun: 1,
                  vo2MaxSlope: nil, baselineMeters: km * 1000, ceilingClamped: false,
                  fatigueGuardActive: false, capMeters: km * 1400, computedAt: date(hour: 7))
    }

    private let threshold = Workout(kind: .threshold, distanceMeters: 10_000, paceMinSecPerKm: 280, paceMaxSecPerKm: 295)
    private let kettlebell = StrengthSession(equipment: .kettlebell, minutes: 35, notes: "Swings")

    private func status(_ workout: Workout, strength: StrengthSession? = nil) -> PlanDayStatus {
        PlanDayStatus(workout: workout, isCompleted: false, strength: strength)
    }

    private func day(_ workout: Workout?, strength: StrengthSession? = nil, unwell: Bool) -> DayPrescription {
        DayPrescription.make(planStatus: workout.map { status($0, strength: strength) }, readiness: .red,
                             target: target(km: 6), easyPace: 330...350, unwell: unwell)!
    }

    func testAPlanRunBecomesRest() {
        let d = day(threshold, strength: kettlebell, unwell: true)
        XCTAssertEqual(d.kind, .rest)
        XCTAssertEqual(d.source, .plan)
        XCTAssertNil(d.distanceMeters)
        XCTAssertNil(d.strength)
        XCTAssertNil(d.runWorkout)
        XCTAssertEqual(d.adjustment, .restForUnwell)
        XCTAssertEqual(d.adjustmentNote, "You said you're unwell, so today is rest")
        XCTAssertFalse(d.isMet(byRunMeters: 10_000))
    }

    func testTheDailyTargetBecomesRest() {
        let d = day(nil, unwell: true)
        XCTAssertEqual(d.kind, .rest)
        XCTAssertEqual(d.source, .dailyTarget)
        XCTAssertNil(d.distanceText)
    }

    func testAStrengthDayBecomesRest() {
        XCTAssertEqual(day(.rest, strength: kettlebell, unwell: true).kind, .rest)
        XCTAssertNil(day(.rest, strength: kettlebell, unwell: true).strength)
    }

    func testTheRaceIsLeftToTheRunner() {
        let race = Workout(kind: .race, distanceMeters: 21_100, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        XCTAssertEqual(day(race, unwell: true).kind, .race)
    }

    func testNotUnwellChangesNothing() {
        XCTAssertEqual(day(threshold, unwell: false).adjustment, .cutForRed)
    }

    func testTheVoiceLineSaysRest() {
        let state = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 4,
                               planStatus: status(threshold), prescription: day(threshold, unwell: true))
        XCTAssertEqual(state, .unwellRest)
        XCTAssertFalse(VoiceCopy().todayCard(for: state).contains("km"))
    }

    func testOneMorningPushAndNoReminders() {
        let pushes = DailyPushPlanner(calendar: cal).pushes(for: DailyPushPlanner.Inputs(
            now: date(hour: 6), body: "x", runs: [], plan: nil,
            planStatus: status(threshold, strength: kettlebell), prescription: day(threshold, strength: kettlebell, unwell: true)
        ))
        XCTAssertEqual(pushes.map(\.slot), [.morning, .nextMorning])
        XCTAssertEqual(pushes.first?.body, "You said you're unwell, so no run today. Rest and get well.")
    }

    func testTheWidgetShowsRest() {
        let cache = WidgetCache(target: target(km: 6), voiceLine: "x", runCompletedToday: false,
                                planStatus: status(threshold, strength: kettlebell),
                                prescription: day(threshold, strength: kettlebell, unwell: true))
        XCTAssertNil(cache.distanceText)
        XCTAssertTrue(cache.isPlanRestDay)
        XCTAssertNil(cache.strengthSummary)
    }

    func testTheWatchGetsNoRunToday() throws {
        let plan = TrainingPlanGenerator().generate(TrainingPlanInputs(goal: .tenK, tier: .medium, vo2Max: 48))
        // The plan's first day with a run.
        let today = try XCTUnwrap((0..<7).map { plan.firstDay.addingTimeInterval(Double($0) * 86_400 + 12 * 3600) }
            .first { plan.todayWorkout(today: $0).map { $0.kind != .rest && $0.kind != .race } ?? false })
        let todayStatus = TrainingPlanReconciler().todayStatus(plan: plan, runs: [], today: today)
        let asWritten = DayPrescription.make(planStatus: todayStatus, readiness: .green, target: target(km: 6), easyPace: nil)
        XCTAssertTrue(WatchSchedulePlanner.runs(plan: plan, today: today, prescription: asWritten, limit: 20)
            .contains { cal.isDate($0.day, inSameDayAs: today) })
        let unwell = try XCTUnwrap(DayPrescription.make(planStatus: todayStatus, readiness: .red, target: target(km: 6),
                                                        easyPace: nil, unwell: true))
        let runs = WatchSchedulePlanner.runs(plan: plan, today: today, prescription: unwell, limit: 20)
        XCTAssertFalse(runs.contains { cal.isDate($0.day, inSameDayAs: today) })
    }
}
