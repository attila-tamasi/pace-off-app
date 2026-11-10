// StrengthPlanTests.swift
// Strength sessions in the plan: how many a week, which days they take,
// what they hold, the taper, and plans saved before strength existed.

import XCTest
@testable import PaceOff

final class StrengthPlanTests: XCTestCase {

    private let generator = TrainingPlanGenerator()
    private let today = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(_ goal: RunningGoal, _ tier: PlanTier,
                      longDay: Weekday = .sunday,
                      kit: StrengthEquipment? = .kettlebell,
                      raceWeeksOut: Int? = nil) -> TrainingPlan {
        generator.generate(TrainingPlanInputs(
            goal: goal, tier: tier, longRunDay: longDay, vo2Max: 49.2,
            goalDate: raceWeeksOut.map { today.addingTimeInterval(Double($0) * 7 * 86_400) },
            crossTraining: kit, today: today
        ))
    }

    /// A week's days, Monday first.
    private func days(_ week: TrainingWeek) -> [TrainingDay] {
        week.days.sorted { $0.weekday.rawValue < $1.weekday.rawValue }
    }

    private func strengthSlots(_ week: TrainingWeek) -> [Int] {
        days(week).enumerated().filter { $0.element.strength != nil }.map(\.offset)
    }

    // MARK: - None by default

    func test_aRunningOnlyPlan_hasNoStrength() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                let p = plan(goal, tier, kit: nil)
                XCTAssertNil(p.crossTraining)
                XCTAssertTrue(p.weeks.flatMap(\.days).allSatisfy { $0.strength == nil }, "\(goal) \(tier)")
            }
        }
    }

    func test_strength_leavesTheRunsAsTheyWere() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                let runs = plan(goal, tier, kit: nil).weeks.flatMap(\.days).map(\.workout)
                let withStrength = plan(goal, tier, kit: .freeWeights).weeks.flatMap(\.days).map(\.workout)
                XCTAssertEqual(withStrength, runs, "\(goal) \(tier)")
            }
        }
    }

    // MARK: - How many, and the taper

    func test_sessionsAWeek_byTier_easingOffInTheTaper() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for longDay in [Weekday.sunday, .saturday, .wednesday, .monday] {
                    let p = plan(goal, tier, longDay: longDay)
                    for week in p.weeks {
                        let weeksToGo = p.weekCount - week.index
                        let expected = weeksToGo == 0 ? 0 : weeksToGo == 1 ? 1 : (tier == .easy ? 1 : 2)
                        XCTAssertEqual(strengthSlots(week).count, expected,
                                       "\(goal) \(tier), long run \(longDay), week \(week.index)")
                    }
                }
            }
        }
    }

    func test_raceWeek_hasNoStrength_whateverTheRaceDate() {
        for goal in RunningGoal.allCases {
            for weeksOut in 3...20 {
                let p = plan(goal, .aggressive, raceWeeksOut: weeksOut)
                XCTAssertEqual(p.weeks.last.map(strengthSlots)?.count, 0, "\(goal), race \(weeksOut) weeks out")
                XCTAssertTrue(p.weeks.flatMap(\.days).contains { $0.strength != nil }, "\(goal), race \(weeksOut) weeks out")
            }
        }
    }

    // MARK: - Which days

    func test_strengthDays_keepTheRules() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for longDay in Weekday.allCases {
                    for week in plan(goal, tier, longDay: longDay).weeks {
                        let label = "\(goal) \(tier), long run \(longDay), week \(week.index)"
                        let d = days(week)
                        let slots = strengthSlots(week)
                        for slot in slots {
                            let kind = d[slot].workout.kind
                            let next = d[(slot + 1) % 7].workout.kind
                            XCTAssertNotEqual(kind, .long, "\(label): not on the long run")
                            XCTAssertNotEqual(next, .long, "\(label): not the day before the long run")
                            XCTAssertFalse(next.isQuality, "\(label): not the day before a quality session")
                            XCTAssertFalse(slots.contains((slot + 1) % 7), "\(label): never two days in a row")
                        }
                        XCTAssertTrue(d.contains { $0.workout.kind == .rest && $0.strength == nil },
                                      "\(label): a full rest day stays")
                    }
                }
            }
        }
    }

    func test_sessionsTakeRestDays_andTheAggressiveSecondFollowsAQualitySession() {
        for longDay in Weekday.allCases {
            for tier in [PlanTier.easy, .medium] {
                let week = plan(.halfMarathon, tier, longDay: longDay).weeks[2]
                for slot in strengthSlots(week) {
                    XCTAssertEqual(days(week)[slot].workout.kind, .rest, "\(tier), long run \(longDay)")
                }
            }
            // The Aggressive week's rest and easy days all sit before a
            // quality session or the long run, but one: one session there,
            // the other after a quality session.
            let week = plan(.halfMarathon, .aggressive, longDay: longDay).weeks[2]
            let kinds = strengthSlots(week).map { days(week)[$0].workout.kind }
            XCTAssertEqual(kinds.filter { $0 == .rest }.count, 1, "long run \(longDay)")
            XCTAssertEqual(kinds.filter(\.isQuality).count, 1, "long run \(longDay)")
        }
    }

    func test_strengthDays_withTheLongRunOnSunday() {
        // Easy: Wednesday. Medium: Wednesday and Friday. Aggressive:
        // Tuesday's quality session and Friday.
        func slots(_ week: [WorkoutKind], _ count: Int) -> [Int] {
            TrainingPlanGenerator.strengthDays(in: week, longRunSlot: 6, count: count).sorted()
        }
        XCTAssertEqual(slots([.rest, .easy, .rest, .easy, .rest, .rest, .long], 1), [2])
        XCTAssertEqual(slots([.rest, .threshold, .rest, .easy, .rest, .easy, .long], 2), [2, 4])
        XCTAssertEqual(slots([.rest, .threshold, .easy, .interval, .rest, .easy, .long], 2), [1, 4])
        XCTAssertEqual(slots([.rest, .threshold, .easy, .interval, .rest, .easy, .long], 0), [])
    }

    func test_aWeekWithoutRoom_getsFewerSessions_ratherThanBreakingTheRules() {
        // A third Medium session has nowhere to go: Monday is before the
        // quality session, Thursday and Tuesday next to a session, Saturday
        // before the long run.
        let medium: [WorkoutKind] = [.rest, .threshold, .rest, .easy, .rest, .easy, .long]
        XCTAssertEqual(TrainingPlanGenerator.strengthDays(in: medium, longRunSlot: 6, count: 3).sorted(), [2, 4])
        // Every day before a quality session or the long run: none.
        let packed: [WorkoutKind] = [.threshold, .interval, .threshold, .interval, .threshold, .interval, .long]
        XCTAssertEqual(TrainingPlanGenerator.strengthDays(in: packed, longRunSlot: 6, count: 2), [])
    }

    // MARK: - What a session holds

    func test_sessions_byKitTierAndTaper() {
        let kettlebell = plan(.marathon, .medium, kit: .kettlebell)
        let build = kettlebell.weeks[5].days.compactMap(\.strength)
        XCTAssertEqual(build.first?.equipment, .kettlebell)
        XCTAssertEqual(build.first?.minutes, 35)
        XCTAssertEqual(build.first?.notes,
                       "Swings 3×15 · goblet squats 3×10 · single-leg deadlifts 3×8 each · "
                       + "reverse lunges 3×8 each · presses 3×8 each · suitcase carries 3×30 m each")
        XCTAssertEqual(build.first?.summary, "Kettlebell · 35 min")

        let weights = plan(.marathon, .aggressive, kit: .freeWeights)
        let heavy = weights.weeks[5].days.compactMap(\.strength).first
        XCTAssertEqual(heavy?.minutes, 40)
        XCTAssertEqual(heavy?.notes,
                       "Squats 3×8 · Romanian deadlifts 3×8 · split squats 3×8 each · step-ups 3×10 each · "
                       + "calf raises 3×15 · rows 3×10 · plank 3×40 s")

        let easy = plan(.marathon, .easy, kit: .freeWeights).weeks[5].days.compactMap(\.strength).first
        XCTAssertEqual(easy?.minutes, 30)
        XCTAssertTrue(easy?.notes.hasPrefix("Squats 2×8") ?? false)

        // Mid-taper and the week before the race: two sets, shorter.
        let n = weights.weekCount
        XCTAssertEqual(weights.weeks[n - 3].days.compactMap(\.strength).first?.minutes, 25)
        XCTAssertEqual(weights.weeks[n - 2].days.compactMap(\.strength).first?.minutes, 20)
        XCTAssertTrue(weights.weeks[n - 2].days.compactMap(\.strength).first?.notes.hasPrefix("Squats 2×8") ?? false)
    }

    // MARK: - Saved plans

    func test_aPlanSavedBeforeStrength_decodesAsRunningOnly() throws {
        let p = plan(.tenK, .medium, kit: nil)
        let json = String(data: try JSONEncoder().encode(p), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("strength"))
        XCTAssertFalse(json.contains("crossTraining"))
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: Data(json.utf8)), p)
    }

    func test_aPlanWithStrength_roundTrips() throws {
        let p = plan(.halfMarathon, .aggressive, kit: .freeWeights)
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(p)), p)
    }

    func test_retunes_rebuilds_andNoteRefreshes_keepTheStrength() {
        let reconciler = TrainingPlanReconciler()
        // A retune re-paces the runs only.
        let p = generator.generate(TrainingPlanInputs(goal: .marathon, tier: .medium, vo2Max: 45,
                                                      crossTraining: .kettlebell, today: today))
        let retuned = reconciler.retunedPlan(p, toVDOT: 50, today: today)
        XCTAssertNotNil(retuned)
        XCTAssertEqual(retuned?.crossTraining, .kettlebell)
        XCTAssertEqual(retuned?.weeks.flatMap(\.days).map(\.strength), p.weeks.flatMap(\.days).map(\.strength))
        // A plan rebuilt before its start keeps its kit.
        let later = plan(.marathon, .medium, kit: .freeWeights, raceWeeksOut: 26)
        let rebuilt = reconciler.rebuiltBeforeStart(later, vo2Max: 55, personalBest: nil,
                                                    recentLongestRunMeters: nil, today: today)
        XCTAssertEqual(rebuilt?.crossTraining, .freeWeights)
        XCTAssertTrue(rebuilt?.weeks.flatMap(\.days).contains { $0.strength?.equipment == .freeWeights } ?? false)
        // Recomputing session notes on load leaves it as it is.
        XCTAssertEqual(generator.withSessionNotes(p), p)
    }
}
