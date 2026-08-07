// PreviewSupport.swift
// Sample data + lightweight wiring for SwiftUI #Preview blocks. Lives only
// in DEBUG builds; never shipped.

#if DEBUG
import SwiftUI
import UIKit

// MARK: - Sample profile

extension UserProfile {
    /// A fully-set-up profile used as the default in previews.
    static var sample: UserProfile {
        UserProfile(
            displayName: "Alex Runner",
            birthday: Calendar.current.date(from: DateComponents(year: 1992, month: 4, day: 17)),
            goal: .halfMarathon,
            personalBest: PersonalBest(durationSeconds: 5_482, year: 2024),
            appleUserID: "preview-user.000123",
            hasPhoto: false
        )
    }

    /// A blank profile, for views that render the "not yet set up" path.
    static var empty: UserProfile { UserProfile() }
}

// MARK: - Sample runs

extension RunRecord {
    /// A single representative 8 km run with full running-dynamics data.
    static var sample: RunRecord {
        let now = Date()
        return RunRecord(
            startDate: Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now,
            endDate: Calendar.current.date(byAdding: .minute, value: -75, to: now) ?? now,
            distanceMeters: 8_120,
            durationSeconds: 45 * 60 + 22,
            activeEnergyKcal: 612,
            averageHeartRate: 154,
            averagePace: 335,
            averagePowerWatts: 248,
            averageStrideLengthMeters: 1.24,
            averageVerticalOscillationCm: 8.2,
            averageGroundContactMs: 232,
            averageCadenceSpm: 174,
            targetDistanceMeters: 8_000,
            hitTarget: true
        )
    }

    /// ~12 weeks of varied runs — enough to populate History grouping and
    /// the weekly-distance / pace charts in Trends.
    static var samples: [RunRecord] {
        let cal = Calendar.current
        let today = Date()
        let plan: [(daysAgo: Int, km: Double, paceSec: Double)] = [
            (1, 8.1, 335), (3, 5.2, 348), (6, 12.4, 352), (8, 4.0, 342),
            (10, 6.6, 339), (13, 10.0, 346), (15, 3.5, 358), (18, 7.8, 331),
            (21, 5.0, 350), (24, 9.4, 344), (28, 6.0, 336), (32, 11.0, 349),
            (35, 4.4, 340), (38, 8.6, 337), (42, 5.5, 351), (47, 7.0, 333),
            (52, 9.0, 345), (58, 6.5, 339), (63, 10.2, 348), (70, 7.5, 336),
            (78, 5.8, 354), (84, 8.8, 341)
        ]
        return plan.map { entry in
            let start = cal.date(byAdding: .day, value: -entry.daysAgo, to: today) ?? today
            let duration = entry.paceSec * entry.km
            return RunRecord(
                startDate: start,
                endDate: start.addingTimeInterval(duration),
                distanceMeters: entry.km * 1000,
                durationSeconds: duration,
                activeEnergyKcal: entry.km * 72,
                averageHeartRate: 148 + Double(entry.daysAgo % 7),
                averagePace: entry.paceSec,
                averagePowerWatts: 240 + Double(entry.daysAgo % 12),
                averageStrideLengthMeters: 1.22,
                averageVerticalOscillationCm: 8.4,
                averageGroundContactMs: 234,
                averageCadenceSpm: 172,
                targetDistanceMeters: entry.km * 1000,
                hitTarget: entry.km >= 5
            )
        }
    }
}

// MARK: - Sample target

extension RunTarget {
    /// A typical "firm" push: 8 km, slight downward VO₂ slope.
    static var sample: RunTarget {
        RunTarget(
            distanceMeters: 7_700,
            tone: .firm,
            daysSinceLastRun: 1,
            vo2MaxSlope: -0.05,
            baselineMeters: 7_200,
            ceilingClamped: false,
            fatigueGuardActive: false,
            computedAt: Date()
        )
    }
}

// MARK: - Sample readiness

extension DailyReadiness {
    /// A yellow "ease off" day — HRV dipped below baseline overnight.
    static var sample: DailyReadiness {
        DailyReadiness(
            level: .yellow,
            sentence: "HRV below your baseline — easy day.",
            hrvMs: 54,
            hrvBaselineMs: 63,
            restingHR: 52,
            restingHRBaseline: 51,
            computedAt: Date()
        )
    }

    /// A red rest day — both signals off baseline.
    static var sampleRed: DailyReadiness {
        DailyReadiness(
            level: .red,
            sentence: "HRV down and resting heart rate up — your body is asking for rest.",
            hrvMs: 44,
            hrvBaselineMs: 63,
            restingHR: 56,
            restingHRBaseline: 51,
            computedAt: Date()
        )
    }
}

// MARK: - Sample VO₂ max series

extension VO2MaxSnapshot {
    /// A year of weekly readings drifting between 46 and 52, used by the
    /// VO₂ Max detail screen and the Trends chart.
    static var samples: [VO2MaxSnapshot] {
        let cal = Calendar.current
        let today = Date()
        return (0..<52).map { weeksAgo in
            let date = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: today) ?? today
            let trend = 48.0 + sin(Double(weeksAgo) / 6.0) * 2.4 - Double(weeksAgo) * 0.03
            return VO2MaxSnapshot(date: date, value: trend)
        }
        .reversed()
    }
}

// MARK: - Preview ProfileStore

@MainActor
enum PreviewProfileStore {
    /// A populated store, used by views that render the runner's identity.
    static var populated: ProfileStore {
        let store = ProfileStore()
        store.previewLoad(profile: .sample, photo: nil)
        return store
    }

    /// An empty store, used by views that render the "needs setup" path.
    static var empty: ProfileStore {
        let store = ProfileStore()
        store.previewLoad(profile: nil, photo: nil)
        return store
    }

    /// Marathon goal with a race day 14 weeks out. Used by the training-plan
    /// picker preview to exercise the race-date code path.
    static var marathonWithRaceDay: ProfileStore {
        var profile = UserProfile.sample
        profile.goal = .marathon
        profile.goalDate = Calendar.current.date(byAdding: .weekOfYear, value: 14, to: Date())
        profile.personalBest = PersonalBest(durationSeconds: 14_400, year: 2024) // 4:00:00
        let store = ProfileStore()
        store.previewLoad(profile: profile, photo: nil)
        return store
    }
}

// MARK: - Preview AppleSignInService

@MainActor
enum PreviewAppleSignInService {
    static var signedIn: AppleSignInService {
        let svc = AppleSignInService.shared
        svc.previewSetState(.signedIn)
        return svc
    }

    static var notSignedIn: AppleSignInService {
        let svc = AppleSignInService.shared
        svc.previewSetState(.notSignedIn)
        return svc
    }
}
#endif
