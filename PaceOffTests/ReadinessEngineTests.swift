// ReadinessEngineTests.swift
// Baseline math + traffic-light grading for the daily readiness engine
// (SPEC §A). Mirrors the relative-date style of PushTargetEngineTests.

import XCTest
@testable import PaceOff

final class ReadinessEngineTests: XCTestCase {

    let engine = ReadinessEngine()
    let cal = Calendar.current

    private func date(_ daysAgo: Int, from today: Date) -> Date {
        cal.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    /// HRV history: one reading per day for `days` days at `baseline` ms,
    /// then today's reading at `todayValue`.
    private func hrvSeries(baseline: Double, days: Int, todayValue: Double, today: Date) -> [HRVSnapshot] {
        var series = (1...days).map { HRVSnapshot(date: date($0, from: today), sdnnMs: baseline) }
        series.append(HRVSnapshot(date: today, sdnnMs: todayValue))
        return series
    }

    private func rhrSeries(baseline: Double, days: Int, todayValue: Double, today: Date) -> [RestingHeartRateSnapshot] {
        var series = (1...days).map { RestingHeartRateSnapshot(date: date($0, from: today), bpm: baseline) }
        series.append(RestingHeartRateSnapshot(date: today, bpm: todayValue))
        return series
    }

    // MARK: - Daily means

    func test_dailyMeans_averagesSameDaySamples() {
        let today = Date()
        let morning = cal.startOfDay(for: today).addingTimeInterval(3600)
        let evening = cal.startOfDay(for: today).addingTimeInterval(20 * 3600)
        let days = engine.dailyMeans([(morning, 40), (evening, 60)])
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].value, 50)
    }

    func test_dailyMeans_sortsAscending() {
        let today = Date()
        let days = engine.dailyMeans([
            (date(1, from: today), 50),
            (date(3, from: today), 40),
            (date(2, from: today), 45),
        ])
        XCTAssertEqual(days.map { $0.value }, [40, 45, 50])
    }

    // MARK: - Baseline selection

    func test_baseline_excludesTodaysReading() {
        let today = Date()
        let days = engine.dailyMeans(
            hrvSeries(baseline: 60, days: 10, todayValue: 30, today: today).map { ($0.date, $0.sdnnMs) }
        )
        let reading = engine.todayValueAndBaseline(
            days, today: today, baselineWindowDays: 30, minBaselineDays: 7
        )
        XCTAssertEqual(reading?.value, 30)
        XCTAssertEqual(reading?.baseline, 60)
    }

    func test_baseline_acceptsYesterdayAsTodaysReading() {
        // Overnight HRV often lands on the previous calendar day.
        let today = Date()
        var series = (2...12).map { HRVSnapshot(date: date($0, from: today), sdnnMs: 60) }
        series.append(HRVSnapshot(date: date(1, from: today), sdnnMs: 30))
        let days = engine.dailyMeans(series.map { ($0.date, $0.sdnnMs) })
        let reading = engine.todayValueAndBaseline(
            days, today: today, baselineWindowDays: 30, minBaselineDays: 7
        )
        XCTAssertEqual(reading?.value, 30)
        XCTAssertEqual(reading?.baseline, 60)
    }

    func test_baseline_nilWhenHistoryTooShort() {
        let today = Date()
        let days = engine.dailyMeans(
            hrvSeries(baseline: 60, days: 4, todayValue: 55, today: today).map { ($0.date, $0.sdnnMs) }
        )
        XCTAssertNil(engine.todayValueAndBaseline(
            days, today: today, baselineWindowDays: 30, minBaselineDays: 7
        ))
    }

    func test_baseline_nilWhenNoRecentReading() {
        // History exists but nothing today or yesterday → no verdict.
        let today = Date()
        let series = (3...14).map { HRVSnapshot(date: date($0, from: today), sdnnMs: 60) }
        let days = engine.dailyMeans(series.map { ($0.date, $0.sdnnMs) })
        XCTAssertNil(engine.todayValueAndBaseline(
            days, today: today, baselineWindowDays: 30, minBaselineDays: 7
        ))
    }

    // MARK: - Traffic light

    func test_green_whenBothOnBaseline() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 61, today: today),
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 50, today: today)
        ))
        XCTAssertEqual(readiness?.level, .green)
    }

    func test_yellow_whenHRVDipsTenPercent() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 52, today: today), // −13%
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 50, today: today)
        ))
        XCTAssertEqual(readiness?.level, .yellow)
        XCTAssertEqual(readiness?.sentence, "HRV below your baseline — easy day.")
    }

    func test_yellow_whenRestingHRRisesFourPercent() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 60, today: today),
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 53, today: today) // +6%
        ))
        XCTAssertEqual(readiness?.level, .yellow)
    }

    func test_red_whenHRVCollapses() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 45, today: today), // −25%
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 50, today: today)
        ))
        XCTAssertEqual(readiness?.level, .red)
    }

    func test_red_whenBothSignalsYellow() {
        // Two independently degraded signals escalate to red.
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 52, today: today),      // −13% → yellow
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 53, today: today) // +6% → yellow
        ))
        XCTAssertEqual(readiness?.level, .red)
    }

    func test_gradesFromRHRAlone_whenNoHRVHistory() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: [],
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 55, today: today) // +10% → red
        ))
        XCTAssertEqual(readiness?.level, .red)
        XCTAssertNil(readiness?.hrvMs)
    }

    func test_nil_whenNoSignalHasHistory() {
        XCTAssertNil(engine.compute(.init(today: Date(), hrv: [], restingHeartRate: [])))
    }

    func test_surfacesNumbersBehindTheVerdict() {
        let today = Date()
        let readiness = engine.compute(.init(
            today: today,
            hrv: hrvSeries(baseline: 60, days: 14, todayValue: 45, today: today),
            restingHeartRate: rhrSeries(baseline: 50, days: 10, todayValue: 52, today: today)
        ))
        XCTAssertEqual(readiness?.hrvMs, 45)
        XCTAssertEqual(readiness?.hrvBaselineMs, 60)
        XCTAssertEqual(readiness?.restingHR, 52)
        XCTAssertEqual(readiness?.restingHRBaseline, 50)
    }
}
