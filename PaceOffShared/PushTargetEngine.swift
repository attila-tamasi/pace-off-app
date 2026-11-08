// PushTargetEngine.swift
// Pure-function core that turns recent Health data into today's run target.
// PRD §7. No HealthKit imports — testable on any platform.

import Foundation

public struct PushTargetEngine: Sendable {

    public struct Inputs: Sendable {
        public let today: Date
        public let runs: [RunRecord]                       // last 90 days, sorted ascending
        public let vo2Max: [VO2MaxSnapshot]                // last 90 days, sorted ascending
        public let restingHeartRate: [RestingHeartRateSnapshot]  // last 14 days
        /// Today's readiness verdict from ReadinessEngine. Nil when there's
        /// not enough HRV/RHR history — the target then computes exactly as
        /// it did before readiness existed.
        public let readiness: ReadinessLevel?

        public init(
            today: Date = Date(),
            runs: [RunRecord],
            vo2Max: [VO2MaxSnapshot],
            restingHeartRate: [RestingHeartRateSnapshot],
            readiness: ReadinessLevel? = nil
        ) {
            self.today = today
            self.runs = runs
            self.vo2Max = vo2Max
            self.restingHeartRate = restingHeartRate
            self.readiness = readiness
        }
    }

    // Algorithm constants (PRD §7.2)
    private static let baselineWindowDays = 14
    private static let vo2MaxTrendWindowDays = 28
    private static let hardCeilingMultiplier = 1.4
    private static let restingHRElevationThreshold = 0.07
    private static let longRunMultiplier = 1.5
    private static let restartFloorMeters = 3000.0  // 3.0 km restart floor
    /// The day after a long run is this fraction of baseline.
    private static let recoveryFactor = 0.6
    /// Red readiness caps the day at this fraction of baseline — the same
    /// reduction a post-long-run recovery day gets.
    static let redReadinessCapFactor = 0.6

    // VO2Max slope thresholds (ml/kg/min per WEEK)
    static let vo2MaxDecliningSlope = -0.05

    // When a VO₂ max trend counts. Apple Watch estimates wobble by a few
    // tenths from one reading to the next, so a trend needs enough
    // readings, over long enough, and a change the wobble can't explain.
    static let vo2MinReadings = 3
    static let vo2MinSpanDays = 14.0
    /// The least change over the window (ml/kg/min) that counts as a trend.
    static let vo2MinChange = 0.25
    /// The fitted slope must be this many standard errors from flat.
    static let vo2MinSignificance = 2.0

    /// What the last 28 days of VO₂ max say.
    public enum VO2Trend: Equatable, Sendable {
        /// Falling beyond noise: push harder (+15%, aggressive).
        case declining(slopePerWeek: Double)
        /// Flat, or moving within noise: stagnation, ask a little more
        /// (+10%, firm).
        case plateau
        /// Rising beyond noise: the work is landing, hold the baseline.
        case improving(slopePerWeek: Double)
    }

    public init() {}

    /// Whether `runs` hold a run on or before `today`. Without one there's
    /// nothing to base a target on: no baseline, no skip count.
    public static func hasRunHistory(_ runs: [RunRecord], today: Date) -> Bool {
        runs.contains { $0.startDate <= today }
    }

    /// Today's target, or nil for a runner Pace Off has never seen run (a
    /// new runner, or Health access denied): then there's no target and no
    /// pushes, and Today shows how to log a first run. `hasRunBefore` is
    /// true once any Health read has held a run; such a runner, back after
    /// more than the 90-day window, gets the restart target as before.
    public func target(_ inputs: Inputs, hasRunBefore: Bool = false) -> RunTarget? {
        guard hasRunBefore || Self.hasRunHistory(inputs.runs, today: inputs.today) else { return nil }
        return compute(inputs)
    }

    public func compute(_ inputs: Inputs) -> RunTarget {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: inputs.today)

        // 1. Baseline = median distance over last 14 days of runs
        let recentWindow = inputs.runs.filter { run in
            guard let days = cal.dateComponents([.day], from: cal.startOfDay(for: run.startDate), to: startOfToday).day else { return false }
            return days >= 0 && days < Self.baselineWindowDays
        }
        let baseline = median(recentWindow.map(\.distanceMeters)) ?? Self.restartFloorMeters

        var target = baseline
        var tone: Tone = .neutral
        var ceilingClamped = false
        var fatigueGuardActive = false

        // The tightest upper bound today: the 1.4× hard ceiling (PRD §7.2,
        // "regardless of skip count"), raised to the restart floor on a
        // restart day, then tightened by each guard below. Rounding, for
        // the 100 m grid and for display, never goes over it.
        let ceiling = baseline * Self.hardCeilingMultiplier
        var cap = ceiling

        // 2. VO2Max trend — only once there's enough of it to trust.
        let vo2Trend = vo2MaxTrend(inputs.vo2Max, asOf: inputs.today)
        var vo2Slope: Double?
        switch vo2Trend {
        case .declining(let slope):
            target *= 1.15
            tone = .aggressive
            vo2Slope = slope
        case .plateau:
            target *= 1.10
            tone = .firm
        case .improving(let slope):
            vo2Slope = slope  // hold baseline
        case nil:
            break             // too little data: no say in the target
        }

        // 3. Skip count
        let skipped = daysSinceLastRun(inputs.runs, today: inputs.today)
        switch skipped {
        case 0:
            break
        case 1:
            target *= 1.05
            if tone == .neutral { tone = .firm }
        case 2:
            target *= 1.12
            tone = .aggressive
        default: // 3+
            // Restart: reset to the last comfortable run, at least the
            // restart floor. The ceiling bounds it (step 6), except where
            // the ceiling sits under the floor (a baseline under ~2.1 km):
            // there the floor stands.
            let last = lastComfortableRun(inputs.runs)
            target = max(Self.restartFloorMeters, last)
            cap = max(ceiling, Self.restartFloorMeters)
            tone = .restart
        }

        // 4. Resting HR fatigue guard
        if isRestingHRElevated(inputs.restingHeartRate, asOf: inputs.today) {
            target = min(target, baseline)
            cap = min(cap, baseline)
            fatigueGuardActive = true
        }

        // 5. Yesterday was a long run → today is recovery
        if yesterdayWasLongRun(inputs.runs, today: inputs.today, baseline: baseline) {
            target = baseline * Self.recoveryFactor
            cap = min(cap, target)
            tone = .recovery
        }

        // 5b. Readiness traffic light (SPEC §11 follow-up). Red means the
        // body asked for rest: cap hard and speak in the recovery register.
        // Yellow means don't push *above* baseline today. Green/unknown
        // changes nothing. A restart day keeps its restart tone — the cap
        // still applies to the distance.
        var readinessCapApplied = false
        switch inputs.readiness {
        case .red:
            let redCap = baseline * Self.redReadinessCapFactor
            if target > redCap {
                target = redCap
                readinessCapApplied = true
            }
            cap = min(cap, redCap)
            if tone != .restart { tone = .recovery }
        case .yellow:
            if target > baseline {
                target = baseline
                readinessCapApplied = true
            }
            cap = min(cap, baseline)
            if tone == .aggressive { tone = .firm }
        case .green, nil:
            break
        }

        // 6. Hard ceiling, restart days included. Each guard above already
        // clamped the target to its own cap, so a target still over `cap`
        // is over the ceiling.
        if target > cap {
            target = cap
            ceilingClamped = true
        }

        // 7. Round to the nearest 100 m for display sanity, but never above
        // today's cap (×1.4 of a 5.2 km baseline is 7.28 km, not 7.3).
        let capOnGrid = ((cap + 1e-6) / 100).rounded(.down) * 100
        target = min((target / 100).rounded() * 100, capOnGrid)

        return RunTarget(
            distanceMeters: target,
            tone: tone,
            daysSinceLastRun: skipped,
            vo2MaxSlope: vo2Slope,
            baselineMeters: baseline,
            ceilingClamped: ceilingClamped,
            fatigueGuardActive: fatigueGuardActive,
            readinessCapApplied: readinessCapApplied,
            capMeters: cap,
            computedAt: inputs.today
        )
    }

    // MARK: - Helpers (internal access for testing)

    func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// The VO₂ max trend over the last 28 days, or nil while there are fewer
    /// than 3 readings or they span under 14 days. A linear fit counts as
    /// rising or falling only when its change over the window is at least
    /// `vo2MinChange` and its slope is `vo2MinSignificance` standard errors
    /// from flat; anything less is a plateau. A 0.3 wobble between readings
    /// is noise, never a decline.
    public func vo2MaxTrend(_ samples: [VO2MaxSnapshot], asOf today: Date) -> VO2Trend? {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -Self.vo2MaxTrendWindowDays, to: today) ?? today
        let window = samples.filter { $0.date >= cutoff && $0.date <= today }.sorted { $0.date < $1.date }
        guard window.count >= Self.vo2MinReadings,
              let first = window.first?.date, let last = window.last?.date
        else { return nil }
        let spanDays = last.timeIntervalSince(first) / 86_400
        guard spanDays >= Self.vo2MinSpanDays else { return nil }

        let xs = window.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = window.map(\.value)
        let n = Double(window.count)
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        let sxx = xs.reduce(0.0) { $0 + ($1 - xMean) * ($1 - xMean) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) }
        let slopePerDay = sxy / sxx
        let intercept = yMean - slopePerDay * xMean
        let residuals = zip(xs, ys).reduce(0.0) { sum, point in
            let r = point.1 - (intercept + slopePerDay * point.0)
            return sum + r * r
        }
        let standardError = (residuals / (n - 2) / sxx).squareRoot()

        let change = slopePerDay * spanDays
        let significant = abs(slopePerDay) >= Self.vo2MinSignificance * standardError
        guard abs(change) >= Self.vo2MinChange, significant else { return .plateau }
        let perWeek = slopePerDay * 7
        return perWeek < 0 ? .declining(slopePerWeek: perWeek) : .improving(slopePerWeek: perWeek)
    }

    /// Linear regression slope of VO2Max over the last 28 days, expressed as ml/kg/min per WEEK.
    func vo2MaxSlopePerWeek(_ samples: [VO2MaxSnapshot], asOf today: Date) -> Double? {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -Self.vo2MaxTrendWindowDays, to: today) ?? today
        let window = samples.filter { $0.date >= cutoff && $0.date <= today }
        guard window.count >= 2 else { return nil }

        // x = days from window start, y = VO2Max value
        let firstDate = window.first!.date
        let xs = window.map { $0.date.timeIntervalSince(firstDate) / 86_400.0 }
        let ys = window.map(\.value)
        let n = Double(window.count)

        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n

        var num = 0.0
        var den = 0.0
        for i in 0..<window.count {
            num += (xs[i] - xMean) * (ys[i] - yMean)
            den += (xs[i] - xMean) * (xs[i] - xMean)
        }
        guard den != 0 else { return nil }
        let slopePerDay = num / den
        return slopePerDay * 7.0 // convert to per-week
    }

    func daysSinceLastRun(_ runs: [RunRecord], today: Date) -> Int {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        guard let last = runs.max(by: { $0.startDate < $1.startDate }) else { return 999 }
        let lastDay = cal.startOfDay(for: last.startDate)
        let days = cal.dateComponents([.day], from: lastDay, to: startOfToday).day ?? 0
        return max(0, days)
    }

    func lastComfortableRun(_ runs: [RunRecord]) -> Double {
        // "Comfortable" = the median of the last 5 runs, regardless of how long ago.
        let recent = runs.sorted { $0.startDate > $1.startDate }.prefix(5).map(\.distanceMeters)
        return median(Array(recent)) ?? Self.restartFloorMeters
    }

    func isRestingHRElevated(_ samples: [RestingHeartRateSnapshot], asOf today: Date) -> Bool {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let window = samples.filter { $0.date >= cutoff && $0.date <= today }
        guard window.count >= 3 else { return false }

        let baseline = window.map(\.bpm).reduce(0, +) / Double(window.count)
        // Compare yesterday's reading (most recent) against the 7-day mean
        guard let mostRecent = window.max(by: { $0.date < $1.date })?.bpm else { return false }
        return mostRecent > baseline * (1.0 + Self.restingHRElevationThreshold)
    }

    func yesterdayWasLongRun(_ runs: [RunRecord], today: Date, baseline: Double) -> Bool {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) else { return false }
        let yesterdayRuns = runs.filter { cal.isDate($0.startDate, inSameDayAs: yesterday) }
        guard let longest = yesterdayRuns.map(\.distanceMeters).max() else { return false }
        return longest > baseline * Self.longRunMultiplier
    }
}
