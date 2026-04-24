// HealthKitService.swift
// All HealthKit reads and writes for Pace Off.
// PRD §12.2 — full set of running dynamics types.

import Foundation
import HealthKit

@MainActor
public final class HealthKitService: ObservableObject {

    public static let shared = HealthKitService()

    private let store = HKHealthStore()

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var lastError: String?

    private init() {}

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
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
