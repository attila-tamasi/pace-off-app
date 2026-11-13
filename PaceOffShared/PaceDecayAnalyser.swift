// PaceDecayAnalyser.swift
// Turns a stream of timestamped GPS samples (as cumulative meters from the
// run's start) plus a stream of timestamped heart-rate samples into
// per-kilometre (or per-mile) splits — pace, avg HR, and where in the run
// each split falls. Pure Swift, `Sendable`, no HealthKit / CoreLocation imports —
// callers do the CLLocation → cumulative-distance conversion before
// handing values here, so the analyser stays unit-testable in isolation.

import Foundation

// MARK: - Split

/// One kilometre, or one mile, of a run.
public struct KilometerSplit: Sendable, Equatable, Identifiable {
    /// 1-based split number (1 = first kilometre or mile, 2 = second, …).
    public let index: Int
    /// The split's pace in seconds per km: its time itself for a km split,
    /// its time over 1.609 for a mile split.
    public let secondsPerKm: Double
    /// Average heart rate over this km, if any HR samples fell within it.
    public let averageHeartRate: Double?
    /// Offset from run start at the *end* of this km, in seconds.
    public let cumulativeSeconds: Double

    public var id: Int { index }

    public init(index: Int,
                secondsPerKm: Double,
                averageHeartRate: Double?,
                cumulativeSeconds: Double) {
        self.index = index
        self.secondsPerKm = secondsPerKm
        self.averageHeartRate = averageHeartRate
        self.cumulativeSeconds = cumulativeSeconds
    }

    /// "5:24" — pace formatted as mm:ss.
    public var formattedPace: String {
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Analyser

public struct PaceDecayAnalyser: Sendable {

    /// A location sample, reduced to what the analyser cares about.
    /// `cumulativeMeters` is total distance from the start of the run.
    public struct LocationSample: Sendable, Equatable {
        public let date: Date
        public let cumulativeMeters: Double
        public init(date: Date, cumulativeMeters: Double) {
            self.date = date
            self.cumulativeMeters = cumulativeMeters
        }
    }

    /// A heart-rate sample.
    public struct HeartRateSample: Sendable, Equatable {
        public let date: Date
        public let bpm: Double
        public init(date: Date, bpm: Double) {
            self.date = date
            self.bpm = bpm
        }
    }

    public init() {}

    /// Compute a split every `splitMeters` (1 km, or a mile). Requires
    /// `locations` sorted ascending by date and starting at ~0 metres.
    /// Returns an empty array when there aren't at least two samples or the
    /// run didn't cover a full split.
    public func splits(
        locations: [LocationSample],
        heartRates: [HeartRateSample] = [],
        splitMeters: Double = 1_000
    ) -> [KilometerSplit] {
        guard locations.count >= 2, splitMeters > 0 else { return [] }

        // We produce a split every time cumulative distance crosses an integer
        // km boundary. Between two consecutive samples that straddle a
        // boundary, we linearly interpolate the crossing time from distance.
        let startDate = locations.first!.date
        var results: [KilometerSplit] = []

        var lastBoundaryDate = startDate
        var lastEmittedBoundary = 0

        // Walk each consecutive pair.
        for i in 1..<locations.count {
            let prev = locations[i - 1]
            let curr = locations[i]
            // Segment distance/time. Skip zero-distance or backward-in-time
            // samples defensively (HealthKit occasionally emits noisy points).
            guard curr.cumulativeMeters > prev.cumulativeMeters,
                  curr.date > prev.date
            else { continue }

            // How many km boundaries does this segment cross? Never re-emit
            // a boundary already produced — a noisy backward sample can put
            // `prev` below a boundary we've crossed, and without this floor
            // that boundary would be counted twice as a phantom split.
            let firstBoundary = max(Int(prev.cumulativeMeters / splitMeters) + 1,
                                    lastEmittedBoundary + 1)
            let lastBoundary = Int(curr.cumulativeMeters / splitMeters)
            guard lastBoundary >= firstBoundary else { continue }

            for boundary in firstBoundary...lastBoundary {
                let boundaryMeters = Double(boundary) * splitMeters
                let frac = (boundaryMeters - prev.cumulativeMeters) /
                           (curr.cumulativeMeters - prev.cumulativeMeters)
                let segSeconds = curr.date.timeIntervalSince(prev.date)
                let boundaryDate = prev.date.addingTimeInterval(segSeconds * frac)

                // Split duration = time between the previous boundary crossing
                // (or start) and this one; per km, for a mile split.
                let kmSeconds = boundaryDate.timeIntervalSince(lastBoundaryDate) * 1_000 / splitMeters
                let avgHR = averageHR(in: heartRates, from: lastBoundaryDate, to: boundaryDate)
                let cumulativeSeconds = boundaryDate.timeIntervalSince(startDate)
                results.append(
                    KilometerSplit(
                        index: boundary,
                        secondsPerKm: kmSeconds,
                        averageHeartRate: avgHR,
                        cumulativeSeconds: cumulativeSeconds
                    )
                )
                lastBoundaryDate = boundaryDate
                lastEmittedBoundary = boundary
            }
        }
        return results
    }

    /// The sentence over the splits: where the pace drifted, from the first
    /// third of the splits to the last (more than 12 s/km slower, or 8 s/km
    /// faster), said in the runner's unit. Nil under four splits.
    public static func headline(_ splits: [KilometerSplit], units: UnitFormatter) -> String? {
        guard splits.count >= 4 else { return nil }
        let third = max(1, splits.count / 3)
        func average(_ slice: ArraySlice<KilometerSplit>) -> Double {
            slice.map(\.secondsPerKm).reduce(0, +) / Double(slice.count)
        }
        let delta = average(splits.suffix(third)) - average(splits.prefix(third))  // + = slower at the end
        let seconds = Int(units.secondsPerUnit(secondsPerKm: abs(delta)).rounded())
        let per = "s/\(units.unit.symbol)"
        if delta > 12 {
            return "Slowed \(seconds) \(per) in the final third — likely fatigue or effort dip."
        } else if delta < -8 {
            return "Sped up \(seconds) \(per) toward the end — strong finish."
        }
        return "Pace held steady across the run — well-judged effort."
    }

    /// Arithmetic mean of the HR samples falling within `[start, end]`.
    /// Nil when nothing falls in the window.
    private func averageHR(in samples: [HeartRateSample],
                           from start: Date, to end: Date) -> Double? {
        let inWindow = samples.filter { $0.date >= start && $0.date <= end }
        guard !inWindow.isEmpty else { return nil }
        return inWindow.reduce(0) { $0 + $1.bpm } / Double(inWindow.count)
    }
}

// MARK: - Convenience: build LocationSamples from a raw (date, coord) stream

public extension PaceDecayAnalyser {
    /// Build `LocationSample`s from a stream of `(date, latitude, longitude)`
    /// by summing great-circle distances between consecutive points. The
    /// analyser doesn't import CoreLocation, so this is the entry point when
    /// you have raw HealthKit route samples.
    static func locationSamples(from stream: [(date: Date, lat: Double, lon: Double)])
        -> [LocationSample]
    {
        guard let first = stream.first else { return [] }
        var samples: [LocationSample] = [
            LocationSample(date: first.date, cumulativeMeters: 0)
        ]
        var cumulative: Double = 0
        for i in 1..<stream.count {
            let a = stream[i - 1]
            let b = stream[i]
            cumulative += haversineMeters(lat1: a.lat, lon1: a.lon,
                                          lat2: b.lat, lon2: b.lon)
            samples.append(LocationSample(date: b.date, cumulativeMeters: cumulative))
        }
        return samples
    }

    /// Great-circle distance in metres between two lat/lon pairs. Earth-
    /// radius mean (6371 km); accuracy is comfortably inside GPS noise for
    /// segment distances < a few km, which is all we need here.
    private static func haversineMeters(lat1: Double, lon1: Double,
                                        lat2: Double, lon2: Double) -> Double {
        let earthRadius: Double = 6_371_000
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let rlat1 = lat1 * .pi / 180
        let rlat2 = lat2 * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(rlat1) * cos(rlat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
