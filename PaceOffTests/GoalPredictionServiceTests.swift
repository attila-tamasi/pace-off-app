// GoalPredictionServiceTests.swift
// Covers the Riegel math, candidate selection, PB integration, age grading,
// and confidence buckets. Numbers below are independently sanity-checked
// against published Riegel and WMA age-grade tables.

import XCTest
@testable import PaceOff

final class GoalPredictionServiceTests: XCTestCase {

    private let service = GoalPredictionService()

    private func run(daysAgo: Int, km: Double, paceSecPerKm: Double, today: Date = Date()) -> RunRecord {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        let duration = paceSecPerKm * km
        return RunRecord(
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            distanceMeters: km * 1000,
            durationSeconds: duration
        )
    }

    // MARK: - Riegel math

    func test_riegel_5kTo10k_canonical() {
        // 5K in 20:00 (1200s) → 10K via Riegel should be ~41:35.
        let t = service.riegel(fromDistanceMeters: 5_000,
                               timeSeconds: 1200,
                               toDistanceMeters: 10_000)
        XCTAssertNotNil(t)
        XCTAssertEqual(t!, 2495, accuracy: 10) // ~41:35 ±10s
    }

    func test_riegel_10kToHalfMarathon() {
        // 10K in 45:00 (2700s) → half marathon should be ~1:39:50.
        let t = service.riegel(fromDistanceMeters: 10_000,
                               timeSeconds: 2700,
                               toDistanceMeters: 21_097.5)
        XCTAssertNotNil(t)
        XCTAssertEqual(t!, 5_988, accuracy: 30)
    }

    func test_riegel_rejectsTooShortSource() {
        // 1 km in 4:00 is too short to extrapolate from.
        let t = service.riegel(fromDistanceMeters: 1_000,
                               timeSeconds: 240,
                               toDistanceMeters: 10_000)
        XCTAssertNil(t)
    }

    // MARK: - Age grading

    func test_ageGrade_youngRunnerIsOpen() {
        XCTAssertEqual(service.ageGradeFactor(age: 25), 1.0, accuracy: 0.0001)
        XCTAssertEqual(service.ageGradeFactor(age: 30), 1.0, accuracy: 0.0001)
    }

    func test_ageGrade_anchorPointsMatchWMATable() {
        // Spot-check several anchors from the WMA-style table the service ships.
        XCTAssertEqual(service.ageGradeFactor(age: 40), 0.965, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 50), 0.908, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 60), 0.834, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 70), 0.738, accuracy: 0.005)
    }

    func test_ageGrade_interpolatesBetweenAnchors() {
        // 42 should fall between 40 (0.965) and 45 (0.940) — closer to 40.
        let f = service.ageGradeFactor(age: 42)
        XCTAssertTrue(f < 0.965 && f > 0.940, "Got \(f)")
    }

    func test_ageGrade_clampsAboveTable() {
        XCTAssertEqual(service.ageGradeFactor(age: 200), service.ageGradeFactor(age: 90), accuracy: 0.0001)
    }

    // MARK: - End-to-end predict()

    func test_predict_returnsNilWhenNoUsableInputs() {
        let p = service.predict(goal: .tenK, runs: [], age: 35, personalBest: nil)
        XCTAssertNil(p)
    }

    func test_predict_usesRecentRun_andReportsHighConfidenceNearGoal() {
        let today = Date()
        // Five recent 8 km runs at 5:00/km — the freshest within the 30-day window.
        let runs = (1...5).map { i in
            run(daysAgo: i * 5, km: 8, paceSecPerKm: 300, today: today)
        }
        let p = service.predict(goal: .tenK,
                                runs: runs,
                                age: 35,
                                personalBest: nil,
                                today: today)
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(p.goal, .tenK)
        // 8 km @ 5:00/km = 40:00. Riegel to 10 km ≈ 50:53.
        XCTAssertEqual(p.projectedTimeSeconds, 3_053, accuracy: 30)
        XCTAssertEqual(p.projectedPaceSecPerKm, p.projectedTimeSeconds / 10, accuracy: 0.5)
        XCTAssertEqual(p.confidence, .high)
        XCTAssertNotNil(p.ageGradedEquivalentSeconds)
    }

    func test_predict_prefersFasterOfRunVsPB() {
        let today = Date()
        // One reasonable training run + a PB that's clearly faster — service
        // should anchor on the PB.
        let runs = [run(daysAgo: 7, km: 10, paceSecPerKm: 360, today: today)] // 60:00 10K
        let pb = PersonalBest(durationSeconds: 2700, year: 2024)              // 45:00 10K
        let p = service.predict(goal: .tenK,
                                runs: runs,
                                age: 35,
                                personalBest: pb,
                                today: today)
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.projectedTimeSeconds, 2700, accuracy: 0.1)
        if case .personalBestExtrapolation = p!.basis {} else {
            XCTFail("Expected PB basis, got \(p!.basis)")
        }
    }

    func test_predict_picksFastestRunWhenMultiple() {
        let today = Date()
        let slow = run(daysAgo: 30, km: 5, paceSecPerKm: 360, today: today) // 30:00 5K
        let fast = run(daysAgo: 10, km: 5, paceSecPerKm: 240, today: today) // 20:00 5K — much fitter
        let p = service.predict(goal: .tenK,
                                runs: [slow, fast],
                                age: nil,
                                personalBest: nil,
                                today: today)
        XCTAssertNotNil(p)
        // 5 km @ 4:00/km = 20:00. Riegel to 10 km ≈ 41:35.
        XCTAssertEqual(p!.projectedTimeSeconds, 2_495, accuracy: 30)
    }

    func test_predict_dropsRunsOlderThanWindow() {
        let today = Date()
        let stale = run(daysAgo: 120, km: 8, paceSecPerKm: 240, today: today) // outside 60d window
        let p = service.predict(goal: .tenK,
                                runs: [stale],
                                age: nil,
                                personalBest: nil,
                                today: today)
        XCTAssertNil(p)
    }

    func test_predict_reportsLowConfidenceWithJustOneRun() {
        let today = Date()
        let runs = [run(daysAgo: 4, km: 6, paceSecPerKm: 300, today: today)]
        let p = service.predict(goal: .tenK,
                                runs: runs,
                                age: nil,
                                personalBest: nil,
                                today: today)
        XCTAssertEqual(p?.confidence, .low)
    }

    func test_predict_gapToPersonalBestIsSignedSeconds() {
        let today = Date()
        let recent = run(daysAgo: 5, km: 10, paceSecPerKm: 240, today: today) // 40:00 10K
        let slowerPB = PersonalBest(durationSeconds: 2700, year: 2024)        // 45:00 10K — recent is faster
        let p = service.predict(goal: .tenK,
                                runs: [recent],
                                age: nil,
                                personalBest: slowerPB,
                                today: today)
        XCTAssertNotNil(p?.gapToPersonalBestSeconds)
        XCTAssertLessThan(p!.gapToPersonalBestSeconds!, 0) // projected ahead of PB
    }
}
