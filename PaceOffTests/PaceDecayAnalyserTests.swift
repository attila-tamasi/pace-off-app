// PaceDecayAnalyserTests.swift
// Covers the km-boundary interpolation, HR windowing, defensive filters,
// and the haversine-based sample builder.

import XCTest
@testable import PaceOff

final class PaceDecayAnalyserTests: XCTestCase {

    private let analyser = PaceDecayAnalyser()

    // Fixed epoch so time math stays deterministic across CI runs.
    private var epoch: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - Empty / degenerate inputs

    func test_splits_empty_whenNoLocations() {
        XCTAssertTrue(analyser.splits(locations: []).isEmpty)
    }

    func test_splits_empty_whenOnlyOneSample() {
        let samples = [PaceDecayAnalyser.LocationSample(date: epoch, cumulativeMeters: 0)]
        XCTAssertTrue(analyser.splits(locations: samples).isEmpty)
    }

    func test_splits_empty_whenDidNotReachOneKm() {
        let samples = [
            PaceDecayAnalyser.LocationSample(date: epoch, cumulativeMeters: 0),
            PaceDecayAnalyser.LocationSample(date: epoch.addingTimeInterval(300), cumulativeMeters: 800)
        ]
        XCTAssertTrue(analyser.splits(locations: samples).isEmpty)
    }

    // MARK: - Even pacing

    func test_splits_evenPacing_yieldsMatchingSplits() {
        // 5 km at exactly 300 sec/km. Sample every 100 m (30 sec).
        let samples: [PaceDecayAnalyser.LocationSample] = (0...50).map { step in
            PaceDecayAnalyser.LocationSample(
                date: epoch.addingTimeInterval(Double(step) * 30),
                cumulativeMeters: Double(step) * 100
            )
        }
        let splits = analyser.splits(locations: samples)
        XCTAssertEqual(splits.count, 5)
        for (i, split) in splits.enumerated() {
            XCTAssertEqual(split.index, i + 1)
            XCTAssertEqual(split.secondsPerKm, 300, accuracy: 0.5)
        }
    }

    // MARK: - Pace decay (slowing down)

    func test_splits_slowingDown_showsRisingSecondsPerKm() {
        // km 1 in 300s, km 2 in 320s, km 3 in 340s.
        let checkpoints: [(Double, TimeInterval)] = [
            (0,     0),
            (1000,  300),
            (2000,  300 + 320),
            (3000,  300 + 320 + 340),
        ]
        let samples = checkpoints.map {
            PaceDecayAnalyser.LocationSample(
                date: epoch.addingTimeInterval($0.1),
                cumulativeMeters: $0.0
            )
        }
        let splits = analyser.splits(locations: samples)
        XCTAssertEqual(splits.map(\.secondsPerKm).map { Int($0.rounded()) }, [300, 320, 340])
    }

    // MARK: - Boundary crossings across a single segment

    func test_splits_singleLongSegment_crossingMultipleBoundaries() {
        // Two samples, one at 0m/0s, one at 2500m/900s. Expect exactly two
        // splits (km 1 at 360s, km 2 at 360s, remaining 500m dropped).
        let samples = [
            PaceDecayAnalyser.LocationSample(date: epoch, cumulativeMeters: 0),
            PaceDecayAnalyser.LocationSample(date: epoch.addingTimeInterval(900), cumulativeMeters: 2500),
        ]
        let splits = analyser.splits(locations: samples)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].secondsPerKm, 360, accuracy: 0.5)
        XCTAssertEqual(splits[1].secondsPerKm, 360, accuracy: 0.5)
    }

    // MARK: - Heart-rate windowing

    func test_splits_hrAveragedPerKmWindow() {
        let samples: [PaceDecayAnalyser.LocationSample] = (0...20).map { step in
            PaceDecayAnalyser.LocationSample(
                date: epoch.addingTimeInterval(Double(step) * 30),
                cumulativeMeters: Double(step) * 100
            )
        }
        // HR: 150 bpm through km 1 (0…300s), 170 through km 2 (300…600s).
        let hr: [PaceDecayAnalyser.HeartRateSample] = (0..<20).map { i in
            let t = Double(i) * 30 + 15  // sample every 30s, offset a bit
            let bpm: Double = t < 300 ? 150 : 170
            return PaceDecayAnalyser.HeartRateSample(
                date: epoch.addingTimeInterval(t),
                bpm: bpm
            )
        }
        let splits = analyser.splits(locations: samples, heartRates: hr)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].averageHeartRate ?? 0, 150, accuracy: 1)
        XCTAssertEqual(splits[1].averageHeartRate ?? 0, 170, accuracy: 1)
    }

    func test_splits_hrNilWhenNoSamplesInWindow() {
        let samples: [PaceDecayAnalyser.LocationSample] = (0...10).map { step in
            PaceDecayAnalyser.LocationSample(
                date: epoch.addingTimeInterval(Double(step) * 30),
                cumulativeMeters: Double(step) * 100
            )
        }
        let splits = analyser.splits(locations: samples, heartRates: [])
        XCTAssertEqual(splits.count, 1)
        XCTAssertNil(splits[0].averageHeartRate)
    }

    // MARK: - Defensive filters

    func test_splits_ignoresBackwardOrStationarySamples() {
        // Include one duplicate (same time, same meters) and one backward
        // sample (later time, less distance). Analyser should skip them.
        let samples = [
            PaceDecayAnalyser.LocationSample(date: epoch, cumulativeMeters: 0),
            PaceDecayAnalyser.LocationSample(date: epoch, cumulativeMeters: 0), // duplicate
            PaceDecayAnalyser.LocationSample(date: epoch.addingTimeInterval(300), cumulativeMeters: 1000),
            PaceDecayAnalyser.LocationSample(date: epoch.addingTimeInterval(310), cumulativeMeters: 950),  // backward
            PaceDecayAnalyser.LocationSample(date: epoch.addingTimeInterval(600), cumulativeMeters: 2000),
        ]
        let splits = analyser.splits(locations: samples)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].secondsPerKm, 300, accuracy: 0.5)
        XCTAssertEqual(splits[1].secondsPerKm, 300, accuracy: 0.5)
    }

    // MARK: - Haversine convenience

    func test_locationSamples_convertsCoordinatesToCumulativeMeters() {
        // Two points ~111 km apart along a meridian (1° of latitude).
        let stream: [(date: Date, lat: Double, lon: Double)] = [
            (epoch, 40.0, -74.0),
            (epoch.addingTimeInterval(60), 41.0, -74.0),
        ]
        let samples = PaceDecayAnalyser.locationSamples(from: stream)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].cumulativeMeters, 0)
        XCTAssertEqual(samples[1].cumulativeMeters, 111_195, accuracy: 500)
    }

    // MARK: - Miles

    func test_splits_perMile() {
        // 5 km at 300 s/km: three whole miles, each 482.8 s, 300 s/km.
        let samples: [PaceDecayAnalyser.LocationSample] = (0...50).map { step in
            PaceDecayAnalyser.LocationSample(
                date: epoch.addingTimeInterval(Double(step) * 30),
                cumulativeMeters: Double(step) * 100
            )
        }
        let splits = analyser.splits(locations: samples, splitMeters: DistanceUnit.metersPerMile)
        XCTAssertEqual(splits.map(\.index), [1, 2, 3])
        for split in splits { XCTAssertEqual(split.secondsPerKm, 300, accuracy: 0.5) }
        XCTAssertEqual(splits[2].cumulativeSeconds, 3 * 482.8, accuracy: 0.5)
        let mi = UnitFormatter(unit: .miles, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(mi.paceNumber(secondsPerKm: splits[0].secondsPerKm), "8:02")
    }

    // MARK: - Headline

    private func splits(_ paces: [Double]) -> [KilometerSplit] {
        paces.enumerated().map { KilometerSplit(index: $0.offset + 1, secondsPerKm: $0.element,
                                                averageHeartRate: nil, cumulativeSeconds: 0) }
    }

    func test_headline_inTheRunnersUnit() {
        let km = UnitFormatter.metric
        let mi = UnitFormatter(unit: .miles, locale: Locale(identifier: "en_US_POSIX"))
        let slowing = splits([300, 300, 310, 330, 330, 330])
        XCTAssertEqual(PaceDecayAnalyser.headline(slowing, units: km),
                       "Slowed 30 s/km in the final third — likely fatigue or effort dip.")
        XCTAssertEqual(PaceDecayAnalyser.headline(slowing, units: mi),
                       "Slowed 48 s/mi in the final third — likely fatigue or effort dip.")
        XCTAssertEqual(PaceDecayAnalyser.headline(splits([330, 330, 320, 300]), units: km),
                       "Sped up 30 s/km toward the end — strong finish.")
        XCTAssertEqual(PaceDecayAnalyser.headline(splits([300, 305, 300, 305]), units: km),
                       "Pace held steady across the run — well-judged effort.")
        XCTAssertNil(PaceDecayAnalyser.headline(splits([300, 400, 500]), units: km))
    }

    // MARK: - Formatting

    func test_split_formattedPace_isMinuteSeconds() {
        let s = KilometerSplit(index: 1, secondsPerKm: 344, averageHeartRate: nil, cumulativeSeconds: 344)
        XCTAssertEqual(s.formattedPace, "5:44")
    }
}
