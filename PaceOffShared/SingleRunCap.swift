// SingleRunCap.swift
// No prescribed run is longer than 110% of the longest run of the previous
// 30 days. In the largest study of running load (BJSM 2025; 5,205 runners,
// 588,071 runs) the overuse-injury rate was 64% higher after a run more
// than 10% longer than the longest of the previous 30 days, and 128%
// higher when it more than doubled; week-to-week change showed no link.
// The study is observational and most injuries followed runs with no
// jump, so the copy never promises fewer injuries.
//
// Pure: the daily target goes through `apply(to:cap:)`, today's plan run
// through `DayPrescription`.

import Foundation

public enum SingleRunCap {

    /// A run may be at most this multiple of the longest recent one.
    public static let factor = 1.1
    /// The days before today the longest run is looked for in.
    public static let windowDays = 30

    /// 110% of the longest run in the 30 days before today (today's runs
    /// don't count), or nil without one: then the restart rules stand.
    public static func capMeters(runs: [RunRecord], today: Date, calendar: Calendar = .current) -> Double? {
        let startOfToday = calendar.startOfDay(for: today)
        let longest = runs
            .filter { run in
                guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: run.startDate),
                                                         to: startOfToday).day else { return false }
                return (1...windowDays).contains(days)
            }
            .map(\.distanceMeters)
            .max()
        guard let longest, longest > 0 else { return nil }
        return longest * factor
    }

    /// The target kept within `cap`: its distance, its cap and so the
    /// whole km it shows. `singleRunCapMeters` records the cap when it
    /// lowered what the runner sees. Nil `cap` leaves the target alone.
    public static func apply(to target: RunTarget, cap: Double?) -> RunTarget {
        guard let cap else { return target }
        let newCap = min(target.capMeters ?? .infinity, cap)
        let capOnGrid = ((cap + 1e-6) / 100).rounded(.down) * 100
        let capped = RunTarget(
            distanceMeters: min(target.distanceMeters, capOnGrid),
            tone: target.tone,
            daysSinceLastRun: target.daysSinceLastRun,
            vo2MaxSlope: target.vo2MaxSlope,
            baselineMeters: target.baselineMeters,
            ceilingClamped: target.ceilingClamped,
            fatigueGuardActive: target.fatigueGuardActive,
            readinessCapApplied: target.readinessCapApplied,
            capMeters: newCap,
            computedAt: target.computedAt
        )
        guard capped.displayedDistanceKm < target.displayedDistanceKm else {
            // The cap didn't change what the runner sees, but keeps the
            // rounding under it.
            return capped
        }
        return RunTarget(
            distanceMeters: capped.distanceMeters,
            tone: capped.tone,
            daysSinceLastRun: capped.daysSinceLastRun,
            vo2MaxSlope: capped.vo2MaxSlope,
            baselineMeters: capped.baselineMeters,
            ceilingClamped: capped.ceilingClamped,
            fatigueGuardActive: capped.fatigueGuardActive,
            readinessCapApplied: capped.readinessCapApplied,
            capMeters: capped.capMeters,
            singleRunCapMeters: cap,
            computedAt: capped.computedAt
        )
    }

    /// "Kept to 11 km: 10% past your longest run of the last 30 days."
    public static func note(keptToKm km: String) -> String {
        note(kept: "\(km) km")
    }

    /// The same with the distance already written in the runner's unit
    /// ("7 mi").
    public static func note(kept distance: String) -> String {
        "Kept to \(distance): 10% past your longest run of the last 30 days"
    }
}
