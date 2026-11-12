import XCTest

final class PaceSourceTests: XCTestCase {

    private let cal = Calendar.current
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))!

    private func daysAgo(_ days: Double) -> Date { today.addingTimeInterval(-days * 86_400) }

    private func effort(_ distance: BestEffortDistance, minutes: Double, daysAgo days: Double = 9) -> BestEffort {
        BestEffort(distance: distance, seconds: minutes * 60, runStart: daysAgo(days))
    }

    private func vdot(_ effort: BestEffort) -> Double {
        VDOTCalculator().vdot(fromRaceDistanceMeters: effort.distance.meters, timeSeconds: effort.seconds)!
    }

    // MARK: - The rule

    func testARecentRaceAboveTheEstimateSetsThePaces() {
        let race = effort(.tenK, minutes: 42)
        let r = PaceSource.resolve(vo2Max: 40, personalBest: nil, bestEfforts: [race], today: today)
        XCTAssertGreaterThan(vdot(race), 40)
        XCTAssertEqual(r.source, .bestEffort(race))
        XCTAssertEqual(r.vdot, vdot(race), accuracy: 1e-9)
        XCTAssertFalse(r.usedFallback)
    }

    func testEasyRunsBelowTheEstimateDontSlowThePaces() {
        let jog = effort(.fiveK, minutes: 32)
        let r = PaceSource.resolve(vo2Max: 50, personalBest: nil, bestEfforts: [jog], today: today)
        XCTAssertEqual(r.source, .vo2Max(50))
        XCTAssertEqual(r.vdot, 50)
    }

    func testTheFastestOfSeveralEffortsWins() {
        let fiveK = effort(.fiveK, minutes: 21)
        let half = effort(.halfMarathon, minutes: 110)
        let r = PaceSource.resolve(vo2Max: nil, personalBest: nil, bestEfforts: [half, fiveK], today: today)
        XCTAssertEqual(r.source, vdot(fiveK) > vdot(half) ? .bestEffort(fiveK) : .bestEffort(half))
    }

    func testAnEffortOlderThanNinetyDaysIsLeftOut() {
        let old = effort(.tenK, minutes: 40, daysAgo: 91)
        let r = PaceSource.resolve(vo2Max: 45, personalBest: nil, bestEfforts: [old], today: today)
        XCTAssertEqual(r.source, .vo2Max(45))
    }

    func testTheOneKmNeverSetsPaces() {
        let fast = effort(.oneK, minutes: 3)
        let r = PaceSource.resolve(vo2Max: 40, personalBest: nil, bestEfforts: [fast], today: today)
        XCTAssertEqual(r.source, .vo2Max(40))
    }

    func testWithNeitherThePBThenTheDefault() {
        let pb = PersonalBest(durationSeconds: 2_700, year: 2025, distance: .tenK)
        let withPB = PaceSource.resolve(vo2Max: nil, personalBest: pb, bestEfforts: [], today: today)
        XCTAssertEqual(withPB.source, .personalBest(pb))
        XCTAssertEqual(withPB.vdot, pb.vdot!, accuracy: 1e-9)

        let none = PaceSource.resolve(vo2Max: nil, personalBest: nil, bestEfforts: [], today: today)
        XCTAssertEqual(none.source, .beginnerDefault)
        XCTAssertEqual(none.vdot, TrainingPlanGenerator.beginnerVDOTFallback)
        XCTAssertTrue(none.usedFallback)
    }

    func testAMeasurementWinsOverThePBEvenWhenThePBIsFaster() {
        let pb = PersonalBest(durationSeconds: 2_400, year: 2025, distance: .tenK)
        let r = PaceSource.resolve(vo2Max: 44, personalBest: pb, bestEfforts: [], today: today)
        XCTAssertEqual(r.source, .vo2Max(44))
    }

    func testASlowReadingGivesWayToAPBInRangeAndIsRaisedWithout() {
        let pb = PersonalBest(durationSeconds: 2_700, year: 2025, distance: .tenK)
        XCTAssertEqual(PaceSource.resolve(vo2Max: 15, personalBest: pb, bestEfforts: [], today: today).source,
                       .personalBest(pb))
        let slow = PaceSource.resolve(vo2Max: 15, personalBest: nil, bestEfforts: [], today: today)
        XCTAssertEqual(slow.source, .vo2Max(15))
        XCTAssertEqual(slow.vdot, VDOTCalculator.validRange.lowerBound)
    }

    func testAnImplausibleReadingIsIgnored() {
        let r = PaceSource.resolve(vo2Max: 120, personalBest: nil, bestEfforts: [], today: today)
        XCTAssertEqual(r.source, .beginnerDefault)
    }

    // MARK: - The note

    func testNotes() {
        let race = BestEffort(distance: .tenK, seconds: 2_892,
                              runStart: cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!)
        XCTAssertEqual(PaceSource.bestEffort(race).note(calendar: cal), "Paces from your 10 km on 3 Nov (48:12)")
        XCTAssertEqual(PaceSource.vo2Max(46.1).note(calendar: cal), "Paces from your VO₂ max in Health (46.1)")
        let pb = PersonalBest(durationSeconds: 2_892, year: 2025, distance: .tenK)
        XCTAssertEqual(PaceSource.personalBest(pb).note(calendar: cal), "Paces from your 10K PB (48:12)")
    }

    // MARK: - The plan keeps it

    func testTheGeneratedPlanRecordsItsSource() {
        let race = effort(.tenK, minutes: 42)
        let plan = TrainingPlanGenerator().generate(TrainingPlanInputs(
            goal: .halfMarathon, tier: .medium, vo2Max: 40, bestEfforts: [race], today: today))
        XCTAssertEqual(plan.paceSource, .bestEffort(race))
        XCTAssertEqual(plan.vdot, vdot(race), accuracy: 1e-9)
        XCTAssertFalse(plan.usedBeginnerDefault)
    }

    func testThePlanSurvivesSaveAndLoadAndAnOldPlanDecodes() throws {
        let plan = TrainingPlanGenerator().generate(TrainingPlanInputs(
            goal: .tenK, tier: .easy, vo2Max: 45, today: today))
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data), plan)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["paceSource"] = nil
        let old = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.paceSource)
        XCTAssertEqual(old.vdot, plan.vdot)
    }

    func testTheRetuneRecordsTheNewSource() throws {
        let plan = TrainingPlanGenerator().generate(TrainingPlanInputs(
            goal: .tenK, tier: .medium, vo2Max: 40, today: today))
        let race = effort(.tenK, minutes: 42)
        let retuned = try XCTUnwrap(TrainingPlanReconciler().retunedPlan(
            plan, toVDOT: vdot(race), source: .bestEffort(race), today: today))
        XCTAssertEqual(retuned.paceSource, .bestEffort(race))
    }
}
