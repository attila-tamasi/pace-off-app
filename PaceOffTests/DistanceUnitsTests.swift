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

// MARK: - The day's text in miles

final class MilesTextTests: XCTestCase {

    private let mi = UnitFormatter(unit: .miles, locale: Locale(identifier: "en_US_POSIX"))

    private func target(km: Double, capKm: Double) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                  baselineMeters: km * 1000, ceilingClamped: false, fatigueGuardActive: false,
                  capMeters: capKm * 1000)
    }

    private let easy = Workout(kind: .easy, distanceMeters: 12_000, paceMinSecPerKm: 325, paceMaxSecPerKm: 345)

    func testAWorkoutInMiles() {
        XCTAssertEqual(easy.summary(in: mi), "7.5 mi · 8:43–9:15/mi")
        XCTAssertEqual(easy.summary, "12.0 km · 5:25–5:45/km", "kilometres stay as they were")
    }

    func testTheDailyTargetIsWholeMiles() throws {
        // 9 km is 5.6 mi: 6 mi, under a 12 km (7.5 mi) cap.
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil, target: target(km: 9, capKm: 12),
                                                     easyPace: nil, units: mi))
        XCTAssertEqual(day.distanceText(in: mi), "6")
        XCTAssertEqual(day.summary(in: mi), "6 mi")
        XCTAssertEqual(day.distanceMeters!, 6 * DistanceUnit.metersPerMile, accuracy: 1e-6)
        XCTAssertTrue(day.isMet(byRunMeters: 5.8 * DistanceUnit.metersPerMile))
    }

    func testTheVoiceLineAndPushSayMiles() throws {
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil, target: target(km: 9, capKm: 12),
                                                     easyPace: nil, units: mi))
        let state = VoiceState(target: target(km: 9, capKm: 12), yesterday: nil, currentStreak: 0, prescription: day)
        XCTAssertEqual(VoiceCopy(units: mi).todayCard(for: state), "On track. Keep it rolling. Today: 6 mi.")
        let status = PlanDayStatus(workout: easy, isCompleted: false, strength: nil)
        let planDay = try XCTUnwrap(DayPrescription.make(planStatus: status, readiness: .green, target: nil,
                                                         easyPace: nil, units: mi))
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 6, hour: 6))!
        let push = DailyPushPlanner().pushes(for: DailyPushPlanner.Inputs(
            now: morning, body: "x", runs: [], plan: nil, planStatus: status, prescription: planDay, units: mi
        )).first { $0.slot == .morning }
        XCTAssertEqual(push?.body, "Today's plan: 7.5 mi · 8:43–9:15/mi.")
    }

    func testTheWidgetAndSiriSayMiles() throws {
        let t = target(km: 9, capKm: 12)
        let day = try XCTUnwrap(DayPrescription.make(planStatus: nil, readiness: nil, target: t, easyPace: nil, units: mi))
        let cache = WidgetCache(target: t, voiceLine: "x", runCompletedToday: false, planStatus: nil,
                                prescription: day, units: mi)
        XCTAssertEqual(cache.distanceText(in: mi), "6")
        XCTAssertEqual(SiriAnswer.runToday(cache, units: mi, now: t.computedAt), "Today's run: 6 mi.")
    }
}
