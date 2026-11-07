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

    func test_load_fromEmptyDefaults_isEmpty() {
        XCTAssertEqual(WidgetCache.load(from: defaults), .empty)
        XCTAssertEqual(WidgetCache.load(from: nil), .empty)
    }
}
