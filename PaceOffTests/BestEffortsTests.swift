import XCTest

final class BestEffortsTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_767_600_000)
    /// Degrees of latitude per metre on the haversine sphere.
    private let degreesPerMeter = 180 / (Double.pi * 6_371_008.8)

    /// A route heading north, one point every `every` seconds, at each
    /// segment's speed for its distance.
    private func route(_ segments: [(meters: Double, speed: Double)], every: Double = 10) -> [RoutePoint] {
        var points = [RoutePoint(time: start, latitude: 47, longitude: 19)]
        var t = 0.0, d = 0.0
        for segment in segments {
            let end = d + segment.meters
            while d + segment.speed * every <= end + 1e-9 {
                t += every
                d += segment.speed * every
                points.append(RoutePoint(time: start.addingTimeInterval(t),
                                         latitude: 47 + d * degreesPerMeter, longitude: 19))
            }
        }
        return points
    }

    private func seconds(_ efforts: [BestEffort], _ distance: BestEffortDistance) -> Double? {
        efforts.first { $0.distance == distance }?.seconds
    }

    func testSteadyRunGivesEachDistanceItCovers() throws {
        let efforts = BestEfforts.efforts(route: route([(6_000, 4)]), runStart: start)
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .oneK)), 250, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .fiveK)), 1_250, accuracy: 0.5)
        XCTAssertNil(seconds(efforts, .tenK))
        XCTAssertNil(seconds(efforts, .halfMarathon))
    }

    func testFastKilometreInsideASlowRunIsFound() throws {
        let efforts = BestEfforts.efforts(route: route([(2_000, 3), (1_000, 5), (2_000, 3)]), runStart: start)
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .oneK)), 200, accuracy: 0.5)
    }

    func testEndIsInterpolatedBetweenPoints() throws {
        // 120 m between points: 1 km ends a third of the way into a step.
        let track = BestEfforts.track(route([(3_000, 4)], every: 30))
        XCTAssertEqual(try XCTUnwrap(BestEfforts.fastestSeconds(over: 1_000, in: track)), 250, accuracy: 0.5)
    }

    func testGPSJumpIsIgnored() throws {
        var points = route([(3_000, 4)])
        // A point 500 m ahead one second later: 500 m/s, left out.
        let jump = RoutePoint(time: points[10].time.addingTimeInterval(1),
                              latitude: points[10].latitude + 500 * degreesPerMeter, longitude: 19)
        points.insert(jump, at: 11)
        let efforts = BestEfforts.efforts(route: points, runStart: start)
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .oneK)), 250, accuracy: 0.5)
    }

    func testShortOrEmptyRouteHasNoEfforts() {
        XCTAssertTrue(BestEfforts.efforts(route: [], runStart: start).isEmpty)
        XCTAssertTrue(BestEfforts.efforts(route: route([(800, 4)]), runStart: start).isEmpty)
    }

    func testHalfMarathonDistance() throws {
        let efforts = BestEfforts.efforts(route: route([(22_000, 3.5)]), runStart: start)
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .halfMarathon)), 21_097.5 / 3.5, accuracy: 3)
    }

    // MARK: - Keeping the bests

    func testMergeKeepsTheFasterAndReportsWhatImproved() {
        let old = [BestEffort(distance: .oneK, seconds: 240, runStart: start),
                   BestEffort(distance: .fiveK, seconds: 1_300, runStart: start)]
        let later = start.addingTimeInterval(86_400)
        let new = [BestEffort(distance: .oneK, seconds: 250, runStart: later),
                   BestEffort(distance: .fiveK, seconds: 1_250, runStart: later),
                   BestEffort(distance: .tenK, seconds: 2_700, runStart: later)]
        let (bests, improved) = BestEfforts.merge(old, with: new)
        XCTAssertEqual(bests.map(\.distance), [.oneK, .fiveK, .tenK])
        XCTAssertEqual(bests.map(\.seconds), [240, 1_250, 2_700])
        XCTAssertEqual(improved.map(\.distance), [.fiveK, .tenK])
    }

    func testEqualTimeIsNoImprovement() {
        let old = [BestEffort(distance: .oneK, seconds: 240, runStart: start)]
        let (_, improved) = BestEfforts.merge(old, with: [BestEffort(distance: .oneK, seconds: 240, runStart: start)])
        XCTAssertTrue(improved.isEmpty)
    }

    func testTheMileIsABestEffort() throws {
        let efforts = BestEfforts.efforts(route: route([(3_000, 4)]), runStart: start)
        XCTAssertEqual(efforts.map(\.distance), [.oneK, .mile])
        XCTAssertEqual(try XCTUnwrap(seconds(efforts, .mile)), DistanceUnit.metersPerMile / 4, accuracy: 0.5)
    }

    func testDistancesMapToRaceGoals() {
        XCTAssertNil(BestEffortDistance.oneK.goal)
        XCTAssertNil(BestEffortDistance.mile.goal)
        XCTAssertEqual(BestEffortDistance.fiveK.goal, .fiveK)
        XCTAssertEqual(BestEffortDistance.halfMarathon.goal, .halfMarathon)
    }
}
