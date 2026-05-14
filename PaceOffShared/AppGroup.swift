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
        public static let onboardingComplete = "paceoff.onboardingComplete"
        public static let preferredVoiceTone = "paceoff.preferredVoiceTone"
        public static let notificationMorningHour = "paceoff.notif.morning"
        public static let notificationAfternoonHour = "paceoff.notif.afternoon"
        public static let notificationEveningHour = "paceoff.notif.evening"
        public static let userProfile = "paceoff.userProfile"
    }

    /// Filename of the profile photo JPEG, stored in the App Group container
    /// (not UserDefaults — binary blobs don't belong there).
    public static let profilePhotoFilename = "profile-photo.jpg"

    /// URL of the shared App Group container directory, if available.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
