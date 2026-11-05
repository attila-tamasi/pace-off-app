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

    func test_pace_thresholdFor50VDOT_matchesDanielsTable() {
        // Daniels' published table at VDOT 50: T pace ≈ 4:15/km (255 s/km).
        // (4:00/km would be the T pace of a ~VDOT 55 runner.)
        let p = vdot.paceSecPerKm(vdot: 50,
                                  fractionOfVDOT: TrainingIntensity.threshold.fractionOfVDOT)
        XCTAssertEqual(p, 255, accuracy: 10) // ±10 s/km tolerance
    }

    // MARK: - Plan length

    func test_planLength_byGoal() {
        XCTAssertEqual(generator.planWeeks(for: .fiveK), 8)
        XCTAssertEqual(generator.planWeeks(for: .tenK), 10)
        XCTAssertEqual(generator.planWeeks(for: .halfMarathon), 12)
        XCTAssertEqual(generator.planWeeks(for: .marathon), 16)
    }

    func test_planLength_raceDateInsideDefaultShrinksPlan() {
        let today = Date()
        // Calendar days, as planWeeks counts them, so a DST change can't
        // move the race by a day.
        let sixWeeksOut = Calendar.current.date(byAdding: .day, value: 42, to: today)!
        let weeks = generator.planWeeks(for: .marathon, goalDate: sixWeeksOut, today: today)
        // Today through race day: six weeks and one day, so seven weeks.
        XCTAssertEqual(weeks, 7, "Plan should condense to the available window")
    }

    func test_planLength_raceDateBeyondDefaultUsesDefault() {
        let today = Date()
        // Race 26 weeks out — well past the 16-week marathon default.
        let farOut = today.addingTimeInterval(26 * 7 * 24 * 3600)
        let weeks = generator.planWeeks(for: .marathon, goalDate: farOut, today: today)
        XCTAssertEqual(weeks, 16, "Plan length is capped at the goal's default")
    }

    func test_planLength_raceDateInPastFallsBackToDefault() {
        let today = Date()
        let lastMonth = today.addingTimeInterval(-4 * 7 * 24 * 3600)
        let weeks = generator.planWeeks(for: .tenK, goalDate: lastMonth, today: today)
        XCTAssertEqual(weeks, 10)
    }

    func test_planLength_neverGoesBelowFourWeeks() {
        let today = Date()
        let inFiveDays = today.addingTimeInterval(5 * 24 * 3600)
        let weeks = generator.planWeeks(for: .marathon, goalDate: inFiveDays, today: today)
        XCTAssertGreaterThanOrEqual(weeks, 4)
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
        // peakWeek = total - 3 (0-indexed: weekCount - 4). With weekCount=16
        // that's weeks[12] (week 13 of 16).
        let peak = p.weeks[p.weekCount - 4]
        let raceWeek = p.weeks.last!
        XCTAssertLessThan(raceWeek.totalDistanceKm, peak.totalDistanceKm,
                          "Race week should taper below peak")
    }

    func test_generate_marathonLongestLongRunIs37km() {
        for tier in PlanTier.allCases {
            let p = plan(.marathon, tier)
            let longestKm = p.weeks
                .flatMap(\.days)
                .filter { $0.workout.kind == .long }
                .map(\.workout.distanceKm)
                .max() ?? 0
            // We accept ±0.05 km (50 m) of float drift around the 37 km peak.
            XCTAssertEqual(longestKm, 37.0, accuracy: 0.05,
                           "Marathon \(tier.displayName) plan should peak at 37 km long run")
        }
    }

    func test_generate_marathonLongRunBuildIsMonotonicUpToPeak() {
        let p = plan(.marathon, .medium)
        let longRunsKm = p.weeks.map { week -> Double in
            week.days.first { $0.workout.kind == .long }!.workout.distanceKm
        }
        // Peak is at weekCount - 3 (1-indexed) → index weekCount - 4. Build is
        // weeks[0...peakIdx] and should be non-decreasing.
        let peakIdx = p.weekCount - 4
        for i in 1...peakIdx {
            XCTAssertGreaterThanOrEqual(longRunsKm[i], longRunsKm[i - 1] - 0.001,
                                        "Long run should not regress during build at week \(i + 1)")
        }
        // And taper should reduce from peak.
        XCTAssertLessThan(longRunsKm.last!, longRunsKm[peakIdx],
                          "Race-day long run should be well below peak")
    }

    func test_generate_nonMarathonLongRunsUnchangedCeilings() {
        // Other distances keep their original ceilings (5K/10K/Half).
        let half = plan(.halfMarathon, .aggressive)
        let halfLong = half.weeks.flatMap(\.days)
            .filter { $0.workout.kind == .long }
            .map(\.workout.distanceKm).max() ?? 0
        XCTAssertEqual(halfLong, 24.0, accuracy: 0.5,
                       "Aggressive half-marathon long run should still peak around 24 km")

        let tenK = plan(.tenK, .aggressive)
        let tenKLong = tenK.weeks.flatMap(\.days)
            .filter { $0.workout.kind == .long }
            .map(\.workout.distanceKm).max() ?? 0
        XCTAssertEqual(tenKLong, 16.0, accuracy: 0.5,
                       "Aggressive 10K long run should still peak around 16 km")
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

    // MARK: - Volume ramp

    private let rampToday = Date(timeIntervalSince1970: 1_800_000_000)

    private func racePlan(_ goal: RunningGoal, _ tier: PlanTier, weeksOut: Int) -> TrainingPlan {
        generator.generate(TrainingPlanInputs(
            goal: goal, tier: tier, vo2Max: 49.2,
            goalDate: rampToday.addingTimeInterval(Double(weeksOut) * 7 * 86_400),
            today: rampToday
        ))
    }

    /// A week's training distance in km: everything but the race itself,
    /// which is the goal, not load the build has to ramp to.
    private func trainingKm(_ week: TrainingWeek) -> Double {
        week.days.map(\.workout)
            .filter { $0.kind != .race && $0.kind != .rest }
            .reduce(0) { $0 + $1.distanceKm }
    }

    func test_volume_risesAtMostTenPercentAWeek_forRaceDates4To20WeeksOut() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for weeksOut in 4...20 {
                    let km = racePlan(goal, tier, weeksOut: weeksOut).weeks.map(trainingKm)
                    for i in 1..<km.count {
                        XCTAssertLessThanOrEqual(
                            km[i], km[i - 1] * 1.10 + 1e-6,
                            "\(goal) \(tier), race \(weeksOut) weeks out: week \(i + 1) is "
                                + "\(Int(((km[i] / km[i - 1]) - 1) * 100))% up on week \(i)"
                        )
                    }
                }
            }
        }
    }

    func test_taper_isAShareOfThePlansOwnPeak_forRaceDates4To20WeeksOut() {
        // A shortened plan peaks lower, and its taper follows that peak. The
        // race week ends on the race; its last days only lose distance, so
        // it comes in at or under its share.
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for weeksOut in 4...20 {
                    let km = racePlan(goal, tier, weeksOut: weeksOut).weeks.map(trainingKm)
                    let peak = km[km.count - 4]  // the last build week
                    let label = "\(goal) \(tier), race \(weeksOut) weeks out"
                    XCTAssertEqual(km[km.count - 3], peak * 0.70, accuracy: 0.01, "\(label): mid-taper")
                    XCTAssertEqual(km[km.count - 2], peak * 0.50, accuracy: 0.01, "\(label): week before the race")
                    XCTAssertLessThanOrEqual(km[km.count - 1], peak * 0.30 + 0.01, "\(label): race week")
                }
            }
        }
    }

    func test_volume_fiveWeekPlan_buildsTenPercent_notToFullPeak() {
        // A race four weeks out gives five weeks (the fifth holds race day)
        // and two build weeks. Week 2 is 10% up on week 1, so the build
        // stops short of the full-length plan's peak.
        let short = racePlan(.marathon, .aggressive, weeksOut: 4)
        XCTAssertEqual(short.weekCount, 5)
        let km = short.weeks.map(trainingKm)
        XCTAssertEqual(km[1] / km[0], 1.10, accuracy: 0.001)

        let full = plan(.marathon, .aggressive)
        let fullPeak = full.weeks.map(trainingKm).max() ?? 0
        XCTAssertLessThan(km.max() ?? 0, fullPeak)
    }

    // MARK: - Race day

    private func day(_ offset: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: date)!
    }

    /// A plan for a race `daysOut` days after `rampToday`.
    private func racePlan(_ goal: RunningGoal, _ tier: PlanTier, daysOut: Int) -> (TrainingPlan, Date) {
        let raceDay = day(daysOut, from: rampToday)
        let p = generator.generate(TrainingPlanInputs(
            goal: goal, tier: tier, vo2Max: 49.2, goalDate: raceDay, today: rampToday
        ))
        return (p, raceDay)
    }

    func test_race_isOnTheGoalDate_forEveryGoalTierAndWeekday() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for daysOut in 28...34 {
                    let (p, raceDay) = racePlan(goal, tier, daysOut: daysOut)
                    let label = "\(goal) \(tier), race \(daysOut) days out"
                    let race = p.todayWorkout(today: raceDay)
                    XCTAssertEqual(race?.kind, .race, label)
                    XCTAssertEqual(race?.distanceMeters ?? 0, goal.distanceMeters, accuracy: 0.001, label)
                    let raceCount = p.weeks.flatMap(\.days).filter { $0.workout.kind == .race }.count
                    XCTAssertEqual(raceCount, 1, label)
                }
            }
        }
    }

    func test_race_endsThePlan_withATaperBeforeIt() {
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                for daysOut in 28...34 {
                    let (p, raceDay) = racePlan(goal, tier, daysOut: daysOut)
                    let label = "\(goal) \(tier), race \(daysOut) days out"
                    XCTAssertEqual(p.todayWorkout(today: day(-1, from: raceDay))?.kind, .rest, "\(label): day before")
                    for before in [-2, -3] {
                        let kind = p.todayWorkout(today: day(before, from: raceDay))?.kind
                        XCTAssertNotNil(kind, "\(label): day \(before) is in the plan")
                        XCTAssertFalse(kind?.isQuality ?? true, "\(label): no quality session on day \(before)")
                        XCTAssertNotEqual(kind, .long, "\(label): no long run on day \(before)")
                    }
                    XCTAssertNil(p.todayWorkout(today: day(1, from: raceDay)), "\(label): the plan ends with the race")
                    // Today is in week 1, which starts at most six days back.
                    XCTAssertEqual(p.currentWeekIndex(today: rampToday), 0, label)
                }
            }
        }
    }

    func test_race_exactlySixWeeksOut_onTodaysWeekday_isInThePlan() {
        let (p, raceDay) = racePlan(.halfMarathon, .medium, daysOut: 42)
        XCTAssertEqual(p.weekCount, 7, "Today through race day spans seven weeks")
        XCTAssertEqual(p.todayWorkout(today: raceDay)?.kind, .race)
        // Week 1 began six days ago, so week 7 ends on race day.
        XCTAssertEqual(p.startDate, Calendar.current.startOfDay(for: day(-6, from: rampToday)))
        XCTAssertEqual(p.createdAt, rampToday)
    }

    func test_race_tenDaysOut_isInTheTaperAlready() {
        // The 4-week minimum still ends on race day, so today falls in week 3
        // of 4, the week before the race week.
        let (p, raceDay) = racePlan(.tenK, .medium, daysOut: 10)
        XCTAssertEqual(p.weekCount, 4)
        XCTAssertEqual(p.todayWorkout(today: raceDay)?.kind, .race)
        XCTAssertEqual(p.currentWeekIndex(today: rampToday), 2)
    }

    func test_race_laterToday_isTodayInThePlan() {
        // A race date set to earlier today, at any hour, is still today.
        let raceDay = Calendar.current.startOfDay(for: rampToday)
        let p = generator.generate(TrainingPlanInputs(
            goal: .fiveK, tier: .easy, vo2Max: 49.2, goalDate: raceDay, today: rampToday
        ))
        XCTAssertEqual(p.weekCount, 4)
        XCTAssertEqual(p.todayWorkout(today: rampToday)?.kind, .race)
    }

    func test_race_furtherOutThanThePlan_isLeftOut() {
        // A marathon 26 weeks out gets the 16-week plan, which ends first.
        let (p, raceDay) = racePlan(.marathon, .medium, daysOut: 26 * 7)
        XCTAssertEqual(p.weekCount, 16)
        XCTAssertNil(p.startDate)
        XCTAssertNil(p.todayWorkout(today: raceDay))
        XCTAssertFalse(p.weeks.flatMap(\.days).contains { $0.workout.kind == .race })
    }

    func test_planSavedWithoutAStartDate_stillDecodes() throws {
        // Plans saved before startDate existed have no such key.
        let p = plan(.tenK, .medium)
        XCTAssertNil(p.startDate)
        let data = try JSONEncoder().encode(p)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("startDate"))
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func test_race_withoutARaceDate_isNeverPlanned() {
        let p = plan(.halfMarathon, .medium)
        XCTAssertFalse(p.weeks.flatMap(\.days).contains { $0.workout.kind == .race })
    }

    func test_race_namesItselfAsRaceDay() {
        let (p, raceDay) = racePlan(.halfMarathon, .medium, daysOut: 30)
        let race = p.todayWorkout(today: raceDay)
        XCTAssertEqual(race?.kind.displayName, "Race day")
        XCTAssertEqual(race?.summary, "21.1 km")
        XCTAssertEqual(race?.headline, "Race day · 21.1 km")
        // Other workouts keep their summary as the headline.
        let easy = Workout(kind: .easy, distanceMeters: 8_000, paceMinSecPerKm: 300, paceMaxSecPerKm: 330)
        XCTAssertEqual(easy.headline, easy.summary)
    }

    func test_volume_stridesWeek_weighsTheSameAsItsEasyRun() {
        // The Easy tier's Tuesday strides run is that week's easy distance.
        let p = plan(.marathon, .easy)
        for week in p.weeks {
            let strides = week.days.map(\.workout).filter { $0.kind == .strides }
            let easy = week.days.map(\.workout).filter { $0.kind == .easy }
            guard let s = strides.first, let e = easy.first else { continue }
            XCTAssertEqual(s.distanceMeters, e.distanceMeters, accuracy: 0.001,
                           "Week \(week.index): strides and easy runs should be the same length")
        }
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
