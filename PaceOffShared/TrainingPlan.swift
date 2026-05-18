// TrainingPlan.swift
// Value types for a multi-week training plan. Codable so the active plan can
// be persisted to the App Group container the same way HealthDataSnapshot is.

import Foundation

// MARK: - Difficulty tier

/// What "Easy / Medium / Aggressive" means in practice. These tiers drive:
/// - Number of runs per week
/// - Whether quality (tempo / interval) sessions are included
/// - Weekly mileage curve
/// - How aggressive the long-run buildup is
public enum PlanTier: String, Codable, Sendable, CaseIterable, Identifiable {
    case easy
    case medium
    case aggressive

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .easy:       return "Easy"
        case .medium:     return "Medium"
        case .aggressive: return "Aggressive"
        }
    }

    public var runsPerWeek: Int {
        switch self {
        case .easy:       return 3
        case .medium:     return 4
        case .aggressive: return 5
        }
    }

    public var blurb: String {
        switch self {
        case .easy:
            return "Three runs a week — one long, two easy. For building a base or coming back from time off."
        case .medium:
            return "Four runs a week — long run, one quality session (tempo or intervals), two easies."
        case .aggressive:
            return "Five runs a week — long run, two quality sessions, recovery easies. For experienced runners chasing a PB."
        }
    }
}

// MARK: - Day-of-week

/// Mon..Sun. We avoid Foundation's `Calendar.Weekday` because its raw values
/// are calendar-dependent (Sunday = 1 in Gregorian, but plans want a stable
/// Mon-first ordering for display).
public enum Weekday: Int, Codable, Sendable, CaseIterable, Identifiable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    public var shortName: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        case .sunday:    return "Sun"
        }
    }

    public var displayName: String {
        switch self {
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        case .sunday:    return "Sunday"
        }
    }
}

// MARK: - Workout kind

public enum WorkoutKind: String, Codable, Sendable, CaseIterable {
    case easy         // E pace — most of the volume
    case long         // E pace, but the week's longest distance
    case marathonPace // M pace — race-specific endurance for HM / marathon goals
    case tempo        // around T pace, continuous (15–30 min sustained)
    case threshold    // T pace, often as cruise intervals (e.g. 4 × 1 km @ T)
    case interval     // I pace (95–100% VO2max) reps with jog recovery
    case strides      // short fast accelerations (~20 s × 4–6), no full quality session
    case rest         // explicit rest day, kept for display

    public var displayName: String {
        switch self {
        case .easy:         return "Easy"
        case .long:         return "Long"
        case .marathonPace: return "Marathon Pace"
        case .tempo:        return "Tempo"
        case .threshold:    return "Threshold"
        case .interval:     return "Interval"
        case .strides:      return "Strides"
        case .rest:         return "Rest"
        }
    }

    /// True for the harder workouts the plan should buffer with easy days.
    public var isQuality: Bool {
        switch self {
        case .tempo, .threshold, .interval, .marathonPace: return true
        default: return false
        }
    }
}

// MARK: - Workout

/// A single prescribed workout for one day. Distances are in meters; paces
/// are seconds-per-kilometre. A pace `range` of single-value low==high means
/// "hit this pace exactly"; otherwise interpret as a band the runner should
/// stay within.
public struct Workout: Codable, Sendable, Equatable {
    public let kind: WorkoutKind
    /// Total distance, in meters. Includes warm-up + main + cool-down for
    /// interval sessions, so this is a "go for a run of about X km" number.
    public let distanceMeters: Double
    /// Pace target range (sec/km). Inclusive on both ends. For rest days
    /// `paceMinSecPerKm == paceMaxSecPerKm == 0` — treat as "n/a".
    public let paceMinSecPerKm: Double
    public let paceMaxSecPerKm: Double
    public let notes: String?

    public init(kind: WorkoutKind,
                distanceMeters: Double,
                paceMinSecPerKm: Double,
                paceMaxSecPerKm: Double,
                notes: String? = nil) {
        self.kind = kind
        self.distanceMeters = distanceMeters
        self.paceMinSecPerKm = paceMinSecPerKm
        self.paceMaxSecPerKm = paceMaxSecPerKm
        self.notes = notes
    }

    public var distanceKm: Double { distanceMeters / 1000 }

    /// "12 km · 5:25–5:45/km" / "Rest" / "Strides".
    public var summary: String {
        if kind == .rest { return "Rest" }
        let km = String(format: "%.1f km", distanceKm)
        if paceMinSecPerKm <= 0 { return km }
        return "\(km) · \(formattedPaceRange)"
    }

    public var formattedPaceRange: String {
        guard paceMinSecPerKm > 0 else { return "" }
        let lo = Self.formatPace(paceMinSecPerKm)
        let hi = Self.formatPace(paceMaxSecPerKm)
        return lo == hi ? "\(lo)/km" : "\(lo)–\(hi)/km"
    }

    private static func formatPace(_ secPerKm: Double) -> String {
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Training day & week

public struct TrainingDay: Codable, Sendable, Equatable, Identifiable {
    public let weekday: Weekday
    public let workout: Workout

    public var id: Int { weekday.rawValue }

    public init(weekday: Weekday, workout: Workout) {
        self.weekday = weekday
        self.workout = workout
    }
}

public struct TrainingWeek: Codable, Sendable, Equatable, Identifiable {
    /// 1-based week number (Week 1, Week 2, ...).
    public let index: Int
    /// Always 7 days, Mon..Sun, even on rest days.
    public let days: [TrainingDay]

    public var id: Int { index }

    public init(index: Int, days: [TrainingDay]) {
        self.index = index
        self.days = days
    }

    /// Sum of run distances this week, in meters.
    public var totalDistanceMeters: Double {
        days.reduce(0) { $0 + ($1.workout.kind == .rest ? 0 : $1.workout.distanceMeters) }
    }

    public var totalDistanceKm: Double { totalDistanceMeters / 1000 }

    /// Count of non-rest days.
    public var runCount: Int {
        days.reduce(0) { $0 + ($1.workout.kind == .rest ? 0 : 1) }
    }
}

// MARK: - Training plan

public struct TrainingPlan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let goal: RunningGoal
    public let tier: PlanTier
    public let longRunDay: Weekday
    /// Mon..Sun weeks, in chronological order.
    public let weeks: [TrainingWeek]
    /// VDOT used to compute the paces — captured so the UI can explain *why*
    /// these paces and so we know when to suggest a recompute.
    public let vdot: Double
    /// True when the VDOT was a beginner-default fallback (no VO2 max, no
    /// PB to anchor on).
    public let usedBeginnerDefault: Bool
    /// When the plan was generated.
    public let createdAt: Date

    public init(id: UUID = UUID(),
                goal: RunningGoal,
                tier: PlanTier,
                longRunDay: Weekday,
                weeks: [TrainingWeek],
                vdot: Double,
                usedBeginnerDefault: Bool,
                createdAt: Date = Date()) {
        self.id = id
        self.goal = goal
        self.tier = tier
        self.longRunDay = longRunDay
        self.weeks = weeks
        self.vdot = vdot
        self.usedBeginnerDefault = usedBeginnerDefault
        self.createdAt = createdAt
    }

    public var weekCount: Int { weeks.count }

    public var displayName: String {
        "\(tier.displayName) \(goal.displayName) Plan"
    }

    /// Which week index (0-based into `weeks`) does `today` fall into?
    /// Returns nil when `today` is before the plan starts or after it ends.
    public func currentWeekIndex(today: Date = Date()) -> Int? {
        let cal = Calendar.current
        let startOfPlan = cal.startOfDay(for: createdAt)
        let startOfToday = cal.startOfDay(for: today)
        guard let days = cal.dateComponents([.day], from: startOfPlan, to: startOfToday).day,
              days >= 0
        else { return nil }
        let weekIndex = days / 7
        return weekIndex < weeks.count ? weekIndex : nil
    }

    /// Number of weeks remaining (counts the current week as remaining).
    public func weeksRemaining(today: Date = Date()) -> Int {
        guard let idx = currentWeekIndex(today: today) else { return 0 }
        return weeks.count - idx
    }

    /// Today's prescribed workout, or nil when the plan isn't active today.
    public func todayWorkout(today: Date = Date()) -> Workout? {
        guard let weekIdx = currentWeekIndex(today: today) else { return nil }
        // Map calendar weekday → our Mon..Sun ordering. Calendar.weekday
        // returns 1 = Sunday … 7 = Saturday on Gregorian.
        let cal = Calendar.current
        let calWeekday = cal.component(.weekday, from: today)
        // Sunday(1) → 6 (sunday=6 in our enum), Monday(2) → 0, etc.
        let mappedRaw = (calWeekday + 5) % 7
        guard let weekday = Weekday(rawValue: mappedRaw) else { return nil }
        return weeks[weekIdx].days.first(where: { $0.weekday == weekday })?.workout
    }
}
