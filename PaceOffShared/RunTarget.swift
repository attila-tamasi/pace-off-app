// RunTarget.swift
// The output of PushTargetEngine — what the app tells you to do today.

import Foundation

public struct RunTarget: Codable, Sendable, Equatable {
    /// Target distance in meters.
    public let distanceMeters: Double
    /// Tone register for the voice line.
    public let tone: Tone
    /// Days since last run as observed at compute time.
    public let daysSinceLastRun: Int
    /// VO2Max slope (ml/kg/min per week) over the last 28 days.
    public let vo2MaxSlope: Double?
    /// The 14-day median that the algorithm anchored on.
    public let baselineMeters: Double
    /// Whether the hard ceiling clamped the result.
    public let ceilingClamped: Bool
    /// Whether resting HR fatigue guard fired.
    public let fatigueGuardActive: Bool
    /// When this target was computed.
    public let computedAt: Date

    public init(
        distanceMeters: Double,
        tone: Tone,
        daysSinceLastRun: Int,
        vo2MaxSlope: Double?,
        baselineMeters: Double,
        ceilingClamped: Bool,
        fatigueGuardActive: Bool,
        computedAt: Date = Date()
    ) {
        self.distanceMeters = distanceMeters
        self.tone = tone
        self.daysSinceLastRun = daysSinceLastRun
        self.vo2MaxSlope = vo2MaxSlope
        self.baselineMeters = baselineMeters
        self.ceilingClamped = ceilingClamped
        self.fatigueGuardActive = fatigueGuardActive
        self.computedAt = computedAt
    }

    public var distanceKm: Double { distanceMeters / 1000 }
    public var baselineKm: Double { baselineMeters / 1000 }

    /// Display string like "5.2 km".
    public var formattedDistance: String {
        String(format: "%.1f km", distanceKm)
    }
}
