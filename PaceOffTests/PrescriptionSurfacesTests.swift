// PrescriptionSurfacesTests.swift
// The day's one prescription reaches every surface: the voice line, the
// pushes and the widget name the same distance, a plan rest day reads as
// rest, and readiness changes the plan's run rather than adding a number.

import XCTest

final class PrescriptionSurfacesTests: XCTestCase {

    private let cal = Calendar.current
    private let easyBand: ClosedRange<Double> = 330...350

    private func date(hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: hour))!
    }

    private func target(km: Double, daysSinceLastRun: Int = 1) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .neutral, daysSinceLastRun: daysSinceLastRun,
                  vo2MaxSlope: nil, baselineMeters: km * 1000, ceilingClamped: false,
                  fatigueGuardActive: false, capMeters: km * 1400, computedAt: date(hour: 7))
    }

    private func status(_ workout: Workout, strength: StrengthSession? = nil) -> PlanDayStatus {
        PlanDayStatus(workout: workout, isCompleted: false, strength: strength)
    }

    private let threshold = Workout(kind: .threshold, distanceMeters: 10_000,
                                    paceMinSecPerKm: 280, paceMaxSecPerKm: 295)

    private func prescription(_ workout: Workout, readiness: ReadinessLevel?, ranMeters: Double = 0,
                              strength: StrengthSession? = nil) -> DayPrescription {
        DayPrescription.make(planStatus: status(workout, strength: strength), readiness: readiness,
                             target: target(km: 6), easyPace: easyBand,
                             longestRunTodayMeters: ranMeters)!
    }

    // MARK: - Summary and note

    func testSummaryOfAPlanRunAsWritten() {
        XCTAssertEqual(prescription(threshold, readiness: .green).summary, "10.0 km · 4:40–4:55/km")
        XCTAssertNil(prescription(threshold, readiness: .green).adjustmentNote)
    }

    func testSummaryOfAnEasedRunNamesTheEasyBand() {
        let day = prescription(threshold, readiness: .yellow)
        XCTAssertEqual(day.summary, "10.0 km · 5:30–5:50/km")
        XCTAssertEqual(day.adjustmentNote, "Readiness is yellow, so today's threshold runs easy")
    }

    func testRedSummaryNamesOnlyTheCutDistance() {
        let day = prescription(threshold, readiness: .red)
        XCTAssertEqual(day.summary, "6.0 km · 5:30–5:50/km")
        XCTAssertEqual(day.distanceText, "6")
        XCTAssertEqual(day.adjustmentNote, "Readiness is red, so today's run is cut to an easy one")
    }

    func testDailyTargetSummary() {
        let day = DayPrescription.make(planStatus: nil, readiness: nil, target: target(km: 5.3), easyPace: nil)!
        XCTAssertEqual(day.summary, "6 km")
        XCTAssertEqual(day.distanceText, "6")
    }

    func testIsDoneFollowsTheLongestRunToday() {
        XCTAssertFalse(prescription(threshold, readiness: .red, ranMeters: 5_000).isDone)
        XCTAssertTrue(prescription(threshold, readiness: .red, ranMeters: 5_100).isDone)
    }

    func testLongestRunCountsOnlyToday() {
        let today = date(hour: 18)
        let runs = [
            RunRecord(startDate: date(hour: 7), endDate: date(hour: 8), distanceMeters: 7_000, durationSeconds: 3_600),
            RunRecord(startDate: date(hour: 7).addingTimeInterval(-86_400), endDate: date(hour: 8).addingTimeInterval(-86_400),
                      distanceMeters: 20_000, durationSeconds: 7_200),
        ]
        XCTAssertEqual(DayPrescription.longestRun(on: today, in: runs, calendar: cal), 7_000)
    }

    // MARK: - Voice line

    func testVoiceLineNamesThePrescribedDistance() {
        let state = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 0,
                               planStatus: status(threshold), prescription: prescription(threshold, readiness: .red))
        XCTAssertEqual(state, .onTrack(todayKm: 6))
        let green = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 0,
                               planStatus: status(threshold), prescription: prescription(threshold, readiness: .green))
        XCTAssertEqual(green, .onTrack(todayKm: 10))
    }

    func testVoiceLineOnAPlanRestDayIsRest() {
        let rest = prescription(.rest, readiness: .green)
        let state = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 0,
                               planStatus: status(.rest), prescription: rest)
        XCTAssertEqual(state, .planRestDay(strength: nil))
        XCTAssertFalse(VoiceCopy().todayCard(for: state).contains("km"))
    }

    func testVoiceLineOnAStrengthDayNamesTheSession() {
        let session = StrengthSession(equipment: .kettlebell, minutes: 35, notes: "Swings")
        let day = prescription(.rest, readiness: .green, strength: session)
        let state = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 0,
                               planStatus: status(.rest, strength: session), prescription: day)
        XCTAssertEqual(state, .planRestDay(strength: "Kettlebell · 35 min"))
    }

    func testVoiceLineOnRaceDay() {
        let race = Workout(kind: .race, distanceMeters: 21_100, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        let state = VoiceState(target: target(km: 6), yesterday: nil, currentStreak: 0,
                               planStatus: status(race), prescription: prescription(race, readiness: .red))
        XCTAssertEqual(state, .raceDay(km: 21.1))
    }

    func testRunTodayThatMeetsTheCutDistanceClosesTheDay() {
        let day = prescription(threshold, readiness: .red, ranMeters: 6_000)
        let state = VoiceState(target: target(km: 6, daysSinceLastRun: 0), yesterday: nil, currentStreak: 3,
                               planStatus: status(threshold), prescription: day)
        XCTAssertEqual(state, .ranToday(streakDays: 3))
    }

    func testShortRunTodayLeavesThePlanStillToDo() {
        let day = prescription(threshold, readiness: .green, ranMeters: 4_000)
        let state = VoiceState(target: target(km: 6, daysSinceLastRun: 0), yesterday: nil, currentStreak: 3,
                               planStatus: status(threshold), prescription: day)
        XCTAssertEqual(state, .planStillToDo)
    }

    // MARK: - Pushes

    private func morningBody(_ day: DayPrescription, workout: Workout, ran: [RunRecord] = []) -> String? {
        DailyPushPlanner(calendar: cal).pushes(for: DailyPushPlanner.Inputs(
            now: date(hour: 6), body: "On track. 6 km today.", runs: ran, plan: nil,
            planStatus: status(workout), prescription: day
        )).first { $0.slot == .morning }?.body
    }

    func testPushNamesOnlyThePlanRun() {
        XCTAssertEqual(morningBody(prescription(threshold, readiness: .green), workout: threshold),
                       "Today's plan: 10.0 km · 4:40–4:55/km.")
    }

    func testPushOnARedDayNamesTheCutRunAndWhy() {
        XCTAssertEqual(morningBody(prescription(threshold, readiness: .red), workout: threshold),
                       "Today's plan: 6.0 km · 5:30–5:50/km. Readiness is red, so today's run is cut to an easy one.")
    }

    func testCutRunDoneSendsNoReminders() {
        let ran = [RunRecord(startDate: date(hour: 7), endDate: date(hour: 8), distanceMeters: 6_000, durationSeconds: 2_400)]
        let day = prescription(threshold, readiness: .red, ranMeters: 6_000)
        let pushes = DailyPushPlanner(calendar: cal).pushes(for: DailyPushPlanner.Inputs(
            now: date(hour: 9), body: "x", runs: ran, plan: nil, planStatus: status(threshold), prescription: day
        ))
        XCTAssertEqual(pushes.map(\.slot), [.nextMorning])
    }

    // MARK: - Widget

    func testWidgetShowsThePrescribedDistanceAndPlanLine() {
        let cache = WidgetCache(target: target(km: 6), voiceLine: "x", runCompletedToday: false,
                                planStatus: status(threshold), prescription: prescription(threshold, readiness: .red))
        XCTAssertEqual(cache.distanceText, "6")
        XCTAssertEqual(cache.planLine, "Plan: 6.0 km · 5:30–5:50/km")
    }

    func testWidgetShowsNoDistanceOnARestDay() {
        let cache = WidgetCache(target: target(km: 6), voiceLine: "x", runCompletedToday: false,
                                planStatus: status(.rest), prescription: prescription(.rest, readiness: .green))
        XCTAssertNil(cache.distanceText)
        XCTAssertEqual(cache.planLine, "Rest day")
    }

    func testWidgetCountsTheCutRunAsDone() {
        let cache = WidgetCache(target: target(km: 6), voiceLine: "x", runCompletedToday: true,
                                planStatus: status(threshold),
                                prescription: prescription(threshold, readiness: .red, ranMeters: 6_000))
        XCTAssertTrue(cache.planCompletedToday)
    }

    func testWidgetWithoutAPrescriptionFallsBackToTheTarget() {
        let cache = WidgetCache(target: target(km: 5.3), voiceLine: "x", runCompletedToday: false, planStatus: nil)
        XCTAssertEqual(cache.distanceText, "6")
    }

    func testWidgetDistanceSurvivesSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "PrescriptionSurfacesTests")!
        defaults.removePersistentDomain(forName: "PrescriptionSurfacesTests")
        let cache = WidgetCache(target: target(km: 6), voiceLine: "x", runCompletedToday: false,
                                planStatus: status(threshold), prescription: prescription(threshold, readiness: .red))
        XCTAssertTrue(cache.save(to: defaults, now: date(hour: 8)))
        XCTAssertEqual(WidgetCache.load(from: defaults).dayDistanceKm, 6)
        defaults.removePersistentDomain(forName: "PrescriptionSurfacesTests")
    }
}
