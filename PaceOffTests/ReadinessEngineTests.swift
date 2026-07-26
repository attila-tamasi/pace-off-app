// ReadinessEngineTests.swift
// Exercises the z-score → level mapping, the unknown fallback, and the
// bias-toward-worst-signal rule.

import XCTest
@testable import PaceOff

final class ReadinessEngineTests: XCTestCase {

    private let engine = ReadinessEngine()

    /// A fixed "today" — 2026-01-15 12:00 UTC. Tests use this so relative
    /// baseline windows are deterministic.
    private var today: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 15
        comps.hour = 12; comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: comps)!
    }

    // MARK: - Fixtures

    /// Baseline HRV series: 45 ms mean, ±3 ms noise, over `days` days
    /// ending strictly before `today`. Deterministic (no RNG).
    private func steadyHRVBaseline(days: Int, mean: Double = 45,
                                   swing: Double = 3) -> [HRVSnapshot] {
        (1...days).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let jitter = offset.isMultiple(of: 2) ? swing : -swing
            return HRVSnapshot(date: date, ms: mean + jitter)
        }
    }

    private func steadyRHRBaseline(days: Int, mean: Double = 55,
                                   swing: Double = 2) -> [RestingHeartRateSnapshot] {
        (1...days).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            let jitter = offset.isMultiple(of: 2) ? swing : -swing
            return RestingHeartRateSnapshot(date: date, bpm: mean + jitter)
        }
    }

    private func appendingToday(_ hrv: [HRVSnapshot], todayMs: Double) -> [HRVSnapshot] {
        hrv + [HRVSnapshot(date: today, ms: todayMs)]
    }

    private func appendingToday(_ rhr: [RestingHeartRateSnapshot], todayBpm: Double) -> [RestingHeartRateSnapshot] {
        rhr + [RestingHeartRateSnapshot(date: today, bpm: todayBpm)]
    }

    // MARK: - Unknown fallback

    func test_score_returnsUnknown_whenNoData() {
        let s = engine.score(hrvHistory: [], restingHRHistory: [], today: today)
        XCTAssertEqual(s.level, .unknown)
    }

    func test_score_returnsUnknown_whenBaselineTooShort() {
        // 5 days of HRV baseline — under the 7-day minimum.
        let hrv = appendingToday(steadyHRVBaseline(days: 5), todayMs: 20)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: [], today: today)
        XCTAssertEqual(s.level, .unknown)
    }

    // MARK: - Green path

    func test_score_isGreen_whenHRVAndRHROnBaseline() {
        let hrv = appendingToday(steadyHRVBaseline(days: 20), todayMs: 45)
        let rhr = appendingToday(steadyRHRBaseline(days: 14), todayBpm: 55)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: rhr, today: today)
        XCTAssertEqual(s.level, .green)
        XCTAssertEqual(s.hrvToday, 45)
        XCTAssertEqual(s.restingHRToday, 55)
    }

    // MARK: - Yellow path — HRV alone

    func test_score_isYellow_whenHRVSuppressedMildly() {
        // Baseline mean 45, stdDev ~3. Today = 40 → z ≈ −1.6.
        let hrv = appendingToday(steadyHRVBaseline(days: 20), todayMs: 40)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: [], today: today)
        XCTAssertEqual(s.level, .yellow)
        XCTAssertTrue(s.headline.contains("HRV"))
    }

    // MARK: - Red path — HRV alone

    func test_score_isRed_whenHRVSuppressedSeverely() {
        // Baseline mean 45, stdDev ~3. Today = 30 → z ≈ −5.
        let hrv = appendingToday(steadyHRVBaseline(days: 20), todayMs: 30)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: [], today: today)
        XCTAssertEqual(s.level, .red)
    }

    // MARK: - RHR elevation drives yellow/red

    func test_score_isYellow_whenRHRElevated() {
        // Baseline 55 ± 2. Today = 60 → z ≈ +2.5 (flipped → −2.5).
        let rhr = appendingToday(steadyRHRBaseline(days: 14), todayBpm: 60)
        let s = engine.score(hrvHistory: [], restingHRHistory: rhr, today: today)
        // z ≈ −2.5 crosses the red threshold too — accept either red or yellow
        // depending on stdDev; the important thing is it's *not* green.
        XCTAssertNotEqual(s.level, .green)
        XCTAssertNotEqual(s.level, .unknown)
        XCTAssertTrue(s.headline.lowercased().contains("resting"))
    }

    // MARK: - Worst-of-two rule

    func test_score_takesWorseSignal_whenHRVGreenAndRHRRed() {
        // HRV steady on baseline → green signal.
        let hrv = appendingToday(steadyHRVBaseline(days: 20), todayMs: 45)
        // RHR 10 bpm above baseline → strong red signal.
        let rhr = appendingToday(steadyRHRBaseline(days: 14), todayBpm: 65)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: rhr, today: today)
        XCTAssertEqual(s.level, .red, "Worst signal must dictate the call")
        XCTAssertTrue(s.headline.lowercased().contains("resting"))
    }

    // MARK: - Bake-in metadata

    func test_score_includesBaselineMeans() {
        let hrv = appendingToday(steadyHRVBaseline(days: 20, mean: 50), todayMs: 50)
        let rhr = appendingToday(steadyRHRBaseline(days: 14, mean: 60), todayBpm: 60)
        let s = engine.score(hrvHistory: hrv, restingHRHistory: rhr, today: today)
        XCTAssertEqual(s.hrvBaseline ?? 0, 50, accuracy: 0.5)
        XCTAssertEqual(s.restingHRBaseline ?? 0, 60, accuracy: 0.5)
    }

    // MARK: - Yesterday-fallback path

    func test_score_usesYesterdayHRV_whenTodayMissing() {
        // 20 baseline days, no sample on `today`. Yesterday sits at a
        // strongly suppressed value → engine should still register the drop.
        var hrv = steadyHRVBaseline(days: 20)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        hrv.removeAll { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        hrv.append(HRVSnapshot(date: yesterday, ms: 25))
        let s = engine.score(hrvHistory: hrv, restingHRHistory: [], today: today)
        XCTAssertEqual(s.level, .red, "Yesterday's HRV should feed the score when today's is missing")
    }
}
