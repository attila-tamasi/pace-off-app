import XCTest

final class HeartRateZonesTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let zones = HeartRateZones(maxHR: 190)

    private func samples(_ bpms: [Double], every seconds: Double = 5) -> [(date: Date, bpm: Double)] {
        bpms.enumerated().map { (date: start.addingTimeInterval(Double($0.offset) * seconds), bpm: $0.element) }
    }

    // MARK: - Max HR

    func testMaxHRIsTheHighestSeenElseFromAge() {
        XCTAssertEqual(HeartRateZones.maxHR(observed: 186, age: 40), 186)
        XCTAssertEqual(HeartRateZones.maxHR(observed: nil, age: 40)!, 180, accuracy: 1e-9)
        XCTAssertEqual(HeartRateZones.maxHR(observed: 125, age: 40)!, 180, accuracy: 1e-9, "too low to be a max")
        XCTAssertEqual(HeartRateZones.maxHR(observed: 250, age: 40)!, 180, accuracy: 1e-9, "a sensor glitch")
        XCTAssertNil(HeartRateZones.maxHR(observed: nil, age: nil))
    }

    // MARK: - Zones

    func testZoneBoundaries() {
        XCTAssertEqual(zones.zone(of: 90), 1)    // 47%
        XCTAssertEqual(zones.zone(of: 114), 2)   // 60%
        XCTAssertEqual(zones.zone(of: 132), 2)   // 69%
        XCTAssertEqual(zones.zone(of: 133), 3)   // 70%
        XCTAssertEqual(zones.zone(of: 152), 4)   // 80%
        XCTAssertEqual(zones.zone(of: 171), 5)   // 90%
        XCTAssertEqual(zones.zone(of: 200), 5)
        XCTAssertEqual(zones.range(of: 2).lowerBound, 114, accuracy: 1e-9)
        XCTAssertEqual(zones.range(of: 2).upperBound, 133, accuracy: 1e-9)
        XCTAssertEqual(zones.range(of: 5).upperBound, 190)
    }

    func testTimeInZones() {
        // 4 samples in zone 2 and 2 in zone 3, 5 s apart; the last holds to the end.
        let t = zones.timeInZones(samples: samples([120, 120, 125, 125, 140, 140]),
                                  start: start, end: start.addingTimeInterval(30))
        XCTAssertEqual(t, [0, 20, 10, 0, 0])
    }

    func testAPauseCountsAtMostAMinute() {
        let s = [(date: start, bpm: 120.0), (date: start.addingTimeInterval(600), bpm: 120.0)]
        let t = zones.timeInZones(samples: s, start: start, end: start.addingTimeInterval(610))
        XCTAssertEqual(t[1], 70)
    }

    func testSamplesOutsideTheRunAreLeftOut() {
        let s = [(date: start.addingTimeInterval(-30), bpm: 180.0), (date: start, bpm: 120.0)]
        let t = zones.timeInZones(samples: s, start: start, end: start.addingTimeInterval(10))
        XCTAssertEqual(t, [0, 10, 0, 0, 0])
    }

    // MARK: - Easy runs

    private func ledgerDay(_ kind: WorkoutKind?, readiness: ReadinessLevel?) -> LedgerDay {
        let workout = kind.map { Workout(kind: $0, distanceMeters: 8_000, paceMinSecPerKm: 330, paceMaxSecPerKm: 350) }
        let target = RunTarget(distanceMeters: 8_000, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                               baselineMeters: 8_000, ceilingClamped: false, fatigueGuardActive: false, capMeters: 11_000)
        let day = DayPrescription.make(planStatus: workout.map { PlanDayStatus(workout: $0, isCompleted: false, strength: nil) },
                                       readiness: nil, target: target, easyPace: nil)!
        return LedgerDay(day: start, prescription: LedgerPrescription(day, readiness: readiness), recordedAt: start)
    }

    func testWhichRunsAreMeantEasy() {
        XCTAssertTrue(EasyRunCheck.isMeantEasy(ledgerDay(.easy, readiness: .green)))
        XCTAssertTrue(EasyRunCheck.isMeantEasy(ledgerDay(.long, readiness: nil)))
        XCTAssertFalse(EasyRunCheck.isMeantEasy(ledgerDay(.threshold, readiness: .green)))
        XCTAssertTrue(EasyRunCheck.isMeantEasy(ledgerDay(.threshold, readiness: .yellow)))
        XCTAssertTrue(EasyRunCheck.isMeantEasy(ledgerDay(nil, readiness: .red)))
        XCTAssertFalse(EasyRunCheck.isMeantEasy(ledgerDay(nil, readiness: .green)))
        XCTAssertFalse(EasyRunCheck.isMeantEasy(nil))
    }

    func testTheNoteOnAnEasyRunRunTooHard() {
        let hard: [TimeInterval] = [0, 1_300, 500, 200, 0]   // 35% above zone 2
        XCTAssertEqual(EasyRunCheck.note(timeInZones: hard, meantEasy: true),
                       "35% of this easy run was in zone 3 or above. Slow down to keep it easy.")
        XCTAssertNil(EasyRunCheck.note(timeInZones: hard, meantEasy: false))
        XCTAssertNil(EasyRunCheck.note(timeInZones: [0, 1_700, 300, 0, 0], meantEasy: true), "15% is fine")
        XCTAssertNil(EasyRunCheck.note(timeInZones: [0, 0, 0, 0, 0], meantEasy: true))
    }
}
