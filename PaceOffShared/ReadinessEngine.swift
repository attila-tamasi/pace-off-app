// ReadinessEngine.swift
// Pure-function daily readiness traffic light (SPEC §A).
// Compares today's HRV (SDNN) and resting heart rate against rolling
// personal baselines and grades the day green / yellow / red with one
// supporting sentence. Display-only in V1 — it never feeds back into
// PushTargetEngine's prescribed distance.
// No HealthKit imports — testable on any platform.

import Foundation

// MARK: - Output types

public enum ReadinessLevel: String, Codable, Sendable {
    case green
    case yellow
    case red
}

/// The traffic light plus the numbers behind it, so the UI can show both
/// the verdict and the "why" without re-deriving anything.
public struct DailyReadiness: Codable, Sendable, Equatable {
    public let level: ReadinessLevel
    /// One supporting sentence ("HRV below your baseline — easy day.").
    public let sentence: String
    public let hrvMs: Double?
    public let hrvBaselineMs: Double?
    public let restingHR: Double?
    public let restingHRBaseline: Double?
    public let computedAt: Date

    public init(
        level: ReadinessLevel,
        sentence: String,
        hrvMs: Double? = nil,
        hrvBaselineMs: Double? = nil,
        restingHR: Double? = nil,
        restingHRBaseline: Double? = nil,
        computedAt: Date = Date()
    ) {
        self.level = level
        self.sentence = sentence
        self.hrvMs = hrvMs
        self.hrvBaselineMs = hrvBaselineMs
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.computedAt = computedAt
    }
}

// MARK: - Engine

public struct ReadinessEngine: Sendable {

    public struct Inputs: Sendable {
        public let today: Date
        public let hrv: [HRVSnapshot]                            // trailing ~35 days
        public let restingHeartRate: [RestingHeartRateSnapshot]  // trailing 14 days

        public init(
            today: Date = Date(),
            hrv: [HRVSnapshot],
            restingHeartRate: [RestingHeartRateSnapshot]
        ) {
            self.today = today
            self.hrv = hrv
            self.restingHeartRate = restingHeartRate
        }
    }

    // Baseline windows. HRV needs a longer memory than RHR because single
    // nights are noisy; RHR reuses the 14-day window the app already fetches.
    static let hrvBaselineWindowDays = 30
    static let rhrBaselineWindowDays = 14
    /// Distinct days of history required before a baseline is trusted.
    /// Below these the signal is silently dropped rather than guessed at.
    static let minHRVBaselineDays = 7
    static let minRHRBaselineDays = 5

    // Deviation thresholds, as fractions of baseline. HRV drops are graded
    // more leniently than RHR rises because overnight SDNN swings ±10% on
    // perfectly normal days.
    static let hrvYellowDrop = 0.10   // ≥10% below baseline → yellow
    static let hrvRedDrop = 0.20      // ≥20% below baseline → red
    static let rhrYellowRise = 0.04   // ≥4% above baseline → yellow
    static let rhrRedRise = 0.08      // ≥8% above baseline → red

    public init() {}

    /// Grade the day. Returns nil when neither signal has enough history —
    /// callers hide the readiness surface entirely rather than show a guess.
    public func compute(_ inputs: Inputs) -> DailyReadiness? {
        let hrvReading = todayValueAndBaseline(
            dailyMeans(inputs.hrv.map { ($0.date, $0.sdnnMs) }),
            today: inputs.today,
            baselineWindowDays: Self.hrvBaselineWindowDays,
            minBaselineDays: Self.minHRVBaselineDays
        )
        let rhrReading = todayValueAndBaseline(
            dailyMeans(inputs.restingHeartRate.map { ($0.date, $0.bpm) }),
            today: inputs.today,
            baselineWindowDays: Self.rhrBaselineWindowDays,
            minBaselineDays: Self.minRHRBaselineDays
        )

        // Severity per signal: 0 green, 1 yellow, 2 red; nil = no data.
        let hrvSeverity: Int? = hrvReading.map { reading in
            let drop = 1.0 - reading.value / reading.baseline
            if drop >= Self.hrvRedDrop { return 2 }
            if drop >= Self.hrvYellowDrop { return 1 }
            return 0
        }
        let rhrSeverity: Int? = rhrReading.map { reading in
            let rise = reading.value / reading.baseline - 1.0
            if rise >= Self.rhrRedRise { return 2 }
            if rise >= Self.rhrYellowRise { return 1 }
            return 0
        }

        guard hrvSeverity != nil || rhrSeverity != nil else { return nil }

        // Worst signal wins; two independently degraded signals escalate to
        // red even if each alone is only yellow.
        let known = [hrvSeverity, rhrSeverity].compactMap { $0 }
        var combined = known.max() ?? 0
        if (hrvSeverity ?? 0) >= 1 && (rhrSeverity ?? 0) >= 1 {
            combined = 2
        }

        let level: ReadinessLevel
        switch combined {
        case 0: level = .green
        case 1: level = .yellow
        default: level = .red
        }

        return DailyReadiness(
            level: level,
            sentence: sentence(level: level, hrvSeverity: hrvSeverity, rhrSeverity: rhrSeverity),
            hrvMs: hrvReading?.value,
            hrvBaselineMs: hrvReading?.baseline,
            restingHR: rhrReading?.value,
            restingHRBaseline: rhrReading?.baseline,
            computedAt: inputs.today
        )
    }

    // MARK: - Copy

    private func sentence(level: ReadinessLevel, hrvSeverity: Int?, rhrSeverity: Int?) -> String {
        let hrvOff = (hrvSeverity ?? 0) >= 1
        let rhrOff = (rhrSeverity ?? 0) >= 1
        switch level {
        case .green:
            return "Recovery is on baseline — you're clear to push."
        case .yellow:
            return hrvOff
                ? "HRV below your baseline — easy day."
                : "Resting heart rate above your baseline — keep it easy."
        case .red:
            if hrvOff && rhrOff {
                return "HRV down and resting heart rate up — your body is asking for rest."
            }
            return hrvOff
                ? "HRV well below your baseline — rest or keep it very easy."
                : "Resting heart rate well above your baseline — rest or keep it very easy."
        }
    }

    // MARK: - Helpers (internal access for testing)

    /// Collapse raw samples to one mean value per calendar day, sorted
    /// ascending. Overnight HRV can log several readings; days compare
    /// fairly only when each contributes a single number.
    func dailyMeans(_ samples: [(date: Date, value: Double)]) -> [(day: Date, value: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { cal.startOfDay(for: $0.date) }
        return grouped
            .map { day, entries in
                (day: day, value: entries.map { $0.value }.reduce(0, +) / Double(entries.count))
            }
            .sorted { $0.day < $1.day }
    }

    /// Pick "today's" reading and the rolling baseline it compares against.
    /// Today's reading may come from yesterday's calendar day — overnight
    /// values often carry the previous day's timestamp — but never older.
    /// Baseline = mean of the daily values in the trailing window, excluding
    /// the day used as today's reading. Nil when either side is missing.
    func todayValueAndBaseline(
        _ days: [(day: Date, value: Double)],
        today: Date,
        baselineWindowDays: Int,
        minBaselineDays: Int
    ) -> (value: Double, baseline: Double)? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: startOfToday),
              let windowStart = cal.date(byAdding: .day, value: -baselineWindowDays, to: startOfToday)
        else { return nil }

        guard let current = days.last(where: { $0.day == startOfToday || $0.day == yesterday })
        else { return nil }

        let baselineDays = days.filter {
            $0.day >= windowStart && $0.day < startOfToday && $0.day != current.day
        }
        guard baselineDays.count >= minBaselineDays else { return nil }

        let baseline = baselineDays.map { $0.value }.reduce(0, +) / Double(baselineDays.count)
        guard baseline > 0 else { return nil }
        return (current.value, baseline)
    }
}
