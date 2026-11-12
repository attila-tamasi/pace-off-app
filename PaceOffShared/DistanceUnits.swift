// DistanceUnits.swift
// Kilometres or miles, and the one formatter for distances, paces and
// speeds. The engines keep working in metres and seconds per km; only what
// a runner reads goes through here. Decimals follow the locale ("10,8 km"
// in Hungarian). Pure and Sendable.

import Foundation

public enum DistanceUnit: String, Codable, Sendable, CaseIterable {
    case kilometers
    case miles

    public static let metersPerMile = 1_609.344

    public var meters: Double { self == .miles ? Self.metersPerMile : 1_000 }

    /// "km", "mi".
    public var symbol: String { self == .miles ? "mi" : "km" }

    /// Miles in the US, the UK, Liberia and Myanmar (the locales whose
    /// measurement system is US or UK), kilometres elsewhere.
    public static func `default`(for locale: Locale) -> DistanceUnit {
        switch locale.measurementSystem {
        case .us, .uk: return .miles
        default: return .kilometers
        }
    }

    /// The runner's choice in App Group defaults, else the locale's.
    public static func current(in defaults: UserDefaults?, locale: Locale = .current) -> DistanceUnit {
        defaults?.string(forKey: AppGroup.Keys.distanceUnit).flatMap(DistanceUnit.init(rawValue:))
            ?? .default(for: locale)
    }

    public static func save(_ unit: DistanceUnit, in defaults: UserDefaults?) {
        defaults?.set(unit.rawValue, forKey: AppGroup.Keys.distanceUnit)
    }
}

public struct UnitFormatter: Sendable {

    public let unit: DistanceUnit
    public let locale: Locale

    public init(unit: DistanceUnit, locale: Locale = .current) {
        self.unit = unit
        self.locale = locale
    }

    /// Metres in the unit.
    public func value(_ meters: Double) -> Double { meters / unit.meters }

    /// "8", "10.8" ("10,8" where the locale uses a comma): whole units
    /// without a decimal, else one decimal.
    public func number(_ meters: Double) -> String {
        let tenths = (value(meters) * 10).rounded() / 10
        let whole = tenths == tenths.rounded()
        return format(tenths, decimals: whole ? 0 : 1)
    }

    /// "8 km", "10.8 mi".
    public func distance(_ meters: Double) -> String { "\(number(meters)) \(unit.symbol)" }

    /// "8.0 km": always one decimal, as the plan's workouts read.
    public func distanceOneDecimal(_ meters: Double) -> String {
        "\(format((value(meters) * 10).rounded() / 10, decimals: 1)) \(unit.symbol)"
    }

    /// "5:24": minutes and seconds per unit, from seconds per km.
    public func paceNumber(secondsPerKm: Double) -> String {
        let perUnit = Int((secondsPerKm * unit.meters / 1_000).rounded())
        return String(format: "%d:%02d", perUnit / 60, perUnit % 60)
    }

    /// "5:24/km", "8:41/mi".
    public func pace(secondsPerKm: Double) -> String { "\(paceNumber(secondsPerKm: secondsPerKm))/\(unit.symbol)" }

    /// "5:25–5:45/km", or one pace when the ends match.
    public func paceBand(minSecondsPerKm: Double, maxSecondsPerKm: Double) -> String {
        let lo = paceNumber(secondsPerKm: minSecondsPerKm)
        let hi = paceNumber(secondsPerKm: maxSecondsPerKm)
        return lo == hi ? "\(lo)/\(unit.symbol)" : "\(lo)–\(hi)/\(unit.symbol)"
    }

    /// "11.1 km/h", "6.9 mph", from metres per second.
    public func speed(metersPerSecond: Double) -> String {
        let perHour = metersPerSecond * 3_600 / unit.meters
        return "\(format(perHour, decimals: 1)) \(unit == .miles ? "mph" : "km/h")"
    }

    /// A whole number of units for a distance, rounded up but never above
    /// `capMeters` (the daily target's rule, in either unit), and at least 1.
    public func wholeUnits(_ meters: Double, capMeters: Double?) -> Int {
        let roundedUp = Int((value(meters) - 1e-6).rounded(.up))
        guard let capMeters else { return max(1, roundedUp) }
        let underCap = max(1, Int((value(capMeters) + 1e-6).rounded(.down)))
        return max(1, min(roundedUp, underCap))
    }

    private func format(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale).grouping(.never))
    }
}
