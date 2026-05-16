// GoalPredictionService.swift
// Pure-Swift, no I/O: project a realistic finish time for the user's stated
// goal, based on what they're actually capable of *today* — not a stale PB.
//
// Why the rewrite (old behaviour was naïve):
//   The old implementation picked whichever of {recent-run projection, PB}
//   was *faster* and called it a day. A 10-year-old half-marathon PB beat a
//   couple of recent slow training runs and was presented as "your projected
//   time", which is obviously wrong for someone who's out of shape.
//
// New layered approach:
//   1. **Base time — current fitness.** Riegel-extrapolate from the best
//      qualifying run in the last 60 days. This is the strongest signal of
//      what the user can do today.
//   2. **Fallback when there are no recent runs:** use the PB but penalize
//      it for age. We assume ~0.5%/yr fitness loss for the first 5 years,
//      then ~1%/yr beyond. A 10-year-old PB therefore costs ~7.5%.
//   3. **VO₂-max fitness adjustment.** If Apple Health says current VO₂ max
//      has dropped meaningfully from the user's recent peak (>10%), apply a
//      multiplier scaled by the ratio. Daniels' VDOT principle: race time
//      scales roughly inversely with VO₂. Only applied when we're projecting
//      from a PB (recent runs already encode current fitness).
//   4. **Goal-date training improvement.** If the user has a future race
//      date, allow a capped improvement: ~0.5%/week for the first 8 weeks,
//      tapering to a hard 8% cap. This says "if you train consistently
//      between now and your race, you can knock this much off".
//   5. **Age grading & PB gap** are still produced as motivational annotations.
//
// Algorithms / references:
//   • **Riegel's formula** for distance extrapolation: T₂ = T₁·(D₂/D₁)^1.06.
//     Pete Riegel, "Athletic Records and Human Endurance" (1981).
//   • **WMA-style age-grade factors** for the open-equivalent annotation.
//   • **Daniels' VDOT** mapping for the VO₂-max adjustment (inverse scaling).
//
// Nothing in here touches HealthKit, ProfileStore, or any actor — the service
// is a `Sendable` value type so the UI can call it inline or off-thread.

import Foundation

// MARK: - Result type

public struct GoalPrediction: Equatable, Sendable {

    public let goal: RunningGoal

    /// Predicted finishing time at `goal.distanceMeters`, in seconds.
    /// Already includes every adjustment (fitness, age of PB, goal-date
    /// training window). What the user sees in the hero card.
    public let projectedTimeSeconds: Double

    /// Implied average pace (seconds per km) for the projected time.
    public let projectedPaceSecPerKm: Double

    /// What the projection was anchored on — drives the explanation footnote.
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

    /// VO₂-max multiplier applied to the base time. `nil` when not enough
    /// VO₂ history was provided, or when no significant decline was detected.
    /// > 1.0 means the projection was slowed because current fitness is below
    /// peak.
    public let vo2FitnessMultiplier: Double?

    /// Training-improvement multiplier applied because the user has a future
    /// goal date. `nil` when no goal date is set. < 1.0 means the projection
    /// was improved on the assumption of consistent training to race day.
    public let trainingImprovementMultiplier: Double?

    /// Goal date the projection was tuned for. Surfaced so the UI can show
    /// "if you race on May 14, 2026" rather than just "today's projection".
    public let goalDate: Date?

    public enum Basis: Equatable, Sendable {
        /// Riegel-projected from a recent training run.
        case recentRun(distanceMeters: Double, durationSeconds: Double)
        /// Falling back to the PB because no recent runs are usable. The
        /// associated value is the PB's age in whole years — drives the
        /// "from a 10-year-old PB" caption.
        case agedPersonalBest(yearsOld: Int)
    }

    public enum Confidence: Equatable, Sendable {
        case high          // 5+ runs in 30d incl. one near goal distance, VO₂ data present
        case medium        // 3+ runs in 60d
        case low           // 1–2 runs OR PB only and < 3 years old
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

    /// Per-year fitness decay applied to the PB when it's the only signal,
    /// for years 1–5. ~0.5%/yr — gentle, reflects that even untrained
    /// recreational runners hold a lot of base fitness.
    public static let pbDecayPerYearEarly: Double = 0.005

    /// Per-year decay beyond 5 years. ~1%/yr — steeper, reflecting more
    /// material loss of base after a long detraining period.
    public static let pbDecayPerYearLate: Double = 0.010

    /// Threshold below which a VO₂-max drop counts as "out of shape". Smaller
    /// fluctuations sit inside HealthKit's noise floor.
    public static let vo2DeclineThreshold: Double = 0.10  // 10%

    /// Weekly training-improvement allowance for the goal-date adjustment.
    public static let trainingImprovementPerWeek: Double = 0.005  // 0.5%/wk

    /// Hard cap on goal-date improvement, no matter how far away the race is.
    /// You don't go from couch to a 10% PB in 14 weeks.
    public static let trainingImprovementMaxFraction: Double = 0.08  // 8%

    // MARK: Main entry point

    /// Produce a `GoalPrediction` for the user's chosen goal. Returns `nil`
    /// when there isn't enough input to project anything credibly.
    public func predict(
        goal: RunningGoal,
        runs: [RunRecord],
        age: Int?,
        personalBest: PersonalBest?,
        vo2MaxHistory: [VO2MaxSnapshot] = [],
        goalDate: Date? = nil,
        today: Date = Date()
    ) -> GoalPrediction? {

        // ─── Step 1: pick the base time and basis ──────────────────────────
        let candidates = candidateRuns(from: runs, today: today)
        let recentBest: (basis: GoalPrediction.Basis, seconds: Double)? = candidates
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

        let base: (basis: GoalPrediction.Basis, seconds: Double)?
        let vo2Multiplier: Double?

        if let recentBest {
            // Recent runs trump everything — they already encode today's
            // fitness, so no VO₂ correction is needed.
            base = recentBest
            vo2Multiplier = nil
        } else if let pb = personalBest {
            // No usable recent runs — fall back to the PB, but decay it for
            // its age and (optionally) for current vs. peak VO₂ max.
            let pbAge = pbAgeYears(pb: pb, today: today)
            let decayed = pb.durationSeconds * pbDecayMultiplier(pbYearsOld: pbAge)
            let vo2 = vo2DeclineMultiplier(history: vo2MaxHistory)
            let basis = GoalPrediction.Basis.agedPersonalBest(yearsOld: pbAge)
            base = (basis, decayed * vo2)
            vo2Multiplier = (vo2 != 1.0) ? vo2 : nil
        } else {
            // Nothing to anchor on.
            return nil
        }

        guard let base else { return nil }

        // ─── Step 2: optional training-improvement curve for goal date ────
        let training = trainingImprovementMultiplier(goalDate: goalDate, today: today)
        let trainingFactorForResult: Double? = (training != 1.0) ? training : nil

        let projectedTime = base.seconds * training
        let pace = projectedTime / (goal.distanceMeters / 1000.0)

        // ─── Step 3: assemble annotations ────────────────────────────────
        let confidence = computeConfidence(
            candidates: candidates,
            personalBest: personalBest,
            today: today,
            goal: goal
        )
        let ageGraded = age.map { projectedTime * ageGradeFactor(age: $0) }
        let gap: Double? = personalBest.map { projectedTime - $0.durationSeconds }

        return GoalPrediction(
            goal: goal,
            projectedTimeSeconds: projectedTime,
            projectedPaceSecPerKm: pace,
            basis: base.basis,
            confidence: confidence,
            ageGradedEquivalentSeconds: ageGraded,
            gapToPersonalBestSeconds: gap,
            vo2FitnessMultiplier: vo2Multiplier,
            trainingImprovementMultiplier: trainingFactorForResult,
            goalDate: goalDate
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

    // MARK: - PB age decay

    /// How old is the PB in whole years, clamped at zero.
    private func pbAgeYears(pb: PersonalBest, today: Date) -> Int {
        let currentYear = Calendar.current.component(.year, from: today)
        return max(0, currentYear - pb.year)
    }

    /// Multiplier ≥ 1.0 representing accumulated fitness loss since the PB.
    /// 0–5 yrs at 0.5%/yr, then 1%/yr. Public for testing.
    public func pbDecayMultiplier(pbYearsOld: Int) -> Double {
        var m = 1.0
        for year in 0..<pbYearsOld {
            m *= 1.0 + (year < 5 ? Self.pbDecayPerYearEarly : Self.pbDecayPerYearLate)
        }
        return m
    }

    // MARK: - VO₂ max fitness adjustment

    /// If current VO₂ is meaningfully below the recent peak, return a
    /// time-multiplier > 1.0 (slower projection). Otherwise 1.0.
    /// We use the trailing 6-month max as the "peak" so a single spike
    /// doesn't unfairly penalise the current reading.
    public func vo2DeclineMultiplier(history: [VO2MaxSnapshot],
                                     today: Date = Date()) -> Double {
        guard history.count >= 3 else { return 1.0 }
        let sorted = history.sorted { $0.date < $1.date }
        guard let current = sorted.last?.value, current > 0 else { return 1.0 }

        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: today) ?? today
        let recentWindow = sorted.filter { $0.date >= sixMonthsAgo }
        guard let peak = recentWindow.map(\.value).max(), peak > current else { return 1.0 }

        let declineFraction = (peak - current) / peak
        guard declineFraction >= Self.vo2DeclineThreshold else { return 1.0 }

        // Daniels-style inverse scaling: time ∝ peak / current.
        // Apply only the *excess* beyond the noise threshold so the
        // adjustment is gentle and proportionate.
        let effective = max(current, peak * (1 - 0.30))  // cap at 30% decline
        return peak / effective
    }

    // MARK: - Goal-date training improvement

    /// Multiplier ≤ 1.0 reflecting consistent-training improvement up to
    /// `goalDate`. Returns 1.0 (no improvement) when goal date is missing,
    /// in the past, or zero weeks away.
    public func trainingImprovementMultiplier(goalDate: Date?, today: Date) -> Double {
        guard let goalDate, goalDate > today else { return 1.0 }
        let weeks = goalDate.timeIntervalSince(today) / (7 * 86_400)
        let usable = max(0, min(weeks, 16))           // cap effective training window
        let improvement = min(usable * Self.trainingImprovementPerWeek,
                              Self.trainingImprovementMaxFraction)
        return 1.0 - improvement
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
                                   personalBest: PersonalBest?,
                                   today: Date,
                                   goal: RunningGoal) -> GoalPrediction.Confidence {
        let cal = Calendar.current

        if candidates.isEmpty {
            // No recent runs — confidence hinges on whether the PB is fresh.
            if let pb = personalBest, pbAgeYears(pb: pb, today: today) <= 2 {
                return .low
            }
            return .insufficient
        }

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

    /// Whole-week countdown to the goal date — "3 weeks", "1 day", or nil if
    /// no goal date or it's already past.
    func formattedCountdown(today: Date = Date()) -> String? {
        guard let goalDate, goalDate > today else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: today, to: goalDate).day ?? 0
        if days <= 0 { return nil }
        if days < 14 { return "\(days) day\(days == 1 ? "" : "s")" }
        let weeks = days / 7
        return "\(weeks) week\(weeks == 1 ? "" : "s")"
    }

    /// Human-readable percent — "8% slower for current fitness", or nil.
    var formattedVO2Adjustment: String? {
        guard let m = vo2FitnessMultiplier, m > 1.001 else { return nil }
        let pct = Int(((m - 1.0) * 100).rounded())
        return "\(pct)% slower for current VO₂ max"
    }

    /// Human-readable percent — "6% off with consistent training", or nil.
    var formattedTrainingImprovement: String? {
        guard let m = trainingImprovementMultiplier, m < 0.999 else { return nil }
        let pct = Int(((1.0 - m) * 100).rounded())
        return "−\(pct)% if you train to race day"
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
