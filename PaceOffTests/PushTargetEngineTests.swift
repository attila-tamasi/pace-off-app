// PushTargetEngineTests.swift
// Verifies PRD §7 behavior including the worked example in §7.3.

import XCTest
@testable import PaceOff

final class PushTargetEngineTests: XCTestCase {

    let engine = PushTargetEngine()
    let cal = Calendar.current

    private func date(_ daysAgo: Int, from today: Date = Date()) -> Date {
        cal.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    private func run(daysAgo: Int, km: Double, today: Date) -> RunRecord {
        let start = date(daysAgo, from: today)
        return RunRecord(
            startDate: start,
            endDate: start.addingTimeInterval(km * 360), // ~6 min/km
            distanceMeters: km * 1000,
            durationSeconds: km * 360
        )
    }

    private func vo2(daysAgo: Int, value: Double, today: Date) -> VO2MaxSnapshot {
        VO2MaxSnapshot(date: date(daysAgo, from: today), value: value)
    }

    // MARK: - Median helper

    func test_median_oddCount() {
        XCTAssertEqual(engine.median([1, 5, 3]), 3)
    }

    func test_median_evenCount() {
        XCTAssertEqual(engine.median([1, 2, 3, 4]), 2.5)
    }

    func test_median_empty() {
        XCTAssertNil(engine.median([]))
    }

    // MARK: - VO2Max slope

    func test_vo2MaxSlope_declining() {
        let today = Date()
        let samples = (0..<14).map { i in
            vo2(daysAgo: i * 2, value: 50.0 - Double(i) * 0.2, today: today)
        }
        let slope = engine.vo2MaxSlopePerWeek(samples, asOf: today)
        XCTAssertNotNil(slope)
        XCTAssertLessThan(slope!, 0)
    }

    func test_vo2MaxSlope_improving() {
        let today = Date()
        let samples = (0..<14).map { i in
            vo2(daysAgo: i * 2, value: 50.0 + Double(i) * 0.2, today: today)
        }
        let slope = engine.vo2MaxSlopePerWeek(samples, asOf: today)
        XCTAssertNotNil(slope)
        XCTAssertGreaterThan(slope!, 0)
    }

    func test_vo2MaxSlope_insufficientSamples() {
        let today = Date()
        XCTAssertNil(engine.vo2MaxSlopePerWeek([vo2(daysAgo: 5, value: 50, today: today)], asOf: today))
    }

    // MARK: - Days since last run

    func test_daysSinceLastRun_yesterday() {
        let today = Date()
        let runs = [run(daysAgo: 1, km: 5, today: today)]
        XCTAssertEqual(engine.daysSinceLastRun(runs, today: today), 1)
    }

    func test_daysSinceLastRun_noRuns() {
        XCTAssertEqual(engine.daysSinceLastRun([], today: Date()), 999)
    }

    // MARK: - Worked example (PRD §7.3)
    // 14-day median = 5.0 km, VO2Max declining (-0.4 ml/kg/min over 28 days), 2 days skipped
    // Expected: target ≈ 6.4 km, tone = aggressive

    func test_workedExample_PRD_7_3() {
        let today = Date()

        // 10 runs over the last 14 days, all 5.0 km, ending 2 days ago
        var runs: [RunRecord] = []
        for i in 0..<10 {
            // skip days 0 and 1 (today and yesterday) — last run was 2 days ago
            let daysAgo = i + 2
            runs.append(run(daysAgo: daysAgo, km: 5.0, today: today))
        }

        // VO2Max declining 0.4 over 28 days = roughly -0.1 per week
        let vo2Series: [VO2MaxSnapshot] = (0..<14).map { i in
            let daysAgo = i * 2
            return vo2(daysAgo: daysAgo, value: 50.0 - (Double(28 - daysAgo) * 0.4 / 28), today: today)
        }

        let inputs = PushTargetEngine.Inputs(
            today: today,
            runs: runs,
            vo2Max: vo2Series,
            restingHeartRate: []
        )
        let target = engine.compute(inputs)

        XCTAssertEqual(target.daysSinceLastRun, 2)
        XCTAssertEqual(target.tone, .aggressive)
        XCTAssertEqual(target.baselineMeters, 5000, accuracy: 0.1)

        // 5.0 * 1.15 (VO2 decline) * 1.12 (2 skipped) = 6.44 km, rounded to 6.4 km
        // Hard ceiling = 5.0 * 1.4 = 7.0 km — passes
        XCTAssertEqual(target.distanceMeters, 6400, accuracy: 100)
        XCTAssertFalse(target.ceilingClamped)
    }

    // MARK: - Restart behavior

    func test_threeDaySkip_triggersRestart() {
        let today = Date()
        let runs = (3...10).map { run(daysAgo: $0, km: 6.0, today: today) }
        let inputs = PushTargetEngine.Inputs(
            today: today,
            runs: runs,
            vo2Max: [],
            restingHeartRate: []
        )
        let target = engine.compute(inputs)
        XCTAssertEqual(target.tone, .restart)
        XCTAssertGreaterThanOrEqual(target.distanceMeters, 3000)
        // Restart should not exceed the ceiling on baseline
        XCTAssertLessThanOrEqual(target.distanceMeters, target.baselineMeters * 1.4 + 0.1)
    }

    // MARK: - Hard ceiling

    func test_hardCeiling_clamps() {
        let today = Date()
        // Many small runs (1 km baseline) but VO2Max plummeting AND 2 days skipped
        let runs = (2...12).map { run(daysAgo: $0, km: 1.0, today: today) }
        let vo2Series: [VO2MaxSnapshot] = (0..<14).map { i in
            vo2(daysAgo: i * 2, value: 60.0 - Double(i) * 1.0, today: today)
        }
        let inputs = PushTargetEngine.Inputs(
            today: today,
            runs: runs,
            vo2Max: vo2Series,
            restingHeartRate: []
        )
        let target = engine.compute(inputs)
        // Baseline 1.0 km, ceiling = 1.4 km
        XCTAssertEqual(target.distanceMeters, 1400, accuracy: 100)
        XCTAssertTrue(target.ceilingClamped)
    }

    // MARK: - Long run recovery

    func test_yesterdayLongRun_triggersRecovery() {
        let today = Date()
        // 14-day baseline 5 km, but yesterday was 10 km
        var runs: [RunRecord] = []
        for i in 2...12 {
            runs.append(run(daysAgo: i, km: 5.0, today: today))
        }
        runs.append(run(daysAgo: 1, km: 10.0, today: today))

        let inputs = PushTargetEngine.Inputs(
            today: today,
            runs: runs,
            vo2Max: [],
            restingHeartRate: []
        )
        let target = engine.compute(inputs)
        XCTAssertEqual(target.tone, .recovery)
        XCTAssertEqual(target.distanceMeters, 3000, accuracy: 100) // 5.0 * 0.6 = 3.0 km
    }

    // MARK: - Fatigue guard

    func test_elevatedRestingHR_capsAtBaseline() {
        let today = Date()
        var runs: [RunRecord] = []
        for i in 1...12 { runs.append(run(daysAgo: i, km: 5.0, today: today)) }

        // Baseline RHR = 50, today's = 60 (20% elevated)
        var rhr: [RestingHeartRateSnapshot] = []
        for i in 1...6 { rhr.append(RestingHeartRateSnapshot(date: date(i, from: today), bpm: 50)) }
        rhr.append(RestingHeartRateSnapshot(date: date(0, from: today), bpm: 60))

        // Force decline so target would otherwise exceed baseline
        let vo2Series: [VO2MaxSnapshot] = (0..<14).map { i in
            vo2(daysAgo: i * 2, value: 50.0 - Double(i) * 0.5, today: today)
        }

        let inputs = PushTargetEngine.Inputs(today: today, runs: runs, vo2Max: vo2Series, restingHeartRate: rhr)
        let target = engine.compute(inputs)
        XCTAssertTrue(target.fatigueGuardActive)
        XCTAssertLessThanOrEqual(target.distanceMeters, target.baselineMeters + 0.01)
    }

    // MARK: - Empty data

    func test_noRuns_returnsRestartFloor() {
        let inputs = PushTargetEngine.Inputs(today: Date(), runs: [], vo2Max: [], restingHeartRate: [])
        let target = engine.compute(inputs)
        XCTAssertGreaterThanOrEqual(target.distanceMeters, 3000)
        XCTAssertEqual(target.tone, .restart)
    }

    // MARK: - Readiness traffic light (SPEC §11 follow-up)

    func test_redReadiness_capsAtSixtyPercentAndSetsRecovery() {
        let today = Date()
        // Ran yesterday: baseline 5 km, skip factor 1.05 → 5.25 km, tone firm.
        let runs = (1...12).map { run(daysAgo: $0, km: 5.0, today: today) }
        let inputs = PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: [], restingHeartRate: [],
            readiness: .red
        )
        let target = engine.compute(inputs)
        XCTAssertEqual(target.distanceMeters, 3000, accuracy: 100) // 5.0 * 0.6
        XCTAssertEqual(target.tone, .recovery)
        XCTAssertEqual(target.readinessCapApplied, true)
    }

    func test_yellowReadiness_holdsBaseline() {
        let today = Date()
        let runs = (1...12).map { run(daysAgo: $0, km: 5.0, today: today) }
        // Declining VO2 would push the target to 5.0 * 1.15 * 1.05 ≈ 6.0 km.
        let vo2Series: [VO2MaxSnapshot] = (0..<14).map { i in
            vo2(daysAgo: i * 2, value: 50.0 - Double(i) * 0.5, today: today)
        }
        let inputs = PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: vo2Series, restingHeartRate: [],
            readiness: .yellow
        )
        let target = engine.compute(inputs)
        XCTAssertEqual(target.distanceMeters, target.baselineMeters, accuracy: 100)
        XCTAssertEqual(target.readinessCapApplied, true)
        XCTAssertNotEqual(target.tone, .aggressive, "Yellow softens an aggressive push")
    }

    func test_greenReadiness_changesNothing() {
        let today = Date()
        let runs = (1...12).map { run(daysAgo: $0, km: 5.0, today: today) }
        let plain = engine.compute(PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: [], restingHeartRate: []
        ))
        let green = engine.compute(PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: [], restingHeartRate: [],
            readiness: .green
        ))
        XCTAssertEqual(green.distanceMeters, plain.distanceMeters)
        XCTAssertEqual(green.tone, plain.tone)
        XCTAssertEqual(green.readinessCapApplied, false)
    }

    func test_redReadiness_noCapFlag_whenAlreadyBelowCap() {
        let today = Date()
        // Yesterday was a long run → recovery already set the target to
        // 0.6 × baseline; red readiness has nothing left to cap.
        var runs = (2...12).map { run(daysAgo: $0, km: 5.0, today: today) }
        runs.append(run(daysAgo: 1, km: 10.0, today: today))
        let inputs = PushTargetEngine.Inputs(
            today: today, runs: runs, vo2Max: [], restingHeartRate: [],
            readiness: .red
        )
        let target = engine.compute(inputs)
        XCTAssertEqual(target.distanceMeters, 3000, accuracy: 100)
        XCTAssertEqual(target.tone, .recovery)
        XCTAssertEqual(target.readinessCapApplied, false)
    }

    // MARK: - RunTarget backward compatibility

    func test_runTarget_codableTolerantOfMissingReadinessField() throws {
        // Cached widget JSON written before readinessCapApplied existed has
        // no such key — encoding a nil optional omits it, so a round-trip
        // with nil proves both directions of the compatibility story.
        let legacy = RunTarget(
            distanceMeters: 5000, tone: .firm, daysSinceLastRun: 1,
            vo2MaxSlope: nil, baselineMeters: 5000,
            ceilingClamped: false, fatigueGuardActive: false
        )
        let data = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("readinessCapApplied"))
        let decoded = try JSONDecoder().decode(RunTarget.self, from: data)
        XCTAssertNil(decoded.readinessCapApplied)
    }
}
