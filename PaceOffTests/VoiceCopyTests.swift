// VoiceCopyTests.swift
// Covers which voice line a day gets: a run yesterday is never a skip, the
// engine's restart and recovery tones win over skip naming, the streak day
// number is right, a run today stops the pushing, and every line keeps to
// the PRD §8.1 word limits. Also covers RunStreak, which the streak lines
// count with.

import XCTest
@testable import PaceOff

final class VoiceCopyTests: XCTestCase {

    private let cal = Calendar.current
    private let voice = VoiceCopy()

    private func target(gap: Int,
                        tone: Tone = .neutral,
                        km: Double = 6,
                        vo2Slope: Double? = nil,
                        fatigue: Bool = false) -> RunTarget {
        RunTarget(
            distanceMeters: km * 1000,
            tone: tone,
            daysSinceLastRun: gap,
            vo2MaxSlope: vo2Slope,
            baselineMeters: 5_000,
            ceilingClamped: false,
            fatigueGuardActive: fatigue
        )
    }

    /// 2026-01-07 is a Wednesday; built from local components so the day is
    /// the same in any timezone.
    private func date(day: Int, hour: Int = 7) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func run(day: Int, km: Double = 5) -> RunRecord {
        let start = date(day: day)
        return RunRecord(startDate: start, endDate: start.addingTimeInterval(1_800),
                         distanceMeters: km * 1000, durationSeconds: 1_800)
    }

    // MARK: - Ran yesterday is not a skip

    func test_ranYesterday_isAStreakLine_notASkip() {
        // The engine nudges a one-day gap to "firm"; the copy still says done.
        let state = VoiceState(target: target(gap: 1, tone: .firm), yesterday: run(day: 6), currentStreak: 3)
        XCTAssertEqual(state, .streakDay1(yesterdayKm: 5, todayKm: 6))
        XCTAssertEqual(voice.notification(for: state), "Yesterday: done. Today: 6 km.")
        XCTAssertFalse(voice.todayCard(for: state).lowercased().contains("skip"))
    }

    func test_ranYesterday_withoutTheRecord_isOnTrack() {
        let state = VoiceState(target: target(gap: 1), yesterday: nil, currentStreak: 1)
        XCTAssertEqual(state, .onTrack(todayKm: 6))
    }

    func test_oneMissedDay_namesTheSkip() {
        let state = VoiceState(target: target(gap: 2, tone: .aggressive), yesterday: run(day: 5), currentStreak: 0)
        XCTAssertEqual(state, .skipOneDay(todayKm: 6))
        XCTAssertEqual(voice.notification(for: state), "You skipped yesterday. Run 6 km.")
    }

    func test_twoMissedDays_namesBoth() {
        let state = VoiceState(target: target(gap: 3, tone: .aggressive), yesterday: run(day: 4), currentStreak: 0)
        XCTAssertEqual(state, .skipTwoDays(todayKm: 6))
    }

    func test_longGap_isARestart() {
        let state = VoiceState(target: target(gap: 6), yesterday: run(day: 1), currentStreak: 0)
        XCTAssertEqual(state, .skipThreePlusDays(todayKm: 6))
    }

    // MARK: - The engine's tone wins

    func test_restartTone_getsRestartCopy_whateverTheGap() {
        let state = VoiceState(target: target(gap: 3, tone: .restart, km: 3), yesterday: run(day: 4), currentStreak: 0)
        XCTAssertEqual(state, .skipThreePlusDays(todayKm: 3))
        XCTAssertEqual(voice.notification(for: state), "Restart. 3 km. Now.")
    }

    func test_recoveryTone_getsRestCopy_neverMandatory() {
        // A red readiness day after a skip: the engine says recovery.
        let state = VoiceState(target: target(gap: 2, tone: .recovery, km: 3), yesterday: run(day: 5), currentStreak: 0)
        XCTAssertEqual(state, .recovery(todayKm: 3))
        let card = voice.todayCard(for: state)
        XCTAssertTrue(card.hasPrefix("Recovery day."))
        XCTAssertFalse(card.lowercased().contains("mandatory"))
        XCTAssertFalse(voice.notification(for: state).lowercased().contains("skip"))
    }

    func test_recoveryAfterALongRunYesterday() {
        let state = VoiceState(target: target(gap: 1, tone: .recovery, km: 3), yesterday: run(day: 6, km: 12), currentStreak: 4)
        XCTAssertEqual(state, .recovery(todayKm: 3))
    }

    func test_fatigueGuard_beatsTheStreakLine() {
        let state = VoiceState(target: target(gap: 1, fatigue: true), yesterday: run(day: 6), currentStreak: 3)
        XCTAssertEqual(state, .fatigueGuard)
    }

    func test_vo2Declining_withoutASkip() {
        let state = VoiceState(target: target(gap: 1, tone: .aggressive, vo2Slope: -0.1), yesterday: run(day: 6), currentStreak: 3)
        XCTAssertEqual(state, .vo2MaxDeclining(deltaPerMonth: 0.4, todayKm: 6))
    }

    // MARK: - Streak day number

    func test_streakDayNumber_countsTodaysRunOnce() {
        // Seven days through yesterday: today's run is day 8.
        let before = VoiceState(target: target(gap: 1), yesterday: run(day: 6), currentStreak: 7)
        XCTAssertEqual(before, .streakDay7Plus(streakDays: 8))
        XCTAssertEqual(voice.notification(for: before), "Day 8. Don't waste it.")

        // Seven days including today: it's day 7, not 8.
        let after = VoiceState(target: target(gap: 0), yesterday: run(day: 6), currentStreak: 7)
        XCTAssertEqual(after, .ranToday(streakDays: 7))
        XCTAssertEqual(voice.todayCard(for: after), "Run logged. 7 days straight. Recover and go again tomorrow.")
    }

    // MARK: - Ran today

    func test_ranToday_stopsPushing() {
        let state = VoiceState(target: target(gap: 0, tone: .firm), yesterday: nil, currentStreak: 1)
        XCTAssertEqual(state, .ranToday(streakDays: 1))
        XCTAssertEqual(voice.notification(for: state), "Run logged. Recover and go again tomorrow.")
        XCTAssertEqual(voice.todayCard(for: state), "Run logged. Recover and go again tomorrow.")
    }

    // MARK: - PRD §8.1 word limits

    func test_everyLine_keepsToTheWordLimits() {
        let states: [VoiceState] = [
            .streakDay1(yesterdayKm: 4.8, todayKm: 6),
            .streakDay7Plus(streakDays: 12),
            .onTrack(todayKm: 6),
            .skipOneDay(todayKm: 6),
            .skipTwoDays(todayKm: 6),
            .skipThreePlusDays(todayKm: 3),
            .vo2MaxDeclining(deltaPerMonth: 0.4, todayKm: 6),
            .recovery(todayKm: 3),
            .ranToday(streakDays: 1),
            .ranToday(streakDays: 14),
            .runCompletedHitTarget(tomorrowKm: 6),
            .runCompletedShortfall(actualKm: 4.5, targetKm: 6),
            .fatigueGuard,
        ]
        for state in states {
            let notification = voice.notification(for: state)
            let card = voice.todayCard(for: state)
            XCTAssertLessThanOrEqual(words(notification), 8, "notification: \(notification)")
            XCTAssertLessThanOrEqual(words(card), 12, "today card: \(card)")
        }
    }

    private func words(_ line: String) -> Int {
        line.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: - RunStreak

    func test_streak_includesToday_onceTodayHasARun() {
        let runs = [run(day: 5), run(day: 6), run(day: 7)]
        XCTAssertEqual(RunStreak.current(runs: runs, today: date(day: 7, hour: 20), calendar: cal), 3)
    }

    func test_streak_runsThroughYesterday_untilTodaysRun() {
        let runs = [run(day: 5), run(day: 6)]
        XCTAssertEqual(RunStreak.current(runs: runs, today: date(day: 7, hour: 6), calendar: cal), 2)
    }

    func test_streak_isBroken_afterAMissedDay() {
        let runs = [run(day: 4), run(day: 5)]
        XCTAssertEqual(RunStreak.current(runs: runs, today: date(day: 7), calendar: cal), 0)
    }

    func test_streak_stopsAtTheFirstGap_andCountsDaysNotRuns() {
        // Two runs on the 6th count once; the 4th is behind a gap.
        let runs = [run(day: 4), run(day: 6), run(day: 6, km: 3), run(day: 7)]
        XCTAssertEqual(RunStreak.current(runs: runs, today: date(day: 7, hour: 20), calendar: cal), 2)
    }
}
