// HealthKitService.swift
// All HealthKit reads and writes for Pace Off.
// PRD §12.2 — full set of running dynamics types.

import Foundation
import HealthKit
import CoreLocation
import Observation

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

    /// Pull every value the UI consumes, in parallel, and write the result
    /// to `HealthDataCache`. Returns the freshly persisted snapshot so the
    /// caller can render it without doing a second disk read.
    ///
    /// Safe to call concurrently — the cache's actor serializes the final
    /// write — but in practice the caller (TodayViewModel, the BG refresh
    /// task) is the only thing invoking it.
    @discardableResult
    public func syncAll(
        runsDaysBack: Int = 90,
        vo2DaysBack: Int = 90,
        restingHRDaysBack: Int = 14,
        hrvDaysBack: Int = 30
    ) async -> HealthDataSnapshot {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        // Parallelise the independent fetches.
        async let runs = fetchRuns(daysBack: runsDaysBack)
        async let vo2  = fetchVO2Max(daysBack: vo2DaysBack)
        async let rhr  = fetchRestingHeartRate(daysBack: restingHRDaysBack)
        async let hrv  = fetchHRV(on: yesterday)
        async let hrvHist = fetchHRVHistory(daysBack: hrvDaysBack)
        async let yAvg = fetchAverageHeartRate(on: yesterday)
        async let lRHR = fetchLatestRestingHeartRate(asOf: now)

        let snapshot = HealthDataSnapshot(
            schemaVersion: HealthDataSnapshot.currentSchema,
            lastSyncedAt: now,
            runsWindowDays: runsDaysBack,
            vo2WindowDays: vo2DaysBack,
            restingHRWindowDays: restingHRDaysBack,
            hrvWindowDays: hrvDaysBack,
            runs: await runs,
            vo2Max: await vo2,
            restingHR: await rhr,
            hrvHistory: await hrvHist,
            yesterdayHRV: await hrv,
            yesterdayAvgHeartRate: await yAvg,
            latestRestingHeartRate: await lRHR,
            userAge: userAge()
        )

        await HealthDataCache.shared.save(snapshot)
        return snapshot
    }

    // MARK: - Reads

    /// All running workouts in the trailing window.
    public func fetchRuns(daysBack: Int = 90) async -> [RunRecord] {
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
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                Task { @MainActor in
                    var records: [RunRecord] = []
                    for workout in workouts {
                        let record = await self.toRunRecord(workout)
                        records.append(record)
                    }
                    continuation.resume(returning: records)
                }
            }
            store.execute(query)
        }
    }

    public func fetchVO2Max(daysBack: Int = 90) async -> [VO2MaxSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit(from: "ml/kg*min")

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let snapshots: [VO2MaxSnapshot] = (samples as? [HKQuantitySample] ?? []).map {
                    VO2MaxSnapshot(date: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: snapshots)
            }
            store.execute(query)
        }
    }

    public func fetchRestingHeartRate(daysBack: Int = 14) async -> [RestingHeartRateSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let snapshots: [RestingHeartRateSnapshot] = (samples as? [HKQuantitySample] ?? []).map {
                    RestingHeartRateSnapshot(date: $0.endDate, bpm: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: snapshots)
            }
            store.execute(query)
        }
    }

    // MARK: - Daily recovery snapshot

    /// Average over all heart-rate samples for the calendar day containing
    /// `referenceDate`. Returns nil if HealthKit has nothing recorded for
    /// that day. Uses statistics aggregation so it's a single fast query.
    public func fetchAverageHeartRate(on referenceDate: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Average HRV (SDNN, in milliseconds) over the calendar day containing
    /// `referenceDate`. Apple Watch typically records HRV during sleep, so
    /// "yesterday's HRV" is usually a single overnight reading. Returns nil
    /// when no samples exist or permission was denied.
    public func fetchHRV(on referenceDate: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let unit = HKUnit.secondUnit(with: .milli)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Trailing daily HRV (SDNN, ms) samples for the last `daysBack` days.
    /// One entry per calendar day that has data — HealthKit typically has
    /// one overnight SDNN reading per night from Apple Watch. Used to build
    /// the ReadinessEngine's rolling personal baseline.
    public func fetchHRVHistory(daysBack: Int = 30) async -> [HRVSnapshot] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let unit = HKUnit.secondUnit(with: .milli)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                // Collapse to one value per calendar day (average when there
                // are multiple readings — rare but happens after naps).
                let cal = Calendar.current
                var byDay: [Date: [Double]] = [:]
                for sample in (samples as? [HKQuantitySample] ?? []) {
                    let day = cal.startOfDay(for: sample.endDate)
                    byDay[day, default: []].append(sample.quantity.doubleValue(for: unit))
                }
                let snapshots = byDay
                    .map { HRVSnapshot(date: $0.key, ms: $0.value.reduce(0, +) / Double($0.value.count)) }
                    .sorted { $0.date < $1.date }
                continuation.resume(returning: snapshots)
            }
            store.execute(query)
        }
    }

    /// Most-recent resting heart rate before or on `referenceDate`. Apple
    /// Watch updates RHR daily but not always on the same calendar day, so
    /// we walk back up to 7 days to find the freshest reading rather than
    /// querying a single day and showing "—" when it's a day stale.
    public func fetchLatestRestingHeartRate(asOf referenceDate: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
              let start = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate)
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: referenceDate, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Workout normalization

    private func toRunRecord(_ workout: HKWorkout) async -> RunRecord {
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let energyType = HKQuantityType(.activeEnergyBurned)
        let energy = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let pace: Double? = (distance > 0)
            ? workout.duration / (distance / 1000)
            : nil

        let avgHR = await averageQuantity(.heartRate, for: workout, unit: HKUnit.count().unitDivided(by: .minute()))
        let avgPower = await averageQuantity(.runningPower, for: workout, unit: .watt())
        let avgStride = await averageQuantity(.runningStrideLength, for: workout, unit: .meter())
        let avgVert = await averageQuantity(.runningVerticalOscillation, for: workout, unit: .meterUnit(with: .centi))
        let avgGCT = await averageQuantity(.runningGroundContactTime, for: workout, unit: .secondUnit(with: .milli))
        // Cadence (steps per minute): stepCount is a CUMULATIVE quantity type,
        // so we must use .cumulativeSum (NOT .discreteAverage — that crashes
        // with HKErrorInvalidArgument) and convert to a per-minute rate.
        let totalSteps = await cumulativeSum(.stepCount, for: workout, unit: .count())
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

    private func averageQuantity(_ id: HKQuantityTypeIdentifier, for workout: HKWorkout, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        // Guard against passing a cumulative type (e.g. stepCount, distance, energy)
        // to .discreteAverage — HealthKit treats that as a programmer error and traps.
        guard type.aggregationStyle == .discreteArithmetic else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Sum of a CUMULATIVE quantity (stepCount, distance, energy) over a workout.
    /// Use this for any type whose `aggregationStyle == .cumulative`.
    private func cumulativeSum(_ id: HKQuantityTypeIdentifier, for workout: HKWorkout, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        guard type.aggregationStyle == .cumulative else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
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
        // Look up workouts in a ±60s window around the record's start date.
        // HealthKit queries are exclusive of `end`, so we widen by one second.
        let windowStart = record.startDate.addingTimeInterval(-60)
        let windowEnd = record.endDate.addingTimeInterval(60)

        let runPred = HKQuery.predicateForWorkouts(with: .running)
        let datePred = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [runPred, datePred])

        let workout: HKWorkout? = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: combined,
                limit: 20,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                // Match by start-date proximity (within 2s) — covers any drift
                // between the record we surfaced and HealthKit's stored sample.
                let match = workouts.min { lhs, rhs in
                    abs(lhs.startDate.timeIntervalSince(record.startDate)) <
                    abs(rhs.startDate.timeIntervalSince(record.startDate))
                }
                continuation.resume(returning: match)
            }
            store.execute(q)
        }
        guard let workout else { return [] }
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

    // MARK: - Observer (background VO2Max updates)

    public func startObservingVO2Max(handler: @escaping @Sendable () -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, _, error in
            guard error == nil else { return }
            handler()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }
}
