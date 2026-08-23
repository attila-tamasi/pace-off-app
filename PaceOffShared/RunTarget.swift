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
    /// Whether the readiness traffic light reduced the distance (red caps
    /// hard, yellow holds the baseline). Optional so RunTarget JSON cached
    /// before this field existed still decodes — nil means "unknown".
    public let readinessCapApplied: Bool?
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
        readinessCapApplied: Bool? = nil,
        computedAt: Date = Date()
    ) {
        self.distanceMeters = distanceMeters
        self.tone = tone
        self.daysSinceLastRun = daysSinceLastRun
        self.vo2MaxSlope = vo2MaxSlope
        self.baselineMeters = baselineMeters
        self.ceilingClamped = ceilingClamped
        self.fatigueGuardActive = fatigueGuardActive
        self.readinessCapApplied = readinessCapApplied
        self.computedAt = computedAt
    }

    public var distanceKm: Double { distanceMeters / 1000 }
    public var baselineKm: Double { baselineMeters / 1000 }

    /// The user-facing target — always rounded **up** to the next whole km.
    /// 7.7 km → 8 km. 5.0 km → 5 km. The engine emits a precise number, but
    /// the UX tells the user a clean integer, and "did I hit the target" is
    /// judged against this rounded value to avoid mismatch.
    public var displayedDistanceKm: Int {
        Int(ceil(distanceKm))
    }

    /// `displayedDistanceKm` re-expressed in meters. Use this when comparing
    /// against actual run distance for "target hit" checks.
    public var displayedDistanceMeters: Double {
        Double(displayedDistanceKm) * 1000.0
    }

    /// Display string — whole km, no decimal, e.g. "8 km".
    public var formattedDistance: String {
        "\(displayedDistanceKm) km"
    }
}
