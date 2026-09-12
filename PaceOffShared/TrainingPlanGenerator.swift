// TrainingPlanGenerator.swift
// Produces a concrete `TrainingPlan` from (race goal, VO₂ max / PB, age,
// tier, long-run day). Pure-Swift, `Sendable`, no I/O.
//
// Pace math: **Jack Daniels' VDOT methodology** ("Daniels' Running Formula").
//
// Two formulas underlie everything below:
//
// 1. **VO₂ demand** of running at velocity v (m/min):
//      VO₂(v) = -4.6 + 0.182258·v + 0.000104·v²       (Daniels 1998/2014)
//
// 2. **Fraction of VO₂ max** sustainable for time t (minutes) of all-out
//    running:
//      f(t) = 0.8 + 0.1894393·e^(-0.012778·t) + 0.2989558·e^(-0.1932605·t)
//
// VDOT for a race performance: VDOT = VO₂(v_race) / f(t_race).
// VDOT for a known VO₂ max: VDOT ≈ VO₂ max (Daniels conflates them for fit
// recreational runners; the table top-out wobble is irrelevant at this
// level of precision).
//
// Training paces are then anchored to VDOT via fixed %VO₂max intensities:
//   E (easy)     ≈ 70%   ← long-run / easy pace
//   M (marathon) ≈ 84%   ← race-specific endurance
//   T (threshold)≈ 88%   ← "comfortably hard" — tempo / cruise intervals
//   I (interval) ≈ 98%   ← VO₂ max stimulus
// Solving VO₂(v) = pct·VDOT for v gives the velocity, then sec/km.
//
// None of this aims to replicate Daniels' published tables exactly — we
// trade ±a-few-seconds-per-km of nominal accuracy for a clean, dependency-
// free implementation. Tests assert paces match the published 5K @ 20:00
// table within 5 s/km, which is well inside coach-tolerance.

import Foundation

// MARK: - VDOT calculator

public struct VDOTCalculator: Sendable {

    public init() {}

    // Daniels coefficients.
    private static let a0: Double = -4.6
    private static let a1: Double = 0.182258
    private static let a2: Double = 0.000104

    private static let b0: Double = 0.8
    private static let b1: Double = 0.1894393
    private static let b1k: Double = -0.012778
    private static let b2: Double = 0.2989558
    private static let b2k: Double = -0.1932605

    /// Oxygen cost (ml/kg/min) of running at `velocityMetersPerMin`.
    public func vo2Demand(velocityMetersPerMin v: Double) -> Double {
        Self.a0 + Self.a1 * v + Self.a2 * v * v
    }

    /// Fraction of VO₂ max sustainable for `timeMinutes` of all-out running.
    public func fractionalIntensity(timeMinutes t: Double) -> Double {
        Self.b0
            + Self.b1 * exp(Self.b1k * t)
            + Self.b2 * exp(Self.b2k * t)
    }

    /// VDOT for a race performance (`distanceMeters` in `timeSeconds`).
    /// Returns nil for non-positive inputs.
    public func vdot(fromRaceDistanceMeters d: Double, timeSeconds: Double) -> Double? {
        guard d > 0, timeSeconds > 0 else { return nil }
        let v = d / (timeSeconds / 60.0)                  // m/min
        let f = fractionalIntensity(timeMinutes: timeSeconds / 60.0)
        guard f > 0 else { return nil }
        return vo2Demand(velocityMetersPerMin: v) / f
    }

    /// Velocity (m/min) at which oxygen demand equals `targetVO2`.
    /// Solves the quadratic `a2·v² + a1·v + (a0 - target) = 0`.
    public func velocity(forVO2Demand target: Double) -> Double {
        let A = Self.a2
        let B = Self.a1
        let C = Self.a0 - target
        // Discriminant is well above zero for any plausible target VO₂ value
        // we'll feed in (VDOT range ~25..80 → target 17..80), so the closed-
        // form solution is safe.
        let disc = B * B - 4 * A * C
        let root = (-B + sqrt(disc)) / (2 * A)
        return root
    }

    /// Pace (seconds per km) for an intensity expressed as %VO₂max of VDOT.
    public func paceSecPerKm(vdot: Double, fractionOfVDOT pct: Double) -> Double {
        let target = vdot * pct
        let v = velocity(forVO2Demand: target)
        guard v > 0 else { return .infinity }
        return 60_000.0 / v
    }
}

// MARK: - Training intensity targets

/// Daniels' standard intensity zones, expressed as a fraction of VDOT
/// (≈ %VO₂ max). Midpoints chosen from his published ranges so a single
/// number maps to a single pace; the generator emits a band around it.
public enum TrainingIntensity: Sendable {
    case easy
    case marathon
    case threshold
    case interval

    /// %VDOT midpoint.
    public var fractionOfVDOT: Double {
        switch self {
        case .easy:      return 0.70
        case .marathon:  return 0.84
        case .threshold: return 0.88
        case .interval:  return 0.98
        }
    }

    /// Plus/minus tolerance applied to the computed sec/km midpoint.
    public var paceToleranceSec: Double {
        switch self {
        case .easy:      return 15   // ±15 s/km — easy is a wide band
        case .marathon:  return 5
        case .threshold: return 5
        case .interval:  return 3
        }
    }

    /// Map a workout kind onto the intensity it should be run at.
    /// Strides are nominally a stand-alone but are paced like intervals.
    public static func forKind(_ kind: WorkoutKind) -> TrainingIntensity {
        switch kind {
        case .easy, .long: return .easy
        case .marathonPace: return .marathon
        case .tempo, .threshold: return .threshold
        case .interval, .strides: return .interval
        case .rest: return .easy
        }
    }
}

// MARK: - Generator inputs / output

public struct TrainingPlanInputs: Sendable {
    public let goal: RunningGoal
    public let tier: PlanTier
    public let longRunDay: Weekday
    /// Latest VO₂ max reading from HealthKit (ml/kg/min). nil if unknown.
    public let vo2Max: Double?
    /// User's PB for *the goal distance*, if recorded. Refines VDOT when
    /// VO₂ max is missing or stale.
    public let personalBest: PersonalBest?
    /// Race-day deadline for the goal. When set in the future, the plan is
    /// shortened to fit (capped at the goal's default plan length, with a
    /// 4-week minimum so we still get a build + taper). When nil the default
    /// plan length is used.
    public let goalDate: Date?
    /// Plan generation date (used only for `createdAt`; not for the schedule).
    public let today: Date

    public init(goal: RunningGoal,
                tier: PlanTier,
                longRunDay: Weekday = .sunday,
                vo2Max: Double? = nil,
                personalBest: PersonalBest? = nil,
                goalDate: Date? = nil,
                today: Date = Date()) {
        self.goal = goal
        self.tier = tier
        self.longRunDay = longRunDay
        self.vo2Max = vo2Max
        self.personalBest = personalBest
        self.goalDate = goalDate
        self.today = today
    }
}

// MARK: - Generator

public struct TrainingPlanGenerator: Sendable {

    /// VDOT used when both VO₂ max and PB are missing. Corresponds to ~30
    /// min 5K / ~5:50/km easy pace — a believable starting baseline for a
    /// returning-recreational runner.
    public static let beginnerVDOTFallback: Double = 38.0

    private let vdotCalc = VDOTCalculator()

    public init() {}

    // MARK: Public entry point

    public func generate(_ inputs: TrainingPlanInputs) -> TrainingPlan {
        let (vdot, fromFallback) = resolveVDOT(inputs)
        let weekCount = planWeeks(for: inputs.goal,
                                  goalDate: inputs.goalDate,
                                  today: inputs.today)
        let weeks = (1...weekCount).map { i in
            buildWeek(
                index: i,
                of: weekCount,
                goal: inputs.goal,
                tier: inputs.tier,
                longRunDay: inputs.longRunDay,
                vdot: vdot
            )
        }
        return TrainingPlan(
            goal: inputs.goal,
            tier: inputs.tier,
            longRunDay: inputs.longRunDay,
            weeks: weeks,
            vdot: vdot,
            usedBeginnerDefault: fromFallback,
            createdAt: inputs.today
        )
    }

    // MARK: VDOT resolution

    /// Pick the best VDOT we can. Preferred order:
    /// 1. VO₂ max from HealthKit, when present and plausible.
    /// 2. Daniels-formula derivation from the user's PB for the goal distance.
    /// 3. The beginner-default fallback.
    /// Returns `(vdot, usedFallback)`.
    public func resolveVDOT(_ inputs: TrainingPlanInputs) -> (Double, Bool) {
        if let vo2 = inputs.vo2Max, vo2 >= 25 && vo2 <= 90 {
            return (vo2, false)
        }
        if let pb = inputs.personalBest,
           let v = vdotCalc.vdot(fromRaceDistanceMeters: inputs.goal.distanceMeters,
                                 timeSeconds: pb.durationSeconds),
           v >= 25 && v <= 90 {
            return (v, false)
        }
        return (Self.beginnerVDOTFallback, true)
    }

    // MARK: Plan length

    /// How many weeks the plan should run. When `goalDate` is in the future,
    /// the plan is condensed to fit (never extended beyond the default — a
    /// race 6 months out doesn't need a 26-week 5K plan). 4-week minimum so
    /// the structure (build + taper) survives.
    public func planWeeks(for goal: RunningGoal,
                          goalDate: Date? = nil,
                          today: Date = Date()) -> Int {
        let defaultWeeks = defaultPlanWeeks(for: goal)
        guard let goalDate, goalDate > today else { return defaultWeeks }
        let secondsUntil = goalDate.timeIntervalSince(today)
        let weeksUntil = Int(ceil(secondsUntil / (7 * 24 * 3600)))
        return max(4, min(defaultWeeks, weeksUntil))
    }

    private func defaultPlanWeeks(for goal: RunningGoal) -> Int {
        switch goal {
        case .fiveK:        return 8
        case .tenK:         return 10
        case .halfMarathon: return 12
        case .marathon:     return 16
        }
    }

    // MARK: Week construction

    private func buildWeek(index: Int,
                           of total: Int,
                           goal: RunningGoal,
                           tier: PlanTier,
                           longRunDay: Weekday,
                           vdot: Double) -> TrainingWeek {

        // Lay out workouts on a Mon..Sun canonical template, with the long
        // run anchored to `longRunDay`. The first day of the template *is*
        // the day after the long run (a recovery / rest), so rotating moves
        // the whole week.
        let template = workoutTemplate(
            tier: tier,
            week: index,
            of: total,
            goal: goal
        )

        // The template assumes long-run on Sunday (slot index 6). Rotate so
        // the long run actually lands on `longRunDay`.
        let canonicalLongRunSlot = 6 // Sunday in 0-Mon..6-Sun ordering
        let shift = longRunDay.rawValue - canonicalLongRunSlot
        let rotated: [WorkoutKind] = (0..<7).map { dayIdx in
            // Find which template slot lands on this weekday after rotation.
            let srcSlot = ((dayIdx - shift) % 7 + 7) % 7
            return template[srcSlot]
        }

        // Quality days must have at least one easy/rest buffer between them
        // and the long run. After rotation we may have a quality adjacent to
        // the long run; if so, swap with the nearest easy slot.
        let smoothed = enforceQualitySpacing(rotated, longRunDay: longRunDay)

        // Concrete distances + paces per workout, in current week.
        let days: [TrainingDay] = Weekday.allCases.map { wd in
            let kind = smoothed[wd.rawValue]
            let workout = materialise(
                kind: kind,
                week: index,
                of: total,
                goal: goal,
                tier: tier,
                vdot: vdot
            )
            return TrainingDay(weekday: wd, workout: workout)
        }
        return TrainingWeek(index: index, days: days)
    }

    /// Choose what kind of workout happens on each Mon..Sun slot for this
    /// week. Long run always lives at slot 6 (Sunday) pre-rotation.
    private func workoutTemplate(tier: PlanTier,
                                 week: Int,
                                 of total: Int,
                                 goal: RunningGoal) -> [WorkoutKind] {
        // Choose tempo vs interval based on the week and goal: alternate
        // weeks so the runner gets both stimuli, but bias longer races
        // toward threshold (more useful for 21K+).
        let qualityForWeek: WorkoutKind = {
            let useThreshold = (goal == .halfMarathon || goal == .marathon)
                ? (week % 3 != 0) // 2/3 threshold for HM+
                : (week % 2 == 0) // alternate for 5K/10K
            return useThreshold ? .threshold : .interval
        }()

        let secondQuality: WorkoutKind = qualityForWeek == .threshold ? .interval : .threshold

        switch tier {
        case .easy:
            // 3 runs: Mon rest, Tue easy, Wed rest, Thu easy, Fri rest,
            //         Sat rest, Sun long. Add strides on the Tue easy in
            //         the middle third of the plan so the runner sees
            //         some leg speed.
            let stridesWeek = (week > total / 3 && week < total - 2) && (week % 2 == 0)
            return [
                .rest,                                       // Mon
                stridesWeek ? .strides : .easy,              // Tue
                .rest,                                       // Wed
                .easy,                                       // Thu
                .rest,                                       // Fri
                .rest,                                       // Sat
                .long                                        // Sun
            ]

        case .medium:
            // 4 runs: Mon rest, Tue quality, Wed rest, Thu easy, Fri rest,
            //         Sat easy, Sun long.
            return [
                .rest,
                qualityForWeek,
                .rest,
                .easy,
                .rest,
                .easy,
                .long
            ]

        case .aggressive:
            // 5 runs: Mon rest (day after the long run — even the aggressive
            //         tier gets its recovery day), Tue quality1, Wed easy,
            //         Thu quality2, Fri rest, Sat easy, Sun long. Matches
            //         PlanTier.aggressive.runsPerWeek == 5 and the blurb.
            return [
                .rest,
                qualityForWeek,
                .easy,
                secondQuality,
                .rest,
                .easy,
                .long
            ]
        }
    }

    /// If a quality session lands immediately before or after the long run,
    /// swap it with the nearest easy/rest day to keep the standard 24-hour
    /// buffer that Daniels and most coaches recommend.
    private func enforceQualitySpacing(_ week: [WorkoutKind],
                                       longRunDay: Weekday) -> [WorkoutKind] {
        var w = week
        let lr = longRunDay.rawValue
        let neighbours = [(lr - 1 + 7) % 7, (lr + 1) % 7]
        for n in neighbours where w[n].isQuality {
            // Find a non-quality, non-long slot to swap with — prefer the
            // furthest from the long run.
            let candidates = (0..<7)
                .filter { $0 != lr && !w[$0].isQuality && w[$0] != .long }
                .sorted { distance(from: lr, to: $0) > distance(from: lr, to: $1) }
            if let target = candidates.first {
                w.swapAt(n, target)
            }
        }
        return w
    }

    private func distance(from a: Int, to b: Int) -> Int {
        let raw = abs(a - b)
        return min(raw, 7 - raw)
    }

    // MARK: Concrete distance + pace

    private func materialise(kind: WorkoutKind,
                             week: Int,
                             of total: Int,
                             goal: RunningGoal,
                             tier: PlanTier,
                             vdot: Double) -> Workout {

        switch kind {
        case .rest:
            return Workout(kind: .rest, distanceMeters: 0,
                           paceMinSecPerKm: 0, paceMaxSecPerKm: 0)

        case .strides:
            // 4–6 × 20s strides woven into a short easy run.
            let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                             fractionOfVDOT: TrainingIntensity.easy.fractionOfVDOT)
            return Workout(
                kind: .strides,
                distanceMeters: 5_000,
                paceMinSecPerKm: pace - 15,
                paceMaxSecPerKm: pace + 15,
                notes: "Easy run + 4–6 × 20 s strides on the flats."
            )

        case .easy:
            return easyWorkout(
                distance: easyDistance(week: week, total: total, goal: goal, tier: tier),
                vdot: vdot,
                kind: .easy
            )

        case .long:
            return easyWorkout(
                distance: longRunDistance(week: week, total: total, goal: goal, tier: tier),
                vdot: vdot,
                kind: .long,
                notes: "Conversational pace — building endurance, not chasing speed."
            )

        case .marathonPace:
            let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                             fractionOfVDOT: TrainingIntensity.marathon.fractionOfVDOT)
            let tol = TrainingIntensity.marathon.paceToleranceSec
            return Workout(
                kind: .marathonPace,
                distanceMeters: marathonPaceDistance(week: week, total: total, goal: goal, tier: tier),
                paceMinSecPerKm: pace - tol,
                paceMaxSecPerKm: pace + tol,
                notes: "Steady marathon-effort segment after a warm-up."
            )

        case .tempo, .threshold:
            let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                             fractionOfVDOT: TrainingIntensity.threshold.fractionOfVDOT)
            let tol = TrainingIntensity.threshold.paceToleranceSec
            let total = thresholdDistance(week: week, of: total, tier: tier)
            return Workout(
                kind: .threshold,
                distanceMeters: total,
                paceMinSecPerKm: pace - tol,
                paceMaxSecPerKm: pace + tol,
                notes: kind == .threshold
                    ? "WU 2 km · 4 × 1 km @ T w/ 60 s jog · CD 2 km"
                    : "WU 2 km · 20 min @ T continuous · CD 2 km"
            )

        case .interval:
            let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                             fractionOfVDOT: TrainingIntensity.interval.fractionOfVDOT)
            let tol = TrainingIntensity.interval.paceToleranceSec
            let total = intervalDistance(week: week, of: total, tier: tier)
            return Workout(
                kind: .interval,
                distanceMeters: total,
                paceMinSecPerKm: pace - tol,
                paceMaxSecPerKm: pace + tol,
                notes: "WU 2 km · 5 × 800 m @ I w/ equal-time jog · CD 2 km"
            )
        }
    }

    private func easyWorkout(distance: Double,
                             vdot: Double,
                             kind: WorkoutKind,
                             notes: String? = nil) -> Workout {
        let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                         fractionOfVDOT: TrainingIntensity.easy.fractionOfVDOT)
        let tol = TrainingIntensity.easy.paceToleranceSec
        return Workout(
            kind: kind,
            distanceMeters: distance,
            paceMinSecPerKm: pace - tol,
            paceMaxSecPerKm: pace + tol,
            notes: notes
        )
    }

    // MARK: Volume curves

    /// Peak weekly km we'd build toward at this tier + goal. The buildup
    /// scales other distances against this.
    private func peakWeeklyKm(goal: RunningGoal, tier: PlanTier) -> Double {
        switch (goal, tier) {
        case (.fiveK,        .easy):        return 22
        case (.fiveK,        .medium):      return 32
        case (.fiveK,        .aggressive):  return 50

        case (.tenK,         .easy):        return 28
        case (.tenK,         .medium):      return 45
        case (.tenK,         .aggressive):  return 65

        case (.halfMarathon, .easy):        return 35
        case (.halfMarathon, .medium):      return 55
        case (.halfMarathon, .aggressive):  return 80

        case (.marathon,     .easy):        return 45
        case (.marathon,     .medium):      return 65
        case (.marathon,     .aggressive):  return 95
        }
    }

    /// Peak long-run distance. Capped at race + 25% for 5K/10K, around
    /// race-distance for half (cap 24 km), and 37 km for marathon across all
    /// tiers (Pfitzinger's 23-mile / ~37 km benchmark — pushes glycogen
    /// economy and race-day confidence without crossing into recovery debt
    /// territory).
    private func peakLongRunKm(goal: RunningGoal, tier: PlanTier) -> Double {
        switch goal {
        case .fiveK:        return tier == .aggressive ? 10 : 8
        case .tenK:         return tier == .aggressive ? 16 : 14
        case .halfMarathon: return tier == .aggressive ? 24 : 20
        case .marathon:     return 37
        }
    }

    /// Linear build from 70% of peak in week 1 to 100% at `total - 3`, then
    /// a three-week taper (70 / 50 / 30%) into race day. The peak week is
    /// included in the build branch on purpose — a plan that says "37 km
    /// long run at peak" should actually prescribe a 37 km run somewhere.
    private func volumeFraction(week: Int, of total: Int) -> Double {
        let peakWeek = max(1, total - 3)  // build to 1.0 here
        if week > peakWeek {
            // Taper.
            let weeksOut = total - week   // 2 = mid-taper, 1 = race-week
            switch weeksOut {
            case 1:  return 0.50          // race week
            case 0:  return 0.30          // race day itself — minimal
            default: return 0.70          // mid-taper
            }
        }
        // Linear build from 0.70 at week 1 to 1.00 at peakWeek.
        let progress = Double(week - 1) / Double(max(peakWeek - 1, 1))
        return 0.70 + 0.30 * min(max(progress, 0), 1)
    }

    private func longRunDistance(week: Int,
                                 total: Int,
                                 goal: RunningGoal,
                                 tier: PlanTier) -> Double {
        let peak = peakLongRunKm(goal: goal, tier: tier) * 1000.0
        return peak * volumeFraction(week: week, of: total)
    }

    private func easyDistance(week: Int,
                              total: Int,
                              goal: RunningGoal,
                              tier: PlanTier) -> Double {
        // Easy runs are roughly (peakWeekly - longRun) / (runsPerWeek - 1).
        let peakWeekKm = peakWeeklyKm(goal: goal, tier: tier)
        let longKm = peakLongRunKm(goal: goal, tier: tier)
        let easyRuns = Double(tier.runsPerWeek - 1)
        let peakEasyKm = max((peakWeekKm - longKm) / easyRuns, 4)
        let frac = volumeFraction(week: week, of: total)
        return peakEasyKm * 1000.0 * frac
    }

    private func thresholdDistance(week: Int, of total: Int, tier: PlanTier) -> Double {
        // 8–10 km total (warm-up + main + cool-down) at peak, scaled down.
        let base: Double = tier == .aggressive ? 10_000 : 8_000
        return base * volumeFraction(week: week, of: total)
    }

    private func intervalDistance(week: Int, of total: Int, tier: PlanTier) -> Double {
        // 7–9 km total (warm-up + reps + cool-down) at peak, scaled down.
        let base: Double = tier == .aggressive ? 9_000 : 7_000
        return base * volumeFraction(week: week, of: total)
    }

    private func marathonPaceDistance(week: Int,
                                      total: Int,
                                      goal: RunningGoal,
                                      tier: PlanTier) -> Double {
        // Only marathon plans really use M-pace as a stand-alone, but a
        // half plan can benefit from a short MP segment. Keep modest.
        switch goal {
        case .marathon:     return 14_000 * volumeFraction(week: week, of: total)
        case .halfMarathon: return 10_000 * volumeFraction(week: week, of: total)
        default:            return 6_000 * volumeFraction(week: week, of: total)
        }
    }
}
