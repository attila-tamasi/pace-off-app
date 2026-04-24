// RunRecord.swift
// A normalized representation of a single running workout from HealthKit.
// Includes running dynamics (PRD §6.3).

import Foundation

public struct RunRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let distanceMeters: Double
    public let durationSeconds: Double
    public let activeEnergyKcal: Double?
    public let averageHeartRate: Double?       // bpm
    public let averagePace: Double?            // seconds per kilometer

    // Running dynamics — Apple Watch Series 8+ / SE 2+
    public let averagePowerWatts: Double?
    public let averageStrideLengthMeters: Double?
    public let averageVerticalOscillationCm: Double?
    public let averageGroundContactMs: Double?
    public let averageCadenceSpm: Double?      // steps per minute

    // Pace Off context — non-HK fields. Currently transient (computed at read time
    // from the day's RunTarget cached in App-Group UserDefaults). If we ever need
    // historical "did the user hit the target" trends, mirror these into SwiftData.
    public let targetDistanceMeters: Double?   // what the app asked for that day
    public let hitTarget: Bool?                // whether distance >= target * 0.95

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        activeEnergyKcal: Double? = nil,
        averageHeartRate: Double? = nil,
        averagePace: Double? = nil,
        averagePowerWatts: Double? = nil,
        averageStrideLengthMeters: Double? = nil,
        averageVerticalOscillationCm: Double? = nil,
        averageGroundContactMs: Double? = nil,
        averageCadenceSpm: Double? = nil,
        targetDistanceMeters: Double? = nil,
        hitTarget: Bool? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.activeEnergyKcal = activeEnergyKcal
        self.averageHeartRate = averageHeartRate
        self.averagePace = averagePace
        self.averagePowerWatts = averagePowerWatts
        self.averageStrideLengthMeters = averageStrideLengthMeters
        self.averageVerticalOscillationCm = averageVerticalOscillationCm
        self.averageGroundContactMs = averageGroundContactMs
        self.averageCadenceSpm = averageCadenceSpm
        self.targetDistanceMeters = targetDistanceMeters
        self.hitTarget = hitTarget
    }

    public var distanceKm: Double { distanceMeters / 1000 }

    /// Pace formatted as mm:ss per km, e.g. "5:24/km"
    public var formattedPace: String {
        guard let pace = averagePace, pace > 0 else { return "—" }
        let mins = Int(pace) / 60
        let secs = Int(pace) % 60
        return String(format: "%d:%02d/km", mins, secs)
    }

    public var formattedDuration: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
