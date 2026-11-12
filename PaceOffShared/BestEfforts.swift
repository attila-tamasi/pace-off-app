// BestEfforts.swift
// A run's fastest 1 km, 5 km, 10 km and half marathon, found inside it from
// its GPS route: the shortest time over each distance, from any point of
// the route, with the end interpolated between the two points that
// straddle it. Pure (latitudes, longitudes and times in, seconds out), so
// it's tested without CoreLocation or HealthKit; F-14b reads the routes,
// keeps the bests and turns a new one into a PB.

import Foundation

/// One point of a run's route.
public struct RoutePoint: Equatable, Sendable {
    public let time: Date
    public let latitude: Double
    public let longitude: Double

    public init(time: Date, latitude: Double, longitude: Double) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum BestEffortDistance: String, Codable, CaseIterable, Sendable, Identifiable {
    case oneK
    case fiveK
    case tenK
    case halfMarathon

    public var id: String { rawValue }

    public var meters: Double {
        switch self {
        case .oneK:         return 1_000
        case .fiveK:        return 5_000
        case .tenK:         return 10_000
        case .halfMarathon: return 21_097.5
        }
    }

    public var displayName: String {
        switch self {
        case .oneK:         return "1 km"
        case .fiveK:        return "5 km"
        case .tenK:         return "10 km"
        case .halfMarathon: return "Half marathon"
        }
    }

    /// The race goal a best over this distance is a PB for; the 1 km has none.
    public var goal: RunningGoal? {
        switch self {
        case .oneK:         return nil
        case .fiveK:        return .fiveK
        case .tenK:         return .tenK
        case .halfMarathon: return .halfMarathon
        }
    }
}

public struct BestEffort: Codable, Equatable, Sendable {
    public let distance: BestEffortDistance
    public let seconds: Double
    /// When the run it came from started.
    public let runStart: Date

    public init(distance: BestEffortDistance, seconds: Double, runStart: Date) {
        self.distance = distance
        self.seconds = seconds
        self.runStart = runStart
    }
}

public enum BestEfforts {

    /// Faster than this between two points (36 km/h, 1:40/km) is a GPS
    /// jump, not running: the later point is left out.
    public static let maxPlausibleSpeed = 10.0

    /// Mean earth radius in metres, for the haversine distance.
    static let earthRadius = 6_371_008.8

    /// The route as (seconds from its first point, metres covered so far),
    /// points out of time order or reached at an impossible speed left out.
    public static func track(_ route: [RoutePoint]) -> [(seconds: Double, meters: Double)] {
        let points = route.sorted { $0.time < $1.time }
        guard let first = points.first else { return [] }
        var result: [(seconds: Double, meters: Double)] = [(0, 0)]
        var last = first
        for point in points.dropFirst() {
            let dt = point.time.timeIntervalSince(last.time)
            guard dt > 0 else { continue }
            let step = distance(from: last, to: point)
            guard step / dt <= maxPlausibleSpeed else { continue }
            result.append((point.time.timeIntervalSince(first.time), result[result.count - 1].meters + step))
            last = point
        }
        return result
    }

    /// The shortest time, in seconds, to cover `meters` anywhere on the
    /// track, starting at one of its points; nil when it's shorter than
    /// that. The end is interpolated between the points on either side.
    public static func fastestSeconds(over meters: Double, in track: [(seconds: Double, meters: Double)]) -> Double? {
        guard meters > 0, track.count >= 2 else { return nil }
        var best: Double?
        var j = 0
        for i in track.indices {
            if j <= i { j = i + 1 }
            while j < track.count, track[j].meters - track[i].meters < meters { j += 1 }
            guard j < track.count else { break }
            let before = track[j - 1], after = track[j]
            let covered = before.meters - track[i].meters
            let step = after.meters - before.meters
            let fraction = step > 0 ? (meters - covered) / step : 0
            let end = before.seconds + fraction * (after.seconds - before.seconds)
            let time = end - track[i].seconds
            if time > 0, best.map({ time < $0 }) ?? true { best = time }
        }
        return best
    }

    /// The run's best over each distance it covers.
    public static func efforts(route: [RoutePoint], runStart: Date) -> [BestEffort] {
        let points = Self.track(route)
        return BestEffortDistance.allCases.compactMap { distance in
            fastestSeconds(over: distance.meters, in: points).map {
                BestEffort(distance: distance, seconds: $0, runStart: runStart)
            }
        }
    }

    /// The bests kept so far with a run's efforts folded in: the faster of
    /// the two for each distance. `improved` holds the new run's efforts
    /// that beat (or first set) a best.
    public static func merge(_ bests: [BestEffort], with efforts: [BestEffort])
        -> (bests: [BestEffort], improved: [BestEffort]) {
        var byDistance = Dictionary(bests.map { ($0.distance, $0) }, uniquingKeysWith: { a, b in a.seconds <= b.seconds ? a : b })
        var improved: [BestEffort] = []
        for effort in efforts {
            if let current = byDistance[effort.distance], current.seconds <= effort.seconds { continue }
            byDistance[effort.distance] = effort
            improved.append(effort)
        }
        let ordered = BestEffortDistance.allCases.compactMap { byDistance[$0] }
        return (ordered, improved)
    }

    /// Great-circle distance between two points, in metres.
    static func distance(from a: RoutePoint, to b: RoutePoint) -> Double {
        let toRadians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * toRadians
        let dLon = (b.longitude - a.longitude) * toRadians
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * toRadians) * cos(b.latitude * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }
}
