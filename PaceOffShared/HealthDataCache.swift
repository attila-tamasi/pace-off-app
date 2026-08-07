// HealthDataCache.swift
// Persistent on-device cache of the HealthKit reads Pace Off depends on.
//
// We hit HealthKit on every cold launch and every Today refresh. The data
// changes slowly (overnight HRV, daily VO₂ max, occasional runs), so we
// snapshot the latest successful read to disk and let views render that
// instantly, then kick off a fresh sync in the background.
//
// Storage:
// - JSON blob in the App Group container (not UserDefaults — a 90-day run
//   history can be tens of KB and pushing that through `setData` thrashes
//   the prefs store).
// - Filename `health-cache.json`, sibling of `profile-photo.jpg`.
//
// Concurrency: a value type, written/read off-thread via Swift's async file
// IO. The shared service is an actor so callers can't race writes.

import Foundation

// MARK: - Snapshot

/// A single point-in-time snapshot of every Health value the UI consumes.
/// Persisted as JSON. Versioned via `schemaVersion` so a future change in
/// shape can choose to nuke the cache rather than crash decoding.
public struct HealthDataSnapshot: Codable, Sendable, Equatable {
    /// Bumped whenever the encoded shape changes incompatibly.
    /// v2: added the HRV series for the readiness traffic light.
    public static let currentSchema: Int = 2

    public var schemaVersion: Int
    public var lastSyncedAt: Date

    // Window descriptors so callers know what `runs` and `vo2Max` cover.
    public var runsWindowDays: Int
    public var vo2WindowDays: Int
    public var restingHRWindowDays: Int
    public var hrvWindowDays: Int

    // Bulk series.
    public var runs: [RunRecord]
    public var vo2Max: [VO2MaxSnapshot]
    public var restingHR: [RestingHeartRateSnapshot]
    public var hrv: [HRVSnapshot]

    // Recovery snapshot — small scalars, all optional because HealthKit may
    // have nothing recorded for the day.
    public var yesterdayHRV: Double?
    public var yesterdayAvgHeartRate: Double?
    public var latestRestingHeartRate: Double?

    // Cached age, since HealthKit's dateOfBirth read is synchronous but
    // requires authorization; surfacing the last-known value lets the UI
    // render through permission re-prompts.
    public var userAge: Int?

    public init(
        schemaVersion: Int = HealthDataSnapshot.currentSchema,
        lastSyncedAt: Date = Date(),
        runsWindowDays: Int = 90,
        vo2WindowDays: Int = 90,
        restingHRWindowDays: Int = 14,
        hrvWindowDays: Int = 35,
        runs: [RunRecord] = [],
        vo2Max: [VO2MaxSnapshot] = [],
        restingHR: [RestingHeartRateSnapshot] = [],
        hrv: [HRVSnapshot] = [],
        yesterdayHRV: Double? = nil,
        yesterdayAvgHeartRate: Double? = nil,
        latestRestingHeartRate: Double? = nil,
        userAge: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.lastSyncedAt = lastSyncedAt
        self.runsWindowDays = runsWindowDays
        self.vo2WindowDays = vo2WindowDays
        self.restingHRWindowDays = restingHRWindowDays
        self.hrvWindowDays = hrvWindowDays
        self.runs = runs
        self.vo2Max = vo2Max
        self.restingHR = restingHR
        self.hrv = hrv
        self.yesterdayHRV = yesterdayHRV
        self.yesterdayAvgHeartRate = yesterdayAvgHeartRate
        self.latestRestingHeartRate = latestRestingHeartRate
        self.userAge = userAge
    }

    /// True if no real sync has happened yet (the snapshot was constructed
    /// from defaults). Lets callers tell "have I ever synced?" apart from
    /// "I synced two seconds ago and have no runs".
    public var isEmpty: Bool {
        runs.isEmpty && vo2Max.isEmpty && restingHR.isEmpty && hrv.isEmpty
            && yesterdayHRV == nil && yesterdayAvgHeartRate == nil
            && latestRestingHeartRate == nil && userAge == nil
    }

    /// Whether the snapshot is older than `maxAge` and should be refreshed.
    public func isStale(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastSyncedAt) > maxAge
    }
}

// MARK: - Cache service

/// Reads and writes `HealthDataSnapshot` in the App Group container.
/// Singleton actor — write contention is rare but possible (foreground
/// refresh + BGAppRefreshTask landing at the same moment), so we serialize.
public actor HealthDataCache {

    public static let shared = HealthDataCache()

    /// Filename inside the App Group container.
    public static let filename = "health-cache.json"

    private let fileManager = FileManager.default

    public init() {}

    /// URL of the cache file inside the shared App Group container.
    /// Nil when the App Group entitlement is missing (e.g. unit tests or
    /// the simulator running without the entitlement provisioned).
    public var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(Self.filename)
    }

    // MARK: - Read

    /// Load the most recent snapshot from disk. Returns nil when there's no
    /// snapshot yet, the file is unreadable, or the schema version doesn't
    /// match (in which case we treat the file as if it never existed and let
    /// the next sync rebuild it).
    public func load() -> HealthDataSnapshot? {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder.healthCache.decode(HealthDataSnapshot.self, from: data)
            guard snapshot.schemaVersion == HealthDataSnapshot.currentSchema else { return nil }
            return snapshot
        } catch {
            return nil
        }
    }

    // MARK: - Write

    /// Persist a snapshot. Atomic write so a crash mid-write doesn't leave
    /// a half-encoded file behind.
    @discardableResult
    public func save(_ snapshot: HealthDataSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        do {
            let data = try JSONEncoder.healthCache.encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Convenience: mutate the current snapshot (or start from a fresh one)
    /// and write it back in a single critical section.
    @discardableResult
    public func update(_ mutate: (inout HealthDataSnapshot) -> Void) -> HealthDataSnapshot {
        var working = load() ?? HealthDataSnapshot()
        mutate(&working)
        working.lastSyncedAt = Date()
        save(working)
        return working
    }

    // MARK: - Clear

    /// Remove the cache file from disk. Called on sign-out.
    public func clear() {
        guard let url = fileURL else { return }
        try? fileManager.removeItem(at: url)
    }
}

// MARK: - Codable plumbing

private extension JSONEncoder {
    /// ISO-8601 dates with fractional seconds so Watch & widget round-trip
    /// identically to the iPhone-side encoder.
    static let healthCache: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let healthCache: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
