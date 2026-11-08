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
    /// VO2Max slope (ml/kg/min per week) over the last 28 days, when the
    /// trend is beyond noise (`PushTargetEngine.vo2MaxTrend`); nil when
    /// there's too little data or the change is within noise.
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
    /// The tightest upper bound on today's distance: the 1.4× hard ceiling,
    /// or a lower cap when a guard applied (resting HR, a recovery day,
    /// readiness). The target never exceeds it, and neither does the
    /// displayed whole km. Optional so RunTarget JSON cached before this
    /// field existed still decodes — nil means "unknown".
    public let capMeters: Double?
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
        capMeters: Double? = nil,
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
        self.capMeters = capMeters
        self.computedAt = computedAt
    }

    public var distanceKm: Double { distanceMeters / 1000 }
    public var baselineKm: Double { baselineMeters / 1000 }

    /// The user-facing target in whole km: rounded **up** (7.7 km → 8 km,
    /// 5.0 km → 5 km) while that stays within `capMeters`, otherwise the
    /// whole km under the cap: a 3.1 km red day shows 3 km, and a 5.6 km
    /// day under a 5.6 km ceiling shows 5. The one exception: whole km
    /// can't show a run under 1 km, so a cap below 1 km still shows 1.
    /// "Did I hit the target" is judged against this value, so the check
    /// matches what the runner saw.
    public var displayedDistanceKm: Int {
        // The tolerance only absorbs floating-point noise.
        let roundedUp = Int((distanceKm - 1e-6).rounded(.up))
        guard let capMeters else { return roundedUp }
        let underCap = max(1, Int((capMeters / 1000 + 1e-6).rounded(.down)))
        return min(roundedUp, underCap)
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
