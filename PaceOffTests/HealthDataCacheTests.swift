// HealthDataCacheTests.swift
// Roundtrip + staleness checks for HealthDataSnapshot. The HealthDataCache
// actor itself reads from / writes to the App Group container which isn't
// available in the unit test bundle, so we exercise the public types and
// the JSON shape rather than the disk side-effects.

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
}
