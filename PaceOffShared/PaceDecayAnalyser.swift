// PaceDecayAnalyser.swift
// Turns a stream of timestamped GPS samples (as cumulative meters from the
// run's start) plus a stream of timestamped heart-rate samples into
// per-kilometre splits — pace, avg HR, and where in the run each split
// falls. Pure Swift, `Sendable`, no HealthKit / CoreLocation imports —
// callers do the CLLocation → cumulative-distance conversion before
// handing values here, so the analyser stays unit-testable in isolation.

import Foundation

// MARK: - Split

/// One kilometre of a run.
public struct KilometerSplit: Sendable, Equatable, Identifiable {
    /// 1-based km number (1 = first kilometre, 2 = second, …).
    public let index: Int
    /// Time to cover this km, in seconds. Pace = this / 1 km.
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

    /// Compute per-km splits. Requires `locations` sorted ascending by date
    /// and starting at ~0 metres. Returns an empty array when there aren't
    /// at least two samples or the run didn't cover a full kilometre.
    public func splits(
        locations: [LocationSample],
        heartRates: [HeartRateSample] = []
    ) -> [KilometerSplit] {
        guard locations.count >= 2 else { return [] }

        // We produce a split every time cumulative distance crosses an integer
        // km boundary. Between two consecutive samples that straddle a
        // boundary, we linearly interpolate the crossing time from distance.
        let startDate = locations.first!.date
        var results: [KilometerSplit] = []

        var lastBoundaryDate = startDate
        var lastBoundaryMeters: Double = 0

        // Walk each consecutive pair.
        for i in 1..<locations.count {
            let prev = locations[i - 1]
            let curr = locations[i]
            // Segment distance/time. Skip zero-distance or backward-in-time
            // samples defensively (HealthKit occasionally emits noisy points).
            guard curr.cumulativeMeters > prev.cumulativeMeters,
                  curr.date > prev.date
            else { continue }

            // How many km boundaries does this segment cross?
            let firstBoundary = Int(prev.cumulativeMeters / 1000) + 1
            let lastBoundary = Int(curr.cumulativeMeters / 1000)
            guard lastBoundary >= firstBoundary else { continue }

            for boundary in firstBoundary...lastBoundary {
                let boundaryMeters = Double(boundary) * 1000
                let frac = (boundaryMeters - prev.cumulativeMeters) /
                           (curr.cumulativeMeters - prev.cumulativeMeters)
                let segSeconds = curr.date.timeIntervalSince(prev.date)
                let boundaryDate = prev.date.addingTimeInterval(segSeconds * frac)

                // Km duration = time between the previous km boundary crossing
                // (or start) and this one. That is exactly `secondsPerKm`.
                let kmSeconds = boundaryDate.timeIntervalSince(lastBoundaryDate)
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
                lastBoundaryMeters = boundaryMeters
                _ = lastBoundaryMeters // silence unused-value warning; kept for readability
            }
        }
        return results
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
