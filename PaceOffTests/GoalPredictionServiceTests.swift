// GoalPredictionServiceTests.swift
// Covers the Riegel math, candidate selection, PB age decay, VO₂ adjustment,
// goal-date training improvement, and confidence buckets.

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

    private func vo2(daysAgo: Int, value: Double, today: Date = Date()) -> VO2MaxSnapshot {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return VO2MaxSnapshot(date: date, value: value)
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
        XCTAssertEqual(service.ageGradeFactor(age: 40), 0.965, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 50), 0.908, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 60), 0.834, accuracy: 0.005)
        XCTAssertEqual(service.ageGradeFactor(age: 70), 0.738, accuracy: 0.005)
    }

    func test_ageGrade_interpolatesBetweenAnchors() {
        let f = service.ageGradeFactor(age: 42)
        XCTAssertTrue(f < 0.965 && f > 0.940, "Got \(f)")
    }

    func test_ageGrade_clampsAboveTable() {
        XCTAssertEqual(service.ageGradeFactor(age: 200), service.ageGradeFactor(age: 90), accuracy: 0.0001)
    }

    // MARK: - PB age decay (new)

    func test_pbDecay_freshPbHasNoPenalty() {
        XCTAssertEqual(service.pbDecayMultiplier(pbYearsOld: 0), 1.0, accuracy: 0.0001)
    }

    func test_pbDecay_oneYearIsHalfPercent() {
        XCTAssertEqual(service.pbDecayMultiplier(pbYearsOld: 1), 1.005, accuracy: 0.0001)
    }

    func test_pbDecay_tenYearsIsRoughlyEightPercent() {
        // 5 years at 0.5%/yr ≈ +2.53%, then 5 years at 1%/yr ≈ +5.10% more.
        // Compounded ≈ 1.005^5 * 1.010^5 ≈ 1.078 → ~7.8% slower than PB.
        let m = service.pbDecayMultiplier(pbYearsOld: 10)
        XCTAssertEqual(m, 1.078, accuracy: 0.005)
    }

    // MARK: - VO₂ decline multiplier (new)

    func test_vo2_noHistory_returnsNoAdjustment() {
        XCTAssertEqual(service.vo2DeclineMultiplier(history: []), 1.0, accuracy: 0.0001)
    }

    func test_vo2_stableHistory_returnsNoAdjustment() {
        let today = Date()
        let history: [VO2MaxSnapshot] = (1...6).map { vo2(daysAgo: $0 * 10, value: 50.0, today: today) }
        XCTAssertEqual(service.vo2DeclineMultiplier(history: history, today: today),
                       1.0, accuracy: 0.0001)
    }

    func test_vo2_significantDecline_returnsMultiplierAboveOne() {
        let today = Date()
        // Peak 55 four months ago, now down to 45 → 18% drop, above threshold.
        let history: [VO2MaxSnapshot] = [
            vo2(daysAgo: 120, value: 55.0, today: today),
            vo2(daysAgo: 90,  value: 53.0, today: today),
            vo2(daysAgo: 30,  value: 47.0, today: today),
            vo2(daysAgo: 1,   value: 45.0, today: today)
        ]
        let m = service.vo2DeclineMultiplier(history: history, today: today)
        XCTAssertGreaterThan(m, 1.0)
        XCTAssertLessThan(m, 1.30)  // capped at 30%
    }

    // MARK: - Training-improvement curve (new)

    func test_training_noGoalDate_returnsOne() {
        XCTAssertEqual(service.trainingImprovementMultiplier(goalDate: nil, today: Date()),
                       1.0, accuracy: 0.0001)
    }

    func test_training_pastGoalDate_returnsOne() {
        let today = Date()
        let pastDate = today.addingTimeInterval(-7 * 86_400)
        XCTAssertEqual(service.trainingImprovementMultiplier(goalDate: pastDate, today: today),
                       1.0, accuracy: 0.0001)
    }

    func test_training_eightWeeks_returnsAboutFourPercent() {
        let today = Date()
        let goalDate = today.addingTimeInterval(8 * 7 * 86_400)
        let m = service.trainingImprovementMultiplier(goalDate: goalDate, today: today)
        // 8 weeks × 0.5%/wk = 4% → multiplier ≈ 0.96
        XCTAssertEqual(m, 0.96, accuracy: 0.005)
    }

    func test_training_cappedAtEightPercent() {
        let today = Date()
        let farAway = today.addingTimeInterval(52 * 7 * 86_400)  // a year out
        let m = service.trainingImprovementMultiplier(goalDate: farAway, today: today)
        XCTAssertEqual(m, 0.92, accuracy: 0.001)  // hard 8% cap → 0.92
    }

    // MARK: - End-to-end predict()

    func test_predict_returnsNilWhenNoUsableInputs() {
        let p = service.predict(goal: .tenK, runs: [], age: 35, personalBest: nil)
        XCTAssertNil(p)
    }

    func test_predict_usesRecentRun_andReportsHighConfidenceNearGoal() {
        let today = Date()
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
        XCTAssertEqual(p.confidence, .high)
        XCTAssertNotNil(p.ageGradedEquivalentSeconds)
    }

    /// New correct behavior: if the user has done a slow recent run, the
    /// projection reflects current fitness — even when the PB is much faster.
    /// (The old behavior picked whichever was faster, which over-promised.)
    func test_predict_recentSlowRunBeatsFasterPB() {
        let today = Date()
        let runs = [run(daysAgo: 7, km: 10, paceSecPerKm: 360, today: today)] // 60:00 10K — out of shape
        let pb = PersonalBest(durationSeconds: 2700, year: 2015)               // 45:00 10K, a decade ago
        let p = service.predict(goal: .tenK,
                                runs: runs,
                                age: 35,
                                personalBest: pb,
                                today: today)
        XCTAssertNotNil(p)
        guard let p else { return }
        // Projection should anchor on the recent run, ~60:00, not the PB's 45:00.
        XCTAssertEqual(p.projectedTimeSeconds, 3_600, accuracy: 60)
        // Gap to PB should be positive (slower than PB) and substantial.
        XCTAssertNotNil(p.gapToPersonalBestSeconds)
        XCTAssertGreaterThan(p.gapToPersonalBestSeconds ?? 0, 600) // >10 min behind
        // Basis should be the recent run, not the PB.
        if case .recentRun = p.basis {} else {
            XCTFail("Expected recent-run basis, got \(p.basis)")
        }
    }

    func test_predict_oldPBOnly_isPenalisedForAge() {
        let today = Date()
        let pb = PersonalBest(durationSeconds: 2700, year: 2015)  // 10-year-old 45:00 10K
        let p = service.predict(goal: .tenK,
                                runs: [],
                                age: 40,
                                personalBest: pb,
                                today: today)
        XCTAssertNotNil(p)
        guard let p else { return }
        // 10y decay ≈ +7.8%. 2700 × 1.078 ≈ 2,910.
        XCTAssertEqual(p.projectedTimeSeconds, 2_910, accuracy: 60)
        if case .agedPersonalBest(let years) = p.basis {
            // Tolerate 9 or 10 here in case the test runs early/late in the calendar year.
            XCTAssertTrue(years >= 9 && years <= 11, "Got \(years)y")
        } else {
            XCTFail("Expected aged-PB basis, got \(p.basis)")
        }
    }

    func test_predict_pickedFastestRunWhenMultiple() {
        let today = Date()
        let slow = run(daysAgo: 30, km: 5, paceSecPerKm: 360, today: today) // 30:00 5K
        let fast = run(daysAgo: 10, km: 5, paceSecPerKm: 240, today: today) // 20:00 5K
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

    func test_predict_goalDateImprovesProjection() {
        let today = Date()
        let runs = (1...5).map { run(daysAgo: $0 * 4, km: 8, paceSecPerKm: 300, today: today) }
        let inEightWeeks = today.addingTimeInterval(8 * 7 * 86_400)

        let noDate = service.predict(goal: .tenK, runs: runs, age: 35,
                                     personalBest: nil, today: today)
        let withDate = service.predict(goal: .tenK, runs: runs, age: 35,
                                       personalBest: nil,
                                       goalDate: inEightWeeks,
                                       today: today)

        XCTAssertNotNil(noDate?.projectedTimeSeconds)
        XCTAssertNotNil(withDate?.projectedTimeSeconds)
        // With 8 weeks to train, projection should be ~4% faster.
        XCTAssertLessThan(withDate!.projectedTimeSeconds, noDate!.projectedTimeSeconds)
        XCTAssertEqual(noDate!.projectedTimeSeconds * 0.96,
                       withDate!.projectedTimeSeconds,
                       accuracy: 10)
        XCTAssertNotNil(withDate!.trainingImprovementMultiplier)
        XCTAssertEqual(withDate!.goalDate, inEightWeeks)
    }
}
