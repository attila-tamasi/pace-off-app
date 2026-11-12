// PaceSource.swift
// Where a plan's paces come from. The Apple Watch VO₂ max estimate reads
// low for many runners, so a recent hard run says more: the plan's VDOT is
// the higher of the best VDOT among the last 90 days' 5 km, 10 km and
// half-marathon best efforts (`BestEfforts`) and Health's latest VO₂ max.
// Without either, the typed PB, then the beginner default. A value inside
// the formula's 20–90 range wins over a slow one (10–20), which is raised
// to 20. The 1 km best never sets paces: a short effort overstates
// endurance.
//
// Pure and Sendable: the plan picker, the rebuild before a plan starts and
// the background retune all resolve the VDOT here.

import Foundation

public enum PaceSource: Codable, Equatable, Sendable {
    /// A best effort inside a recent run.
    case bestEffort(BestEffort)
    /// Health's latest VO₂ max, in ml/kg/min.
    case vo2Max(Double)
    /// The PB the runner typed in.
    case personalBest(PersonalBest)
    /// No measurement: `TrainingPlanGenerator.beginnerVDOTFallback`.
    case beginnerDefault

    /// Best efforts older than this don't set paces.
    public static let effortWindowDays = 90

    /// The distances whose best efforts can set paces.
    public static let effortDistances: Set<BestEffortDistance> = [.fiveK, .tenK, .halfMarathon]

    /// The VDOT and where it came from.
    public struct Resolution: Equatable, Sendable {
        public let vdot: Double
        public let source: PaceSource
        public var usedFallback: Bool { source == .beginnerDefault }
    }

    /// The plan's VDOT from what's known about the runner. A value outside
    /// `VDOTCalculator.plausibleRange` is a bad sample or a typo and is
    /// ignored; a slow one (10–20) is raised to the formula's 20.
    public static func resolve(vo2Max: Double?,
                               personalBest: PersonalBest?,
                               bestEfforts: [BestEffort],
                               today: Date) -> Resolution {
        let plausible = VDOTCalculator.plausibleRange
        let earliest = today.addingTimeInterval(-Double(effortWindowDays) * 86_400)
        let calculator = VDOTCalculator()

        var candidates: [(vdot: Double, source: PaceSource)] = bestEfforts
            .filter { effortDistances.contains($0.distance) && $0.runStart >= earliest && $0.runStart <= today }
            .compactMap { effort in
                calculator.vdot(fromRaceDistanceMeters: effort.distance.meters, timeSeconds: effort.seconds)
                    .map { (vdot: $0, source: PaceSource.bestEffort(effort)) }
            }
        if let vo2Max { candidates.append((vdot: vo2Max, source: .vo2Max(vo2Max))) }
        // A best effort wins a tie: it's a run, not an estimate.
        let measured = candidates.filter { plausible.contains($0.vdot) }.max { $0.vdot < $1.vdot }
        var fromPB: (vdot: Double, source: PaceSource)?
        if let personalBest, let vdot = personalBest.vdot, plausible.contains(vdot) {
            fromPB = (vdot: vdot, source: .personalBest(personalBest))
        }

        // One inside the formula's range first, the PB only without a
        // measurement there; then a slow one, raised to the range.
        let valid = VDOTCalculator.validRange
        let inRange = [measured, fromPB].compactMap { $0 }.first { valid.contains($0.vdot) }
        let pick = inRange ?? measured ?? fromPB
        guard let pick else {
            return Resolution(vdot: TrainingPlanGenerator.beginnerVDOTFallback, source: .beginnerDefault)
        }
        return Resolution(vdot: VDOTCalculator.clamped(pick.vdot), source: pick.source)
    }

    /// The plan detail's line: "Paces from your 10 km on 3 Nov (48:12)",
    /// "Paces from your VO₂ max in Health (46.1)".
    public func note(calendar: Calendar = .current) -> String {
        switch self {
        case .bestEffort(let effort):
            return "Paces from your \(effort.distance.displayName) on \(Self.dayText(effort.runStart, calendar: calendar)) (\(BestEffortLog.formatTime(effort.seconds)))"
        case .vo2Max(let value):
            return "Paces from your VO₂ max in Health (\(String(format: "%.1f", value)))"
        case .personalBest(let pb):
            let distance = pb.distance.map { "\($0.displayName) " } ?? ""
            return "Paces from your \(distance)PB (\(pb.formattedTime))"
        case .beginnerDefault:
            return "Paces from a starting estimate: no VO₂ max, PB or recent hard run yet"
        }
    }

    /// "3 Nov".
    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
