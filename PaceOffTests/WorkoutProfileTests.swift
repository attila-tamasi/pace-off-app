// WorkoutProfileTests.swift
// Covers the run detail's derived numbers: heart rate only from inside the
// run, bucketed for the chart; elevation gain and loss that ignore GPS
// jitter, with a capped profile along the route's distance.

import XCTest
@testable import PaceOff

final class WorkoutProfileTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var end: Date { start.addingTimeInterval(1_800) }

    // MARK: - Heart rate

    func test_heartRate_onlyCountsSamplesInsideTheRun() {
        let samples: [(date: Date, bpm: Double)] = [
            (date: start.addingTimeInterval(-60), bpm: 200),   // before
            (date: start.addingTimeInterval(10), bpm: 140),
            (date: start.addingTimeInterval(900), bpm: 160),
            (date: start.addingTimeInterval(1_790), bpm: 150),
            (date: end.addingTimeInterval(60), bpm: 90),       // after
        ]
        let hr = WorkoutHeartRate(samples: samples, start: start, end: end)
        XCTAssertEqual(hr?.average ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(hr?.low, 140)
        XCTAssertEqual(hr?.high, 160)
    }

    func test_heartRate_bucketsAreSliceMeans_oldestFirst() {
        let samples: [(date: Date, bpm: Double)] = [
            (date: start.addingTimeInterval(65), bpm: 160),
            (date: start.addingTimeInterval(5), bpm: 140),
            (date: start.addingTimeInterval(20), bpm: 150),
        ]
        let hr = WorkoutHeartRate(samples: samples, start: start, end: end, bucketSeconds: 30)
        XCTAssertEqual(hr?.points.map(\.bpm), [145, 160])
        XCTAssertEqual(hr?.points.map(\.date), [start, start.addingTimeInterval(60)])
    }

    func test_heartRate_isNil_withoutSamplesInTheRun() {
        XCTAssertNil(WorkoutHeartRate(samples: [], start: start, end: end))
        XCTAssertNil(WorkoutHeartRate(samples: [(date: end.addingTimeInterval(5), bpm: 150)], start: start, end: end))
    }

    // MARK: - Elevation

    /// Points 11 m apart along the route at the given altitudes.
    private func route(_ altitudes: [Double]) -> [(meters: Double, altitude: Double)] {
        altitudes.enumerated().map { index, altitude in
            (meters: Double(index) * 11, altitude: altitude)
        }
    }

    func test_elevation_steadyClimb_withJitter() {
        // 0 → 30 m in 1 m steps, each point wobbling ±1 m.
        let altitudes = (0...30).map { Double($0) + ($0 % 2 == 0 ? 1 : -1) }
        let elevation = WorkoutElevation(samples: route(altitudes))
        XCTAssertEqual(elevation?.gain ?? 0, 30, accuracy: 3)
        XCTAssertEqual(elevation?.loss ?? -1, 0, accuracy: 0.001)
    }

    func test_elevation_upAndDown() {
        let altitudes: [Double] = [100, 105, 110, 115, 120, 115, 110, 105, 100]
        let elevation = WorkoutElevation(samples: route(altitudes))
        XCTAssertEqual(elevation?.gain ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(elevation?.loss ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(elevation?.low, 100)
        XCTAssertEqual(elevation?.high, 120)
    }

    func test_elevation_flatGroundJitter_addsNothing() {
        let altitudes: [Double] = [50, 52, 49, 51, 50, 52, 48, 50, 51]
        let elevation = WorkoutElevation(samples: route(altitudes))
        XCTAssertEqual(elevation?.gain ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(elevation?.loss ?? -1, 0, accuracy: 0.001)
    }

    func test_elevation_profile_isCapped_andRunsAlongTheDistance() {
        let altitudes = (0..<1_000).map { Double($0 % 40) }
        let elevation = WorkoutElevation(samples: route(altitudes), maxPoints: 150)
        let points = elevation?.points ?? []
        XCTAssertLessThanOrEqual(points.count, 151)
        XCTAssertEqual(points.first?.meters, 0)
        XCTAssertEqual(points.map(\.meters), points.map(\.meters).sorted())
        // The last point is the finish, 999 × 11 m along.
        XCTAssertEqual(points.last?.meters ?? 0, 10_989, accuracy: 0.001)
        XCTAssertEqual(points.last?.altitude, altitudes.last)
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
    }

    func test_elevation_standingStill_keepsUniqueIDs() {
        // Waiting at a crossing: three points at the same distance.
        let samples: [(meters: Double, altitude: Double)] = [
            (meters: 0, altitude: 10), (meters: 0, altitude: 10), (meters: 0, altitude: 11),
            (meters: 20, altitude: 15),
        ]
        let points = WorkoutElevation(samples: samples)?.points ?? []
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(Set(points.map(\.id)).count, 4)
    }

    func test_elevation_isNil_withFewerThanTwoPoints() {
        XCTAssertNil(WorkoutElevation(samples: []))
        XCTAssertNil(WorkoutElevation(samples: route([10])))
    }
}
