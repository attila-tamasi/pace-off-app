// BestEffortLog.swift
// The best efforts kept across runs (`BestEfforts`), and which runs' routes
// have been looked at, so each route is read once. Stored as JSON in App
// Group defaults (`AppGroup.Keys.bestEfforts`), erased with the runner's
// other data. Pure apart from load and save.

import Foundation

public struct BestEffortLog: Codable, Equatable, Sendable {

    /// The fastest of each distance so far, in `BestEffortDistance` order.
    public private(set) var bests: [BestEffort]
    /// Start times (seconds since 1970) of the runs already looked at.
    public private(set) var seenRunStarts: Set<Double>

    /// Runs older than this aren't looked at.
    public static let windowDays = 90
    /// Runs shorter than the shortest distance can't hold an effort.
    public static let minimumMeters = 1_000.0
    /// A run's route can reach Health after the run itself (the watch syncs
    /// it later), so a run without one is looked at again until this long
    /// after it ended.
    public static let routeWaitHours = 24.0

    public init(bests: [BestEffort] = [], seenRunStarts: Set<Double> = []) {
        self.bests = bests
        self.seenRunStarts = seenRunStarts
    }

    public func best(_ distance: BestEffortDistance) -> BestEffort? {
        bests.first { $0.distance == distance }
    }

    /// The runs of the last 90 days, at least 1 km, not looked at yet,
    /// newest first.
    public func unseen(_ runs: [RunRecord], now: Date) -> [RunRecord] {
        let earliest = now.addingTimeInterval(-Double(Self.windowDays) * 86_400)
        return runs
            .filter { $0.startDate >= earliest && $0.startDate <= now }
            .filter { $0.distanceMeters >= Self.minimumMeters }
            .filter { !seenRunStarts.contains($0.startDate.timeIntervalSince1970) }
            .sorted { $0.startDate > $1.startDate }
    }

    /// Whether a run read with `routeIsEmpty` is done with: it has a route,
    /// or it ended long enough ago that none is coming (a treadmill run).
    public static func isSettled(_ run: RunRecord, routeIsEmpty: Bool, now: Date) -> Bool {
        !routeIsEmpty || now.timeIntervalSince(run.endDate) >= routeWaitHours * 3600
    }

    /// Folds one run's efforts in and marks it looked at. Returns the
    /// efforts that set or beat a best.
    @discardableResult
    public mutating func record(runStart: Date, efforts: [BestEffort]) -> [BestEffort] {
        seenRunStarts.insert(runStart.timeIntervalSince1970)
        let (merged, improved) = BestEfforts.merge(bests, with: efforts)
        bests = merged
        return improved
    }

    // MARK: - What a new best changes

    /// The PB after `improved`: a best over the PB's own distance that's
    /// faster replaces it; with no PB stored, a best over the goal's
    /// distance becomes it. Nil when nothing changes. The 1 km sets no PB.
    public static func updatedPB(current: PersonalBest?, goal: RunningGoal, improved: [BestEffort],
                                 calendar: Calendar = .current) -> PersonalBest? {
        var pb = current
        for effort in improved {
            guard let distance = effort.distance.goal else { continue }
            let year = calendar.component(.year, from: effort.runStart)
            if let existing = pb, existing.distance == distance {
                if effort.seconds < existing.durationSeconds {
                    pb = PersonalBest(durationSeconds: effort.seconds, year: year, distance: distance)
                }
            } else if pb == nil, distance == goal {
                pb = PersonalBest(durationSeconds: effort.seconds, year: year, distance: distance)
            }
        }
        return pb == current ? nil : pb
    }

    /// "New best: 5 km in 22:41, inside Tuesday's run." With more than one:
    /// "New bests: 1 km in 3:58 and 5 km in 22:41, inside Tuesday's run."
    public static func notificationBody(_ efforts: [BestEffort], calendar: Calendar = .current) -> String? {
        guard let first = efforts.first else { return nil }
        let parts = efforts.map { "\($0.distance.displayName) in \(formatTime($0.seconds))" }
        let list = parts.count == 1 ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        let day = weekdayNames[calendar.component(.weekday, from: first.runStart) - 1]
        return "\(efforts.count == 1 ? "New best" : "New bests"): \(list), inside \(day)'s run."
    }

    /// "22:41", "1:41:05".
    public static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    // MARK: - App Group defaults

    public static func load(from defaults: UserDefaults?) -> BestEffortLog {
        guard let data = defaults?.data(forKey: AppGroup.Keys.bestEfforts),
              let log = try? JSONDecoder().decode(BestEffortLog.self, from: data)
        else { return BestEffortLog() }
        return log
    }

    public func save(to defaults: UserDefaults?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: AppGroup.Keys.bestEfforts)
    }
}
