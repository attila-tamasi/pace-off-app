// AppGroupTests.swift
// "Delete my data" and sign-out erase everything Pace Off keeps in the App
// Group, and nothing else.

import XCTest
@testable import PaceOff

final class AppGroupTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var container: URL!

    override func setUpWithError() throws {
        suiteName = "PaceOffTests.appGroup.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: container)
    }

    func test_eraseAll_removesEveryPaceOffKey_andLeavesOthers() {
        defaults.set(Data([1]), forKey: AppGroup.Keys.userProfile)
        defaults.set(true, forKey: AppGroup.Keys.onboardingComplete)
        defaults.set(7, forKey: AppGroup.Keys.notificationMorningHour)
        defaults.set(true, forKey: AppGroup.Keys.hasSeenRun)
        defaults.set("x", forKey: "someone.else")

        AppGroup.eraseAll(defaults: defaults, containerURL: container)

        for key in [AppGroup.Keys.userProfile, AppGroup.Keys.onboardingComplete,
                    AppGroup.Keys.notificationMorningHour, AppGroup.Keys.hasSeenRun] {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.string(forKey: "someone.else"), "x")
    }

    func test_eraseAll_removesPaceOffsFiles_andLeavesOthers() throws {
        for name in AppGroup.containerFiles + ["Library-note.txt"] {
            try Data([1]).write(to: container.appendingPathComponent(name))
        }

        AppGroup.eraseAll(defaults: nil, containerURL: container)

        for name in AppGroup.containerFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: container.appendingPathComponent(name).path), name)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: container.appendingPathComponent("Library-note.txt").path))
    }

    func test_containerFiles_coverTheHealthSnapshotAndPhoto() {
        XCTAssertTrue(AppGroup.containerFiles.contains(HealthDataCache.filename))
        XCTAssertTrue(AppGroup.containerFiles.contains(AppGroup.profilePhotoFilename))
        XCTAssertTrue(AppGroup.containerFiles.contains("training-plan.json"))
    }

    func test_everyKey_hasThePrefixEraseAllLooksFor() {
        let keys = [AppGroup.Keys.lastTodayTarget, AppGroup.Keys.lastTodayVoiceLine,
                    AppGroup.Keys.runCompletedToday, AppGroup.Keys.authComplete,
                    AppGroup.Keys.onboardingComplete, AppGroup.Keys.preferredVoiceTone,
                    AppGroup.Keys.notificationMorningHour, AppGroup.Keys.notificationAfternoonHour,
                    AppGroup.Keys.notificationEveningHour, AppGroup.Keys.userProfile,
                    AppGroup.Keys.lastPlanWorkoutSummary, AppGroup.Keys.planWorkoutCompletedToday,
                    AppGroup.Keys.hasSeenRun, AppGroup.Keys.notificationsEnabled,
                    AppGroup.Keys.lastPlanStrengthSummary, AppGroup.Keys.strengthCompletedToday,
                    AppGroup.Keys.lastDayDistanceKm, AppGroup.Keys.sendWorkoutsToWatch,
                    AppGroup.Keys.bestEfforts, AppGroup.Keys.checkIn,
                    AppGroup.Keys.lastReadinessLevel, AppGroup.Keys.lastReadinessSentence]
        for key in keys {
            XCTAssertTrue(key.hasPrefix(AppGroup.keyPrefix), key)
        }
    }
}
