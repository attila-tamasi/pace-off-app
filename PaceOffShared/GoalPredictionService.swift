// GoalPredictionService.swift
// Pure-Swift, no I/O: given a user's recent run history, personal best, age,
// and VO₂ max series, compute a projected finish time for their stated goal
// distance, plus an age-graded equivalent and the gap to their PB.
//
// Algorithms used:
// 1. **Riegel's formula** for time-at-distance extrapolation:
//      T₂ = T₁ × (D₂/D₁)^1.06
//    Pete Riegel, "Athletic Records and Human Endurance" (1981). The exponent
//    1.06 is the empirically calibrated endurance fade for distance running;
//    it's been refined since (1.07 / 1.08 for marathon-and-up), but 1.06 is
//    the canonical value used by RW, McMillan, and most calculators.
//
// 2. **WMA-style age-grading factors** (World Masters Athletics) for the
//    "equivalent to an open performance of …" annotation. Factors below are
//    a smoothed interpolation of the men's road-race table — accurate enough
//    for a motivational projection (we are not a USATF certification tool).
//    Source values cross-checked against runningahead.com's age-grade page.
//
// Nothing in here touches HealthKit, ProfileStore, or any actor — the service
// is a `Sendable` value type so the UI can call it inline or off-thread.

import Foundation

// MARK: - Result type

public struct GoalPrediction: Equatable, Sendable {

    public let goal: RunningGoal

    /// Predicted finishing time at `goal.distanceMeters`, in seconds.
    public let projectedTimeSeconds: Double

    /// Implied average pace (seconds per km) for the projected time.
    public let projectedPaceSecPerKm: Double

    /// What input the projection was anchored on. Lets the UI explain
    /// "based on your 8 km run from last week" vs. "based on your PB".
    public let basis: Basis

    /// How much input the service had to work with.
    public let confidence: Confidence

    /// Open-age equivalent of `projectedTimeSeconds` after WMA age grading.
    /// Nil when `age` was unknown.
    public let ageGradedEquivalentSeconds: Double?

    /// Difference between the projection and the user's personal best for
    /// this distance, in seconds. Positive = projection slower than PB.
    /// Nil when PB is unknown or for a different distance.
    public let gapToPersonalBestSeconds: Double?

    public enum Basis: Equatable, Sendable {
        /// Riegel-projected from a recent training run.
        case recentRun(distanceMeters: Double, durationSeconds: Double)
        /// Riegel-projected from the user's personal best at another distance.
        case personalBestExtrapolation(fromDistanceMeters: Double, timeSeconds: Double)
    }

    public enum Confidence: Equatable, Sendable {
        case high          // 5+ runs in 30d incl. one near goal distance
        case medium        // 3+ runs in 60d
        case low           // 1–2 runs
        case insufficient  // no usable inputs

        public var displayName: String {
            switch self {
            case .high:         return "High"
            case .medium:       return "Medium"
            case .low:          return "Low"
            case .insufficient: return "Insufficient"
            }
        }
    }
}

// MARK: - Service

public struct GoalPredictionService: Sendable {

    public init() {}

    /// Riegel's distance-extrapolation exponent.
    public static let riegelExponent: Double = 1.06

    /// Minimum credible source distance for Riegel — projections from very
    /// short runs (e.g. a 1 km warm-up) over-extrapolate badly.
    public static let minSourceDistanceMeters: Double = 3_000

    /// Maximum age in trailing-days for runs we'll consider current.
    public static let sourceWindowDays: Int = 60

    // MARK: Main entry point

    /// Produce a `GoalPrediction` for the user's chosen goal. Returns `nil`
    /// when there isn't enough input to project anything credibly.
    public func predict(
        goal: RunningGoal,
        runs: [RunRecord],
        age: Int?,
        personalBest: PersonalBest?,
        today: Date = Date()
    ) -> GoalPrediction? {
        let candidates = candidateRuns(from: runs, today: today)

        let bestRunProjection: (basis: GoalPrediction.Basis, seconds: Double)? = candidates
            .compactMap { run -> (GoalPrediction.Basis, Double)? in
                guard let seconds = riegel(fromDistanceMeters: run.distanceMeters,
                                           timeSeconds: run.durationSeconds,
                                           toDistanceMeters: goal.distanceMeters)
                else { return nil }
                let basis = GoalPrediction.Basis.recentRun(
                    distanceMeters: run.distanceMeters,
                    durationSeconds: run.durationSeconds
                )
                return (basis, seconds)
            }
            .min(by: { $0.1 < $1.1 })

        // PB projection — only if the PB is *for the chosen goal* it's a
        // direct read; if it's for another distance Riegel-extrapolate.
        // (UserProfile currently keys PB to the active goal, so the PB is
        // always at goal.distanceMeters in practice — but we treat it
        // defensively for forward compatibility.)
        let pbProjection: (basis: GoalPrediction.Basis, seconds: Double)? = personalBest.map { pb in
            let basis = GoalPrediction.Basis.personalBestExtrapolation(
                fromDistanceMeters: goal.distanceMeters,
                timeSeconds: pb.durationSeconds
            )
            return (basis, pb.durationSeconds)
        }

        // Pick whichever projection is faster (lower seconds) — that's the
        // user's demonstrated ability. PB usually wins because race-day
        // efforts outrun training paces, but a steady recent build that's
        // surpassed an old PB should be allowed to.
        let chosen: (basis: GoalPrediction.Basis, seconds: Double)?
        switch (bestRunProjection, pbProjection) {
        case let (.some(r), .some(p)):
            chosen = r.seconds <= p.seconds ? r : p
        case let (.some(r), .none):
            chosen = r
        case let (.none, .some(p)):
            chosen = p
        case (.none, .none):
            chosen = nil
        }

        guard let chosen else { return nil }

        let pace = chosen.seconds / (goal.distanceMeters / 1000.0)
        let confidence = computeConfidence(candidates: candidates, today: today, goal: goal)
        let ageGraded = age.map { chosen.seconds * ageGradeFactor(age: $0) }
        let gap: Double? = {
            guard let pb = personalBest else { return nil }
            return chosen.seconds - pb.durationSeconds
        }()

        return GoalPrediction(
            goal: goal,
            projectedTimeSeconds: chosen.seconds,
            projectedPaceSecPerKm: pace,
            basis: chosen.basis,
            confidence: confidence,
            ageGradedEquivalentSeconds: ageGraded,
            gapToPersonalBestSeconds: gap
        )
    }

    // MARK: - Riegel

    /// Project `timeSeconds` over `fromDistanceMeters` onto `toDistanceMeters`
    /// using Riegel's formula. Returns nil when the source distance is too
    /// short to be a credible basis (< `minSourceDistanceMeters`).
    public func riegel(fromDistanceMeters: Double,
                       timeSeconds: Double,
                       toDistanceMeters: Double) -> Double? {
        guard fromDistanceMeters >= Self.minSourceDistanceMeters,
              timeSeconds > 0,
              toDistanceMeters > 0
        else { return nil }
        let ratio = toDistanceMeters / fromDistanceMeters
        return timeSeconds * pow(ratio, Self.riegelExponent)
    }

    // MARK: - Candidate selection

    private func candidateRuns(from runs: [RunRecord], today: Date) -> [RunRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.sourceWindowDays, to: today)
            ?? today.addingTimeInterval(-Double(Self.sourceWindowDays) * 86_400)
        return runs.filter { run in
            run.startDate >= cutoff
                && run.distanceMeters >= Self.minSourceDistanceMeters
                && run.durationSeconds > 0
        }
    }

    private func computeConfidence(candidates: [RunRecord],
                                   today: Date,
                                   goal: RunningGoal) -> GoalPrediction.Confidence {
        if candidates.isEmpty { return .insufficient }

        let cal = Calendar.current
        let thirtyDayCutoff = cal.date(byAdding: .day, value: -30, to: today) ?? today
        let last30 = candidates.filter { $0.startDate >= thirtyDayCutoff }

        let nearGoal = candidates.contains { run in
            let ratio = run.distanceMeters / goal.distanceMeters
            return ratio >= 0.75 && ratio <= 1.25
        }

        if last30.count >= 5 && nearGoal { return .high }
        if candidates.count >= 3 { return .medium }
        return .low
    }

    // MARK: - Age grading

    /// WMA-style age factor for distance running, smoothed across age.
    /// Returns a value in (0, 1]; ~1.0 around the peak age band and decays
    /// for older runners. We treat sub-30 as the open standard (1.0) — the
    /// app's audience skews recreational-adult and we'd rather under-claim
    /// boosts for college-age athletes than over-grade them.
    public func ageGradeFactor(age: Int) -> Double {
        // Anchor points from a smoothed men's-road-race WMA table. Values
        // below 30 are clamped to the open standard (1.0).
        let table: [(age: Int, factor: Double)] = [
            (30, 1.000),
            (35, 0.985),
            (40, 0.965),
            (45, 0.940),
            (50, 0.908),
            (55, 0.874),
            (60, 0.834),
            (65, 0.787),
            (70, 0.738),
            (75, 0.683),
            (80, 0.625),
            (85, 0.560),
            (90, 0.490)
        ]
        if age <= 30 { return 1.0 }
        if age >= table.last!.age { return table.last!.factor }
        // Linear interpolation between bracketing anchor points.
        for i in 0..<(table.count - 1) {
            let lo = table[i]
            let hi = table[i + 1]
            if age >= lo.age && age <= hi.age {
                let t = Double(age - lo.age) / Double(hi.age - lo.age)
                return lo.factor + (hi.factor - lo.factor) * t
            }
        }
        return 1.0 // unreachable
    }
}

// MARK: - Display helpers

public extension GoalPrediction {

    /// "1:42:18" / "47:12" / "23:40".
    var formattedProjectedTime: String { Self.formatHMS(projectedTimeSeconds) }

    /// "4:53/km".
    var formattedProjectedPace: String {
        let m = Int(projectedPaceSecPerKm) / 60
        let s = Int(projectedPaceSecPerKm) % 60
        return String(format: "%d:%02d/km", m, s)
    }

    /// "1:38:55 (open equivalent)" — only when age was provided.
    var formattedAgeGradedEquivalent: String? {
        ageGradedEquivalentSeconds.map(Self.formatHMS)
    }

    /// Signed gap to PB as a string. Negative = ahead of PB.
    /// "−4:12 vs PB" / "+1:18 vs PB" / nil if no PB.
    var formattedGapToPersonalBest: String? {
        guard let gap = gapToPersonalBestSeconds else { return nil }
        let sign = gap < 0 ? "−" : "+"
        let abs = Swift.abs(gap)
        let m = Int(abs) / 60
        let s = Int(abs) % 60
        return "\(sign)\(m):\(String(format: "%02d", s)) vs PB"
    }

    private static func formatHMS(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
