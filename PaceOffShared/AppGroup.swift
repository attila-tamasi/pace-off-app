// AppGroup.swift
// Shared app group identifier for sharing state between iOS app, Watch app, and widget.

import Foundation

public enum AppGroup {
    /// Must match the App Group entitlement on the iOS app, Watch app, and widget targets.
    public static let identifier = "group.com.paceoff.app"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    public enum Keys {
        public static let lastTodayTarget = "paceoff.lastTodayTarget"
        public static let lastTodayVoiceLine = "paceoff.lastTodayVoiceLine"
        public static let runCompletedToday = "paceoff.runCompletedToday"
        public static let authComplete = "paceoff.authComplete"
        public static let onboardingComplete = "paceoff.onboardingComplete"
        public static let preferredVoiceTone = "paceoff.preferredVoiceTone"
        public static let notificationMorningHour = "paceoff.notif.morning"
        public static let notificationAfternoonHour = "paceoff.notif.afternoon"
        public static let notificationEveningHour = "paceoff.notif.evening"
        /// The daily pushes' on/off switch. Unset reads as on
        /// (`DailyPushPlanner.pushesEnabled`).
        public static let notificationsEnabled = "paceoff.notif.enabled"
        public static let userProfile = "paceoff.userProfile"
        public static let lastPlanWorkoutSummary = "paceoff.lastPlanWorkoutSummary"
        public static let planWorkoutCompletedToday = "paceoff.planWorkoutCompletedToday"
        /// Today's strength session for the widget ("Kettlebell · 35 min").
        public static let lastPlanStrengthSummary = "paceoff.lastPlanStrengthSummary"
        /// Whether a strength workout in Health covered today's session.
        public static let strengthCompletedToday = "paceoff.strengthCompletedToday"
        /// The day's prescribed distance in km (`DayPrescription`), absent
        /// on a rest day or when no prescription was written.
        public static let lastDayDistanceKm = "paceoff.lastDayDistanceKm"
        /// Set once a Health read has held a run. A runner back after more
        /// than the 90-day window gets a restart target, not the first-run
        /// card a new runner gets.
        public static let hasSeenRun = "paceoff.hasSeenRun"
    }

    /// Filename of the profile photo JPEG, stored in the App Group container
    /// (not UserDefaults — binary blobs don't belong there).
    public static let profilePhotoFilename = "profile-photo.jpg"

    /// Every App Group defaults key Pace Off writes starts with this.
    public static let keyPrefix = "paceoff."

    /// Filename of the active training plan's JSON in the container.
    public static let trainingPlanFilename = "training-plan.json"

    /// Whether a runner is set up (onboarding done). Nothing about a runner
    /// is computed, cached or shown before, or after they delete their data.
    public static var isRunnerSetUp: Bool {
        sharedDefaults?.bool(forKey: Keys.onboardingComplete) == true
    }

    /// The files Pace Off writes in the container: the active plan, the
    /// Health snapshot and the profile photo.
    public static let containerFiles = [trainingPlanFilename, HealthDataCache.filename, profilePhotoFilename]

    /// Erases everything Pace Off keeps in the App Group, for "Delete my
    /// data" and sign-out: every `keyPrefix` defaults key (profile, flags,
    /// settings, the widget's day) and every file in `containerFiles`.
    /// Apple Health keeps its data; only Pace Off's copy goes.
    public static func eraseAll(defaults: UserDefaults?,
                                containerURL: URL?,
                                fileManager: FileManager = .default) {
        if let defaults {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
        if let containerURL {
            for name in containerFiles {
                try? fileManager.removeItem(at: containerURL.appendingPathComponent(name))
            }
        }
    }

    /// URL of the shared App Group container directory, if available.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
