// SleepReadinessTests.swift
// Nights of sleep from Health's asleep intervals, and sleep as the third
// readiness signal.

import XCTest

final class SleepReadinessTests: XCTestCase {

    private let engine = ReadinessEngine()
    private let cal = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!

    private func at(_ daysAgo: Int, hour: Double) -> Date {
        cal.startOfDay(for: today).addingTimeInterval(Double(-daysAgo) * 86_400 + hour * 3600)
    }

    private func nights(usual: Double, lastNight: Double?, count: Int = 14) -> [SleepNight] {
        var all = (1...count).map {
            SleepNight(night: cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: today))!,
                       asleepSeconds: usual * 3600)
        }
        if let lastNight { all.append(SleepNight(night: cal.startOfDay(for: today), asleepSeconds: lastNight * 3600)) }
        return all.sorted { $0.night < $1.night }
    }

    private func readiness(sleep: [SleepNight],
                           hrv: [HRVSnapshot] = [], rhr: [RestingHeartRateSnapshot] = []) -> DailyReadiness? {
        engine.compute(ReadinessEngine.Inputs(today: today, hrv: hrv, restingHeartRate: rhr, sleep: sleep))
    }

    private func hrv(baseline: Double, today value: Double) -> [HRVSnapshot] {
        (1...10).map { HRVSnapshot(date: at($0, hour: 6), sdnnMs: baseline) } + [HRVSnapshot(date: at(0, hour: 6), sdnnMs: value)]
    }

    private func rhr(baseline: Double, today value: Double) -> [RestingHeartRateSnapshot] {
        (1...10).map { RestingHeartRateSnapshot(date: at($0, hour: 6), bpm: baseline) }
            + [RestingHeartRateSnapshot(date: at(0, hour: 6), bpm: value)]
    }

    // MARK: - Nights

    func testANightBelongsToTheDayItEndsOn() {
        let night = SleepNight.nights(from: [DateInterval(start: at(1, hour: 23), end: at(0, hour: 7))], calendar: cal)
        XCTAssertEqual(night, [SleepNight(night: cal.startOfDay(for: today), asleepSeconds: 8 * 3600)])
    }

    func testStagesAddUpAndOverlapsCountOnce() {
        let intervals = [
            DateInterval(start: at(1, hour: 23), end: at(0, hour: 2)),   // core
            DateInterval(start: at(0, hour: 2), end: at(0, hour: 3)),    // deep
            DateInterval(start: at(0, hour: 1), end: at(0, hour: 2.5)),  // another source, overlapping
            DateInterval(start: at(0, hour: 4), end: at(0, hour: 6.5)),  // after waking at 3–4
        ]
        let nights = SleepNight.nights(from: intervals, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].asleepHours, 6.5, accuracy: 1e-9)
    }

    func testTwoNightsStayApart() {
        let nights = SleepNight.nights(from: [
            DateInterval(start: at(2, hour: 23), end: at(1, hour: 6)),
            DateInterval(start: at(1, hour: 22.5), end: at(0, hour: 6)),
        ], calendar: cal)
        XCTAssertEqual(nights.map(\.asleepHours), [7, 7.5])
    }

    // MARK: - Readiness

    func testAUsualNightIsGreen() {
        let r = readiness(sleep: nights(usual: 7.5, lastNight: 7.4))
        XCTAssertEqual(r?.level, .green)
        XCTAssertEqual(r?.sleepHours ?? 0, 7.4, accuracy: 1e-9)
        XCTAssertEqual(r?.sleepBaselineHours ?? 0, 7.5, accuracy: 1e-9)
    }

    func testFifteenPercentShortIsYellow() {
        let r = readiness(sleep: nights(usual: 8, lastNight: 6.7))
        XCTAssertEqual(r?.level, .yellow)
        XCTAssertEqual(r?.sentence, "Less sleep than usual last night — keep it easy.")
    }

    func testThirtyPercentShortIsRed() {
        let r = readiness(sleep: nights(usual: 8, lastNight: 5.5))
        XCTAssertEqual(r?.level, .red)
        XCTAssertEqual(r?.sentence, "Much less sleep than usual last night — rest or keep it very easy.")
    }

    func testItNeedsFiveNightsBehindIt() {
        XCTAssertNil(readiness(sleep: nights(usual: 8, lastNight: 4, count: 4)))
        XCTAssertEqual(readiness(sleep: nights(usual: 8, lastNight: 4, count: 5))?.level, .red)
    }

    func testWithoutLastNightSleepDoesNotCount() {
        XCTAssertNil(readiness(sleep: nights(usual: 8, lastNight: nil)))
        let r = readiness(sleep: nights(usual: 8, lastNight: nil), hrv: hrv(baseline: 60, today: 60))
        XCTAssertEqual(r?.level, .green)
        XCTAssertNil(r?.sleepHours)
    }

    func testShortSleepAndLowHRVTogetherAreRedAndBothNamed() {
        let r = readiness(sleep: nights(usual: 8, lastNight: 6.7), hrv: hrv(baseline: 60, today: 53))
        XCTAssertEqual(r?.level, .red)
        XCTAssertEqual(r?.sentence, "HRV down and short sleep — your body is asking for rest.")
    }

    func testAllThreeOffAreNamed() {
        let r = readiness(sleep: nights(usual: 8, lastNight: 6.7),
                          hrv: hrv(baseline: 60, today: 53), rhr: rhr(baseline: 50, today: 53))
        XCTAssertEqual(r?.sentence, "HRV down, resting heart rate up and short sleep — your body is asking for rest.")
    }

    func testTheWorstSignalSetsTheDay() {
        let r = readiness(sleep: nights(usual: 8, lastNight: 8), hrv: hrv(baseline: 60, today: 46))
        XCTAssertEqual(r?.level, .red)
        XCTAssertEqual(r?.sentence, "HRV well below your baseline — rest or keep it very easy.")
    }

    func testTheCardsGradeIsTheEngines() {
        XCTAssertEqual(ReadinessEngine.sleepLevel(hours: 7.5, baseline: 8), .green)
        XCTAssertEqual(ReadinessEngine.sleepLevel(hours: 6.7, baseline: 8), .yellow)
        XCTAssertEqual(ReadinessEngine.sleepLevel(hours: 5.5, baseline: 8), .red)
        let r = readiness(sleep: nights(usual: 8, lastNight: 6.7))
        XCTAssertEqual(ReadinessEngine.sleepLevel(hours: r!.sleepHours!, baseline: r!.sleepBaselineHours!), r!.level)
    }

    func testSleepText() {
        XCTAssertEqual(ReadinessEngine.sleepText(hours: 7.0833333), "7:05")
        XCTAssertEqual(ReadinessEngine.sleepText(hours: 8), "8:00")
        XCTAssertEqual(ReadinessEngine.sleepText(hours: 5.999), "6:00")
    }

    func testTheSnapshotKeepsItsNightsAndAnOldOneDecodes() throws {
        var snapshot = HealthDataSnapshot(lastSyncedAt: today)
        XCTAssertFalse(snapshot.hasReadings)
        snapshot.sleep = nights(usual: 7, lastNight: 7)
        XCTAssertTrue(snapshot.hasReadings)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(HealthDataSnapshot.self, from: data), snapshot)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sleep"] = nil
        let old = try JSONDecoder().decode(HealthDataSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.sleepOrEmpty, [])
    }
}
