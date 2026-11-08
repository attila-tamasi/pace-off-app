// HeartTrend.swift
// What the HRV and resting heart rate detail screens show: one value per
// day over a range, the baseline the readiness card compares against, and
// where the latest reading sits. It uses ReadinessEngine's own daily means,
// windows and thresholds, so the screen and the readiness card agree.

import Foundation

public struct HeartTrend: Equatable, Sendable {

    public enum Metric: Hashable, Sendable {
        /// Heart rate variability (SDNN, ms). Higher than baseline is better.
        case hrv
        /// Resting heart rate (bpm). Lower than baseline is better.
        case restingHeartRate
    }

    public enum Range: Int, CaseIterable, Identifiable, Sendable {
        case week = 7
        case month = 30
        case threeMonths = 90

        public var id: Int { rawValue }
        public var days: Int { rawValue }
    }

    public struct Day: Equatable, Identifiable, Sendable {
        /// Start of the calendar day.
        public let date: Date
        /// The day's mean.
        public let value: Double
        public var id: Date { date }
    }

    public let metric: Metric
    public let range: Range
    /// One mean per calendar day in the range, today included, oldest
    /// first. Days without a reading are left out.
    public let days: [Day]
    /// The reading readiness uses: today's, or yesterday's (overnight
    /// readings often carry the previous day's date), never older.
    public let latest: Day?
    /// The mean readiness compares `latest` with. Nil without a latest
    /// reading or before `baselineDaysNeeded` days of history.
    public let baseline: Double?
    /// Days with a reading in the baseline window so far, `latest`'s day
    /// left out, as readiness counts them.
    public let baselineDaysSoFar: Int
    public let baselineDaysNeeded: Int
    public let baselineWindowDays: Int

    public init(metric: Metric,
                samples: [(date: Date, value: Double)],
                range: Range,
                today: Date = Date()) {
        let engine = ReadinessEngine()
        let cal = Calendar.current
        let all = engine.dailyMeans(samples)
        let window = metric == .hrv
            ? ReadinessEngine.hrvBaselineWindowDays
            : ReadinessEngine.rhrBaselineWindowDays
        let needed = metric == .hrv
            ? ReadinessEngine.minHRVBaselineDays
            : ReadinessEngine.minRHRBaselineDays

        let startOfToday = cal.startOfDay(for: today)
        let rangeStart = cal.date(byAdding: .day, value: -(range.days - 1), to: startOfToday) ?? startOfToday
        let yesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let windowStart = cal.date(byAdding: .day, value: -window, to: startOfToday) ?? startOfToday
        let current = all.last { $0.day == startOfToday || $0.day == yesterday }

        self.metric = metric
        self.range = range
        self.days = all
            .filter { $0.day >= rangeStart && $0.day <= startOfToday }
            .map { Day(date: $0.day, value: $0.value) }
        self.latest = current.map { Day(date: $0.day, value: $0.value) }
        self.baseline = engine.todayValueAndBaseline(
            all,
            today: today,
            baselineWindowDays: window,
            minBaselineDays: needed
        )?.baseline
        self.baselineDaysSoFar = all.filter {
            $0.day >= windowStart && $0.day < startOfToday && $0.day != current?.day
        }.count
        self.baselineDaysNeeded = needed
        self.baselineWindowDays = window
    }

    // MARK: - Over the range

    public var average: Double? {
        days.isEmpty ? nil : days.map(\.value).reduce(0, +) / Double(days.count)
    }
    public var low: Double? { days.map(\.value).min() }
    public var high: Double? { days.map(\.value).max() }

    // MARK: - Against the baseline

    /// `latest` against `baseline`: 0.08 is 8% above, −0.08 is 8% below.
    public var change: Double? {
        guard let latest, let baseline, baseline > 0 else { return nil }
        return latest.value / baseline - 1
    }

    /// The share of the baseline at which this signal alone turns the day
    /// yellow, then red: a drop for HRV, a rise for resting heart rate.
    public var yellowThreshold: Double {
        metric == .hrv ? ReadinessEngine.hrvYellowDrop : ReadinessEngine.rhrYellowRise
    }
    public var redThreshold: Double {
        metric == .hrv ? ReadinessEngine.hrvRedDrop : ReadinessEngine.rhrRedRise
    }

    /// What this signal alone says about today, by the readiness card's
    /// thresholds. Nil without a latest reading or a baseline.
    public var level: ReadinessLevel? {
        guard let change else { return nil }
        // HRV going down and resting HR going up are the bad directions.
        let offBy = metric == .hrv ? -change : change
        if offBy >= redThreshold { return .red }
        if offBy >= yellowThreshold { return .yellow }
        return .green
    }
}
