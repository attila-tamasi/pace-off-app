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
    /// Red readiness caps the day at this fraction of baseline — the same
    /// reduction a post-long-run recovery day gets.
    private static let redReadinessCapFactor = 0.6

    // VO2Max slope thresholds (ml/kg/min per WEEK)
    private static let vo2MaxDecliningSlope = -0.05
    private static let vo2MaxPlateauAbsSlope = 0.10

    public init() {}

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

        // 2. VO2Max trend
        let vo2Slope = vo2MaxSlopePerWeek(inputs.vo2Max, asOf: inputs.today)
        if let slope = vo2Slope {
            if slope < Self.vo2MaxDecliningSlope {
                target *= 1.15
                tone = .aggressive
            } else if abs(slope) < Self.vo2MaxPlateauAbsSlope {
                target *= 1.10
                tone = .firm
            }
            // else: improving — hold baseline
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
            // Restart: reset to last comfortable run, capped by restart floor
            let last = lastComfortableRun(inputs.runs)
            target = max(Self.restartFloorMeters, last)
            tone = .restart
        }

        // 4. Resting HR fatigue guard
        if isRestingHRElevated(inputs.restingHeartRate, asOf: inputs.today) {
            target = min(target, baseline)
            fatigueGuardActive = true
        }

        // 5. Yesterday was a long run → today is recovery
        if yesterdayWasLongRun(inputs.runs, today: inputs.today, baseline: baseline) {
            target = baseline * 0.6
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
            let cap = baseline * Self.redReadinessCapFactor
            if target > cap {
                target = cap
                readinessCapApplied = true
            }
            if tone != .restart { tone = .recovery }
        case .yellow:
            if target > baseline {
                target = baseline
                readinessCapApplied = true
            }
            if tone == .aggressive { tone = .firm }
        case .green, nil:
            break
        }

        // 6. Hard ceiling
        let ceiling = baseline * Self.hardCeilingMultiplier
        if target > ceiling && tone != .restart {
            target = ceiling
            ceilingClamped = true
        }

        // 7. Round to nearest 100m for display sanity
        target = (target / 100).rounded() * 100

        return RunTarget(
            distanceMeters: target,
            tone: tone,
            daysSinceLastRun: skipped,
            vo2MaxSlope: vo2Slope,
            baselineMeters: baseline,
            ceilingClamped: ceilingClamped,
            fatigueGuardActive: fatigueGuardActive,
            readinessCapApplied: readinessCapApplied,
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
