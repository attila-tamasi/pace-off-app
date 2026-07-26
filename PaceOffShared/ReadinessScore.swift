// ReadinessScore.swift
// Daily Green / Yellow / Red readiness signal computed from HRV (SDNN) and
// resting heart rate versus the runner's own rolling personal baseline.
//
// This is not a diagnostic — it's a nudge. HRV suppression + resting-HR
// elevation vs. the runner's own baseline correlates with poor recovery,
// illness, or accumulated training load. The engine outputs a colour and a
// plain-English reason the UI can render straight onto the home screen.
//
// Pure Swift, `Sendable`, no I/O. Unit-tested.
//
// Method (aligns with Buchheit 2014 practical guidance):
//   1. Take yesterday's HRV (or the most recent within the last 3 days).
//      Compute the mean + standard deviation over the trailing 30 days,
//      excluding the reference day itself.
//   2. Compute the z-score `(today - mean) / stdDev`.
//   3. Repeat for resting HR (but flipped — higher RHR is worse).
//   4. Combine: readiness is the *worse* of the two signals. Any signal
//      that lacks enough baseline data (fewer than 7 valid days) is skipped.
//   5. Fresh install / missing sensor data → `.unknown` — never guess.

import Foundation

// MARK: - Level

/// Traffic-light state for today's readiness.
public enum ReadinessLevel: String, Codable, Sendable, CaseIterable {
    /// Enough baseline missing to make a call. UI should render neutrally.
    case unknown
    /// Recovered — green light for the day's planned session.
    case green
    /// Warning — HRV suppressed or resting HR elevated. Ease off if possible.
    case yellow
    /// Recovery signal is strongly off baseline. Take it easy or rest.
    case red

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .green:   return "Ready"
        case .yellow:  return "Caution"
        case .red:     return "Recover"
        }
    }
}

// MARK: - Score

/// Output of the engine — a level plus the numbers the UI needs to explain it.
public struct ReadinessScore: Codable, Sendable, Equatable {
    public let level: ReadinessLevel
    /// Short plain-English headline ("HRV suppressed vs baseline").
    public let headline: String
    /// Longer sentence explaining what to do ("Consider an easy day.").
    public let reason: String
    /// Today's HRV value used, if any (ms).
    public let hrvToday: Double?
    /// 30-day HRV baseline, if computable (ms).
    public let hrvBaseline: Double?
    /// Today's resting HR used, if any (bpm).
    public let restingHRToday: Double?
    /// 14-day resting-HR baseline, if computable (bpm).
    public let restingHRBaseline: Double?

    public init(level: ReadinessLevel,
                headline: String,
                reason: String,
                hrvToday: Double? = nil,
                hrvBaseline: Double? = nil,
                restingHRToday: Double? = nil,
                restingHRBaseline: Double? = nil) {
        self.level = level
        self.headline = headline
        self.reason = reason
        self.hrvToday = hrvToday
        self.hrvBaseline = hrvBaseline
        self.restingHRToday = restingHRToday
        self.restingHRBaseline = restingHRBaseline
    }

    public static let unknown = ReadinessScore(
        level: .unknown,
        headline: "Not enough data",
        reason: "Wear your Apple Watch overnight for a few days to unlock readiness."
    )
}

// MARK: - Engine

public struct ReadinessEngine: Sendable {

    /// Minimum baseline days below which we refuse to score. Fewer than a
    /// week of readings gives a noisy z-score.
    public static let minBaselineDays: Int = 7

    /// Fallback for stdDev when the baseline is essentially flat — avoids
    /// division-by-zero producing infinities.
    public static let minStdDev: Double = 0.5

    /// z-thresholds. Anything within ±this on both signals is green.
    public static let yellowThreshold: Double = -1.0   // HRV: below −1σ
    public static let redThreshold: Double = -2.0      // HRV: below −2σ
    public static let rhrYellowThreshold: Double =  1.0
    public static let rhrRedThreshold: Double =  2.0

    public init() {}

    /// Compute today's readiness. `today` picks which sample counts as
    /// "today's" — everything strictly *before* that day feeds the baseline.
    public func score(
        hrvHistory: [HRVSnapshot],
        restingHRHistory: [RestingHeartRateSnapshot],
        today: Date = Date()
    ) -> ReadinessScore {

        let cal = Calendar.current
        let dayOfToday = cal.startOfDay(for: today)

        // Split into today's value + baseline (last 30 days before today).
        let hrvToday = hrvHistory
            .last { cal.isDate($0.date, inSameDayAs: dayOfToday) }?.ms
            ?? mostRecentBefore(hrvHistory.map { ($0.date, $0.ms) }, today: dayOfToday, maxDaysBack: 3)
        let hrvBaseline = baseline(hrvHistory.map { ($0.date, $0.ms) },
                                   endingBefore: dayOfToday, days: 30)

        let rhrToday = restingHRHistory
            .last { cal.isDate($0.date, inSameDayAs: dayOfToday) }?.bpm
            ?? mostRecentBefore(restingHRHistory.map { ($0.date, $0.bpm) }, today: dayOfToday, maxDaysBack: 3)
        let rhrBaseline = baseline(restingHRHistory.map { ($0.date, $0.bpm) },
                                   endingBefore: dayOfToday, days: 14)

        let hrvZ = z(current: hrvToday, baseline: hrvBaseline)
        // Higher RHR is *worse*, so flip the sign so both signals share the
        // "more negative = worse" convention.
        let rhrZ = z(current: rhrToday, baseline: rhrBaseline).map { -$0 }

        // Available signals only.
        let signals = [hrvZ, rhrZ].compactMap { $0 }
        guard !signals.isEmpty else {
            return .unknown
        }

        // Readiness is dictated by the *worst* signal.
        let worst = signals.min()!

        let level: ReadinessLevel
        if worst <= Self.redThreshold {
            level = .red
        } else if worst <= Self.yellowThreshold {
            level = .yellow
        } else {
            level = .green
        }

        let (headline, reason) = copy(for: level, hrvZ: hrvZ, rhrZ: rhrZ)

        return ReadinessScore(
            level: level,
            headline: headline,
            reason: reason,
            hrvToday: hrvToday,
            hrvBaseline: hrvBaseline?.mean,
            restingHRToday: rhrToday,
            restingHRBaseline: rhrBaseline?.mean
        )
    }

    // MARK: - Helpers

    /// Mean + stdDev of the values whose date falls in the window
    /// `[endingBefore - days, endingBefore)`. Returns nil when fewer than
    /// `minBaselineDays` samples land in the window.
    private struct Baseline { let mean: Double; let stdDev: Double }

    private func baseline(_ series: [(date: Date, value: Double)],
                          endingBefore reference: Date,
                          days: Int) -> Baseline? {
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -days, to: reference)
        else { return nil }
        let window = series
            .filter { $0.date >= windowStart && $0.date < reference }
            .map(\.value)
        guard window.count >= Self.minBaselineDays else { return nil }
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + pow($1 - mean, 2) } / Double(window.count)
        let stdDev = max(sqrt(variance), Self.minStdDev)
        return Baseline(mean: mean, stdDev: stdDev)
    }

    /// z-score of `current` against `baseline`, or nil if either input missing.
    private func z(current: Double?, baseline: Baseline?) -> Double? {
        guard let current, let baseline else { return nil }
        return (current - baseline.mean) / baseline.stdDev
    }

    /// Most recent value whose date is strictly before `today`, within
    /// `maxDaysBack` days. Used when there's no sample for today itself —
    /// HealthKit sometimes lags a day on HRV.
    private func mostRecentBefore(_ series: [(date: Date, value: Double)],
                                  today: Date,
                                  maxDaysBack: Int) -> Double? {
        guard let earliest = Calendar.current.date(byAdding: .day, value: -maxDaysBack, to: today)
        else { return nil }
        return series
            .filter { $0.date < today && $0.date >= earliest }
            .sorted { $0.date > $1.date }
            .first?.value
    }

    /// UI copy for the level. Kept in one place so tone stays consistent.
    private func copy(for level: ReadinessLevel, hrvZ: Double?, rhrZ: Double?)
        -> (headline: String, reason: String)
    {
        // Which signal drove the call?
        let hrvWorse = (hrvZ ?? .infinity) <= (rhrZ ?? .infinity)
        switch level {
        case .unknown:
            return ("Not enough data",
                    "Wear your Apple Watch overnight for a few days to unlock readiness.")
        case .green:
            return ("Ready to run",
                    "Recovery markers look normal for you — go run what you planned.")
        case .yellow:
            if hrvWorse {
                return ("HRV below your baseline",
                        "Consider trimming volume or dropping the quality session.")
            } else {
                return ("Resting HR above your baseline",
                        "Your body's under some load — an easy day fits better than a hard one.")
            }
        case .red:
            if hrvWorse {
                return ("HRV well below your baseline",
                        "Take an easy or rest day. Pushing hard here rarely pays off.")
            } else {
                return ("Resting HR well above baseline",
                        "You may be fighting something. Rest and revisit tomorrow.")
            }
        }
    }
}
