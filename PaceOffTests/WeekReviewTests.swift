// WeekReviewTests.swift
// Covers the week screen behind "Last 7 days": seven days oldest first
// with today last, each day's runs, the plan workout and its mark by the
// reconciler's own completion rule, and the week's totals.

import XCTest
@testable import PaceOff

final class WeekReviewTests: XCTestCase {

    private let cal = Calendar.current

    /// 2026-01-05 is a Monday; dates come from local components, so the
    /// weekday is the same in any time zone.
    private func date(day: Int, hour: Int = 7) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func run(day: Int, km: Double, hour: Int = 7) -> RunRecord {
        let start = date(day: day, hour: hour)
        return RunRecord(startDate: start, endDate: start.addingTimeInterval(1_800),
                         distanceMeters: km * 1000, durationSeconds: 1_800)
    }

    private func workout(_ kind: WorkoutKind, km: Double) -> Workout {
        Workout(kind: kind, distanceMeters: km * 1000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350)
    }

    /// One week from Monday 2026-01-05: Mon rest, Tue easy 8, Wed easy 8,
    /// Thu rest, Fri easy 8, Sat easy 8, Sun long 16.
    private func plan() -> TrainingPlan {
        let kinds: [(WorkoutKind, Double)] = [(.rest, 0), (.easy, 8), (.easy, 8), (.rest, 0), (.easy, 8), (.easy, 8), (.long, 16)]
        let days = zip(Weekday.allCases, kinds).map { weekday, entry in
            TrainingDay(weekday: weekday, workout: entry.0 == .rest ? Workout.rest : workout(entry.0, km: entry.1))
        }
        return TrainingPlan(goal: .tenK, tier: .medium, longRunDay: .sunday,
                            weeks: [TrainingWeek(index: 1, days: days)],
                            vdot: 45, usedBeginnerDefault: false,
                            createdAt: date(day: 5, hour: 6))
    }

    // MARK: - Days

    func test_sevenDays_oldestFirst_todayLast() {
        // Saturday the 10th.
        let week = WeekReview(runs: [], plan: nil, today: date(day: 10, hour: 9))
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.first?.date, cal.startOfDay(for: date(day: 4)))
        XCTAssertEqual(week.days.last?.date, cal.startOfDay(for: date(day: 10)))
        XCTAssertEqual(week.days.map(\.isToday), [false, false, false, false, false, false, true])
    }

    func test_runsLandOnTheirDay_andOlderOnesAreLeftOut() {
        let runs = [run(day: 2, km: 10), run(day: 6, km: 5), run(day: 6, km: 3, hour: 18), run(day: 9, km: 8)]
        let week = WeekReview(runs: runs, plan: nil, today: date(day: 10, hour: 9))
        let tuesday = week.days.first { cal.isDate($0.date, inSameDayAs: date(day: 6)) }
        XCTAssertEqual(tuesday?.runs.map(\.distanceKm), [5, 3], "Earliest first")
        XCTAssertEqual(tuesday?.distanceKm ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(week.totalKm, 16, accuracy: 0.001)
        XCTAssertEqual(week.runCount, 3)
        XCTAssertFalse(week.hasPlan)
        XCTAssertTrue(week.days.allSatisfy { $0.plan == nil && $0.planMark == nil })
    }

    func test_streak_matchesTodaysCard() {
        let runs = [run(day: 8, km: 5), run(day: 9, km: 5)]
        let today = date(day: 10, hour: 9)
        XCTAssertEqual(WeekReview(runs: runs, plan: nil, today: today).streak,
                       RunStreak.current(runs: runs, today: today))
    }

    // MARK: - Against the plan

    func test_planMarks_doneMissedPendingRest() {
        // Saturday the 10th, 09:00. Tue ran 8 (done), Wed ran 5 of 8 (missed,
        // under 85%), Fri ran 7 of 8 (done, over 85%), Sat not yet run (pending).
        let runs = [run(day: 6, km: 8), run(day: 7, km: 5), run(day: 9, km: 7)]
        let week = WeekReview(runs: runs, plan: plan(), today: date(day: 10, hour: 9))
        let marks = week.days.map(\.planMark)
        // Days: Sun 4 (before the plan), Mon 5 rest, Tue 6, Wed 7, Thu 8 rest, Fri 9, Sat 10.
        XCTAssertEqual(marks, [nil, .rest, .done, .missed, .rest, .done, .pending])
        XCTAssertTrue(week.hasPlan)
        XCTAssertEqual(week.plannedSessions, 4)
        XCTAssertEqual(week.completedSessions, 2)
        XCTAssertEqual(week.plannedKm, 32, accuracy: 0.001)
    }

    func test_planStatus_isTheReconcilersOwn() {
        let runs = [run(day: 6, km: 8), run(day: 7, km: 5)]
        let p = plan()
        let week = WeekReview(runs: runs, plan: p, today: date(day: 10, hour: 9))
        for day in week.days where day.plan != nil {
            let expected = TrainingPlanReconciler().todayStatus(
                plan: p, runs: runs, today: cal.date(byAdding: .hour, value: 12, to: day.date)!
            )
            XCTAssertEqual(day.plan, expected, "\(day.date)")
        }
    }

    func test_todayDone_isMarkedDone_notPending() {
        let week = WeekReview(runs: [run(day: 10, km: 8)], plan: plan(), today: date(day: 10, hour: 9))
        XCTAssertEqual(week.days.last?.planMark, .done)
    }
}
