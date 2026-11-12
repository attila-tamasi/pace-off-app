import XCTest

final class SiriAnswerTests: XCTestCase {

    private let cal = Calendar.current
    private let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))!

    private func target(km: Double, at date: Date) -> RunTarget {
        RunTarget(distanceMeters: km * 1000, tone: .firm, daysSinceLastRun: 1, vo2MaxSlope: nil,
                  baselineMeters: km * 1000, ceilingClamped: false, fatigueGuardActive: false,
                  capMeters: km * 1400, computedAt: date)
    }

    private func cache(km: Double = 6, at date: Date? = nil, plan: String? = nil, ran: Bool = false,
                       planDone: Bool = false, strength: String? = nil,
                       readiness: ReadinessLevel? = nil, sentence: String? = nil) -> WidgetCache {
        WidgetCache(target: target(km: km, at: date ?? morning), voiceLine: "x", runCompletedToday: ran,
                    planSummary: plan, planCompletedToday: planDone, strengthSummary: strength,
                    dayDistanceKm: plan == Workout.rest.summary ? nil : km,
                    readinessLevel: readiness, readinessSentence: sentence)
    }

    func testTheRunToday() {
        XCTAssertEqual(SiriAnswer.runToday(cache(km: 6), now: morning), "Today's run: 6 km.")
        XCTAssertEqual(SiriAnswer.runToday(cache(km: 8, plan: "8.0 km · 5:25–5:45/km"), now: morning),
                       "Today's run: 8.0 km · 5:25–5:45/km.")
    }

    func testARunThatsDone() {
        XCTAssertEqual(SiriAnswer.runToday(cache(km: 6, ran: true), now: morning), "Today's run is done: 6 km.")
        XCTAssertEqual(SiriAnswer.runToday(cache(km: 8, plan: "8.0 km · 5:25–5:45/km", ran: true), now: morning),
                       "Today's run: 8.0 km · 5:25–5:45/km.", "a short run doesn't tick off the plan's")
    }

    func testRestAndStrengthDays() {
        XCTAssertEqual(SiriAnswer.runToday(cache(plan: Workout.rest.summary), now: morning), "Rest day today.")
        XCTAssertEqual(SiriAnswer.runToday(cache(plan: Workout.rest.summary, strength: "Kettlebell · 35 min"), now: morning),
                       "Strength day: Kettlebell · 35 min. No run today.")
    }

    func testAnOldDayAsksToOpenTheApp() {
        let yesterday = morning.addingTimeInterval(-86_400)
        XCTAssertEqual(SiriAnswer.runToday(cache(at: yesterday), now: morning), SiriAnswer.openApp)
        XCTAssertEqual(SiriAnswer.readiness(cache(at: yesterday, readiness: .green, sentence: "x"), now: morning),
                       SiriAnswer.openApp)
        XCTAssertEqual(SiriAnswer.runToday(.empty, now: morning), SiriAnswer.openApp)
    }

    func testReadiness() {
        XCTAssertEqual(SiriAnswer.readiness(cache(readiness: .yellow, sentence: "HRV below your baseline — easy day."), now: morning),
                       "Ease off: HRV below your baseline — easy day.")
        XCTAssertEqual(SiriAnswer.readiness(cache(), now: morning),
                       "No readiness today yet: it needs a reading from Apple Watch.")
    }

    func testReadinessSurvivesSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "SiriAnswerTests")!
        defaults.removePersistentDomain(forName: "SiriAnswerTests")
        XCTAssertTrue(cache(readiness: .red, sentence: "Rest.").save(to: defaults, now: morning))
        let loaded = WidgetCache.load(from: defaults)
        XCTAssertEqual(loaded.readinessLevel, .red)
        XCTAssertEqual(loaded.readinessSentence, "Rest.")
        XCTAssertTrue(cache().save(to: defaults, now: morning.addingTimeInterval(60)))
        XCTAssertNil(WidgetCache.load(from: defaults).readinessLevel)
        defaults.removePersistentDomain(forName: "SiriAnswerTests")
    }
}
