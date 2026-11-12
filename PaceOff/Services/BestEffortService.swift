// BestEffortService.swift
// Keeps the runner's best efforts up to date: after a foreground refresh it
// reads the routes of runs not looked at yet (a few per refresh, newest
// first, the last 90 days), folds their fastest 1 km, 5 km, 10 km and half
// marathon into the log, makes a faster best the PB for its distance, and
// sends one notification for bests set in the last three days. The first
// fill sends none, so an existing history doesn't arrive as a burst.

import Foundation
import Observation

@MainActor
@Observable
public final class BestEffortService {

    public static let shared = BestEffortService()

    /// The bests as last loaded or updated, for Profile.
    public private(set) var log: BestEffortLog

    /// Routes read per refresh, so a long history is filled in over a few
    /// launches rather than all at once.
    static let routesPerRefresh = 12
    /// A best older than this is caught up quietly, without a notification.
    static let notifyWithinDays = 3.0

    private init() {
        log = BestEffortLog.load(from: AppGroup.sharedDefaults)
    }

    public func update(runs: [RunRecord], now: Date = Date()) async {
        let defaults = AppGroup.sharedDefaults
        var log = BestEffortLog.load(from: defaults)
        let firstFill = log.seenRunStarts.isEmpty
        let todo = log.unseen(runs, now: now).prefix(Self.routesPerRefresh)
        guard !todo.isEmpty else {
            self.log = log
            return
        }
        var improved: [BestEffort] = []
        for run in todo {
            let route = await HealthKitService.shared.fetchRoutePoints(for: run)
            improved += log.record(runStart: run.startDate,
                                   efforts: BestEfforts.efforts(route: route, runStart: run.startDate))
        }
        // Deleted or signed out while the routes were read: keep nothing.
        guard AppGroup.isRunnerSetUp else { return }
        log.save(to: defaults)
        self.log = log

        if let profile = ProfileStore.shared.profile,
           let pb = BestEffortLog.updatedPB(current: profile.personalBest, goal: profile.goal, improved: improved) {
            ProfileStore.shared.update { $0.personalBest = pb }
        }

        // Only bests that still stand, from recent runs.
        let fresh = improved.filter { effort in
            log.best(effort.distance) == effort
                && now.timeIntervalSince(effort.runStart) < Self.notifyWithinDays * 86_400
        }
        if !firstFill, let body = BestEffortLog.notificationBody(Self.latestRunOnly(fresh)) {
            NotificationScheduler.shared.notifyBestEffort(body)
        }
    }

    /// The efforts of the most recent run among them, in distance order:
    /// one notification names one run.
    private static func latestRunOnly(_ efforts: [BestEffort]) -> [BestEffort] {
        guard let latest = efforts.map(\.runStart).max() else { return [] }
        return efforts.filter { $0.runStart == latest }
            .sorted { $0.distance.meters < $1.distance.meters }
    }

    /// After "Delete my data" or sign-out.
    public func reset() {
        log = BestEffortLog()
    }
}
