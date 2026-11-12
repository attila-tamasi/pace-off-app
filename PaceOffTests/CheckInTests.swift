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
