// WidgetCacheTests.swift
// Covers what the widget draws from the cached day: a day cached on an
// earlier date never passes for today, the status dot, the timeline's noon
// and midnight entries, and the App Group round trip.

import XCTest
@testable import PaceOff

final class WidgetCacheTests: XCTestCase {

    private let cal = Calendar.current
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WidgetCacheTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Dates from local components, so the day is the same in any timezone.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    private func target(computedAt: Date) -> RunTarget {
        RunTarget(
            distanceMeters: 7_700,
            tone: .firm,
            daysSinceLastRun: 1,
            vo2MaxSlope: nil,
            baselineMeters: 7_200,
            ceilingClamped: false,
            fatigueGuardActive: false,
            computedAt: computedAt
        )
    }

    /// A day finished with a logged run, cached at 19:00 on the 6th.
    private func doneDay() -> WidgetCache {
        WidgetCache(
            target: target(computedAt: date(day: 6, hour: 19)),
            voiceLine: "Run logged. Recover and go again tomorrow.",
            runCompletedToday: true,
            planSummary: "8.0 km · 5:25–5:45/km",
            planCompletedToday: true
        )
    }

    // MARK: - An earlier day never passes for today

    func test_sameDay_isShownAsCached() {
        let cache = doneDay()
        XCTAssertEqual(cache.asOf(date(day: 6, hour: 23, minute: 59)), cache)
    }

    func test_nextDay_dropsTheTarget_theVoiceLine_andThePlan() {
        let nextMorning = doneDay().asOf(date(day: 7, hour: 0, minute: 1))
        XCTAssertNil(nextMorning.target)
        XCTAssertNil(nextMorning.voiceLine, "Yesterday's \"Run logged\" line must not show today")
        XCTAssertFalse(nextMorning.runCompletedToday)
        XCTAssertNil(nextMorning.planSummary)
        XCTAssertFalse(nextMorning.planCompletedToday)
    }

    func test_noTarget_isEmpty() {
        let cache = WidgetCache(voiceLine: "Open Pace Off.", planSummary: "Rest")
        XCTAssertEqual(cache.asOf(date(day: 6, hour: 9)), .empty)
    }

    // MARK: - Status dot

    func test_dot_yesterdaysDoneDay_isNeutralTheNextDay_notGreen() {
        XCTAssertEqual(doneDay().dot(at: date(day: 6, hour: 20)), .green)
        XCTAssertEqual(doneDay().dot(at: date(day: 7, hour: 0, minute: 1)), .neutral)
        XCTAssertEqual(doneDay().dot(at: date(day: 7, hour: 15)), .neutral)
    }

    func test_dot_pending_isOrangeBeforeNoon_andRedFromNoon() {
        let pending = WidgetCache(target: target(computedAt: date(day: 6, hour: 7)), voiceLine: "Run 8 km.")
        XCTAssertEqual(pending.dot(at: date(day: 6, hour: 11, minute: 59)), .orange)
        XCTAssertEqual(pending.dot(at: date(day: 6, hour: 12)), .red)
    }

    func test_dot_isGreen_onAPlannedRestDay_andOnceThePlanWorkoutIsDone() {
        let rest = WidgetCache(target: target(computedAt: date(day: 6, hour: 7)), planSummary: Workout.rest.summary)
        XCTAssertTrue(rest.isPlanRestDay)
        XCTAssertEqual(rest.dot(at: date(day: 6, hour: 18)), .green)

        let planDone = WidgetCache(target: target(computedAt: date(day: 6, hour: 7)), planCompletedToday: true)
        XCTAssertEqual(planDone.dot(at: date(day: 6, hour: 18)), .green)
    }

    func test_dot_withNoTarget_isNeutral() {
        XCTAssertEqual(WidgetCache.empty.dot(at: date(day: 6, hour: 18)), .neutral)
    }

    // MARK: - Timeline

    func test_timeline_morning_hasNoonAndMidnight() {
        XCTAssertEqual(WidgetCache.timelineDates(from: date(day: 6, hour: 8)), [
            date(day: 6, hour: 8),
            date(day: 6, hour: 12),
            date(day: 7, hour: 0),
        ])
    }

    func test_timeline_fromNoonOn_hasOnlyMidnight() {
        XCTAssertEqual(WidgetCache.timelineDates(from: date(day: 6, hour: 12)), [
            date(day: 6, hour: 12),
            date(day: 7, hour: 0),
        ])
        XCTAssertEqual(WidgetCache.timelineDates(from: date(day: 6, hour: 21, minute: 30)), [
            date(day: 6, hour: 21, minute: 30),
            date(day: 7, hour: 0),
        ])
    }

    func test_timeline_midnightEntry_drawsTheCachedDayAsStale() {
        let midnight = WidgetCache.timelineDates(from: date(day: 6, hour: 20)).last!
        XCTAssertEqual(doneDay().asOf(midnight), .empty)
        XCTAssertEqual(doneDay().dot(at: midnight), .neutral)
    }

    // MARK: - App Group round trip

    func test_saveThenLoad_roundTrips() {
        let cache = doneDay()
        cache.save(to: defaults)
        XCTAssertEqual(WidgetCache.load(from: defaults), cache)
    }

    func test_save_clearsWhatTheNewDayDoesntHave() {
        doneDay().save(to: defaults)
        let noPlan = WidgetCache(target: target(computedAt: date(day: 7, hour: 7)), voiceLine: "Run 8 km.")
        noPlan.save(to: defaults)

        let loaded = WidgetCache.load(from: defaults)
        XCTAssertEqual(loaded, noPlan)
        XCTAssertNil(loaded.planSummary)
        XCTAssertFalse(loaded.runCompletedToday)
        XCTAssertFalse(loaded.planCompletedToday)
    }

    func test_save_keepsADayComputedLater() {
        // A slower refresh that computed its day first must not overwrite
        // the one that computed later and finished first.
        let later = WidgetCache(target: target(computedAt: date(day: 7, hour: 9)), voiceLine: "Run 8 km.",
                                runCompletedToday: true)
        let earlier = WidgetCache(target: target(computedAt: date(day: 7, hour: 8)), voiceLine: "Run 8 km.")
        XCTAssertTrue(later.save(to: defaults, now: date(day: 7, hour: 9, minute: 1)))
        XCTAssertFalse(earlier.save(to: defaults, now: date(day: 7, hour: 9, minute: 1)))
        XCTAssertEqual(WidgetCache.load(from: defaults), later)
    }

    func test_save_aStoredDayFromTheFuture_doesntBlockWrites() {
        // The clock was set back: a day stamped after now isn't "later".
        let future = WidgetCache(target: target(computedAt: date(day: 9, hour: 9)), voiceLine: "Run 8 km.")
        let current = WidgetCache(target: target(computedAt: date(day: 7, hour: 9)), voiceLine: "Run 6 km.")
        future.save(to: defaults, now: date(day: 9, hour: 9))
        XCTAssertTrue(current.save(to: defaults, now: date(day: 7, hour: 9)))
        XCTAssertEqual(WidgetCache.load(from: defaults), current)
    }

    func test_planStatusInit_takesTheHeadlineAndCompletion() {
        let t = target(computedAt: date(day: 7, hour: 7))
        let race = Workout(kind: .race, distanceMeters: 21_097.5, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        let raceDay = WidgetCache(target: t, voiceLine: "Go.", runCompletedToday: false,
                                  planStatus: PlanDayStatus(workout: race, isCompleted: false))
        XCTAssertEqual(raceDay.planSummary, race.headline)
        XCTAssertFalse(raceDay.planCompletedToday)

        let rest = WidgetCache(target: t, voiceLine: "Rest.", runCompletedToday: false,
                               planStatus: PlanDayStatus(workout: .rest, isCompleted: false))
        XCTAssertTrue(rest.isPlanRestDay)

        let noPlan = WidgetCache(target: t, voiceLine: "Run 8 km.", runCompletedToday: true, planStatus: nil)
        XCTAssertNil(noPlan.planSummary)
        XCTAssertFalse(noPlan.planCompletedToday)
        XCTAssertTrue(noPlan.runCompletedToday)
    }

    func test_load_fromEmptyDefaults_isEmpty() {
        XCTAssertEqual(WidgetCache.load(from: defaults), .empty)
        XCTAssertEqual(WidgetCache.load(from: nil), .empty)
    }

    // MARK: - The plan line

    func test_planLine_byDay() {
        let t = target(computedAt: date(day: 7, hour: 7))
        func line(_ summary: String?, done: Bool = false, strength: String? = nil) -> String? {
            WidgetCache(target: t, voiceLine: "Go.", planSummary: summary,
                        planCompletedToday: done, strengthSummary: strength).planLine
        }
        XCTAssertNil(line(nil))
        XCTAssertEqual(line("Rest"), "Rest day")
        XCTAssertEqual(line("Rest", strength: "Kettlebell · 35 min"), "Strength: Kettlebell · 35 min")
        XCTAssertEqual(line("8.0 km · 5:25–5:45/km"), "Plan: 8.0 km · 5:25–5:45/km")
        XCTAssertEqual(line("8.0 km · 5:25–5:45/km", done: true), "Plan: 8.0 km · 5:25–5:45/km ✓")
        XCTAssertEqual(line("8.0 km · 5:25–5:45/km", strength: "Free weights · 40 min"),
                       "Plan: 8.0 km · 5:25–5:45/km + strength")
    }

    func test_strength_comesFromThePlanStatus_andRoundTrips() {
        let t = target(computedAt: date(day: 7, hour: 7))
        let session = StrengthSession(equipment: .freeWeights, minutes: 40, notes: "Squats 3×8")
        let day = WidgetCache(target: t, voiceLine: "Rest.", runCompletedToday: false,
                              planStatus: PlanDayStatus(workout: .rest, isCompleted: false, strength: session))
        XCTAssertEqual(day.strengthSummary, "Free weights · 40 min")
        XCTAssertTrue(day.isPlanRestDay)
        day.save(to: defaults)
        XCTAssertEqual(WidgetCache.load(from: defaults), day)
        // The next day's write without a session clears it.
        WidgetCache(target: target(computedAt: date(day: 8, hour: 7)), voiceLine: "Run 8 km.").save(to: defaults)
        XCTAssertNil(WidgetCache.load(from: defaults).strengthSummary)
    }

    // MARK: - Strength done from Health

    func test_aStrengthOnlyDay_isPendingUntilTheSessionIsLogged() {
        let t = target(computedAt: date(day: 6, hour: 7))
        let pending = WidgetCache(target: t, voiceLine: "Rest.", planSummary: Workout.rest.summary,
                                  strengthSummary: "Kettlebell · 35 min")
        XCTAssertTrue(pending.isStrengthOnlyDay)
        XCTAssertEqual(pending.dot(at: date(day: 6, hour: 10)), .orange)
        XCTAssertEqual(pending.dot(at: date(day: 6, hour: 18)), .red)
        XCTAssertEqual(pending.planLine, "Strength: Kettlebell · 35 min")

        let done = WidgetCache(target: t, voiceLine: "Rest.", planSummary: Workout.rest.summary,
                               strengthSummary: "Kettlebell · 35 min", strengthCompletedToday: true)
        XCTAssertEqual(done.dot(at: date(day: 6, hour: 18)), .green)
        XCTAssertEqual(done.planLine, "Strength: Kettlebell · 35 min ✓")
        done.save(to: defaults)
        XCTAssertEqual(WidgetCache.load(from: defaults), done)
    }

    func test_aRunDayWithStrength_ticksEachPart() {
        let t = target(computedAt: date(day: 6, hour: 7))
        let day = WidgetCache(target: t, voiceLine: "Go.", planSummary: "8.0 km · 5:25–5:45/km",
                              planCompletedToday: true, strengthSummary: "Kettlebell · 35 min",
                              strengthCompletedToday: true)
        XCTAssertEqual(day.planLine, "Plan: 8.0 km · 5:25–5:45/km ✓ + strength ✓")
        XCTAssertEqual(day.dot(at: date(day: 6, hour: 18)), .green)
        // Without a session, nothing can be ticked.
        XCTAssertFalse(WidgetCache(target: t, strengthCompletedToday: true).strengthCompletedToday)
    }

    func test_aRunOnAStrengthOnlyDay_greensTheDot() {
        let t = target(computedAt: date(day: 6, hour: 7))
        let ranInstead = WidgetCache(target: t, voiceLine: "Rest.", runCompletedToday: true,
                                     planSummary: Workout.rest.summary, strengthSummary: "Kettlebell · 35 min")
        XCTAssertTrue(ranInstead.isPlanDayDone)
        XCTAssertEqual(ranInstead.dot(at: date(day: 6, hour: 18)), .green)
    }
}
