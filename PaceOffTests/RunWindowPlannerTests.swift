// RunWindowPlannerTests.swift
// Picking the run's window from the hourly forecast: rain, heat, wind and
// darkness avoided in that order, the least bad window on a bad day, and the
// reason line the morning push carries.

import XCTest
@testable import PaceOff

final class RunWindowPlannerTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: hour, minute: minute))!
    }

    /// A whole day, every hour 10 °C, dry and calm, light 07:00–17:00;
    /// `change` adjusts the hours it's given.
    private func day(daylight: Range<Int> = 7..<17,
                     _ change: (Int, inout Weather) -> Void = { _, _ in }) -> [HourlyWeather] {
        (0..<24).map { hour in
            var w = Weather()
            w.isDaylight = daylight.contains(hour)
            change(hour, &w)
            return HourlyWeather(date: at(hour), temperatureC: w.temperature, feelsLikeC: w.feelsLike,
                                 precipitationChance: w.chance, precipitationMm: w.mm,
                                 windKmh: w.wind, isDaylight: w.isDaylight)
        }
    }

    private struct Weather {
        var temperature = 10.0
        var feelsLike = 10.0
        var chance = 0.0
        var mm = 0.0
        var wind = 10.0
        var isDaylight = true
    }

    private func window(_ forecast: [HourlyWeather], minutes: Double? = 50, from: Date? = nil) -> RunWindow? {
        RunWindowPlanner.window(forecast: forecast, runMinutes: minutes, from: from ?? at(7), calendar: calendar)
    }

    // MARK: - The roadmap's cases

    func test_rainAllAfternoon_runsInTheMorning_andSaysWhenTheRainComes() {
        let forecast = day { hour, w in if hour >= 13 { w.chance = 0.8; w.mm = 1.2 } }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(7))
        XCTAssertEqual(w?.end, at(8))
        XCTAssertEqual(w?.isClear, true)
        XCTAssertEqual(w?.reason, "Dry and 10 °C 07:00–08:00; rain from 13:00")
    }

    func test_aHotMidday_runsBeforeTheHeat() {
        let forecast = day { hour, w in
            w.temperature = 18; w.feelsLike = 18
            if (11..<16).contains(hour) { w.temperature = 27; w.feelsLike = 28 }
        }
        // 90 minutes: two hours.
        let w = window(forecast, minutes: 90)
        XCTAssertEqual(w?.start, at(7))
        XCTAssertEqual(w?.end, at(9))
        XCTAssertEqual(w?.goByEffort, false)
        XCTAssertEqual(w?.reason, "Dry and 18 °C 07:00–09:00; over 25 °C from 11:00")
    }

    func test_strongWindAllMorning_runsOnceItDrops() {
        let forecast = day { hour, w in if hour < 14 { w.wind = 40 } }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(14))
        XCTAssertEqual(w?.isClear, true)
        XCTAssertEqual(w?.reason, "Dry and 10 °C 14:00–15:00; strong wind until 14:00")
    }

    func test_rainAllDay_namesTheLeastBadWindow_andSaysSo() {
        // Rain every hour, lightest at 18:00, which is dark: rain counts
        // first, so the dark hour still wins.
        let forecast = day { hour, w in
            w.chance = hour == 18 ? 0.6 : 0.9
            w.mm = hour == 18 ? 0.2 : 2
        }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(18))
        XCTAssertEqual(w?.isClear, false)
        XCTAssertEqual(w?.reason, "No clear window today; least bad 18:00–19:00: rain likely, 10 °C and dark")
    }

    func test_aRestDay_hasNoWindow() {
        XCTAssertNil(window(day(), minutes: nil))
        XCTAssertNil(window(day(), minutes: 0))
    }

    // MARK: - The rules around them

    func test_aHotDayAllDay_picksTheCoolestHour_andSaysGoByEffort() {
        let forecast = day { hour, w in
            w.temperature = 29; w.feelsLike = hour == 7 ? 27 : 31
        }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(7))
        XCTAssertEqual(w?.isClear, false)
        XCTAssertEqual(w?.goByEffort, true)
        XCTAssertEqual(w?.reason, "No clear window today; least bad 07:00–08:00: dry and feels like 27 °C")
    }

    func test_bitterCold_waitsForItToEase() {
        let forecast = day { hour, w in
            w.temperature = hour < 11 ? -4 : 0
            w.feelsLike = hour < 11 ? -9 : -3
        }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(11))
        XCTAssertEqual(w?.reason, "Dry and 0 °C 11:00–12:00; below −5 °C until 11:00")
    }

    func test_darkMornings_waitForDaylight() {
        let forecast = day(daylight: 8..<16)
        let w = window(forecast, from: at(6, 30))
        XCTAssertEqual(w?.start, at(8))
        XCTAssertEqual(w?.reason, "Dry and 10 °C 08:00–09:00")
    }

    func test_aDryDarkHour_beatsARainyLightOne() {
        // Dry only after dark: a dry dark hour beats a rainy light one.
        let forecast = day { hour, w in if hour < 17 { w.chance = 0.7 } }
        let w = window(forecast)
        XCTAssertEqual(w?.start, at(17))
        XCTAssertEqual(w?.isClear, false)
        XCTAssertEqual(w?.reason, "No clear window today; least bad 17:00–18:00: dry, 10 °C and dark")
    }

    func test_theRunEndsBy21_00() {
        // Light until 21:00, rain until 19:00: a two-hour run fits only
        // 19:00–21:00; a three-hour one can't stay dry before 21:00.
        let forecast = day(daylight: 5..<21) { hour, w in if hour < 19 { w.chance = 0.8 } }
        let two = window(forecast, minutes: 120)
        XCTAssertEqual(two?.start, at(19))
        XCTAssertEqual(two?.end, at(21))
        XCTAssertEqual(two?.reason, "Dry and 10 °C 19:00–21:00; rain until 19:00")
        let three = window(forecast, minutes: 180)
        XCTAssertEqual(three?.end, at(21))
        XCTAssertEqual(three?.isClear, false)
    }

    func test_theNote_namesWhatClosesInOnTheWindow_notJustTheWorstOfTheDay() {
        // Rain until 09:00, then wind until 14:00: the wind kept the run
        // back, so the note names it, not the earlier rain.
        let forecast = day { hour, w in
            if hour < 9 { w.chance = 0.8 }
            if hour < 14 { w.wind = 40 }
        }
        XCTAssertEqual(window(forecast)?.reason, "Dry and 10 °C 14:00–15:00; strong wind until 14:00")
    }

    func test_onARainyDay_theLowerChanceWins_beforeTheAmount() {
        // 10:00 is certain rain, if light; 12:00 may stay dry.
        let forecast = day { hour, w in
            switch hour {
            case 10: w.chance = 1.0; w.mm = 0.6
            case 12: w.chance = 0.6; w.mm = 1.1
            default: w.chance = 1.0; w.mm = 3
            }
        }
        XCTAssertEqual(window(forecast)?.start, at(12))
    }

    func test_rainPossibleOrABreeze_givesWayToAClearerHour_butStillCountsAsClear() {
        let forecast = day { hour, w in if hour == 7 { w.chance = 0.45; w.wind = 29 } }
        XCTAssertEqual(window(forecast)?.start, at(8))
        let showery = day { _, w in w.chance = 0.4 }
        let w = window(showery)
        XCTAssertEqual(w?.isClear, true)
        XCTAssertEqual(w?.reason, "Rain possible and 10 °C 07:00–08:00")
    }

    func test_aRunAHairOverAnHour_fitsInOne() {
        XCTAssertEqual(window(day(), minutes: 60.000_001)?.end, at(8))
        XCTAssertEqual(window(day(), minutes: 61)?.end, at(9))
    }

    func test_aWindowSkipsAMissingHour() {
        let forecast = day().filter { $0.date != at(8) }
        let w = window(forecast, minutes: 120)
        XCTAssertEqual(w?.start, at(9))
        XCTAssertEqual(w?.end, at(11))
    }

    func test_aGoodDay_takesTheEarliestWindow_fromThePush() {
        let w = window(day(), from: at(9, 15))
        XCTAssertEqual(w?.start, at(10))
        XCTAssertEqual(w?.reason, "Dry and 10 °C 10:00–11:00")
    }

    func test_noForecast_orTooLateInTheDay_hasNoWindow() {
        XCTAssertNil(window([]))
        XCTAssertNil(window(day(), from: at(20, 30)))
        XCTAssertNil(window(day(), minutes: 120, from: at(20)))
    }

    func test_negativeTemperatures_useAMinusSign() {
        let forecast = day { _, w in w.temperature = -2; w.feelsLike = -4 }
        XCTAssertEqual(window(forecast)?.reason, "Dry and −2 °C 07:00–08:00")
    }

    // MARK: - The day's run

    func test_runMinutes_comeFromThePlanWorkout_elseTheTarget() {
        let easy = Workout(kind: .easy, distanceMeters: 8_000, paceMinSecPerKm: 300, paceMaxSecPerKm: 330)
        // 8 km at the slow end of the band, 5:30/km.
        XCTAssertEqual(RunWindowPlanner.runMinutes(planWorkout: easy, targetKm: 5) ?? 0, 44, accuracy: 1e-9)
        // A 12 km threshold session: its warm-up, jogs and cool-down go
        // slower than its 4:40–4:50 band, so 6:00/km.
        let threshold = Workout(kind: .threshold, distanceMeters: 12_000, paceMinSecPerKm: 280, paceMaxSecPerKm: 290)
        XCTAssertEqual(RunWindowPlanner.runMinutes(planWorkout: threshold, targetKm: nil) ?? 0, 72, accuracy: 1e-9)
        // No plan: the target at 6:00/km.
        XCTAssertEqual(RunWindowPlanner.runMinutes(planWorkout: nil, targetKm: 6) ?? 0, 36, accuracy: 1e-9)
    }

    func test_runMinutes_areNil_onRestAndRaceDays() {
        let race = Workout(kind: .race, distanceMeters: 21_097.5, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        XCTAssertNil(RunWindowPlanner.runMinutes(planWorkout: .rest, targetKm: 5), "a planned rest day")
        XCTAssertNil(RunWindowPlanner.runMinutes(planWorkout: race, targetKm: nil))
        XCTAssertNil(RunWindowPlanner.runMinutes(planWorkout: nil, targetKm: nil))
        XCTAssertNil(RunWindowPlanner.runMinutes(planWorkout: nil, targetKm: 0))
    }

    func test_forecastHours_roundTripThroughJSON() throws {
        let original = day()
        let decoded = try JSONDecoder().decode([HourlyWeather].self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
