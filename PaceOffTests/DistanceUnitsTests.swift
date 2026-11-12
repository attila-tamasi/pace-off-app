import XCTest

final class DistanceUnitsTests: XCTestCase {

    private let en = Locale(identifier: "en_US_POSIX")
    private var km: UnitFormatter { UnitFormatter(unit: .kilometers, locale: en) }
    private var mi: UnitFormatter { UnitFormatter(unit: .miles, locale: en) }

    func testTheDefaultFollowsTheLocale() {
        XCTAssertEqual(DistanceUnit.default(for: Locale(identifier: "en_US")), .miles)
        XCTAssertEqual(DistanceUnit.default(for: Locale(identifier: "en_GB")), .miles)
        XCTAssertEqual(DistanceUnit.default(for: Locale(identifier: "hu_HU")), .kilometers)
        XCTAssertEqual(DistanceUnit.default(for: Locale(identifier: "de_DE")), .kilometers)
    }

    func testTheChoiceIsKept() {
        let defaults = UserDefaults(suiteName: "DistanceUnitsTests")!
        defaults.removePersistentDomain(forName: "DistanceUnitsTests")
        XCTAssertEqual(DistanceUnit.current(in: defaults, locale: Locale(identifier: "hu_HU")), .kilometers)
        DistanceUnit.save(.miles, in: defaults)
        XCTAssertEqual(DistanceUnit.current(in: defaults, locale: Locale(identifier: "hu_HU")), .miles)
        defaults.removePersistentDomain(forName: "DistanceUnitsTests")
    }

    func testDistances() {
        XCTAssertEqual(km.distance(8_000), "8 km")
        XCTAssertEqual(km.distance(10_800), "10.8 km")
        XCTAssertEqual(km.distanceOneDecimal(8_000), "8.0 km")
        XCTAssertEqual(mi.distance(DistanceUnit.metersPerMile * 5), "5 mi")
        XCTAssertEqual(mi.distance(10_000), "6.2 mi")
        XCTAssertEqual(mi.distanceOneDecimal(21_097.5), "13.1 mi")
    }

    func testDecimalsFollowTheLocale() {
        XCTAssertEqual(UnitFormatter(unit: .kilometers, locale: Locale(identifier: "hu_HU")).distance(10_800), "10,8 km")
        XCTAssertEqual(UnitFormatter(unit: .kilometers, locale: Locale(identifier: "hu_HU")).distance(12_000), "12 km")
    }

    func testPaces() {
        XCTAssertEqual(km.pace(secondsPerKm: 324), "5:24/km")
        XCTAssertEqual(mi.pace(secondsPerKm: 324), "8:41/mi")   // 324 × 1.609 = 521 s
        XCTAssertEqual(km.paceBand(minSecondsPerKm: 325, maxSecondsPerKm: 345), "5:25–5:45/km")
        XCTAssertEqual(km.paceBand(minSecondsPerKm: 300, maxSecondsPerKm: 300), "5:00/km")
        XCTAssertEqual(mi.paceBand(minSecondsPerKm: 325, maxSecondsPerKm: 345), "8:43–9:15/mi")
    }

    func testSpeeds() {
        XCTAssertEqual(km.speed(metersPerSecond: 3.0833), "11.1 km/h")
        XCTAssertEqual(mi.speed(metersPerSecond: 3.0833), "6.9 mph")
    }

    func testWholeUnitsRoundUpButNeverPassTheCap() {
        XCTAssertEqual(km.wholeUnits(5_300, capMeters: nil), 6)
        XCTAssertEqual(km.wholeUnits(5_300, capMeters: 5_800), 5)
        XCTAssertEqual(km.wholeUnits(6_000, capMeters: 8_000), 6)
        // 9 km is 5.59 mi: rounded up to 6 mi, but a 9.5 km cap (5.9 mi) keeps it at 5.
        XCTAssertEqual(mi.wholeUnits(9_000, capMeters: nil), 6)
        XCTAssertEqual(mi.wholeUnits(9_000, capMeters: 9_500), 5)
        XCTAssertEqual(mi.wholeUnits(800, capMeters: 1_000), 1, "at least one")
    }

    func testKilometresMatchTheTargetsOwnRounding() {
        for (meters, cap) in [(5_300.0, 7_420.0), (6_000.0, 6_100.0), (11_240.0, 12_000.0)] {
            let target = RunTarget(distanceMeters: meters, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                                   baselineMeters: meters, ceilingClamped: false, fatigueGuardActive: false,
                                   capMeters: cap)
            XCTAssertEqual(km.wholeUnits(meters, capMeters: cap), target.displayedDistanceKm)
        }
    }
}
