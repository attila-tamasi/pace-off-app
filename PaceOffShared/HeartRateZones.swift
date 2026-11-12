// HeartRateZones.swift
// Five heart-rate zones from max HR, a run's time in each, and whether a
// run meant to be easy stayed easy. Running easy days too hard is the most
// common amateur mistake; this catches it. Pure and Sendable.

import Foundation

public struct HeartRateZones: Equatable, Sendable {

    /// The zones' lower bounds as shares of max HR: zone 1 50%, zone 2 60%,
    /// zone 3 70%, zone 4 80%, zone 5 90%. Anything below 60% counts as
    /// zone 1.
    public static let lowerBounds: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]

    /// A gap between samples longer than this is a pause, not time in a zone.
    public static let maxSampleGap: TimeInterval = 60

    public let maxHR: Double

    public init(maxHR: Double) {
        self.maxHR = maxHR
    }

    /// Max HR: the highest seen in the last 90 days when it's plausible,
    /// else 208 − 0.7 × age (Tanaka), else nil.
    public static func maxHR(observed: Double?, age: Int?) -> Double? {
        if let observed, (140...230).contains(observed) { return observed }
        if let age, (10...100).contains(age) { return 208 - 0.7 * Double(age) }
        return nil
    }

    /// The zone (1–5) a heart rate falls in.
    public func zone(of bpm: Double) -> Int {
        let share = bpm / maxHR
        return (Self.lowerBounds.lastIndex { share >= $0 } ?? 0) + 1
    }

    /// "142–157 bpm" for a zone; zone 5 ends at max HR.
    public func range(of zone: Int) -> ClosedRange<Double> {
        let i = min(max(zone, 1), 5) - 1
        let low = i == 0 ? 0 : Self.lowerBounds[i] * maxHR
        let high = i == 4 ? maxHR : Self.lowerBounds[i + 1] * maxHR
        return low...high
    }

    /// Seconds in each zone (index 0 is zone 1) over a run, from its
    /// samples: each sample holds until the next, a gap over a minute
    /// counts a minute, and the last holds to the end, up to a minute.
    public func timeInZones(samples: [(date: Date, bpm: Double)], start: Date, end: Date) -> [TimeInterval] {
        let inRun = samples.filter { $0.date >= start && $0.date <= end && $0.bpm > 0 }
            .sorted { $0.date < $1.date }
        var seconds = [TimeInterval](repeating: 0, count: 5)
        for (i, sample) in inRun.enumerated() {
            let next = i + 1 < inRun.count ? inRun[i + 1].date : end
            let held = min(next.timeIntervalSince(sample.date), Self.maxSampleGap)
            guard held > 0 else { continue }
            seconds[zone(of: sample.bpm) - 1] += held
        }
        return seconds
    }
}

/// Whether a run meant to be easy stayed easy.
public enum EasyRunCheck {

    /// More than this share of the run above zone 2 is too hard for easy.
    public static let maxShareAboveZone2 = 0.20

    /// A run is meant to be easy when the day's prescription was an easy or
    /// long plan run, or readiness was yellow or red. Unknown without the
    /// day's ledger row.
    public static func isMeantEasy(_ day: LedgerDay?) -> Bool {
        guard let prescription = day?.prescription else { return false }
        if prescription.readiness == .yellow || prescription.readiness == .red { return true }
        return prescription.kind == .run
            && (prescription.workoutKind == .easy || prescription.workoutKind == .long)
    }

    /// The share of the run's time in zone 3 or above, nil without time.
    public static func shareAboveZone2(_ timeInZones: [TimeInterval]) -> Double? {
        let total = timeInZones.reduce(0, +)
        guard total > 0, timeInZones.count == 5 else { return nil }
        return timeInZones[2...].reduce(0, +) / total
    }

    /// The share of time in zones 1–2 across runs ("easy"), nil without
    /// time. The week screen's easy/hard balance.
    public static func easyShare(_ runs: [[TimeInterval]]) -> Double? {
        let total = runs.joined().reduce(0, +)
        guard total > 0 else { return nil }
        let easy = runs.filter { $0.count == 5 }.map { $0[0] + $0[1] }.reduce(0, +)
        return easy / total
    }

    /// "35% of this easy run was in zone 3 or above. Slow down to keep it
    /// easy." for a run meant to be easy that wasn't; nil otherwise.
    public static func note(timeInZones: [TimeInterval], meantEasy: Bool) -> String? {
        guard meantEasy, let share = shareAboveZone2(timeInZones), share > maxShareAboveZone2 else { return nil }
        let percent = Int((share * 100).rounded())
        return "\(percent)% of this easy run was in zone 3 or above. Slow down to keep it easy."
    }
}
