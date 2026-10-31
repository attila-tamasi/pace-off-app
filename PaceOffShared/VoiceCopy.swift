// VoiceCopy.swift
// Drill-sergeant voice library — PRD §8.2.
// One state, one line. No randomization in MVP.

import Foundation

public enum VoiceState: Sendable, Equatable {
    case streakDay1(yesterdayKm: Double, todayKm: Double)
    case streakDay7Plus(streakDays: Int)
    case onTrack(todayKm: Double)
    case skipOneDay(todayKm: Double)
    case skipTwoDays(todayKm: Double)
    case skipThreePlusDays(todayKm: Double)
    case vo2MaxDeclining(deltaPerMonth: Double, todayKm: Double)
    case recovery(todayKm: Double)
    case ranToday(streakDays: Int)
    case runCompletedHitTarget(tomorrowKm: Double)
    case runCompletedShortfall(actualKm: Double, targetKm: Double)
    case fatigueGuard

    /// `target.daysSinceLastRun` counts calendar days back to the last run:
    /// 0 means the runner already ran today, 1 that the last run was
    /// yesterday, so nothing was skipped. Only from 2 on was a day missed,
    /// and the skip count is one less than the gap.
    ///
    /// `currentStreak` is `RunStreak.current`: it includes today once
    /// today has a run, and runs through yesterday until then.
    public init(target: RunTarget, yesterday: RunRecord?, currentStreak: Int) {
        // Use the *displayed* (rounded-up) target so every voice line and
        // notification matches the integer the user sees on the hero card.
        let displayedKm = Double(target.displayedDistanceKm)
        let gap = target.daysSinceLastRun

        // Today's run is in: nothing left to push for.
        if gap == 0 {
            self = .ranToday(streakDays: currentStreak)
            return
        }
        // The engine's tone decides the restart and recovery days; the copy
        // follows it, so the words never fight the badge next to them.
        if target.tone == .restart {
            self = .skipThreePlusDays(todayKm: displayedKm)
            return
        }
        if target.tone == .recovery {
            self = .recovery(todayKm: displayedKm)
            return
        }
        if target.fatigueGuardActive {
            self = .fatigueGuard
            return
        }
        switch gap {
        case 1:
            if let slope = target.vo2MaxSlope, slope < -0.05 {
                // VO2Max declining wins over a neutral streak line.
                self = .vo2MaxDeclining(deltaPerMonth: abs(slope) * 4.0, todayKm: displayedKm)
            } else if currentStreak >= 7 {
                // The streak runs through yesterday; today's run makes it one longer.
                self = .streakDay7Plus(streakDays: currentStreak + 1)
            } else if let y = yesterday {
                self = .streakDay1(yesterdayKm: y.distanceKm, todayKm: displayedKm)
            } else {
                self = .onTrack(todayKm: displayedKm)
            }
        case 2:
            self = .skipOneDay(todayKm: displayedKm)
        case 3:
            self = .skipTwoDays(todayKm: displayedKm)
        default:
            self = .skipThreePlusDays(todayKm: displayedKm)
        }
    }
}

public struct VoiceCopy: Sendable {

    public init() {}

    /// Notification body — max ~8 words per PRD §8.1.
    public func notification(for state: VoiceState) -> String {
        switch state {
        case .streakDay1(_, let today):
            return "Yesterday: done. Today: \(format(today)) km."
        case .streakDay7Plus(let days):
            return "Day \(days). Don't waste it."
        case .onTrack(let today):
            return "On track. \(format(today)) km today."
        case .skipOneDay(let today):
            return "You skipped yesterday. Run \(format(today)) km."
        case .skipTwoDays(_):
            return "Two days. This is the run."
        case .skipThreePlusDays(let today):
            return "Restart. \(format(today)) km. Now."
        case .vo2MaxDeclining(_, let today):
            return "Fitness dropped. \(format(today)) km today."
        case .recovery(let today):
            return "Recovery day. Easy \(format(today)) km, nothing more."
        case .ranToday:
            return "Run logged. Recover and go again tomorrow."
        case .runCompletedHitTarget:
            return "Done."
        case .runCompletedShortfall:
            return "Short. Tomorrow we close it."
        case .fatigueGuard:
            return "HR is up. Easy run today."
        }
    }

    /// Today card — max ~12 words per PRD §8.1.
    public func todayCard(for state: VoiceState) -> String {
        switch state {
        case .streakDay1(let y, let t):
            return "Yesterday was \(format(y)). Today is \(format(t)). Earn the streak."
        case .streakDay7Plus(let days):
            return "\(days) days. The streak is the product. Protect it."
        case .onTrack(let t):
            return "On track. Keep it rolling. Today: \(format(t)) km."
        case .skipOneDay(let t):
            return "One skip. Two becomes a habit. Today: \(format(t)) km."
        case .skipTwoDays(let t):
            return "Two skips. Today is mandatory. Target: \(format(t)) km."
        case .skipThreePlusDays(let t):
            return "Restart day. Don't argue. \(format(t)) km. Lace up."
        case .vo2MaxDeclining(let d, let t):
            return "VO2Max down \(formatDecimal(d, places: 1)) this month. Fix it. \(format(t)) km."
        case .recovery(let t):
            return "Recovery day. \(format(t)) km, easy pace. Rest is part of training."
        case .ranToday(let days):
            return days >= 2
                ? "Run logged. \(days) days straight. Recover and go again tomorrow."
                : "Run logged. Recover and go again tomorrow."
        case .runCompletedHitTarget(let tomorrow):
            return "Done. Tomorrow: \(format(tomorrow)) km."
        case .runCompletedShortfall(let actual, let target):
            return "Finished \(format(actual)) of \(format(target)). Tomorrow we close the gap."
        case .fatigueGuard:
            return "Resting HR is elevated. Easy run today, no hero stuff."
        }
    }

    /// Format kilometers as either a whole number (`"8"`) when the value is
    /// integral or one decimal place (`"5.4"`) otherwise. Targets are always
    /// integral after rounding-up; actual run distances keep their decimal.
    private func format(_ km: Double) -> String {
        if km == km.rounded() {
            return String(format: "%.0f", km)
        }
        return String(format: "%.1f", km)
    }
    private func formatDecimal(_ v: Double, places: Int) -> String { String(format: "%.\(places)f", v) }
}
