// CheckIn.swift
// The runner's own word on the morning: one optional tap on Today, Fresh,
// Normal, Tired, Sore or Unwell. Self-reported recovery follows training
// load more closely than the watch's numbers, and catches what never
// reaches Health (sore legs, a cold, a rough night with a child).
// ReadinessEngine reads it as a signal; the run ledger keeps it with the
// day. Kept in App Group defaults for today only, on the device.

import Foundation

public enum CheckInFeeling: String, Codable, Sendable, CaseIterable {
    case fresh
    case normal
    case tired
    case sore
    case unwell

    public var displayName: String {
        switch self {
        case .fresh: return "Fresh"
        case .normal: return "Normal"
        case .tired: return "Tired"
        case .sore: return "Sore"
        case .unwell: return "Unwell"
        }
    }

    /// The answer as a readiness signal: 0 on track, 1 off. Unwell is red
    /// on its own (`ReadinessEngine`), whatever else says.
    var severity: Int {
        switch self {
        case .fresh, .normal: return 0
        case .tired, .sore: return 1
        case .unwell: return 2
        }
    }
}

/// Today's answer, stored with its day so tomorrow starts unanswered.
public struct CheckIn: Codable, Equatable, Sendable {
    public let day: Date
    public let feeling: CheckInFeeling

    public init(day: Date, feeling: CheckInFeeling) {
        self.day = day
        self.feeling = feeling
    }

    /// Today's answer, nil when there's none or it's from another day.
    public static func todayFeeling(in defaults: UserDefaults?, now: Date = Date(),
                                    calendar: Calendar = .current) -> CheckInFeeling? {
        guard let data = defaults?.data(forKey: AppGroup.Keys.checkIn),
              let checkIn = try? JSONDecoder().decode(CheckIn.self, from: data),
              calendar.isDate(checkIn.day, inSameDayAs: now)
        else { return nil }
        return checkIn.feeling
    }

    /// Saves today's answer, or clears it with nil.
    public static func save(_ feeling: CheckInFeeling?, in defaults: UserDefaults?, now: Date = Date(),
                            calendar: Calendar = .current) {
        guard let feeling else {
            defaults?.removeObject(forKey: AppGroup.Keys.checkIn)
            return
        }
        let checkIn = CheckIn(day: calendar.startOfDay(for: now), feeling: feeling)
        if let data = try? JSONEncoder().encode(checkIn) {
            defaults?.set(data, forKey: AppGroup.Keys.checkIn)
        }
    }
}
