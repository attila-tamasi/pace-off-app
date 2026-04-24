// WorkoutSessionManager.swift
// watchOS HKWorkoutSession + HKLiveWorkoutBuilder for outdoor running.
// Captures running dynamics in real time. PRD §6.3.

import Foundation
import HealthKit
import SwiftUI

@MainActor
public final class WorkoutSessionManager: NSObject, ObservableObject {

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var distanceMeters: Double = 0
    @Published public private(set) var currentHeartRate: Double?
    @Published public private(set) var currentPace: Double?      // s/km
    @Published public private(set) var currentPower: Double?     // W
    @Published public private(set) var currentStride: Double?    // m
    @Published public private(set) var currentCadence: Double?   // spm

    @Published public var lastRun: RunRecord?

    private var timer: Timer?

    public override init() {
        super.init()
    }

    public func requestAuthorization() async {
        let toShare: Set = [HKObjectType.workoutType()]
        var toRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        ]
        if let p = HKObjectType.quantityType(forIdentifier: .runningPower) { toRead.insert(p) }
        if let s = HKObjectType.quantityType(forIdentifier: .runningStrideLength) { toRead.insert(s) }
        if let v = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) { toRead.insert(v) }
        if let g = HKObjectType.quantityType(forIdentifier: .runningGroundContactTime) { toRead.insert(g) }
        try? await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    public func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: store, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session?.delegate = self
            builder?.delegate = self

            let start = Date()
            session?.startActivity(with: start)
            builder?.beginCollection(withStart: start) { _, _ in }
            isRunning = true
            startTimer(from: start)
        } catch {
            isRunning = false
        }
    }

    public func stop() {
        session?.end()
        timer?.invalidate()
        timer = nil
    }

    private func startTimer(from start: Date) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    private func snapshotMetrics() {
        guard let builder else { return }
        let unitBPM = HKUnit.count().unitDivided(by: .minute())
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let stat = builder.statistics(for: hrType) {
            currentHeartRate = stat.mostRecentQuantity()?.doubleValue(for: unitBPM)
        }
        if let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
           let stat = builder.statistics(for: distType) {
            distanceMeters = stat.sumQuantity()?.doubleValue(for: .meter()) ?? distanceMeters
            if elapsedSeconds > 0 && distanceMeters > 0 {
                currentPace = elapsedSeconds / (distanceMeters / 1000)
            }
        }
        if let pType = HKQuantityType.quantityType(forIdentifier: .runningPower),
           let stat = builder.statistics(for: pType) {
            currentPower = stat.mostRecentQuantity()?.doubleValue(for: .watt())
        }
        if let sType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength),
           let stat = builder.statistics(for: sType) {
            currentStride = stat.mostRecentQuantity()?.doubleValue(for: .meter())
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession,
                                           didChangeTo toState: HKWorkoutSessionState,
                                           from fromState: HKWorkoutSessionState,
                                           date: Date) {
        if toState == .ended {
            Task { @MainActor in
                self.builder?.endCollection(withEnd: date) { _, _ in
                    self.builder?.finishWorkout { workout, _ in
                        Task { @MainActor in
                            self.isRunning = false
                            if let workout {
                                self.lastRun = RunRecord(
                                    startDate: workout.startDate,
                                    endDate: workout.endDate,
                                    distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                                    durationSeconds: workout.duration,
                                    activeEnergyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession,
                                           didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                           didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.snapshotMetrics() }
    }

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
