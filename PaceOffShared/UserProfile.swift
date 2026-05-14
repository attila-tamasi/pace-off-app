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

/// A personal best for a given distance — the time, and the year it was set.
/// The user only logs a PB for the distance matching their current goal.
public struct PersonalBest: Codable, Sendable, Equatable {
    /// Finishing time in seconds.
    public var durationSeconds: Double
    /// Calendar year the PB was achieved.
    public var year: Int

    public init(durationSeconds: Double, year: Int) {
        self.durationSeconds = durationSeconds
        self.year = year
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
    /// Personal best for the `goal` distance. Nil if the user hasn't run it yet.
    public var personalBest: PersonalBest?
    /// Stable Sign in with Apple user identifier. Nil if the user skipped sign-in.
    public var appleUserID: String?
    /// Whether a profile photo JPEG exists in the App Group container.
    public var hasPhoto: Bool

    public init(
        displayName: String = "",
        birthday: Date? = nil,
        goal: RunningGoal = .tenK,
        personalBest: PersonalBest? = nil,
        appleUserID: String? = nil,
        hasPhoto: Bool = false
    ) {
        self.displayName = displayName
        self.birthday = birthday
        self.goal = goal
        self.personalBest = personalBest
        self.appleUserID = appleUserID
        self.hasPhoto = hasPhoto
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
