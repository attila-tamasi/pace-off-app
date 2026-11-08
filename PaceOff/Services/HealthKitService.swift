// HealthKitService.swift
// All HealthKit reads and writes for Pace Off.
// PRD §12.2 — full set of running dynamics types.

import Foundation
import HealthKit
import CoreLocation
import Observation
import UIKit

/// Whether any read of one sync failed. The reads run on the main actor,
/// so a plain flag is enough.
@MainActor
public final class HealthReadLog {
    public private(set) var failed = false

    public init() {}

    /// Notes a query's error. Only a locked store counts: Health's store is
    /// encrypted while the phone is locked, and every read fails with
    /// `errorDatabaseInaccessible`. The other errors (no data, authorization
    /// not asked yet) mean there's nothing to read, like an empty result, and
    /// a retry doesn't clear them, so counting them would freeze the cache.
    func note(_ error: Error?) {
        guard let healthError = error as? HKError,
              healthError.code == .errorDatabaseInaccessible
        else { return }
        failed = true
    }
}

@MainActor
@Observable
public final class HealthKitService {

    public static let shared = HealthKitService()

    @ObservationIgnored private let store = HKHealthStore()

    public private(set) var isAuthorized: Bool = false
    public private(set) var lastError: String?

    private init() {}

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKSeriesType.workoutRoute(),
        ]
        // Running dynamics — guarded because identifiers vary by SDK version
        if let power = HKObjectType.quantityType(forIdentifier: .runningPower) { types.insert(power) }
        if let stride = HKObjectType.quantityType(forIdentifier: .runningStrideLength) { types.insert(stride) }
        if let vert = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) { types.insert(vert) }
        if let gct = HKObjectType.quantityType(forIdentifier: .runningGroundContactTime) { types.insert(gct) }
        if let speed = HKObjectType.quantityType(forIdentifier: .runningSpeed) { types.insert(speed) }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    // MARK: - Authorization

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization() async {
        guard isHealthDataAvailable else {
            lastError = "HealthKit is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
            isAuthorized = false
        }
    }

    // MARK: - High-level sync

    /// Pull every value the UI consumes, in parallel, and save the result to
    /// `HealthDataCache` when it can be trusted (`HealthSyncDecision`). The
    /// result carries the snapshot to render, fresh or kept, so the caller
    /// doesn't need a second disk read.
    ///
    /// On a locked phone nothing is read: Health's store stays encrypted
    /// until the runner unlocks, so the cache is kept as it is.
    ///
    /// Safe to call concurrently — the cache's actor serializes the final
    /// write — but in practice the caller (TodayViewModel, the BG refresh
    /// task) is the only thing invoking it.
    @discardableResult
    public func syncAll(
        runsDaysBack: Int = 90,
        vo2DaysBack: Int = 90,
        restingHRDaysBack: Int = 14,
        hrvDaysBack: Int = 35
    ) async -> HealthSyncResult {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let unlockedAtStart = UIApplication.shared.isProtectedDataAvailable

        var fresh = HealthDataSnapshot(
            lastSyncedAt: now,
            runsWindowDays: runsDaysBack,
            vo2WindowDays: vo2DaysBack,
            restingHRWindowDays: restingHRDaysBack,
            hrvWindowDays: hrvDaysBack
        )
        let log = HealthReadLog()

        if unlockedAtStart {
            // Parallelise the independent fetches.
            async let runs = fetchRuns(daysBack: runsDaysBack, log: log)
            async let vo2  = fetchVO2Max(daysBack: vo2DaysBack, log: log)
            async let rhr  = fetchRestingHeartRate(daysBack: restingHRDaysBack, log: log)
            async let hrvS = fetchHRVSeries(daysBack: hrvDaysBack, log: log)
            async let hrv  = fetchHRV(on: yesterday, log: log)
            async let yAvg = fetchAverageHeartRate(on: yesterday, log: log)
            async let lRHR = fetchLatestRestingHeartRate(asOf: now, log: log)

            fresh.runs = await runs
            fresh.vo2Max = await vo2
            fresh.restingHR = await rhr
            fresh.hrv = await hrvS
            fresh.yesterdayHRV = await hrv
            fresh.yesterdayAvgHeartRate = await yAvg
            fresh.latestRestingHeartRate = await lRHR
            fresh.userAge = userAge()
        }

        // Loaded after the reads, so a save by a sync that ran meanwhile
        // counts. The phone can also lock while the reads run: check again.
        let cached = await HealthDataCache.shared.load()
        let decision = HealthSyncDecision(
            fresh: fresh,
            cached: cached,
            protectedDataAvailable: unlockedAtStart && UIApplication.shared.isProtectedDataAvailable,
            readFailed: log.failed
        )
        if decision == .accept {
            await HealthDataCache.shared.save(fresh)
        }
        return HealthSyncResult(fresh: fresh, cached: cached, decision: decision)
    }

    // MARK: - Reads

    /// All running workouts in the trailing window.
    public func fetchRuns(daysBack: Int = 90, log: HealthReadLog? = nil) async -> [RunRecord] {
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, datePredicate])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                let workouts = (samples as? [HKWorkout]) ?? []
                Task { @MainActor in
                    log?.note(error)
                    var records: [RunRecord] = []
                    for workout in workouts {
                        let record = await self.toRunRecord(workout, log: log)
                        records.append(record)
                    }
                    continuation.resume(returning: records)
                }
            }
            store.execute(query)
        }
    }

    public func fetchVO2Max(daysBack: Int = 90, log: HealthReadLog? = nil) async -> [VO2MaxSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit(from: "ml/kg*min")

        let (snapshots, failure): ([VO2MaxSnapshot], Error?) = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                let values: [VO2MaxSnapshot] = (samples as? [HKQuantitySample] ?? []).map {
                    VO2MaxSnapshot(date: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: (values, error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return snapshots
    }

    public func fetchRestingHeartRate(daysBack: Int = 14, log: HealthReadLog? = nil) async -> [RestingHeartRateSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let (snapshots, failure): ([RestingHeartRateSnapshot], Error?) = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                let values: [RestingHeartRateSnapshot] = (samples as? [HKQuantitySample] ?? []).map {
                    RestingHeartRateSnapshot(date: $0.endDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: (values, error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return snapshots
    }

    /// All HRV (SDNN) samples in the trailing window, in milliseconds.
    /// The ReadinessEngine collapses these to per-day means and builds its
    /// rolling baseline, so we hand over raw samples rather than aggregates.
    public func fetchHRVSeries(daysBack: Int = 35, log: HealthReadLog? = nil) async -> [HRVSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit.secondUnit(with: .milli)

        let (snapshots, failure): ([HRVSnapshot], Error?) = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                let values: [HRVSnapshot] = (samples as? [HKQuantitySample] ?? []).map {
                    HRVSnapshot(date: $0.endDate, sdnnMs: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: (values, error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return snapshots
    }

    // MARK: - Daily recovery snapshot

    /// Average over all heart-rate samples for the calendar day containing
    /// `referenceDate`. Returns nil if HealthKit has nothing recorded for
    /// that day. Uses statistics aggregation so it's a single fast query.
    public func fetchAverageHeartRate(on referenceDate: Date, log: HealthReadLog? = nil) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let (average, failure): (Double?, Error?) = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                continuation.resume(returning: (stats?.averageQuantity()?.doubleValue(for: unit), error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return average
    }

    /// Average HRV (SDNN, in milliseconds) over the calendar day containing
    /// `referenceDate`. Apple Watch typically records HRV during sleep, so
    /// "yesterday's HRV" is usually a single overnight reading. Returns nil
    /// when no samples exist or permission was denied.
    public func fetchHRV(on referenceDate: Date, log: HealthReadLog? = nil) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let unit = HKUnit.secondUnit(with: .milli)

        let (average, failure): (Double?, Error?) = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                continuation.resume(returning: (stats?.averageQuantity()?.doubleValue(for: unit), error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return average
    }

    /// Most-recent resting heart rate before or on `referenceDate`. Apple
    /// Watch updates RHR daily but not always on the same calendar day, so
    /// we walk back up to 7 days to find the freshest reading rather than
    /// querying a single day and showing "—" when it's a day stale.
    public func fetchLatestRestingHeartRate(asOf referenceDate: Date, log: HealthReadLog? = nil) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let start = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate)
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: referenceDate, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let (latest, failure): (Double?, Error?) = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: (value, error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return latest
    }

    // MARK: - Workout normalization

    private func toRunRecord(_ workout: HKWorkout, log: HealthReadLog?) async -> RunRecord {
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let energyType = HKQuantityType(.activeEnergyBurned)
        let energy = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let pace: Double? = (distance > 0)
            ? workout.duration / (distance / 1000)
            : nil

        let avgHR = await averageQuantity(.heartRate, for: workout, unit: HKUnit.count().unitDivided(by: .minute()), log: log)
        let avgPower = await averageQuantity(.runningPower, for: workout, unit: .watt(), log: log)
        let avgStride = await averageQuantity(.runningStrideLength, for: workout, unit: .meter(), log: log)
        let avgVert = await averageQuantity(.runningVerticalOscillation, for: workout, unit: .meterUnit(with: .centi), log: log)
        let avgGCT = await averageQuantity(.runningGroundContactTime, for: workout, unit: .secondUnit(with: .milli), log: log)
        // Cadence (steps per minute): stepCount is a CUMULATIVE quantity type,
        // so we must use .cumulativeSum (NOT .discreteAverage — that crashes
        // with HKErrorInvalidArgument) and convert to a per-minute rate.
        let totalSteps = await cumulativeSum(.stepCount, for: workout, unit: .count(), log: log)
        let durationMinutes = workout.duration / 60.0
        let avgCadence: Double? = (totalSteps != nil && durationMinutes > 0)
            ? totalSteps! / durationMinutes
            : nil

        return RunRecord(
            startDate: workout.startDate,
            endDate: workout.endDate,
            distanceMeters: distance,
            durationSeconds: workout.duration,
            activeEnergyKcal: energy,
            averageHeartRate: avgHR,
            averagePace: pace,
            averagePowerWatts: avgPower,
            averageStrideLengthMeters: avgStride,
            averageVerticalOscillationCm: avgVert,
            averageGroundContactMs: avgGCT,
            averageCadenceSpm: avgCadence
        )
    }

    private func averageQuantity(_ id: HKQuantityTypeIdentifier, for workout: HKWorkout, unit: HKUnit, log: HealthReadLog?) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        // Guard against passing a cumulative type (e.g. stepCount, distance, energy)
        // to .discreteAverage — HealthKit treats that as a programmer error and traps.
        guard type.aggregationStyle == .discreteArithmetic else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let (average, failure): (Double?, Error?) = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                continuation.resume(returning: (stats?.averageQuantity()?.doubleValue(for: unit), error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return average
    }

    /// Sum of a CUMULATIVE quantity (stepCount, distance, energy) over a workout.
    /// Use this for any type whose `aggregationStyle == .cumulative`.
    private func cumulativeSum(_ id: HKQuantityTypeIdentifier, for workout: HKWorkout, unit: HKUnit, log: HealthReadLog?) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        guard type.aggregationStyle == .cumulative else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let (sum, failure): (Double?, Error?) = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                continuation.resume(returning: (stats?.sumQuantity()?.doubleValue(for: unit), error))
            }
            store.execute(query)
        }
        log?.note(failure)
        return sum
    }

    // MARK: - Workout routes

    /// Fetch the GPS route for today's longest running workout, if one exists.
    /// Returns an empty array when: (a) no run happened today, (b) route
    /// permission wasn't granted, or (c) the run was indoors/treadmill and
    /// therefore has no route attached.
    public func fetchTodayRunRoute() async -> [CLLocationCoordinate2D] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let runPred = HKQuery.predicateForWorkouts(with: .running)
        let datePred = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [runPred, datePred])

        // 1) Find today's running workouts (pick the longest)
        let workout: HKWorkout? = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: combined,
                limit: 10,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let longest = workouts.max {
                    ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                    ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
                }
                continuation.resume(returning: longest)
            }
            store.execute(q)
        }
        guard let workout else { return [] }
        return await routeCoordinates(for: workout)
    }

    /// Fetch the GPS route for an arbitrary RunRecord (used by RunDetailView).
    /// We look up the matching HKWorkout by its start date — runs are uniquely
    /// keyed by start time within a tight tolerance. Returns an empty array
    /// when the run has no attached route (treadmill, permission denied, or
    /// the workout was already evicted from HealthKit).
    public func fetchRunRoute(for record: RunRecord) async -> [CLLocationCoordinate2D] {
        guard let workout = await matchingWorkout(for: record) else { return [] }
        return await routeCoordinates(for: workout)
    }

    /// Stream all `CLLocationCoordinate2D` samples out of every workout-route
    /// series attached to the given workout, sorted by timestamp.
    private func routeCoordinates(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        let routeType = HKSeriesType.workoutRoute()
        let routePred = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let q = HKAnchoredObjectQuery(
                type: routeType,
                predicate: routePred,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(q)
        }
        guard !routes.isEmpty else { return [] }

        var all: [CLLocation] = []
        for route in routes {
            let locations: [CLLocation] = await withCheckedContinuation { continuation in
                // HealthKit serializes route-query callbacks on its own queue,
                // so a single mutable accumulator is safe — but Swift 6 won't
                // let us capture `var` in the @Sendable closure. Wrap it in a
                // class (@unchecked Sendable) to make the intent explicit.
                final class LocationCollector: @unchecked Sendable {
                    var items: [CLLocation] = []
                }
                let collector = LocationCollector()
                let q = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                    if let batch { collector.items.append(contentsOf: batch) }
                    if done { continuation.resume(returning: collector.items) }
                }
                store.execute(q)
            }
            all.append(contentsOf: locations)
        }

        return all
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.coordinate)
    }

    /// Fetch the timestamped route points for a given RunRecord — same
    /// matching logic as `fetchRunRoute` but returns the raw `CLLocation`
    /// values so callers can compute per-km splits from timestamps + coords.
    public func fetchRunLocations(for record: RunRecord) async -> [CLLocation] {
        guard let workout = await matchingWorkout(for: record) else { return [] }
        return await routeLocations(for: workout)
    }

    /// What Health keeps on the workout behind `record`: indoor or outdoor,
    /// its own elevation gain, the weather, steps and average METs. Nil when
    /// the workout can't be found; each value is nil when it isn't stored.
    public func fetchWorkoutExtras(for record: RunRecord) async -> WorkoutExtras? {
        guard let workout = await matchingWorkout(for: record) else { return nil }
        let metadata = workout.metadata ?? [:]

        /// A metadata quantity in `unit`, or nil when it's missing or in a
        /// unit that doesn't convert (`doubleValue(for:)` would trap).
        func quantity(_ key: String, _ unit: HKUnit) -> Double? {
            guard let q = metadata[key] as? HKQuantity, q.is(compatibleWith: unit) else { return nil }
            return q.doubleValue(for: unit)
        }

        let metsUnit = HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour()))
        return WorkoutExtras(
            indoor: (metadata[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue,
            elevationGainMeters: quantity(HKMetadataKeyElevationAscended, .meter()),
            elevationLossMeters: quantity(HKMetadataKeyElevationDescended, .meter()),
            temperatureCelsius: quantity(HKMetadataKeyWeatherTemperature, .degreeCelsius()),
            // Health stores humidity as a percent quantity: 0.65 is 65%.
            humidityPercent: quantity(HKMetadataKeyWeatherHumidity, .percent()).map { $0 * 100 },
            steps: await stepCount(from: workout.startDate, to: workout.endDate),
            averageMETs: quantity(HKMetadataKeyAverageMETs, metsUnit)
        )
    }

    /// Steps taken between two moments, from every source, merged the way
    /// Health shows them. Step samples usually aren't attached to the
    /// workout itself, so they're found by time, not by workout.
    private func stepCount(from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(query)
        }
    }

    /// The running workout `record` was made from: the one starting
    /// closest to it within a minute either side.
    private func matchingWorkout(for record: RunRecord) async -> HKWorkout? {
        let windowStart = record.startDate.addingTimeInterval(-60)
        let windowEnd = record.endDate.addingTimeInterval(60)

        let runPred = HKQuery.predicateForWorkouts(with: .running)
        let datePred = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [runPred, datePred])

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: combined,
                limit: 20,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                let match = workouts.min { lhs, rhs in
                    abs(lhs.startDate.timeIntervalSince(record.startDate)) <
                    abs(rhs.startDate.timeIntervalSince(record.startDate))
                }
                continuation.resume(returning: match)
            }
            store.execute(q)
        }
    }

    /// Timestamped `CLLocation` samples from a workout's attached route
    /// series, sorted chronologically. Shares plumbing with
    /// `routeCoordinates(for:)` but preserves the full `CLLocation`.
    private func routeLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routeType = HKSeriesType.workoutRoute()
        let routePred = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let q = HKAnchoredObjectQuery(
                type: routeType,
                predicate: routePred,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(q)
        }
        guard !routes.isEmpty else { return [] }

        var all: [CLLocation] = []
        for route in routes {
            let locations: [CLLocation] = await withCheckedContinuation { continuation in
                final class LocationCollector: @unchecked Sendable {
                    var items: [CLLocation] = []
                }
                let collector = LocationCollector()
                let q = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                    if let batch { collector.items.append(contentsOf: batch) }
                    if done { continuation.resume(returning: collector.items) }
                }
                store.execute(q)
            }
            all.append(contentsOf: locations)
        }

        return all.sorted { $0.timestamp < $1.timestamp }
    }

    /// Timestamped heart-rate samples across a date range — the raw feed
    /// the pace-decay analyser averages into per-km HR values.
    public func fetchHeartRateSamples(from startDate: Date, to endDate: Date)
        async -> [(date: Date, bpm: Double)]
    {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let list = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: list)
            }
            store.execute(query)
        }
    }

    // MARK: - User profile (read-only characteristics)

    /// User's age in whole years, derived from `HKCharacteristicTypeIdentifier.dateOfBirth`.
    /// Returns nil if the user hasn't entered DOB in the Health app or hasn't authorized read access.
    public func userAge(on referenceDate: Date = Date()) -> Int? {
        let components: DateComponents
        do {
            components = try store.dateOfBirthComponents()
        } catch {
            return nil
        }
        guard let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year
    }

    // MARK: - Observers (background delivery)

    @ObservationIgnored private var observersStarted = false

    /// Watches for new workouts and VO₂ max readings, with background
    /// delivery, so a finished run reaches Pace Off without the app being
    /// opened. `onUpdate` runs for each change and gets a completion to
    /// call once the change is handled, as HealthKit requires. Started at
    /// most once per launch; call it at launch (once onboarding has asked
    /// for Health access) so iOS can wake the app for deliveries.
    public func startObservingHealthUpdates(
        onUpdate: @escaping @Sendable (_ done: HealthUpdateCompletion) -> Void
    ) {
        guard !observersStarted else { return }
        observersStarted = true
        var types: [(HKSampleType, HKUpdateFrequency)] = [(HKObjectType.workoutType(), .immediate)]
        if let vo2 = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.append((vo2, .hourly))
        }
        for (type, frequency) in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                let done = HealthUpdateCompletion(completion)
                guard error == nil else {
                    done()
                    return
                }
                onUpdate(done)
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }
}

/// HealthKit's "handled" callback for one observer delivery, carried to
/// wherever the delivery is handled and called once that's done.
public final class HealthUpdateCompletion: @unchecked Sendable {
    private let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    public func callAsFunction() {
        body()
    }
}
