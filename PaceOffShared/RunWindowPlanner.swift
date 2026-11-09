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
    /// The latest a run ends.
    public static let latestEndHour = 21
    /// A run with no pace band (the day's target, without a plan) is timed
    /// at this.
    public static let defaultPaceSecPerKm = 360.0

    /// The day's run in minutes: the plan workout at the middle of its pace
    /// band, or, with no plan workout, the target distance at 6:00/km. Nil
    /// on a rest day, a planned one included, and on race day, whose start
    /// is the race's.
    public static func runMinutes(planWorkout: Workout?, targetKm: Double?) -> Double? {
        if let workout = planWorkout {
            guard workout.kind != .rest, workout.kind != .race, workout.distanceMeters > 0 else { return nil }
            let pace = workout.paceMinSecPerKm > 0
                ? (workout.paceMinSecPerKm + workout.paceMaxSecPerKm) / 2
                : defaultPaceSecPerKm
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
    /// tie, the lightest rain, then the fewest hours too hot or too cold,
    /// the mildest, the fewest windy hours, the calmest, the fewest dark
    /// hours, and finally the earliest.
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
        let length = max(1, Int((runMinutes / 60).rounded(.up)))
        guard hours.count >= length else { return nil }

        // Windows of consecutive hours, none missing in between.
        let windows: [ArraySlice<HourlyWeather>] = (0...(hours.count - length)).compactMap { i in
            let slice = hours[i..<(i + length)]
            let unbroken = zip(slice.dropFirst(), slice).allSatisfy {
                abs($0.date.timeIntervalSince($1.date) - 3_600) < 1
            }
            return unbroken ? slice : nil
        }
        guard let best = windows.min(by: { Badness($0) < Badness($1) }),
              let first = best.first, let last = best.last
        else { return nil }

        let badness = Badness(best)
        let isClear = badness.isClear
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
                         goByEffort: best.contains { $0.feelsLikeC > hotC },
                         reason: reason)
    }

    // MARK: - What counts against an hour

    static func isRainy(_ h: HourlyWeather) -> Bool {
        h.precipitationChance >= rainChance || h.precipitationMm >= rainMm
    }

    static func isHot(_ h: HourlyWeather) -> Bool { h.feelsLikeC > hotC }
    static func isCold(_ h: HourlyWeather) -> Bool { h.feelsLikeC < coldC }
    static func isWindy(_ h: HourlyWeather) -> Bool { h.windKmh >= strongWindKmh }

    /// A window's problems, compared in priority order: how many hours
    /// have each, then how bad they are, then the earlier start.
    private struct Badness: Comparable {
        let rainHours: Int
        let rainAmount: Double
        let temperatureHours: Int
        let temperatureExcess: Double
        let windHours: Int
        let windExcess: Double
        let darkHours: Int
        let start: Date

        init(_ window: ArraySlice<HourlyWeather>) {
            let rainy = window.filter(RunWindowPlanner.isRainy)
            rainHours = rainy.count
            rainAmount = rainy.reduce(0) { $0 + $1.precipitationChance + $1.precipitationMm }
            let offTemperature = window.filter { RunWindowPlanner.isHot($0) || RunWindowPlanner.isCold($0) }
            temperatureHours = offTemperature.count
            temperatureExcess = offTemperature.reduce(0) {
                $0 + max($1.feelsLikeC - RunWindowPlanner.hotC, RunWindowPlanner.coldC - $1.feelsLikeC)
            }
            let windy = window.filter(RunWindowPlanner.isWindy)
            windHours = windy.count
            windExcess = windy.reduce(0) { $0 + $1.windKmh - RunWindowPlanner.strongWindKmh }
            darkHours = window.filter { !$0.isDaylight }.count
            start = window.first?.date ?? .distantFuture
        }

        var isClear: Bool { rainHours == 0 && temperatureHours == 0 && windHours == 0 && darkHours == 0 }

        static func < (a: Badness, b: Badness) -> Bool {
            if a.rainHours != b.rainHours { return a.rainHours < b.rainHours }
            if a.rainAmount != b.rainAmount { return a.rainAmount < b.rainAmount }
            if a.temperatureHours != b.temperatureHours { return a.temperatureHours < b.temperatureHours }
            if a.temperatureExcess != b.temperatureExcess { return a.temperatureExcess < b.temperatureExcess }
            if a.windHours != b.windHours { return a.windHours < b.windHours }
            if a.windExcess != b.windExcess { return a.windExcess < b.windExcess }
            if a.darkHours != b.darkHours { return a.darkHours < b.darkHours }
            return a.start < b.start
        }
    }

    // MARK: - The reason line

    /// "dry and 12 °C", "rain likely, feels like 28 °C and windy".
    private static func describe(_ window: ArraySlice<HourlyWeather>) -> String {
        let count = Double(window.count)
        var parts = [window.contains(where: isRainy) ? "rain likely" : "dry"]
        if window.contains(where: { isHot($0) || isCold($0) }) {
            parts.append("feels like \(degrees(window.reduce(0) { $0 + $1.feelsLikeC } / count))")
        } else {
            parts.append(degrees(window.reduce(0) { $0 + $1.temperatureC } / count))
        }
        if window.contains(where: isWindy) { parts.append("windy") }
        if window.contains(where: { !$0.isDaylight }) { parts.append("dark") }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

    /// The first problem, by priority, in the day's other hours: "rain from
    /// 16:00" when it comes after the window, "rain until 11:00" when it's
    /// over by then. Darkness goes unsaid.
    private static func problemNote(hours: [HourlyWeather],
                                    window: ArraySlice<HourlyWeather>,
                                    calendar: Calendar) -> String? {
        guard let start = window.first?.date, let end = window.last?.date.addingTimeInterval(3_600)
        else { return nil }
        let kinds: [(String, (HourlyWeather) -> Bool)] = [
            ("rain", isRainy),
            ("over 25 °C", isHot),
            ("below −5 °C", isCold),
            ("strong wind", isWindy),
        ]
        for (name, matches) in kinds {
            let problem = hours.filter(matches)
            if let next = problem.first(where: { $0.date >= end }) {
                return "\(name) from \(clock(next.date, calendar))"
            }
            if let lastBefore = problem.last(where: { $0.date < start }) {
                return "\(name) until \(clock(lastBefore.date.addingTimeInterval(3_600), calendar))"
            }
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
