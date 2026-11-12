import XCTest

final class WorkoutBlocksTests: XCTestCase {

    private let easyBand: ClosedRange<Double> = 330...350

    private func workout(_ kind: WorkoutKind, km: Double, pace: ClosedRange<Double> = 280...295) -> Workout {
        Workout(kind: kind, distanceMeters: km * 1000,
                paceMinSecPerKm: pace.lowerBound, paceMaxSecPerKm: pace.upperBound)
    }

    // MARK: - One step

    func testEasyRunIsOneWorkStepWithItsBand() throws {
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.easy, km: 8, pace: easyBand),
                                                      goal: .halfMarathon, tier: .medium, easyPace: easyBand))
        XCTAssertNil(blocks.warmUp)
        XCTAssertNil(blocks.coolDown)
        XCTAssertEqual(blocks.blocks, [WorkoutBlock(iterations: 1, steps: [
            WorkoutStep(purpose: .work, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350),
        ])])
        XCTAssertEqual(blocks.distanceMeters, 8_000)
    }

    func testLongAndMarathonPaceRunsAreOneStep() throws {
        for kind in [WorkoutKind.long, .marathonPace, .strides] {
            let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(kind, km: 16), goal: .marathon,
                                                          tier: .aggressive, easyPace: easyBand))
            XCTAssertEqual(blocks.blocks.count, 1, "\(kind)")
            XCTAssertEqual(blocks.blocks[0].steps.count, 1, "\(kind)")
            XCTAssertEqual(blocks.distanceMeters, 16_000, "\(kind)")
            XCTAssertEqual(blocks.kind, kind)
        }
    }

    func testRestAndRaceAreNotSent() {
        XCTAssertNil(WorkoutBlocks.make(.rest, goal: .tenK, tier: .easy, easyPace: easyBand))
        let race = Workout(kind: .race, distanceMeters: 10_000, paceMinSecPerKm: 0, paceMaxSecPerKm: 0)
        XCTAssertNil(WorkoutBlocks.make(race, goal: .tenK, tier: .easy, easyPace: easyBand))
    }

    func testRunWithoutAPaceBandHasNoAlert() throws {
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.easy, km: 5, pace: 0...0),
                                                      goal: .fiveK, tier: .easy, easyPace: nil))
        XCTAssertNil(blocks.blocks[0].steps[0].paceMinSecPerKm)
        XCTAssertNil(blocks.blocks[0].steps[0].paceMaxSecPerKm)
    }

    // MARK: - Quality sessions

    func testPeakThresholdSessionFollowsItsNotes() throws {
        // Medium half: "WU 2 km · 3 × 1.6 km @ T w/ 200 m jog · CD 1.8 km", 9 km.
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.threshold, km: 9), goal: .halfMarathon,
                                                      tier: .medium, easyPace: easyBand))
        XCTAssertEqual(blocks.warmUp, WorkoutStep(purpose: .warmUp, distanceMeters: 2_000,
                                                  paceMinSecPerKm: 330, paceMaxSecPerKm: 350))
        let rep = WorkoutStep(purpose: .work, distanceMeters: 1_600, paceMinSecPerKm: 280, paceMaxSecPerKm: 295)
        let jog = WorkoutStep(purpose: .recovery, distanceMeters: 200)
        XCTAssertEqual(blocks.blocks, [WorkoutBlock(iterations: 2, steps: [rep, jog]),
                                       WorkoutBlock(iterations: 1, steps: [rep])])
        XCTAssertEqual(blocks.coolDown, WorkoutStep(purpose: .coolDown, distanceMeters: 1_800,
                                                    paceMinSecPerKm: 330, paceMaxSecPerKm: 350))
        XCTAssertEqual(blocks.distanceMeters, 9_000)
    }

    func testPeakIntervalSession() throws {
        // Marathon: "WU 3 km · 5 × 1 km @ I w/ 500 m jog · CD 2 km", 12 km.
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.interval, km: 12, pace: 255...265),
                                                      goal: .marathon, tier: .medium, easyPace: easyBand))
        XCTAssertEqual(blocks.blocks.map(\.iterations), [4, 1])
        XCTAssertEqual(blocks.blocks[0].steps.map(\.distanceMeters), [1_000, 500])
        XCTAssertEqual(blocks.blocks[0].steps[0].paceMinSecPerKm, 255)
        XCTAssertNil(blocks.blocks[0].steps[1].paceMinSecPerKm)
        XCTAssertEqual(blocks.warmUp?.distanceMeters, 3_000)
        XCTAssertEqual(blocks.coolDown?.distanceMeters, 2_000)
        XCTAssertEqual(blocks.distanceMeters, 12_000)
    }

    func testTempoUsesTheThresholdSessionLikeItsNotes() throws {
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.tempo, km: 9), goal: .halfMarathon,
                                                      tier: .medium, easyPace: easyBand))
        XCTAssertNotNil(blocks.warmUp)
        XCTAssertEqual(blocks.distanceMeters, 9_000)
    }

    func testSingleRepHasNoJog() throws {
        // The 5K's race-week session: "WU 1 km · 1 × 400 m @ T · CD 1 km".
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.threshold, km: 2.4), goal: .fiveK,
                                                      tier: .medium, easyPace: easyBand))
        XCTAssertEqual(blocks.blocks.count, 1)
        XCTAssertEqual(blocks.blocks[0].iterations, 1)
        XCTAssertEqual(blocks.blocks[0].steps.map(\.purpose), [.work])
        XCTAssertEqual(blocks.distanceMeters, 2_400)
    }

    func testWarmUpWithoutAnEasyBandIsRunByFeel() throws {
        let blocks = try XCTUnwrap(WorkoutBlocks.make(workout(.threshold, km: 9), goal: .halfMarathon,
                                                      tier: .medium, easyPace: nil))
        XCTAssertNil(blocks.warmUp?.paceMinSecPerKm)
        XCTAssertNil(blocks.coolDown?.paceMaxSecPerKm)
    }

    /// Every quality session of every generated plan adds up to its
    /// distance, as its notes do, to the tenth of a km.
    func testEveryGeneratedQualitySessionAddsUpToItsDistance() {
        let generator = TrainingPlanGenerator()
        for goal in RunningGoal.allCases {
            for tier in PlanTier.allCases {
                let plan = generator.generate(TrainingPlanInputs(goal: goal, tier: tier, vo2Max: 48))
                let easy = DayPrescription.easyPaceBand(in: plan, today: plan.firstDay)
                for week in plan.weeks {
                    for day in week.days where day.workout.kind.isQuality {
                        guard let blocks = WorkoutBlocks.make(day.workout, goal: goal, tier: tier, easyPace: easy) else {
                            XCTFail("\(goal) \(tier) week \(week.index): no blocks"); continue
                        }
                        XCTAssertEqual(blocks.distanceMeters, day.workout.distanceMeters, accuracy: 50,
                                       "\(goal) \(tier) week \(week.index) \(day.workout.kind)")
                        XCTAssertTrue(blocks.blocks.allSatisfy { $0.iterations >= 1 })
                    }
                }
            }
        }
    }
}
