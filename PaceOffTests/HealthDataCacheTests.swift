// HealthDataCacheTests.swift
// Roundtrip + staleness checks for HealthDataSnapshot, and the
// accept-or-keep rule that stops a locked, failed or empty Health read from
// replacing a good cache. The HealthDataCache actor itself reads from /
// writes to the App Group container which isn't available in the unit test
// bundle, so we exercise the public types and the JSON shape rather than
// the disk side-effects.

import XCTest
@testable import PaceOff

final class HealthDataCacheTests: XCTestCase {

    func test_snapshot_codableRoundtrip() throws {
        let original = HealthDataSnapshot(
            schemaVersion: HealthDataSnapshot.currentSchema,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000),
            runsWindowDays: 90,
            vo2WindowDays: 90,
            restingHRWindowDays: 14,
            hrvWindowDays: 35,
            runs: [
                RunRecord(
                    startDate: Date(timeIntervalSince1970: 1_699_000_000),
                    endDate: Date(timeIntervalSince1970: 1_699_002_400),
                    distanceMeters: 8_120,
                    durationSeconds: 2_400,
                    averageHeartRate: 154
                )
            ],
            vo2Max: [VO2MaxSnapshot(date: Date(timeIntervalSince1970: 1_699_500_000), value: 49.2)],
            restingHR: [RestingHeartRateSnapshot(date: Date(timeIntervalSince1970: 1_699_800_000), bpm: 51)],
            hrv: [HRVSnapshot(date: Date(timeIntervalSince1970: 1_699_850_000), sdnnMs: 62)],
            yesterdayHRV: 62,
            yesterdayAvgHeartRate: 68,
            latestRestingHeartRate: 51,
            userAge: 33
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthDataSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - The day "yesterday" values describe

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    func test_yesterdayValues_fromASyncToday_areYesterdays() {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 18))!   // a Sunday
        let synced = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 7))!
        let snapshot = HealthDataSnapshot(lastSyncedAt: synced, yesterdayHRV: 60)
        XCTAssertEqual(snapshot.yesterdayValuesDayName(now: now, calendar: cal), "yesterday")
    }

    func test_yesterdayValues_fromAnEarlierSync_nameTheirOwnDay() {
        // Synced Friday morning, seen Sunday: the values are Thursday's.
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        let synced = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 8))!
        let snapshot = HealthDataSnapshot(lastSyncedAt: synced, yesterdayHRV: 60)
        XCTAssertEqual(snapshot.yesterdayValuesDayName(now: now, calendar: cal), "Thursday")
    }

    func test_yesterdayValues_sixDaysOld_nameTheirDay_aWeekOld_areHidden() {
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        // Synced Tuesday: Monday's values, six days back.
        let tuesday = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8))!
        XCTAssertEqual(HealthDataSnapshot(lastSyncedAt: tuesday, yesterdayHRV: 60)
                        .yesterdayValuesDayName(now: now, calendar: cal), "Monday")
        // Synced Monday: last Sunday's, a week back.
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))!
        XCTAssertNil(HealthDataSnapshot(lastSyncedAt: monday, yesterdayHRV: 60)
                        .yesterdayValuesDayName(now: now, calendar: cal))
    }

    func test_yesterdayValues_fromASyncDatedTomorrow_areHidden() {
        // A clock that ran ahead: the values would be today's, not yesterday's.
        let cal = utcCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        let synced = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!
        XCTAssertNil(HealthDataSnapshot(lastSyncedAt: synced, yesterdayHRV: 60)
                        .yesterdayValuesDayName(now: now, calendar: cal))
    }

    func test_snapshot_isEmpty_detectsFreshConstruction() {
        let blank = HealthDataSnapshot()
        XCTAssertTrue(blank.isEmpty)

        var populated = blank
        populated.userAge = 33
        XCTAssertFalse(populated.isEmpty)
    }

    func test_snapshot_isStale_basedOnAge() {
        let now = Date()
        let fresh = HealthDataSnapshot(lastSyncedAt: now.addingTimeInterval(-5 * 60)) // 5 min old
        let stale = HealthDataSnapshot(lastSyncedAt: now.addingTimeInterval(-60 * 60)) // 1 h old

        XCTAssertFalse(fresh.isStale(maxAge: 15 * 60, now: now))
        XCTAssertTrue(stale.isStale(maxAge: 15 * 60, now: now))
    }

    func test_actor_loadSaveClearRoundtrip_inTempContainer() async throws {
        // The shared cache writes to the App Group container, which isn't
        // mounted in unit tests. To exercise the actual save/load/clear
        // behaviour we mirror the same encoding to a tmpdir and verify the
        // file shape. This is a behaviour-equivalent test, not a direct
        // singleton test.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("paceoff-health-cache-\(UUID().uuidString).json")
        let snapshot = HealthDataSnapshot(userAge: 42)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: tmp, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = try decoder.decode(HealthDataSnapshot.self,
                                      from: Data(contentsOf: tmp))
        XCTAssertEqual(read.userAge, 42)

        try FileManager.default.removeItem(at: tmp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }

    // MARK: - Accept or keep

    private let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // Built once per test: each RunRecord gets its own id, so a fixture
    // rebuilt on every access would never equal itself.

    /// Last night's good sync: a run, VO₂ max, resting HR and HRV.
    private lazy var goodCache: HealthDataSnapshot = {
        let start = self.syncedAt.addingTimeInterval(-86_400)
        return HealthDataSnapshot(
            lastSyncedAt: self.syncedAt,
            runs: [RunRecord(startDate: start, endDate: start.addingTimeInterval(1_800),
                             distanceMeters: 5_000, durationSeconds: 1_800)],
            vo2Max: [VO2MaxSnapshot(date: start, value: 49.2)],
            restingHR: [RestingHeartRateSnapshot(date: start, bpm: 51)],
            hrv: [HRVSnapshot(date: start, sdnnMs: 62)],
            userAge: 33
        )
    }()

    /// What a read on a locked phone brings back: nothing.
    private lazy var emptyRead: HealthDataSnapshot =
        HealthDataSnapshot(lastSyncedAt: self.syncedAt.addingTimeInterval(6 * 3_600))

    /// A full read a few hours later, with an extra run.
    private lazy var freshRead: HealthDataSnapshot = {
        var read = self.goodCache
        read.lastSyncedAt = self.syncedAt.addingTimeInterval(6 * 3_600)
        let start = self.syncedAt.addingTimeInterval(3_600)
        read.runs.append(RunRecord(startDate: start, endDate: start.addingTimeInterval(2_400),
                                   distanceMeters: 8_000, durationSeconds: 2_400))
        return read
    }()

    private func decide(fresh: HealthDataSnapshot,
                        cached: HealthDataSnapshot?,
                        unlocked: Bool = true,
                        failed: Bool = false) -> HealthSyncResult {
        let decision = HealthSyncDecision(fresh: fresh, cached: cached,
                                          protectedDataAvailable: unlocked, readFailed: failed)
        return HealthSyncResult(fresh: fresh, cached: cached, decision: decision)
    }

    func test_lockedPhone_emptyRead_keepsTheCache() {
        // A night-time read on a locked phone brings back nothing.
        let result = decide(fresh: emptyRead, cached: goodCache, unlocked: false)
        XCTAssertEqual(result.decision, .keepCache(.protectedDataUnavailable))
        XCTAssertEqual(result.snapshot, goodCache)
        XCTAssertFalse(result.isFresh)
    }

    func test_lockedPhone_withNothingCached_leavesNothingToWorkFrom() {
        let result = decide(fresh: emptyRead, cached: nil, unlocked: false)
        XCTAssertEqual(result.decision, .keepCache(.protectedDataUnavailable))
        XCTAssertNil(result.snapshot)
        XCTAssertFalse(result.isFresh)
    }

    func test_failedRead_keepsTheCache_evenWithSomeReadings() {
        // The phone locked partway: some reads came back, others failed.
        var partial = emptyRead
        partial.hrv = [HRVSnapshot(date: syncedAt, sdnnMs: 70)]
        let result = decide(fresh: partial, cached: goodCache, failed: true)
        XCTAssertEqual(result.decision, .keepCache(.readFailed))
        XCTAssertEqual(result.snapshot, goodCache)
        XCTAssertFalse(result.isFresh)
    }

    func test_failedRead_withNothingCached_leavesNothingToWorkFrom() {
        // A partial read has no runs: working from it would make a restart day.
        var partial = emptyRead
        partial.hrv = [HRVSnapshot(date: syncedAt, sdnnMs: 70)]
        let result = decide(fresh: partial, cached: nil, failed: true)
        XCTAssertEqual(result.decision, .keepCache(.readFailed))
        XCTAssertNil(result.snapshot)
        XCTAssertFalse(result.isFresh)
    }

    func test_emptyRead_whileTheCacheHasData_keepsTheCache() {
        let result = decide(fresh: emptyRead, cached: goodCache)
        XCTAssertEqual(result.decision, .keepCache(.emptyRead))
        XCTAssertEqual(result.snapshot, goodCache)
    }

    func test_emptyRead_isBelieved_onceTheCacheIsOlderThanTheDoubtWindow() {
        // Reads that stay empty for days mean access was revoked or the data
        // deleted; the cache mustn't stand in for them for ever.
        let window = HealthSyncDecision.emptyReadDoubtedFor
        var justInside = emptyRead
        justInside.lastSyncedAt = syncedAt.addingTimeInterval(window - 60)
        XCTAssertEqual(decide(fresh: justInside, cached: goodCache).decision, .keepCache(.emptyRead))

        var pastIt = emptyRead
        pastIt.lastSyncedAt = syncedAt.addingTimeInterval(window + 60)
        let result = decide(fresh: pastIt, cached: goodCache)
        XCTAssertEqual(result.decision, .accept)
        XCTAssertEqual(result.snapshot, pastIt)
    }

    func test_lockedPhone_keepsEvenAnOldCache() {
        // The doubt window only applies to empty reads: a locked phone is
        // always temporary.
        var later = emptyRead
        later.lastSyncedAt = syncedAt.addingTimeInterval(HealthSyncDecision.emptyReadDoubtedFor * 2)
        XCTAssertEqual(decide(fresh: later, cached: goodCache, unlocked: false).decision,
                       .keepCache(.protectedDataUnavailable))
    }

    func test_readWithOnlyAnAge_countsAsEmpty() {
        var ageOnly = emptyRead
        ageOnly.userAge = 33
        XCTAssertFalse(ageOnly.hasReadings)
        XCTAssertEqual(decide(fresh: ageOnly, cached: goodCache).decision, .keepCache(.emptyRead))
    }

    func test_emptyRead_forANewRunner_isAccepted() {
        // Nothing cached yet, or a cache holding no readings: an empty read
        // is just a runner with no Health data so far.
        XCTAssertEqual(decide(fresh: emptyRead, cached: nil).decision, .accept)
        var ageOnlyCache = emptyRead
        ageOnlyCache.userAge = 40
        XCTAssertEqual(decide(fresh: emptyRead, cached: ageOnlyCache).decision, .accept)
    }

    func test_fullRead_replacesTheCache() {
        let result = decide(fresh: freshRead, cached: goodCache)
        XCTAssertEqual(result.decision, .accept)
        XCTAssertEqual(result.snapshot, freshRead)
        XCTAssertTrue(result.isFresh)
    }

    func test_readWithFewerRuns_isStillAccepted() {
        // Runs age out of the 90-day window; a smaller read isn't a failure.
        var smaller = freshRead
        smaller.runs = []
        XCTAssertEqual(decide(fresh: smaller, cached: goodCache).decision, .accept)
    }

    func test_hasReadings_ignoresAgeOnly() {
        XCTAssertFalse(HealthDataSnapshot().hasReadings)
        XCTAssertFalse(HealthDataSnapshot(userAge: 33).hasReadings)
        XCTAssertTrue(HealthDataSnapshot(latestRestingHeartRate: 51).hasReadings)
        XCTAssertTrue(goodCache.hasReadings)
    }
}
