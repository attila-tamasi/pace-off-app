// HeartTrendTests.swift
// Covers the numbers behind the HRV and resting heart rate screens: the
// baseline and level agree with ReadinessEngine, the latest reading is
// today's or yesterday's and never older, short history has no baseline,
// and each range keeps one mean per day, oldest first.

import XCTest
@testable import PaceOff

final class HeartTrendTests: XCTestCase {

    private let cal = Calendar.current

    /// A Friday morning; dates are built from local components, so the day
    /// is the same in any timezone.
    private lazy var today = cal.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 9))!

    /// `offset` days from today at `hour` o'clock (overnight readings by
    /// default).
    private func day(_ offset: Int, hour: Int = 3) -> Date {
        let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today))!
        return cal.date(byAdding: .hour, value: hour, to: start)!
    }

    /// One reading a day at `value` for each offset, plus the given extras.
    private func samples(_ offsets: ClosedRange<Int>, value: Double,
                         plus extra: [(date: Date, value: Double)] = []) -> [(date: Date, value: Double)] {
        offsets.map { (date: day($0), value: value) } + extra
    }

    // MARK: - Agrees with ReadinessEngine

    func test_hrv_baselineAndLevel_matchReadiness() {
        // 20 nights at 60 ms, then 47 ms last night: 22% below → red.
        let s = samples(-20 ... -1, value: 60, plus: [(date: day(0), value: 47)])
        let trend = HeartTrend(metric: .hrv, samples: s, range: .month, today: today)
        let readiness = ReadinessEngine().compute(ReadinessEngine.Inputs(
            today: today,
            hrv: s.map { HRVSnapshot(date: $0.date, sdnnMs: $0.value) },
            restingHeartRate: []
        ))

        XCTAssertEqual(trend.latest?.value ?? 0, 47, accuracy: 0.001)
        XCTAssertEqual(trend.baseline ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(trend.baseline ?? 0, readiness?.hrvBaselineMs ?? -1, accuracy: 0.001)
        XCTAssertEqual(trend.latest?.value ?? 0, readiness?.hrvMs ?? -1, accuracy: 0.001)
        XCTAssertEqual(trend.change ?? 0, -13.0 / 60, accuracy: 0.001)
        XCTAssertEqual(trend.level, .red)
        XCTAssertEqual(readiness?.level, .red)
    }

    func test_hrv_levels() {
        func level(_ latest: Double) -> ReadinessLevel? {
            HeartTrend(metric: .hrv,
                       samples: samples(-20 ... -1, value: 60, plus: [(date: day(0), value: latest)]),
                       range: .month, today: today).level
        }
        XCTAssertEqual(level(53), .yellow)   // 11.7% below
        XCTAssertEqual(level(58), .green)    // 3.3% below
        XCTAssertEqual(level(70), .green)    // above is good
    }

    func test_restingHR_levels_matchReadiness() {
        func trendAndReadiness(_ latest: Double) -> (HeartTrend, DailyReadiness?) {
            let s = samples(-10 ... -1, value: 50, plus: [(date: day(0, hour: 8), value: latest)])
            let trend = HeartTrend(metric: .restingHeartRate, samples: s, range: .week, today: today)
            let readiness = ReadinessEngine().compute(ReadinessEngine.Inputs(
                today: today,
                hrv: [],
                restingHeartRate: s.map { RestingHeartRateSnapshot(date: $0.date, bpm: $0.value) }
            ))
            return (trend, readiness)
        }

        let (red, redReadiness) = trendAndReadiness(54.5)       // 9% above
        XCTAssertEqual(red.level, .red)
        XCTAssertEqual(redReadiness?.level, .red)
        XCTAssertEqual(red.baseline ?? 0, redReadiness?.restingHRBaseline ?? -1, accuracy: 0.001)

        let (yellow, yellowReadiness) = trendAndReadiness(52.5) // 5% above
        XCTAssertEqual(yellow.level, .yellow)
        XCTAssertEqual(yellowReadiness?.level, .yellow)

        XCTAssertEqual(trendAndReadiness(48).0.level, .green)   // below is good
    }

    // MARK: - One signal on its own, as the readiness screen shows it

    func test_staticLevel_gradesOneSignal() {
        XCTAssertEqual(HeartTrend.level(for: .hrv, value: 47, baseline: 60), .red)
        XCTAssertEqual(HeartTrend.level(for: .hrv, value: 53, baseline: 60), .yellow)
        XCTAssertEqual(HeartTrend.level(for: .hrv, value: 66, baseline: 60), .green)
        XCTAssertEqual(HeartTrend.level(for: .restingHeartRate, value: 54.5, baseline: 50), .red)
        XCTAssertEqual(HeartTrend.level(for: .restingHeartRate, value: 52.5, baseline: 50), .yellow)
        XCTAssertEqual(HeartTrend.level(for: .restingHeartRate, value: 48, baseline: 50), .green)
        XCTAssertNil(HeartTrend.level(for: .hrv, value: 50, baseline: 0))
    }

    func test_twoYellowSignals_eachYellow_dayRed() {
        // The readiness screen shows each signal yellow and explains why the
        // day is red: both are off.
        let hrv = samples(-20 ... -1, value: 60, plus: [(date: day(0), value: 53)])
        let rhr = samples(-10 ... -1, value: 50, plus: [(date: day(0, hour: 8), value: 52.5)])
        let readiness = ReadinessEngine().compute(ReadinessEngine.Inputs(
            today: today,
            hrv: hrv.map { HRVSnapshot(date: $0.date, sdnnMs: $0.value) },
            restingHeartRate: rhr.map { RestingHeartRateSnapshot(date: $0.date, bpm: $0.value) }
        ))
        XCTAssertEqual(readiness?.level, .red)
        XCTAssertEqual(HeartTrend.level(for: .hrv, value: readiness?.hrvMs ?? 0, baseline: readiness?.hrvBaselineMs ?? 0), .yellow)
        XCTAssertEqual(HeartTrend.level(for: .restingHeartRate,
                                        value: readiness?.restingHR ?? 0,
                                        baseline: readiness?.restingHRBaseline ?? 0), .yellow)
    }

    // MARK: - Latest reading

    func test_latest_fallsBackToYesterday() {
        let trend = HeartTrend(metric: .hrv, samples: samples(-20 ... -1, value: 60), range: .month, today: today)
        XCTAssertEqual(trend.latest?.date, cal.startOfDay(for: day(-1)))
        // Yesterday is the reading, so the baseline is the 19 nights before.
        XCTAssertEqual(trend.baseline ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(trend.baselineDaysSoFar, 19)
    }

    func test_latest_isNeverOlderThanYesterday() {
        let trend = HeartTrend(metric: .hrv, samples: samples(-20 ... -2, value: 60), range: .month, today: today)
        XCTAssertNil(trend.latest)
        XCTAssertNil(trend.baseline)
        XCTAssertNil(trend.level)
        XCTAssertFalse(trend.days.isEmpty, "The chart still shows the history")
    }

    // MARK: - Short history

    func test_shortHistory_hasNoBaseline_butCountsTheDays() {
        let hrv = HeartTrend(metric: .hrv,
                             samples: samples(-4 ... -1, value: 60, plus: [(date: day(0), value: 55)]),
                             range: .week, today: today)
        XCTAssertNotNil(hrv.latest)
        XCTAssertNil(hrv.baseline)
        XCTAssertNil(hrv.level)
        XCTAssertEqual(hrv.baselineDaysSoFar, 4)
        XCTAssertEqual(hrv.baselineDaysNeeded, 7)
        XCTAssertEqual(hrv.baselineWindowDays, 30)

        let rhr = HeartTrend(metric: .restingHeartRate, samples: [], range: .week, today: today)
        XCTAssertEqual(rhr.baselineDaysNeeded, 5)
        XCTAssertEqual(rhr.baselineWindowDays, 14)
    }

    func test_noSamples_isEmpty() {
        let trend = HeartTrend(metric: .hrv, samples: [], range: .month, today: today)
        XCTAssertTrue(trend.days.isEmpty)
        XCTAssertNil(trend.latest)
        XCTAssertNil(trend.average)
        XCTAssertNil(trend.low)
        XCTAssertNil(trend.level)
        XCTAssertEqual(trend.baselineDaysSoFar, 0)
    }

    // MARK: - Ranges

    func test_ranges_keepOneMeanPerDay_oldestFirst() {
        // 100 days with two readings a day, 40 and 60: each day's mean is 50.
        let s = (-99 ... 0).flatMap { offset in
            [(date: day(offset, hour: 2), value: 40.0), (date: day(offset, hour: 4), value: 60.0)]
        }
        for range in HeartTrend.Range.allCases {
            let trend = HeartTrend(metric: .hrv, samples: s, range: range, today: today)
            XCTAssertEqual(trend.days.count, range.days, "\(range)")
            XCTAssertEqual(trend.days.first?.date, cal.startOfDay(for: day(-(range.days - 1))), "\(range)")
            XCTAssertEqual(trend.days.last?.date, cal.startOfDay(for: today), "\(range)")
            XCTAssertEqual(trend.days.map(\.date), trend.days.map(\.date).sorted(), "\(range)")
            XCTAssertTrue(trend.days.allSatisfy { abs($0.value - 50) < 0.001 }, "\(range)")
        }
    }

    func test_average_low_high_overTheRange() {
        // Older values (100) fall outside the week and don't count.
        let s = samples(-20 ... -7, value: 100) + [
            (date: day(-2), value: 50), (date: day(-1), value: 60), (date: day(0), value: 70),
        ]
        let week = HeartTrend(metric: .hrv, samples: s, range: .week, today: today)
        XCTAssertEqual(week.days.count, 3)
        XCTAssertEqual(week.average ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(week.low ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(week.high ?? 0, 70, accuracy: 0.001)
    }
}
