// TrainingPlanGeneratorTests.swift
// Covers VDOT math, plan structure (week count, runs/week per tier, long
// run on the requested day), pace plausibility, and beginner fallback.
// We don't try to match Daniels' published tables to the second — small
// arithmetic drift between his lookup tables and the closed-form
// computation we use is expected. We assert paces fall in coach-tolerable
// bands instead.

import XCTest
@testable import PaceOff

final class TrainingPlanGeneratorTests: XCTestCase {

    private let generator = TrainingPlanGenerator()
    private let vdot = VDOTCalculator()

    // MARK: - VDOT math sanity

    func test_vdot_5kAt20Minutes_lookupTableAnchor() {
        // Daniels' published table: 20:00 5K ≈ VDOT 49–50.
        let v = vdot.vdot(fromRaceDistanceMeters: 5_000, timeSeconds: 1_200)
        XCTAssertNotNil(v)
        XCTAssertEqual(v!, 49.5, accuracy: 1.0)
    }

    func test_vdot_10kAt45Minutes_lookupTableAnchor() {
        // Daniels: 45:00 10K ≈ VDOT 46.
        let v = vdot.vdot(fromRaceDistanceMeters: 10_000, timeSeconds: 2_700)
        XCTAssertNotNil(v)
        XCTAssertEqual(v!, 46, accuracy: 1.5)
    }

    func test_pace_easyIsSlowerThanThresholdIsSlowerThanInterval() {
        let v: Double = 50
        let easy = vdot.paceSecPerKm(vdot: v, fractionOfVDOT: TrainingIntensity.easy.fractionOfVDOT)
        let m    = vdot.paceSecPerKm(vdot: v, fractionOfVDOT: TrainingIntensity.marathon.fractionOfVDOT)
        let t    = vdot.paceSecPerKm(vdot: v, fractionOfVDOT: TrainingIntensity.threshold.fractionOfVDOT)
        let i    = vdot.paceSecPerKm(vdot: v, fractionOfVDOT: TrainingIntensity.interval.fractionOfVDOT)
        XCTAssertGreaterThan(easy, m, "easy should be slower than marathon (larger sec/km)")
        XCTAssertGreaterThan(m, t, "marathon should be slower than threshold")
        XCTAssertGreaterThan(t, i, "threshold should be slower than interval")
    }

    func test_pace_thresholdFor50VDOT_isAroundFourMinutesPerKm() {
        // Daniels' table at VDOT 50: T pace ≈ 4:00/km (3:54–4:01 range).
        let p = vdot.paceSecPerKm(vdot: 50,
                                  fractionOfVDOT: TrainingIntensity.threshold.fractionOfVDOT)
        XCTAssertEqual(p, 240, accuracy: 10) // ±10 s/km tolerance
    }

    // MARK: - Plan length

    func test_planLength_byGoal() {
        XCTAssertEqual(generator.planWeeks(for: .fiveK), 8)
        XCTAssertEqual(generator.planWeeks(for: .tenK), 10)
        XCTAssertEqual(generator.planWeeks(for: .halfMarathon), 12)
        XCTAssertEqual(generator.planWeeks(for: .marathon), 16)
    }

    // MARK: - Structural assertions

    private func plan(_ goal: RunningGoal,
                      _ tier: PlanTier,
                      vo2: Double? = 49.2,
                      pb: PersonalBest? = nil,
                      longDay: Weekday = .sunday) -> TrainingPlan {
        generator.generate(
            TrainingPlanInputs(goal: goal,
                               tier: tier,
                               longRunDay: longDay,
                               vo2Max: vo2,
                               personalBest: pb)
        )
    }

    func test_generate_returnsExpectedWeekCount() {
        XCTAssertEqual(plan(.fiveK, .easy).weekCount, 8)
        XCTAssertEqual(plan(.marathon, .aggressive).weekCount, 16)
    }

    func test_generate_eachWeekHasSevenDays() {
        let p = plan(.halfMarathon, .medium)
        for week in p.weeks {
            XCTAssertEqual(week.days.count, 7)
            XCTAssertEqual(Set(week.days.map(\.weekday)).count, 7)
        }
    }

    func test_generate_runsPerWeekMatchesTier() {
        let easy = plan(.tenK, .easy)
        let mid  = plan(.tenK, .medium)
        let agg  = plan(.tenK, .aggressive)
        XCTAssertEqual(easy.weeks[2].runCount, 3)
        XCTAssertEqual(mid.weeks[2].runCount,  4)
        XCTAssertEqual(agg.weeks[2].runCount,  5)
    }

    func test_generate_longRunLandsOnRequestedDay() {
        for day in Weekday.allCases {
            let p = plan(.tenK, .medium, longDay: day)
            for week in p.weeks {
                let longDays = week.days.filter { $0.workout.kind == .long }
                XCTAssertEqual(longDays.count, 1, "Week \(week.index) should have exactly one long run")
                XCTAssertEqual(longDays.first?.weekday, day,
                               "Week \(week.index) long run should be on \(day.displayName)")
            }
        }
    }

    func test_generate_qualitySessionsNotAdjacentToLongRun() {
        for tier in [PlanTier.medium, .aggressive] {
            let p = plan(.halfMarathon, tier, longDay: .sunday)
            for week in p.weeks {
                let longIdx = week.days.firstIndex { $0.workout.kind == .long }!
                let before = (longIdx - 1 + 7) % 7
                let after  = (longIdx + 1) % 7
                XCTAssertFalse(week.days[before].workout.kind.isQuality,
                               "Quality directly before long run, tier=\(tier), week=\(week.index)")
                XCTAssertFalse(week.days[after].workout.kind.isQuality,
                               "Quality directly after long run, tier=\(tier), week=\(week.index)")
            }
        }
    }

    func test_generate_aggressiveHasTwoQualityDaysInBuildWeeks() {
        let p = plan(.marathon, .aggressive)
        // Race week and final taper week reduce quality to one. Pick a
        // mid-plan week where the buildup should be at full structure.
        let week = p.weeks[6]
        let qualityCount = week.days.filter { $0.workout.kind.isQuality }.count
        XCTAssertEqual(qualityCount, 2, "Aggressive plan should have two quality days mid-plan")
    }

    func test_generate_taperReducesVolume() {
        let p = plan(.marathon, .medium)
        let peak = p.weeks[p.weekCount - 3]   // build to peak here
        let raceWeek = p.weeks.last!
        XCTAssertLessThan(raceWeek.totalDistanceKm, peak.totalDistanceKm,
                          "Race week should taper below peak")
    }

    // MARK: - Pace plausibility

    func test_generate_easyPaceIsCoachTolerableForVDOT50() {
        // VDOT 50 easy pace lands around 5:00/km (Daniels table 4:56–5:12).
        let p = plan(.tenK, .medium, vo2: 50)
        let easyDay = p.weeks.first!.days.first { $0.workout.kind == .easy }!
        let mid = (easyDay.workout.paceMinSecPerKm + easyDay.workout.paceMaxSecPerKm) / 2
        XCTAssertEqual(mid, 300, accuracy: 25) // ±25 s/km
    }

    // MARK: - VDOT resolution

    func test_resolveVDOT_prefersVO2MaxWhenPresent() {
        let inputs = TrainingPlanInputs(
            goal: .tenK,
            tier: .medium,
            vo2Max: 52,
            personalBest: PersonalBest(durationSeconds: 3_000, year: 2024) // worse than VO₂ implies
        )
        let (v, fallback) = generator.resolveVDOT(inputs)
        XCTAssertEqual(v, 52, accuracy: 0.001)
        XCTAssertFalse(fallback)
    }

    func test_resolveVDOT_fallsBackToPBWhenVO2Missing() {
        let pb = PersonalBest(durationSeconds: 2_700, year: 2024) // 45:00 10K
        let inputs = TrainingPlanInputs(
            goal: .tenK,
            tier: .medium,
            vo2Max: nil,
            personalBest: pb
        )
        let (v, fallback) = generator.resolveVDOT(inputs)
        XCTAssertGreaterThanOrEqual(v, 40)
        XCTAssertLessThanOrEqual(v, 55)
        XCTAssertFalse(fallback)
    }

    func test_resolveVDOT_usesBeginnerFallbackWhenNothingAvailable() {
        let inputs = TrainingPlanInputs(
            goal: .tenK,
            tier: .medium,
            vo2Max: nil,
            personalBest: nil
        )
        let (v, fallback) = generator.resolveVDOT(inputs)
        XCTAssertEqual(v, TrainingPlanGenerator.beginnerVDOTFallback, accuracy: 0.001)
        XCTAssertTrue(fallback)
    }

    func test_generate_flagsBeginnerDefaultWhenUsed() {
        let p = generator.generate(
            TrainingPlanInputs(goal: .fiveK, tier: .easy, vo2Max: nil, personalBest: nil)
        )
        XCTAssertTrue(p.usedBeginnerDefault)
    }

    // MARK: - Workout.summary formatting

    func test_workout_summary_restIsRest() {
        let r = Workout(kind: .rest, distanceMeters: 0, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        XCTAssertEqual(r.summary, "Rest")
    }

    func test_workout_summary_includesPaceRange() {
        let w = Workout(kind: .easy, distanceMeters: 8_000,
                        paceMinSecPerKm: 300, paceMaxSecPerKm: 330)
        XCTAssertTrue(w.summary.contains("8.0 km"))
        XCTAssertTrue(w.summary.contains("5:00"))
        XCTAssertTrue(w.summary.contains("5:30"))
    }
}
