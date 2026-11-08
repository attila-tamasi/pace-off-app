// WorkoutProfile.swift
// The derived numbers on a run's detail screen: heart rate across the run
// (average, lowest, highest and a line for the chart), elevation across
// the distance (gain, loss and a profile), and the extras Health keeps on
// the workout itself. Pure: callers hand over HealthKit's samples.

import Foundation

// MARK: - Heart rate

public struct WorkoutHeartRate: Equatable, Sendable {

    public struct Point: Equatable, Identifiable, Sendable {
        public let date: Date
        public let bpm: Double
        public var id: Date { date }
    }

    public let average: Double
    public let low: Double
    public let high: Double
    /// The mean of each `bucketSeconds` slice of the run that has samples,
    /// dated at the slice's start, oldest first.
    public let points: [Point]

    /// Nil when no sample falls inside the run.
    public init?(samples: [(date: Date, bpm: Double)],
                 start: Date,
                 end: Date,
                 bucketSeconds: Double = 30) {
        let inRun = samples.filter { $0.date >= start && $0.date <= end && $0.bpm > 0 }
        guard !inRun.isEmpty, bucketSeconds > 0 else { return nil }
        let values = inRun.map(\.bpm)
        average = values.reduce(0, +) / Double(values.count)
        low = values.min() ?? 0
        high = values.max() ?? 0

        let buckets = Dictionary(grouping: inRun) {
            Int(($0.date.timeIntervalSince(start) / bucketSeconds).rounded(.down))
        }
        points = buckets
            .map { index, slice in
                Point(date: start.addingTimeInterval(Double(index) * bucketSeconds),
                      bpm: slice.map(\.bpm).reduce(0, +) / Double(slice.count))
            }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Elevation

public struct WorkoutElevation: Equatable, Sendable {

    public struct Point: Equatable, Identifiable, Sendable {
        /// Distance from the start, in metres.
        public let meters: Double
        public let altitude: Double
        public var id: Double { meters }
    }

    /// Climbing and descending in metres, counting a change only once it
    /// passes `noise` metres, so GPS jitter on flat ground adds nothing.
    public let gain: Double
    public let loss: Double
    public let low: Double
    public let high: Double
    /// At most `maxPoints` points along the route, for the chart.
    public let points: [Point]

    /// Nil with fewer than two points.
    public init?(samples: [(date: Date, lat: Double, lon: Double, altitude: Double)],
                 noise: Double = 3,
                 maxPoints: Int = 150) {
        guard samples.count >= 2, maxPoints >= 2 else { return nil }
        let distances = PaceDecayAnalyser.locationSamples(
            from: samples.map { (date: $0.date, lat: $0.lat, lon: $0.lon) }
        ).map(\.cumulativeMeters)
        let altitudes = samples.map(\.altitude)

        var gain = 0.0, loss = 0.0
        var reference = altitudes[0]
        for altitude in altitudes.dropFirst() {
            if altitude - reference >= noise {
                gain += altitude - reference
                reference = altitude
            } else if reference - altitude >= noise {
                loss += reference - altitude
                reference = altitude
            }
        }
        self.gain = gain
        self.loss = loss
        low = altitudes.min() ?? 0
        high = altitudes.max() ?? 0

        let step = max(1, Int((Double(samples.count) / Double(maxPoints)).rounded(.up)))
        var kept = Array(stride(from: 0, to: samples.count, by: step))
        if kept.last != samples.count - 1 { kept.append(samples.count - 1) }
        points = kept.map { Point(meters: distances[$0], altitude: altitudes[$0]) }
    }
}

// MARK: - What Health keeps on the workout

/// Values HealthKit stores on the workout itself, read when its detail
/// opens. Each is nil when the workout doesn't carry it.
public struct WorkoutExtras: Equatable, Sendable {
    public var indoor: Bool?
    /// Health's own elevation gain, in metres; preferred over the one
    /// worked out from the route.
    public var elevationGainMeters: Double?
    public var temperatureCelsius: Double?
    /// 0–100.
    public var humidityPercent: Double?
    public var steps: Double?
    public var averageMETs: Double?

    public init(indoor: Bool? = nil,
                elevationGainMeters: Double? = nil,
                temperatureCelsius: Double? = nil,
                humidityPercent: Double? = nil,
                steps: Double? = nil,
                averageMETs: Double? = nil) {
        self.indoor = indoor
        self.elevationGainMeters = elevationGainMeters
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.steps = steps
        self.averageMETs = averageMETs
    }
}
