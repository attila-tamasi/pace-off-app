// RunWindowPlanner.swift
// When in the day to run, from the hourly forecast: the window that best
// avoids rain, heat or cold, strong wind and darkness, in that order, and a
// one-line reason for the morning push. Pure, so the background refresh and
// the foreground refresh pick the same window, and tests can pin it.

import Foundation

/// One hour of the forecast.
public struct HourlyWeather: Codable, Sendable, Equatable {
    /// The hour's start.
    public let date: Date
    public let temperatureC: Double
    public let feelsLikeC: Double
    /// 0…1.
    public let precipitationChance: Double
    /// Over the hour.
    public let precipitationMm: Double
    public let windKmh: Double
    public let isDaylight: Bool

    public init(date: Date, temperatureC: Double, feelsLikeC: Double, precipitationChance: Double,
                precipitationMm: Double, windKmh: Double, isDaylight: Bool) {
        self.date = date
        self.temperatureC = temperatureC
        self.feelsLikeC = feelsLikeC
        self.precipitationChance = precipitationChance
        self.precipitationMm = precipitationMm
        self.windKmh = windKmh
        self.isDaylight = isDaylight
    }
}

/// The hours to run in, and why.
public struct RunWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date
    /// False when no window of the run's length clears rain, heat, cold,
    /// wind and darkness: this one is the least bad, and the reason says so.
    public let isClear: Bool
    /// Over 25 °C feels-like in some hour of the window: go by effort, not
    /// pace.
    public let goByEffort: Bool
    /// "Dry and 12 °C 07:00–09:00; rain from 16:00".
    public let reason: String
}

public enum RunWindowPlanner {

    /// An hour is rainy from this chance on, or from `rainMm` in the hour.
    public static let rainChance = 0.5
    public static let rainMm = 0.5
    /// Too hot above this, too cold below that, feels-like.
    public static let hotC = 25.0
    public static let coldC = -5.0
    /// Strong wind from here on (Beaufort 5, a fresh breeze).
    public static let strongWindKmh = 30.0
    /// Below the rules, still worth avoiding when an hour without them is
    /// free: rain possible from this chance, a breeze from this wind.
    public static let possibleRainChance = 0.3
    public static let breezyKmh = 20.0
    /// The latest a run ends.
    public static let latestEndHour = 21
    /// A run with no pace band (the day's target, without a plan) is timed
    /// at this, and so is a quality session, whose warm-up, jogs and
    /// cool-down go slower than its band, unless its band is slower still.
    public static let defaultPaceSecPerKm = 360.0

    /// The day's run in minutes, on the long side, so the window doesn't run
    /// short: the plan workout at the slow end of its pace band (a quality
    /// session at 6:00/km unless its band is slower), or, with no plan
    /// workout, the target distance at 6:00/km. Nil on a rest day, a planned
    /// one included, and on race day, whose start is the race's.
    public static func runMinutes(planWorkout: Workout?, targetKm: Double?) -> Double? {
        if let workout = planWorkout {
            guard workout.kind != .rest, workout.kind != .race, workout.distanceMeters > 0 else { return nil }
            let slowEnd = workout.paceMaxSecPerKm
            let pace = workout.kind.isQuality || slowEnd <= 0 ? max(slowEnd, defaultPaceSecPerKm) : slowEnd
            return workout.distanceKm * pace / 60
        }
        guard let km = targetKm, km > 0 else { return nil }
        return km * defaultPaceSecPerKm / 60
    }

    /// The window for a run of `runMinutes`, from `from` (the morning push)
    /// to 21:00 that day, or nil on a rest day (`runMinutes` nil or 0) or
    /// when the forecast has no stretch of hours long enough in that span.
    ///
    /// A window is whole forecast hours, as many as the run needs. Of all
    /// the windows that fit, the one with the fewest rainy hours wins; on a
    /// tie, the lowest rain chance, then the least rain, the fewest hours
    /// too hot or too cold, the mildest, the fewest windy hours, the
    /// calmest, the fewest dark hours, the fewest hours with rain possible
    /// or a breeze, and finally the earliest.
    public static func window(forecast: [HourlyWeather],
                              runMinutes: Double?,
                              from: Date,
                              calendar: Calendar = .current) -> RunWindow? {
        guard let runMinutes, runMinutes > 0,
              let until = calendar.date(bySettingHour: latestEndHour, minute: 0, second: 0, of: from)
        else { return nil }
        let hours = forecast
            .filter { $0.date >= from && $0.date.addingTimeInterval(3_600) <= until }
            .sorted { $0.date < $1.date }
        // A hair over a whole hour (a scaled distance) still fits in it.
        let length = max(1, Int((runMinutes / 60 - 0.01).rounded(.up)))
        guard hours.count >= length else { return nil }

        // Windows of consecutive hours, none missing in between.
        let windows: [(hours: ArraySlice<HourlyWeather>, badness: Badness)] =
            (0...(hours.count - length)).compactMap { (i: Int) -> (hours: ArraySlice<HourlyWeather>, badness: Badness)? in
                let slice = hours[i..<(i + length)]
                let unbroken = zip(slice.dropFirst(), slice).allSatisfy {
                    abs($0.date.timeIntervalSince($1.date) - 3_600) < 1
                }
                guard unbroken else { return nil }
                return (hours: slice, badness: Badness(slice))
            }
        guard let chosen = windows.min(by: { $0.badness < $1.badness }),
              let first = chosen.hours.first, let last = chosen.hours.last
        else { return nil }

        let best = chosen.hours
        let isClear = chosen.badness.isClear
        let span = "\(clock(first.date, calendar))–\(clock(last.date.addingTimeInterval(3_600), calendar))"
        let reason: String
        if isClear {
            let note = problemNote(hours: hours, window: best, calendar: calendar)
            reason = "\(capitalized(describe(best))) \(span)" + (note.map { "; \($0)" } ?? "")
        } else {
            reason = "No clear window today; least bad \(span): \(describe(best))"
        }
        return RunWindow(start: first.date,
                         end: last.date.addingTimeInterval(3_600),
                         isClear: isClear,
                         goByEffort: best.contains(where: isHot),
                         reason: reason)
    }

    // MARK: - What counts against an hour

    static func isRainy(_ h: HourlyWeather) -> Bool {
        h.precipitationChance >= rainChance || h.precipitationMm >= rainMm
    }

    static func isHot(_ h: HourlyWeather) -> Bool { h.feelsLikeC > hotC }
    static func isCold(_ h: HourlyWeather) -> Bool { h.feelsLikeC < coldC }
    static func isWindy(_ h: HourlyWeather) -> Bool { h.windKmh >= strongWindKmh }
    static func isRainPossible(_ h: HourlyWeather) -> Bool {
        !isRainy(h) && h.precipitationChance >= possibleRainChance
    }
    static func isBreezy(_ h: HourlyWeather) -> Bool { !isWindy(h) && h.windKmh >= breezyKmh }

    /// A window's problems, compared in priority order: how many hours
    /// have each, then how bad they are, then the earlier start.
    private struct Badness: Comparable {
        let rainHours: Int
        let rainChance: Double
        let rainMm: Double
        let temperatureHours: Int
        let temperatureExcess: Double
        let windHours: Int
        let windExcess: Double
        let darkHours: Int
        let minorHours: Int
        let start: Date

        init(_ window: ArraySlice<HourlyWeather>) {
            let rainy = window.filter(RunWindowPlanner.isRainy)
            rainHours = rainy.count
            rainChance = rainy.reduce(0) { $0 + $1.precipitationChance }
            rainMm = rainy.reduce(0) { $0 + $1.precipitationMm }
            let offTemperature = window.filter { RunWindowPlanner.isHot($0) || RunWindowPlanner.isCold($0) }
            temperatureHours = offTemperature.count
            temperatureExcess = offTemperature.reduce(0) {
                $0 + max($1.feelsLikeC - RunWindowPlanner.hotC, RunWindowPlanner.coldC - $1.feelsLikeC)
            }
            let windy = window.filter(RunWindowPlanner.isWindy)
            windHours = windy.count
            windExcess = windy.reduce(0) { $0 + $1.windKmh - RunWindowPlanner.strongWindKmh }
            darkHours = window.filter { !$0.isDaylight }.count
            minorHours = window.filter { RunWindowPlanner.isRainPossible($0) || RunWindowPlanner.isBreezy($0) }.count
            start = window.first?.date ?? .distantFuture
        }

        /// Clear of every rule; rain possible or a breeze doesn't count.
        var isClear: Bool { rainHours == 0 && temperatureHours == 0 && windHours == 0 && darkHours == 0 }

        static func < (a: Badness, b: Badness) -> Bool {
            if a.rainHours != b.rainHours { return a.rainHours < b.rainHours }
            if a.rainChance != b.rainChance { return a.rainChance < b.rainChance }
            if a.rainMm != b.rainMm { return a.rainMm < b.rainMm }
            if a.temperatureHours != b.temperatureHours { return a.temperatureHours < b.temperatureHours }
            if a.temperatureExcess != b.temperatureExcess { return a.temperatureExcess < b.temperatureExcess }
            if a.windHours != b.windHours { return a.windHours < b.windHours }
            if a.windExcess != b.windExcess { return a.windExcess < b.windExcess }
            if a.darkHours != b.darkHours { return a.darkHours < b.darkHours }
            if a.minorHours != b.minorHours { return a.minorHours < b.minorHours }
            return a.start < b.start
        }
    }

    // MARK: - The reason line

    /// "dry and 12 °C", "rain likely, feels like 28 °C and windy".
    private static func describe(_ window: ArraySlice<HourlyWeather>) -> String {
        let count = Double(window.count)
        let rain = window.contains(where: isRainy) ? "rain likely"
            : window.contains(where: isRainPossible) ? "rain possible" : "dry"
        var parts = [rain]
        if window.contains(where: { isHot($0) || isCold($0) }) {
            parts.append("feels like \(degrees(window.reduce(0) { $0 + $1.feelsLikeC } / count))")
        } else {
            parts.append(degrees(window.reduce(0) { $0 + $1.temperatureC } / count))
        }
        if window.contains(where: isWindy) { parts.append("windy") }
        if window.contains(where: { !$0.isDaylight }) { parts.append("dark") }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    /// What closes in on the window: the first problem after it ("rain from
    /// 16:00"), or else the last one before it ("strong wind until 14:00").
    /// In an hour with several, the first by priority names it. Darkness
    /// goes unsaid.
    private static func problemNote(hours: [HourlyWeather],
                                    window: ArraySlice<HourlyWeather>,
                                    calendar: Calendar) -> String? {
        guard let start = window.first?.date, let end = window.last?.date.addingTimeInterval(3_600)
        else { return nil }
        let kinds: [(String, (HourlyWeather) -> Bool)] = [
            ("rain", isRainy),
            ("over \(degrees(hotC))", isHot),
            ("below \(degrees(coldC))", isCold),
            ("strong wind", isWindy),
        ]
        func kind(of hour: HourlyWeather) -> String? { kinds.first { $0.1(hour) }?.0 }
        if let next = hours.first(where: { $0.date >= end && kind(of: $0) != nil }), let name = kind(of: next) {
            return "\(name) from \(clock(next.date, calendar))"
        }
        if let previous = hours.last(where: { $0.date < start && kind(of: $0) != nil }), let name = kind(of: previous) {
            return "\(name) until \(clock(previous.date.addingTimeInterval(3_600), calendar))"
        }
        return nil
    }

    /// "12 °C", "−3 °C".
    private static func degrees(_ celsius: Double) -> String {
        let rounded = Int(celsius.rounded())
        return rounded < 0 ? "−\(-rounded) °C" : "\(rounded) °C"
    }

    /// "07:00".
    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
