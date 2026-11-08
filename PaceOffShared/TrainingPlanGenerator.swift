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

    /// The VDOTs the pace formula is used for. At 20 the easy pace is about
    /// 10:20/km; below it the "easy run" turns into a walk, which the
    /// running-economy curve doesn't describe. 90 is beyond any measured
    /// runner.
    public static let validRange: ClosedRange<Double> = 20...90

    /// The VDOTs a measurement can have. Below 10 is less oxygen than an
    /// ordinary walk takes and above 90 is beyond any measured runner, so a
    /// reading outside this is a bad sample or a mistyped PB, not a runner.
    public static let plausibleRange: ClosedRange<Double> = 10...90

    /// `vdot` brought inside `validRange`.
    public static func clamped(_ vdot: Double) -> Double {
        min(max(vdot, validRange.lowerBound), validRange.upperBound)
    }

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

    /// The race time over `distanceMeters` that `vdot` predicts: the
    /// inverse of `vdot(fromRaceDistanceMeters:timeSeconds:)`, found by
    /// bisection (VDOT falls as the time grows). Nil outside 1 minute to
    /// 12 hours.
    public func raceTimeSeconds(distanceMeters: Double, vdot target: Double) -> Double? {
        guard distanceMeters > 0, target > 0 else { return nil }
        var fast = 60.0, slow = 12 * 3600.0
        guard let atFast = vdot(fromRaceDistanceMeters: distanceMeters, timeSeconds: fast),
              let atSlow = vdot(fromRaceDistanceMeters: distanceMeters, timeSeconds: slow),
              target <= atFast, target >= atSlow
        else { return nil }
        for _ in 0..<60 {
            let mid = (fast + slow) / 2
            guard let v = vdot(fromRaceDistanceMeters: distanceMeters, timeSeconds: mid) else { return nil }
            if v > target { fast = mid } else { slow = mid }
        }
        return (fast + slow) / 2
    }

    /// Velocity (m/min) at which oxygen demand equals `targetVO2`.
    /// Solves the quadratic `a2·v² + a1·v + (a0 - target) = 0`.
    public func velocity(forVO2Demand target: Double) -> Double {
        let A = Self.a2
        let B = Self.a1
        let C = Self.a0 - target
        // The discriminant is positive for any non-negative target VO₂, so
        // the closed-form solution is safe.
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
        // Neither has a pace band of its own.
        case .rest, .race: return .easy
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
    /// The runner's PB, for whichever distance it records. Its VDOT is
    /// distance-free, so a 10K PB anchors a marathon plan as well. A PB of
    /// unknown distance is ignored. Refines VDOT when VO₂ max is missing.
    public let personalBest: PersonalBest?
    /// Race-day deadline for the goal. When set in the future, the plan is
    /// shortened to fit (capped at the goal's default plan length, with a
    /// 4-week minimum so we still get a build + taper). When nil the default
    /// plan length is used.
    public let goalDate: Date?
    /// The runner's longest run of the last four weeks, in meters, from
    /// Health (`TrainingPlanGenerator.longestRecentRunMeters`): 0 when there
    /// was none. Week 1 starts from it. Nil when nothing is known, as in
    /// previews: week 1 is then the usual 70% of the peak week.
    public let recentLongestRunMeters: Double?
    /// Plan generation date (used only for `createdAt`; not for the schedule).
    public let today: Date

    public init(goal: RunningGoal,
                tier: PlanTier,
                longRunDay: Weekday = .sunday,
                vo2Max: Double? = nil,
                personalBest: PersonalBest? = nil,
                goalDate: Date? = nil,
                recentLongestRunMeters: Double? = nil,
                today: Date = Date()) {
        self.goal = goal
        self.tier = tier
        self.longRunDay = longRunDay
        self.vo2Max = vo2Max
        self.personalBest = personalBest
        self.goalDate = goalDate
        self.recentLongestRunMeters = recentLongestRunMeters
        self.today = today
    }
}

// MARK: - Generator

public struct TrainingPlanGenerator: Sendable {

    /// VDOT used when both VO₂ max and PB are missing. Corresponds to a ~25
    /// min 5K / ~6:20/km easy pace — a believable starting baseline for a
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
        // A race is the plan's last day: count the weeks back from it, so
        // the taper weeks line up with the race whatever its weekday. When
        // the plan's weeks reach it, week 1 begins up to six days before
        // today (more when the 4-week minimum applies). A race further out
        // than the plan's length moves week 1 later: the plan starts on the
        // day that makes it end on race day, and until then it isn't
        // running (`TrainingPlan.startsLater`).
        let cal = Calendar.current
        let raceDay = inputs.goalDate.flatMap { goalDate -> Date? in
            guard daysUntilRace(goalDate, today: inputs.today) != nil else { return nil }
            return cal.startOfDay(for: goalDate)
        }
        let start = raceDay.flatMap {
            cal.date(byAdding: .day, value: -(weekCount * 7 - 1), to: $0)
        }

        let peaks = peakRuns(goal: inputs.goal, tier: inputs.tier)
        let curve = volumeCurve(
            weeks: weekCount,
            start: startFraction(recentLongestRunMeters: inputs.recentLongestRunMeters,
                                 peakLongRunMeters: peaks.longKm * 1000)
        )
        var weeks = (1...weekCount).map { i in
            buildWeek(
                index: i,
                of: weekCount,
                fraction: curve[i - 1],
                peaks: peaks,
                goal: inputs.goal,
                tier: inputs.tier,
                longRunDay: inputs.longRunDay,
                vdot: vdot
            )
        }
        if let raceDay, let start {
            weeks = placingRace(on: raceDay, in: weeks, planStart: start, curve: curve,
                                peaks: peaks, goal: inputs.goal, vdot: vdot)
        }
        return TrainingPlan(
            goal: inputs.goal,
            tier: inputs.tier,
            longRunDay: inputs.longRunDay,
            weeks: weeks,
            vdot: vdot,
            usedBeginnerDefault: fromFallback,
            createdAt: inputs.today,
            startDate: start
        )
    }

    // MARK: VDOT resolution

    /// Pick the best VDOT we can from the runner's measurements:
    /// 1. VO₂ max from HealthKit.
    /// 2. Daniels-formula derivation from the user's PB for the goal distance.
    /// A measurement outside `VDOTCalculator.plausibleRange` is a bad
    /// sample or a mistyped PB and is ignored. The first measurement inside
    /// `VDOTCalculator.validRange` wins; when there's none, a slow one is
    /// clamped up to the range rather than swapped for the default: a slow
    /// runner's 18 is far nearer the truth than 38, whose paces suit a
    /// 25-minute 5K. The beginner default applies only with no measurement.
    /// Returns `(vdot, usedFallback)`.
    public func resolveVDOT(_ inputs: TrainingPlanInputs) -> (Double, Bool) {
        let fromPB = inputs.personalBest?.vdot
        let measured = [inputs.vo2Max, fromPB]
            .compactMap { $0 }
            .filter { VDOTCalculator.plausibleRange.contains($0) }
        if let inRange = measured.first(where: { VDOTCalculator.validRange.contains($0) }) {
            return (inRange, false)
        }
        if let slow = measured.first {
            return (VDOTCalculator.clamped(slow), false)
        }
        return (Self.beginnerVDOTFallback, true)
    }

    // MARK: Plan length

    /// How many weeks the plan should run. When `goalDate` is in the future,
    /// the plan is condensed to fit (never extended beyond the default — a
    /// race 6 months out doesn't need a 26-week 5K plan; it starts later
    /// instead). 4-week minimum so the structure (build + taper) survives.
    ///
    /// The count covers today through race day: a race exactly six weeks
    /// out, on today's weekday, needs seven weeks, the plan ending on it.
    public func planWeeks(for goal: RunningGoal,
                          goalDate: Date? = nil,
                          today: Date = Date()) -> Int {
        let defaultWeeks = defaultPlanWeeks(for: goal)
        guard let goalDate, let daysUntil = daysUntilRace(goalDate, today: today)
        else { return defaultWeeks }
        let weeksUntil = daysUntil / 7 + 1
        return max(4, min(defaultWeeks, weeksUntil))
    }

    /// Calendar days from today to race day: 0 when the race is today, at
    /// any hour. Nil once race day has passed.
    private func daysUntilRace(_ goalDate: Date, today: Date) -> Int? {
        let cal = Calendar.current
        guard let days = cal.dateComponents([.day],
                                            from: cal.startOfDay(for: today),
                                            to: cal.startOfDay(for: goalDate)).day,
              days >= 0
        else { return nil }
        return days
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
                           fraction: Double,
                           peaks: PeakRuns,
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
                fraction: fraction,
                peaks: peaks,
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
                             fraction: Double,
                             peaks: PeakRuns,
                             goal: RunningGoal,
                             tier: PlanTier,
                             vdot: Double) -> Workout {

        switch kind {
        case .rest:
            return .rest

        case .strides:
            // 4–6 × 20s strides woven into that week's easy run, so a
            // strides week weighs the same as any other.
            return easyWorkout(
                distance: peaks.easyKm * 1000 * fraction,
                vdot: vdot,
                kind: .strides,
                notes: "Easy run + 4–6 × 20 s strides on the flats."
            )

        case .easy:
            return easyWorkout(
                distance: peaks.easyKm * 1000 * fraction,
                vdot: vdot,
                kind: .easy
            )

        case .long:
            return easyWorkout(
                distance: peaks.longKm * 1000 * fraction,
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
                distanceMeters: marathonPaceMeters(goal: goal) * fraction,
                paceMinSecPerKm: pace - tol,
                paceMaxSecPerKm: pace + tol,
                notes: "Steady marathon-effort segment after a warm-up."
            )

        case .tempo, .threshold:
            let pace = vdotCalc.paceSecPerKm(vdot: vdot,
                                             fractionOfVDOT: TrainingIntensity.threshold.fractionOfVDOT)
            let tol = TrainingIntensity.threshold.paceToleranceSec
            return Workout(
                kind: .threshold,
                distanceMeters: thresholdMeters(tier: tier) * fraction,
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
            return Workout(
                kind: .interval,
                distanceMeters: intervalMeters(tier: tier) * fraction,
                paceMinSecPerKm: pace - tol,
                paceMaxSecPerKm: pace + tol,
                notes: "WU 2 km · 5 × 800 m @ I w/ equal-time jog · CD 2 km"
            )

        case .race:
            // Templates never hold a race; `placingRace` sets it on its date.
            return raceWorkout(goal: goal)
        }
    }

    // MARK: Race day

    /// The goal race: its full distance, no pace band to chase.
    private func raceWorkout(goal: RunningGoal) -> Workout {
        Workout(
            kind: .race,
            distanceMeters: goal.distanceMeters,
            paceMinSecPerKm: 0,
            paceMaxSecPerKm: 0,
            notes: "\(goal.displayName) race. Start controlled and let the taper work."
        )
    }

    /// Put the race on its date, the plan's last day. The day before it is
    /// rest, and the two days before that carry no quality session or long
    /// run: an easy run, never longer than the session it replaces.
    ///
    /// Weeks are 7-day blocks from `planStart`, and a block's days are
    /// found by weekday, the same way `TrainingPlan.todayWorkout` reads
    /// them back.
    private func placingRace(on raceDate: Date,
                             in weeks: [TrainingWeek],
                             planStart: Date,
                             curve: [Double],
                             peaks: PeakRuns,
                             goal: RunningGoal,
                             vdot: Double) -> [TrainingWeek] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: planStart)
        let dayCount = weeks.count * 7
        guard let raceOffset = cal.dateComponents([.day], from: start,
                                                  to: cal.startOfDay(for: raceDate)).day,
              raceOffset >= 0, raceOffset < dayCount
        else { return weeks }

        var days = weeks.map(\.days)

        // Rewrite the workout `offset` days after the plan's start; the
        // closure also gets that day's 1-based week number.
        func rewrite(_ offset: Int, _ change: (Workout, Int) -> Workout) {
            guard offset >= 0, offset < dayCount,
                  let date = cal.date(byAdding: .day, value: offset, to: start)
            else { return }
            let week = offset / 7
            let slot = Weekday(date: date, calendar: cal).rawValue
            let day = days[week][slot]
            days[week][slot] = TrainingDay(weekday: day.weekday,
                                           workout: change(day.workout, week + 1))
        }
        // A session turned into an easy run, never longer than it was.
        func easy(_ workout: Workout, week: Int) -> Workout {
            let distance = min(workout.distanceMeters, peaks.easyKm * 1000 * curve[week - 1])
            return easyWorkout(distance: distance, vdot: vdot, kind: .easy)
        }

        rewrite(raceOffset) { _, _ in self.raceWorkout(goal: goal) }
        rewrite(raceOffset - 1) { _, _ in .rest }
        for offset in [raceOffset - 2, raceOffset - 3] {
            rewrite(offset) { workout, week in
                workout.kind.isQuality || workout.kind == .long ? easy(workout, week: week) : workout
            }
        }

        return zip(weeks, days).map { week, rewritten in TrainingWeek(index: week.index, days: rewritten) }
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

    /// Sizes the easy runs: this, less the long-run benchmark, shared over
    /// the week's other runs as if each were easy. Quality sessions keep
    /// their own distances, so a week that has them comes out under this
    /// figure (the aggressive marathon's peak week is 85 km, not 95).
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

    /// The long-run benchmark for the goal: race + 25% for 5K/10K, around
    /// race distance for the half (24 km at most), and Pfitzinger's 37 km
    /// for the marathon. A plan's peak long run is this, cut to its share of
    /// the week (`peakRuns`).
    private func longRunBenchmarkKm(goal: RunningGoal, tier: PlanTier) -> Double {
        switch goal {
        case .fiveK:        return tier == .aggressive ? 10 : 8
        case .tenK:         return tier == .aggressive ? 16 : 14
        case .halfMarathon: return tier == .aggressive ? 24 : 20
        case .marathon:     return 37
        }
    }

    /// The most of a week's distance its long run may take. With three runs
    /// a week the long run can't fall under a third, so the share loosens
    /// as runs go down: 45% with three, 35% with four, 30% with five.
    public static func longRunShareCap(runsPerWeek: Int) -> Double {
        switch runsPerWeek {
        case ...3: return 0.45
        case 4:    return 0.35
        default:   return 0.30
        }
    }

    /// The peak week's long and easy runs, in km.
    struct PeakRuns {
        let longKm: Double
        let easyKm: Double
    }

    /// The peak week's long and easy runs. The week as the tier's template
    /// lays it out holds the long run, its quality sessions at their own
    /// distances, and its easy runs (a strides run counts as one). The long
    /// run is the goal's benchmark, cut to the tier's share of that week;
    /// the distance it gives up goes to the easy runs, so the week's total
    /// is what it was with the full benchmark.
    func peakRuns(goal: RunningGoal, tier: PlanTier) -> PeakRuns {
        let benchmark = longRunBenchmarkKm(goal: goal, tier: tier)
        let peakWeek = peakWeeklyKm(goal: goal, tier: tier)
        let easy = max((peakWeek - benchmark) / Double(tier.runsPerWeek - 1), 4)
        // Every week of a tier has the same easy-run count and quality
        // distance (the medium tier's alternating sessions are equally
        // long), so any week's template stands for the peak week.
        let layout = workoutTemplate(tier: tier, week: 1, of: 1, goal: goal)
        let easyRuns = Double(max(layout.filter { $0 == .easy || $0 == .strides }.count, 1))
        let quality = layout.reduce(0) { $0 + qualityMeters($1, tier: tier, goal: goal) } / 1000
        let week = benchmark + quality + easyRuns * easy
        let long = min(benchmark, Self.longRunShareCap(runsPerWeek: tier.runsPerWeek) * week)
        return PeakRuns(longKm: long, easyKm: easy + (benchmark - long) / easyRuns)
    }

    /// A quality session's distance at the peak; 0 for any other kind.
    private func qualityMeters(_ kind: WorkoutKind, tier: PlanTier, goal: RunningGoal) -> Double {
        switch kind {
        case .tempo, .threshold: return thresholdMeters(tier: tier)
        case .interval:          return intervalMeters(tier: tier)
        case .marathonPace:      return marathonPaceMeters(goal: goal)
        default:                 return 0
        }
    }

    /// Weekly distance rises by at most this factor from one week to the
    /// next (the usual 10% rule).
    private static let maxWeeklyRise = 1.10

    /// Week 1's share of the peak week when nothing is known of the runner.
    static let defaultStartFraction = 0.70
    /// The least week 1 can be, however little the runner has run lately.
    static let minimumStartFraction = 0.40

    /// Week 1's share of the peak week. With the runner's longest run of
    /// the last four weeks known, week 1's long run goes at most 10% past
    /// it: a beginner starts where they are, never under 40% of the peak,
    /// and a runner already past 70% starts at the usual 70%.
    func startFraction(recentLongestRunMeters: Double?, peakLongRunMeters: Double) -> Double {
        guard let longest = recentLongestRunMeters, peakLongRunMeters > 0
        else { return Self.defaultStartFraction }
        let reach = longest * Self.maxWeeklyRise / peakLongRunMeters
        return min(Self.defaultStartFraction, max(Self.minimumStartFraction, reach))
    }

    /// How far back the runner's longest recent run is looked for.
    public static let recentRunWindowDays = 28

    /// The longest run in `runs` that started in the last `days` calendar
    /// days, today included, in meters: 0 when there was none.
    public static func longestRecentRunMeters(in runs: [RunRecord],
                                              today: Date = Date(),
                                              days: Int = TrainingPlanGenerator.recentRunWindowDays) -> Double {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: today)) ?? today
        return runs
            .filter { $0.startDate >= from && $0.startDate <= today }
            .map(\.distanceMeters)
            .max() ?? 0
    }

    /// The longest recent run from a Health snapshot, or nil when the
    /// snapshot can't say: none at all, or one synced before the window
    /// began, whose runs stop short of it. Nil starts week 1 at the usual
    /// 70%, where a stale 0 would drop it to the floor.
    public static func longestRecentRunMeters(in snapshot: HealthDataSnapshot?,
                                              today: Date = Date()) -> Double? {
        guard let snapshot else { return nil }
        let cal = Calendar.current
        guard let windowStart = cal.date(byAdding: .day, value: -Self.recentRunWindowDays,
                                         to: cal.startOfDay(for: today)),
              snapshot.lastSyncedAt >= windowStart
        else { return nil }
        return longestRecentRunMeters(in: snapshot.runs, today: today)
    }

    /// Each week's share of the peak week, week 1 first. The build runs
    /// from `start` toward 100% at week `weeks - 3`, at most 10% up on the
    /// week before, then a three-week taper (70 / 50 / 30% of the peak the
    /// build reached) into race day. A full-length plan reaches the full
    /// peak; only the 8-week 5K's linear steps touch the limit, moving its
    /// weeks 2–3 by under 1%. A plan shortened by a race date, or started
    /// low for a beginner, builds only as far as the limit allows: its peak
    /// is lower, not its jumps bigger. The peak week is part of the build,
    /// so a full-length plan prescribes its peak long run somewhere.
    ///
    /// Every distance in a week scales by its one fraction, so the week's
    /// total rises by the same factor and the long run's share holds.
    func volumeCurve(weeks total: Int, start: Double) -> [Double] {
        let peakWeek = max(1, total - 3)  // the build peaks here
        var build = [start]
        if peakWeek > 1 {
            for w in 2...peakWeek {
                let progress = Double(w - 1) / Double(peakWeek - 1)
                let linear = start + (1 - start) * progress
                build.append(min(linear, build[w - 2] * Self.maxWeeklyRise))
            }
        }
        let peak = build[peakWeek - 1]
        return (1...max(total, 1)).map { week -> Double in
            if week <= peakWeek { return build[week - 1] }
            switch total - week {         // weeks to go
            case 0:  return 0.30 * peak   // race week
            case 1:  return 0.50 * peak   // the week before
            default: return 0.70 * peak   // mid-taper
            }
        }
    }

    /// The threshold session at the peak: warm-up, main set and cool-down.
    private func thresholdMeters(tier: PlanTier) -> Double {
        tier == .aggressive ? 10_000 : 8_000
    }

    /// The interval session at the peak: warm-up, reps, jogs and cool-down.
    /// Below the aggressive tier it matches the threshold session, since
    /// the medium tier alternates the two: weeks then differ only by the
    /// volume fraction.
    private func intervalMeters(tier: PlanTier) -> Double {
        tier == .aggressive ? 9_000 : 8_000
    }

    /// A marathon-pace session at the peak. Only marathon plans really use
    /// M-pace as a stand-alone, but a half plan can benefit from a short MP
    /// segment. Keep modest.
    private func marathonPaceMeters(goal: RunningGoal) -> Double {
        switch goal {
        case .marathon:     return 14_000
        case .halfMarathon: return 10_000
        default:            return 6_000
        }
    }
}
