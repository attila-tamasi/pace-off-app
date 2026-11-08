// UserProfile.swift
// The runner's profile — identity, goal, and personal best. Persisted locally
// (App Group UserDefaults); never leaves the device. Created during onboarding
// and editable later from the Profile tab.

import Foundation

/// A standard race distance the user is training toward.
public enum RunningGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case fiveK
    case tenK
    case halfMarathon
    case marathon

    public var id: String { rawValue }

    /// Short label for chips and pickers, e.g. "10K".
    public var shortName: String {
        switch self {
        case .fiveK:        return "5K"
        case .tenK:         return "10K"
        case .halfMarathon: return "Half"
        case .marathon:     return "Marathon"
        }
    }

    /// Full label for headings, e.g. "Half Marathon".
    public var displayName: String {
        switch self {
        case .fiveK:        return "5K"
        case .tenK:         return "10K"
        case .halfMarathon: return "Half Marathon"
        case .marathon:     return "Marathon"
        }
    }

    /// The official race distance in meters.
    public var distanceMeters: Double {
        switch self {
        case .fiveK:        return 5_000
        case .tenK:         return 10_000
        case .halfMarathon: return 21_097.5
        case .marathon:     return 42_195
        }
    }

    /// Distance in km, for display ("21.1 km").
    public var distanceKm: Double { distanceMeters / 1000 }
}

/// A personal best: the time, the year it was set, and the race distance
/// it's for. A PB for another distance than the goal is converted through
/// VDOT wherever it's used, never taken as a time for the goal's distance.
public struct PersonalBest: Codable, Sendable, Equatable {
    /// Finishing time in seconds.
    public var durationSeconds: Double
    /// Calendar year the PB was achieved.
    public var year: Int
    /// The race distance the time is for. Nil only on a PB saved before
    /// distances were stored: `UserProfile` gives it the goal's distance
    /// when it decodes, and callers read a nil as the goal's.
    public var distance: RunningGoal?

    public init(durationSeconds: Double, year: Int, distance: RunningGoal? = nil) {
        self.durationSeconds = durationSeconds
        self.year = year
        self.distance = distance
    }

    /// The runner's VDOT from this PB, over its own distance (the goal's
    /// when it has none). Nil when Daniels' formula can't use the time.
    public func vdot(goal: RunningGoal) -> Double? {
        VDOTCalculator().vdot(fromRaceDistanceMeters: (distance ?? goal).distanceMeters,
                              timeSeconds: durationSeconds)
    }

    /// The time this PB is worth over `goal`'s distance: the time itself
    /// when it's for that distance, otherwise the time at the same VDOT
    /// (Daniels' equivalent performance). Nil when it can't be converted.
    public func equivalentSeconds(at goal: RunningGoal) -> Double? {
        let own = distance ?? goal
        if own == goal { return durationSeconds }
        guard let vdot = vdot(goal: goal) else { return nil }
        return VDOTCalculator().raceTimeSeconds(distanceMeters: goal.distanceMeters, vdot: vdot)
    }

    /// "3:58:21" for marathons, "47:12" for shorter distances.
    public var formattedTime: String {
        let total = Int(durationSeconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Average pace implied by the PB over the given distance, as "5:24/km".
    public func formattedPace(over distanceMeters: Double) -> String {
        guard distanceMeters > 0, durationSeconds > 0 else { return "—" }
        let secPerKm = durationSeconds / (distanceMeters / 1000)
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d/km", m, s)
    }
}

/// The user's locally-stored profile.
public struct UserProfile: Codable, Sendable, Equatable {
    /// Display name. Pre-filled from Sign in with Apple when available.
    public var displayName: String
    /// Birthday (date only — time component is ignored).
    public var birthday: Date?
    /// The race distance the user is training toward.
    public var goal: RunningGoal
    /// The runner's personal best, for the distance it records. Nil when
    /// they haven't logged one.
    public var personalBest: PersonalBest?
    /// Optional race-day deadline for the goal. When set, the prediction
    /// service projects a realistic training-improvement curve up to this
    /// date; without it, the projection is purely "what could you run today".
    public var goalDate: Date?
    /// Stable Sign in with Apple user identifier. Nil if the user skipped sign-in.
    public var appleUserID: String?
    /// Whether a profile photo JPEG exists in the App Group container.
    public var hasPhoto: Bool

    public init(
        displayName: String = "",
        birthday: Date? = nil,
        goal: RunningGoal = .tenK,
        personalBest: PersonalBest? = nil,
        goalDate: Date? = nil,
        appleUserID: String? = nil,
        hasPhoto: Bool = false
    ) {
        self.displayName = displayName
        self.birthday = birthday
        self.goal = goal
        self.personalBest = personalBest
        self.goalDate = goalDate
        self.appleUserID = appleUserID
        self.hasPhoto = hasPhoto
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, birthday, goal, personalBest, goalDate, appleUserID, hasPhoto
    }

    /// Decodes profiles of every earlier shape: optional fields that didn't
    /// exist yet decode as nil, and a PB saved without a distance was the
    /// goal's (the editor only took one for the goal), so it gets it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        birthday = try c.decodeIfPresent(Date.self, forKey: .birthday)
        goal = try c.decodeIfPresent(RunningGoal.self, forKey: .goal) ?? .tenK
        var pb = try c.decodeIfPresent(PersonalBest.self, forKey: .personalBest)
        if pb != nil, pb?.distance == nil { pb?.distance = goal }
        personalBest = pb
        goalDate = try c.decodeIfPresent(Date.self, forKey: .goalDate)
        appleUserID = try c.decodeIfPresent(String.self, forKey: .appleUserID)
        hasPhoto = try c.decodeIfPresent(Bool.self, forKey: .hasPhoto) ?? false
    }

    /// Age in whole years derived from `birthday`, or nil if no birthday set.
    public func age(asOf referenceDate: Date = Date()) -> Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: referenceDate).year
    }

    /// True once the user has given us enough to call the profile "set up".
    public var isComplete: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
