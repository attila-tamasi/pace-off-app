// VoiceCopy.swift
// Drill-sergeant voice library — PRD §8.2.
// One state, one line. No randomization in MVP.

import Foundation

public enum VoiceState: Sendable {
    case streakDay1(yesterdayKm: Double, todayKm: Double)
    case streakDay7Plus(streakDays: Int)
    case skipOneDay(todayKm: Double)
    case skipTwoDays(todayKm: Double)
    case skipThreePlusDays(todayKm: Double)
    case vo2MaxDeclining(deltaPerMonth: Double, todayKm: Double)
    case runCompletedHitTarget(tomorrowKm: Double)
    case runCompletedShortfall(actualKm: Double, targetKm: Double)
    case fatigueGuard

    public init(target: RunTarget, yesterday: RunRecord?, currentStreak: Int) {
        // Order matters: most specific state first
        if let slope = target.vo2MaxSlope, slope < -0.05, target.daysSinceLastRun == 0 {
            // VO2Max declining wins over neutral streak
            let monthly = abs(slope) * 4.0
            self = .vo2MaxDeclining(deltaPerMonth: monthly, todayKm: target.distanceKm)
            return
        }
        if target.fatigueGuardActive {
            self = .fatigueGuard
            return
        }
        switch target.daysSinceLastRun {
        case 0:
            if currentStreak >= 7 {
                self = .streakDay7Plus(streakDays: currentStreak + 1)
            } else if let y = yesterday {
                self = .streakDay1(yesterdayKm: y.distanceKm, todayKm: target.distanceKm)
            } else {
                self = .skipOneDay(todayKm: target.distanceKm)
            }
        case 1:
            self = .skipOneDay(todayKm: target.distanceKm)
        case 2:
            self = .skipTwoDays(todayKm: target.distanceKm)
        default:
            self = .skipThreePlusDays(todayKm: target.distanceKm)
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
        case .skipOneDay(let today):
            return "You skipped yesterday. Run \(format(today)) km."
        case .skipTwoDays(_):
            return "Two days. This is the run."
        case .skipThreePlusDays(let today):
            return "Restart. \(format(today)) km. Now."
        case .vo2MaxDeclining(_, let today):
            return "Fitness dropped. \(format(today)) km today."
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
        case .skipOneDay(let t):
            return "One skip. Two becomes a habit. Today: \(format(t)) km."
        case .skipTwoDays(let t):
            return "Two skips. Today is mandatory. Target: \(format(t)) km."
        case .skipThreePlusDays(let t):
            return "Restart day. Don't argue. \(format(t)) km. Lace up."
        case .vo2MaxDeclining(let d, let t):
            return "VO2Max down \(formatDecimal(d, places: 1)) this month. Fix it. \(format(t)) km."
        case .runCompletedHitTarget(let tomorrow):
            return "Done. Tomorrow: \(format(tomorrow)) km."
        case .runCompletedShortfall(let actual, let target):
            return "Finished \(format(actual)) of \(format(target)). Tomorrow we close the gap."
        case .fatigueGuard:
            return "Resting HR is elevated. Easy run today, no hero stuff."
        }
    }

    private func format(_ km: Double) -> String { String(format: "%.1f", km) }
    private func formatDecimal(_ v: Double, places: Int) -> String { String(format: "%.\(places)f", v) }
}
