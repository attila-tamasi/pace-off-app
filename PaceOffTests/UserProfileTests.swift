// UserProfileTests.swift
// The personal best and its distance: converting a PB for one distance to
// another through VDOT, and profiles saved before a PB had a distance.

import XCTest
@testable import PaceOff

final class UserProfileTests: XCTestCase {

    private let calc = VDOTCalculator()

    // MARK: - VDOT, both ways

    func test_raceTime_isTheInverseOfVDOT() {
        for (distance, time) in [(5_000.0, 1_500.0), (10_000, 2_700), (21_097.5, 6_300), (42_195, 14_400)] {
            let vdot = calc.vdot(fromRaceDistanceMeters: distance, timeSeconds: time)!
            let back = calc.raceTimeSeconds(distanceMeters: distance, vdot: vdot)
            XCTAssertEqual(back ?? 0, time, accuracy: 1, "\(distance) m")
        }
    }

    func test_raceTime_matchesDanielsTable_atVDOT50() {
        // Daniels: VDOT 50 is a 19:57 5K and a 3:10:49 marathon.
        XCTAssertEqual(calc.raceTimeSeconds(distanceMeters: 5_000, vdot: 50) ?? 0, 1_197, accuracy: 10)
        XCTAssertEqual(calc.raceTimeSeconds(distanceMeters: 42_195, vdot: 50) ?? 0, 11_449, accuracy: 60)
    }

    func test_raceTime_isNil_outOfRange() {
        XCTAssertNil(calc.raceTimeSeconds(distanceMeters: 5_000, vdot: 0))
        XCTAssertNil(calc.raceTimeSeconds(distanceMeters: 0, vdot: 50))
        XCTAssertNil(calc.raceTimeSeconds(distanceMeters: 5_000, vdot: 5_000))
    }

    // MARK: - A PB for another distance

    func test_PB_overItsOwnDistance_isTheTimeItself() {
        let pb = PersonalBest(durationSeconds: 2_700, year: 2026, distance: .tenK)
        XCTAssertEqual(pb.equivalentSeconds(at: .tenK), 2_700)
    }

    func test_PB_forAnotherDistance_isConvertedThroughVDOT_neverUsedRaw() {
        // A 45:00 10K is VDOT 45.3: about 1:39:44 for the half, 3:27:15 for
        // the marathon. Used raw it would claim a 45-minute half.
        let pb = PersonalBest(durationSeconds: 2_700, year: 2026, distance: .tenK)
        XCTAssertEqual(pb.vdot ?? 0, 45.26, accuracy: 0.01)
        XCTAssertEqual(pb.equivalentSeconds(at: .halfMarathon) ?? 0, 5_984, accuracy: 5)
        XCTAssertEqual(pb.equivalentSeconds(at: .marathon) ?? 0, 12_435, accuracy: 5)
    }

    func test_PB_ofUnknownDistance_isNotUsed() {
        let pb = PersonalBest(durationSeconds: 2_700, year: 2026, distance: nil)
        XCTAssertNil(pb.vdot)
        XCTAssertNil(pb.equivalentSeconds(at: .tenK))
    }

    func test_PB_noOneCouldRun_isNotUsed() {
        // A 0:00 left by the toggle, or a 4:30 10K typo.
        for pb in [PersonalBest(durationSeconds: 0, year: 2026, distance: .tenK),
                   PersonalBest(durationSeconds: 270, year: 2026, distance: .tenK)] {
            XCTAssertNil(pb.vdot)
            XCTAssertNil(pb.equivalentSeconds(at: .tenK))
            XCTAssertNil(pb.equivalentSeconds(at: .halfMarathon))
        }
    }

    // MARK: - Migration

    func test_profileSavedWithoutAPBDistance_getsTheGoals() throws {
        let json = """
        {"displayName":"Ana","goal":"halfMarathon","hasPhoto":false,
         "personalBest":{"durationSeconds":5482,"year":2024}}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.personalBest?.distance, .halfMarathon)
        XCTAssertEqual(profile.personalBest?.durationSeconds, 5_482)
        XCTAssertEqual(profile.goal, .halfMarathon)
        XCTAssertNil(profile.goalDate)
    }

    func test_profileSavedWithoutAPBDistance_whoseTimeCantBeTheGoals_leavesItUnknown() throws {
        // A 45:00 10K, saved before distances, by a runner who has since
        // switched the goal to the half: it isn't a 45-minute half.
        let json = """
        {"displayName":"Ana","goal":"halfMarathon","hasPhoto":false,
         "personalBest":{"durationSeconds":2700,"year":2024}}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertNotNil(profile.personalBest)
        XCTAssertNil(profile.personalBest?.distance)
        XCTAssertNil(profile.personalBest?.vdot)
    }

    func test_profile_keepsAPBForAnotherDistance_throughAGoalChange() throws {
        var profile = UserProfile(displayName: "Ana", goal: .tenK,
                                  personalBest: PersonalBest(durationSeconds: 2_700, year: 2026, distance: .tenK))
        profile.goal = .marathon
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.personalBest?.distance, .tenK)
        XCTAssertEqual(decoded, profile)
    }

    func test_profileWithoutAGoal_doesNotDecode() {
        // A broken blob fails, as before, rather than loading a goal no one chose.
        let json = #"{"displayName":"Ana"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8)))
    }

    func test_oldestProfileShape_stillDecodes() throws {
        // Before goalDate, appleUserID and hasPhoto existed.
        let json = #"{"displayName":"Ana","goal":"fiveK"}"#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.goal, .fiveK)
        XCTAssertFalse(profile.hasPhoto)
        XCTAssertNil(profile.personalBest)
    }
}
