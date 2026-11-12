import XCTest

final class BestEffortLogTests: XCTestCase {

    private let cal = Calendar.current
    /// Tuesday 2026-11-10, 07:00 local.
    private let tuesday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 7))!
    private var now: Date { tuesday.addingTimeInterval(86_400) }

    private func run(daysAgo: Double, km: Double) -> RunRecord {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return RunRecord(startDate: start, endDate: start.addingTimeInterval(km * 330),
                         distanceMeters: km * 1000, durationSeconds: km * 330)
    }

    private func effort(_ distance: BestEffortDistance, _ seconds: Double, _ start: Date? = nil) -> BestEffort {
        BestEffort(distance: distance, seconds: seconds, runStart: start ?? tuesday)
    }

    // MARK: - Which runs to look at

    func testUnseenRunsAreRecentLongEnoughNewestFirst() {
        let runs = [run(daysAgo: 3, km: 5), run(daysAgo: 1, km: 8), run(daysAgo: 91, km: 10),
                    run(daysAgo: 2, km: 0.8)]
        let unseen = BestEffortLog().unseen(runs, now: now)
        XCTAssertEqual(unseen.map(\.distanceMeters), [8_000, 5_000])
    }

    func testSeenRunsAreSkipped() {
        let runs = [run(daysAgo: 3, km: 5), run(daysAgo: 1, km: 8)]
        var log = BestEffortLog()
        log.record(runStart: runs[1].startDate, efforts: [])
        XCTAssertEqual(log.unseen(runs, now: now).map(\.distanceMeters), [5_000])
    }

    func testRecordReturnsWhatImproved() {
        var log = BestEffortLog()
        XCTAssertEqual(log.record(runStart: tuesday, efforts: [effort(.oneK, 240), effort(.fiveK, 1_300)]).count, 2)
        let improved = log.record(runStart: now, efforts: [effort(.oneK, 250, now), effort(.fiveK, 1_280, now)])
        XCTAssertEqual(improved.map(\.distance), [.fiveK])
        XCTAssertEqual(log.best(.oneK)?.seconds, 240)
        XCTAssertEqual(log.best(.fiveK)?.seconds, 1_280)
    }

    // MARK: - The PB

    func testFasterBestReplacesThePBForItsDistance() throws {
        let pb = PersonalBest(durationSeconds: 1_400, year: 2025, distance: .fiveK)
        let new = try XCTUnwrap(BestEffortLog.updatedPB(current: pb, goal: .halfMarathon,
                                                        improved: [effort(.fiveK, 1_350)], calendar: cal))
        XCTAssertEqual(new, PersonalBest(durationSeconds: 1_350, year: 2026, distance: .fiveK))
    }

    func testSlowerBestOrOtherDistanceLeavesThePB() {
        let pb = PersonalBest(durationSeconds: 1_400, year: 2025, distance: .fiveK)
        XCTAssertNil(BestEffortLog.updatedPB(current: pb, goal: .fiveK, improved: [effort(.fiveK, 1_450)], calendar: cal))
        XCTAssertNil(BestEffortLog.updatedPB(current: pb, goal: .fiveK, improved: [effort(.tenK, 2_600)], calendar: cal))
        XCTAssertNil(BestEffortLog.updatedPB(current: pb, goal: .fiveK, improved: [effort(.oneK, 200)], calendar: cal))
    }

    func testWithoutAPBTheGoalsDistanceBecomesIt() {
        XCTAssertEqual(BestEffortLog.updatedPB(current: nil, goal: .tenK, improved: [effort(.tenK, 2_700)], calendar: cal),
                       PersonalBest(durationSeconds: 2_700, year: 2026, distance: .tenK))
        XCTAssertNil(BestEffortLog.updatedPB(current: nil, goal: .tenK, improved: [effort(.fiveK, 1_300)], calendar: cal))
    }

    // MARK: - The notification

    func testNotificationNamesTheBestAndTheDay() {
        XCTAssertEqual(BestEffortLog.notificationBody([effort(.fiveK, 1_361)], calendar: cal),
                       "New best: 5 km in 22:41, inside Tuesday's run.")
        XCTAssertEqual(BestEffortLog.notificationBody([effort(.oneK, 238), effort(.fiveK, 1_361)], calendar: cal),
                       "New bests: 1 km in 3:58 and 5 km in 22:41, inside Tuesday's run.")
        XCTAssertNil(BestEffortLog.notificationBody([], calendar: cal))
    }

    func testTimeFormat() {
        XCTAssertEqual(BestEffortLog.formatTime(238), "3:58")
        XCTAssertEqual(BestEffortLog.formatTime(6_065), "1:41:05")
    }

    // MARK: - Storage

    func testSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "BestEffortLogTests")!
        defaults.removePersistentDomain(forName: "BestEffortLogTests")
        var log = BestEffortLog()
        log.record(runStart: tuesday, efforts: [effort(.tenK, 2_700)])
        log.save(to: defaults)
        XCTAssertEqual(BestEffortLog.load(from: defaults), log)
        XCTAssertEqual(BestEffortLog.load(from: nil), BestEffortLog())
        defaults.removePersistentDomain(forName: "BestEffortLogTests")
    }
}
