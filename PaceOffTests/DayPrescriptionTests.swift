import XCTest

final class DayPrescriptionTests: XCTestCase {

    private let easyBand: ClosedRange<Double> = 330...350
    private let kettlebell = StrengthSession(equipment: .kettlebell, minutes: 35, notes: "Swings 3×15")

    private func workout(_ kind: WorkoutKind, km: Double, pace: ClosedRange<Double> = 280...295) -> Workout {
        Workout(kind: kind, distanceMeters: km * 1000,
                paceMinSecPerKm: pace.lowerBound, paceMaxSecPerKm: pace.upperBound)
    }

    private func status(_ workout: Workout?, strength: StrengthSession? = nil) -> PlanDayStatus {
        PlanDayStatus(workout: workout, isCompleted: false, strength: strength)
    }

    private func target(km: Double) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                  baselineMeters: km * 1000, ceilingClamped: false, fatigueGuardActive: false,
                  capMeters: km * 1400)
    }

    // MARK: - Plan days

    func testGreenKeepsThePlanWorkoutAsWritten() throws {
        let threshold = workout(.threshold, km: 10)
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(threshold), readiness: .green,
                                                     target: target(km: 6), easyPace: easyBand))
        XCTAssertEqual(day.kind, .run)
        XCTAssertEqual(day.source, .plan)
        XCTAssertEqual(day.workoutKind, .threshold)
        XCTAssertEqual(day.distanceMeters, 10_000)
        XCTAssertEqual(day.paceMinSecPerKm, 280)
        XCTAssertEqual(day.paceMaxSecPerKm, 295)
        XCTAssertNil(day.adjustment)
        XCTAssertEqual(day.planWorkout, threshold)
    }

    func testUnknownReadinessKeepsThePlanWorkout() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.interval, km: 9)),
                                                     readiness: nil, target: nil, easyPace: easyBand))
        XCTAssertEqual(day.workoutKind, .interval)
        XCTAssertNil(day.adjustment)
    }

    func testThePlanWinsOverTheDailyTarget() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.easy, km: 8, pace: easyBand)),
                                                     readiness: .green, target: target(km: 6), easyPace: easyBand))
        XCTAssertEqual(day.distanceMeters, 8_000)
        XCTAssertEqual(day.source, .plan)
    }

    func testYellowRunsAQualitySessionEasyAtTheSameDistance() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.threshold, km: 10)),
                                                     readiness: .yellow, target: nil, easyPace: easyBand))
        XCTAssertEqual(day.workoutKind, .easy)
        XCTAssertEqual(day.distanceMeters, 10_000)
        XCTAssertEqual(day.paceMinSecPerKm, 330)
        XCTAssertEqual(day.paceMaxSecPerKm, 350)
        XCTAssertEqual(day.adjustment, .easedForYellow)
        XCTAssertEqual(day.planWorkout?.kind, .threshold)
    }

    func testYellowLeavesEasyAndLongRunsAlone() throws {
        for kind in [WorkoutKind.easy, .long, .strides] {
            let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(kind, km: 12, pace: easyBand)),
                                                         readiness: .yellow, target: nil, easyPace: easyBand))
            XCTAssertEqual(day.workoutKind, kind)
            XCTAssertEqual(day.distanceMeters, 12_000)
            XCTAssertNil(day.adjustment, "\(kind)")
        }
    }

    func testRedCutsAnyRunToAnEasyRunOfSixtyPercent() throws {
        for kind in [WorkoutKind.long, .interval, .easy] {
            let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(kind, km: 18)),
                                                         readiness: .red, target: nil, easyPace: easyBand))
            XCTAssertEqual(day.workoutKind, .easy)
            XCTAssertEqual(try XCTUnwrap(day.distanceMeters), 10_800, accuracy: 0.001, "\(kind)")
            XCTAssertEqual(day.adjustment, .cutForRed)
        }
    }

    func testRedCutIsRoundedDownToATenthOfAKm() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.easy, km: 9.7, pace: easyBand)),
                                                     readiness: .red, target: nil, easyPace: easyBand))
        // 60% of 9.7 km is 5.82 km.
        XCTAssertEqual(try XCTUnwrap(day.distanceMeters), 5_800, accuracy: 0.001)
    }

    func testEasedRunWithoutAnEasyBandHasNoPaceBand() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.tempo, km: 8)),
                                                     readiness: .yellow, target: nil, easyPace: nil))
        XCTAssertEqual(day.workoutKind, .easy)
        XCTAssertNil(day.paceMinSecPerKm)
        XCTAssertNil(day.paceMaxSecPerKm)
    }

    func testRaceDayIsNeverChangedByReadiness() throws {
        let race = Workout(kind: .race, distanceMeters: 21_097.5, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(race), readiness: .red,
                                                     target: target(km: 5), easyPace: easyBand))
        XCTAssertEqual(day.kind, .race)
        XCTAssertEqual(day.distanceMeters, 21_097.5)
        XCTAssertNil(day.adjustment)
    }

    func testPlanRestDayIsRestEvenWithADailyTarget() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(.rest), readiness: .green,
                                                     target: target(km: 6), easyPace: easyBand))
        XCTAssertEqual(day.kind, .rest)
        XCTAssertNil(day.distanceMeters)
    }

    func testStrengthOnlyDay() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(.rest, strength: kettlebell),
                                                     readiness: .red, target: target(km: 6), easyPace: easyBand))
        XCTAssertEqual(day.kind, .strength)
        XCTAssertEqual(day.strength, kettlebell)
        XCTAssertNil(day.distanceMeters)
    }

    func testRunDayKeepsItsStrengthSession() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.easy, km: 6, pace: easyBand),
                                                                        strength: kettlebell),
                                                     readiness: .green, target: nil, easyPace: easyBand))
        XCTAssertEqual(day.kind, .run)
        XCTAssertEqual(day.strength, kettlebell)
    }

    // MARK: - Without a plan workout

    func testNoPlanUsesTheDailyTargetAsShown() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: .yellow,
                                                     target: target(km: 5.3), easyPace: nil))
        XCTAssertEqual(day.kind, .run)
        XCTAssertEqual(day.source, .dailyTarget)
        XCTAssertEqual(day.distanceMeters, 6_000)
        XCTAssertNil(day.workoutKind)
        XCTAssertNil(day.adjustment)
    }

    func testPlanThatHasNotStartedUsesTheDailyTarget() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(nil), readiness: .green,
                                                     target: target(km: 6), easyPace: easyBand))
        XCTAssertEqual(day.source, .dailyTarget)
        XCTAssertEqual(day.distanceMeters, 6_000)
    }

    func testNothingToPrescribeWithoutPlanOrTarget() {
        XCTAssertNil(DayPrescription.make(planStatus: nil, readiness: .green, target: nil, easyPace: nil))
        XCTAssertNil(DayPrescription.make(planStatus: status(nil), readiness: nil, target: nil, easyPace: nil))
    }

    // MARK: - Completion

    func testPlanRunIsMetAtEightyFivePercent() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.easy, km: 10, pace: easyBand)),
                                                     readiness: .green, target: nil, easyPace: easyBand))
        XCTAssertTrue(day.isMet(byRunMeters: 8_500))
        XCTAssertFalse(day.isMet(byRunMeters: 8_400))
    }

    func testRedDayIsMetAgainstTheCutDistance() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(workout(.long, km: 20)),
                                                     readiness: .red, target: nil, easyPace: easyBand))
        XCTAssertTrue(day.isMet(byRunMeters: 12_000 * 0.85))
    }

    func testDailyTargetIsMetAtNinetyFivePercentOfTheWholeKm() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil,
                                                     target: target(km: 6), easyPace: nil))
        XCTAssertTrue(day.isMet(byRunMeters: 5_700))
        XCTAssertFalse(day.isMet(byRunMeters: 5_600))
    }

    func testRestDayIsNeverMetByARun() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: status(.rest), readiness: nil,
                                                     target: nil, easyPace: nil))
        XCTAssertFalse(day.isMet(byRunMeters: 10_000))
    }

    // MARK: - Easy band

    func testEasyBandComesFromThePlansEasyRuns() throws {
        let plan = TrainingPlanGenerator().generate(TrainingPlanInputs(goal: .halfMarathon, tier: .medium, vo2Max: 49.2))
        let band = try XCTUnwrap(DayPrescription.easyPaceBand(in: plan, today: plan.firstDay))
        let easy = try XCTUnwrap(plan.weeks[0].days.map(\.workout).first { $0.kind == .easy })
        XCTAssertEqual(band.lowerBound, easy.paceMinSecPerKm)
        XCTAssertEqual(band.upperBound, easy.paceMaxSecPerKm)
    }
}
