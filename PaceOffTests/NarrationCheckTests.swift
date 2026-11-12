import XCTest

final class NarrationCheckTests: XCTestCase {

    func testSameNumbersInAnotherOrderAreAccepted() {
        XCTAssertTrue(NarrationCheck.accepts("Day 3 of the streak. 6 km, easy.",
                                             for: "6 km easy today. Day 3 of your streak."))
    }

    func testLineWithoutNumbersIsAccepted() {
        XCTAssertTrue(NarrationCheck.accepts("Rest up. Tomorrow we go again.",
                                             for: "Recover today. Back at it tomorrow."))
    }

    func testChangedNumberIsRejected() {
        XCTAssertFalse(NarrationCheck.accepts("Run 8 km today.", for: "Run 6 km today."))
    }

    func testAddedNumberIsRejected() {
        XCTAssertFalse(NarrationCheck.accepts("Run 6 km, then 4 strides.", for: "Run 6 km today."))
    }

    func testDroppedNumberIsRejected() {
        XCTAssertFalse(NarrationCheck.accepts("Run 6 km.", for: "Run 6 km in 30 minutes."))
    }

    func testEachNumberCountsAsOftenAsItAppears() {
        XCTAssertFalse(NarrationCheck.accepts("3 km easy.", for: "3 km easy, then 3 km steady."))
        XCTAssertFalse(NarrationCheck.accepts("3 km easy, then 3 km steady.", for: "3 km easy."))
    }

    func testNumberWrittenAsAWordIsRejected() {
        XCTAssertFalse(NarrationCheck.accepts("Run six km today.", for: "Run 6 km today."))
        XCTAssertFalse(NarrationCheck.accepts("Rest today, two days to go.", for: "Rest today."))
    }

    func testNumberWordKeptFromTheOriginalIsAccepted() {
        XCTAssertTrue(NarrationCheck.accepts("Two easy days, then 5 km.",
                                             for: "5 km after two easy days."))
    }

    func testDecimalsMustMatchAsWritten() {
        XCTAssertTrue(NarrationCheck.accepts("8.0 km on the plan today.", for: "Today's plan: 8.0 km."))
        XCTAssertFalse(NarrationCheck.accepts("8 km on the plan today.", for: "Today's plan: 8.0 km."))
        XCTAssertFalse(NarrationCheck.accepts("8.5 km on the plan today.", for: "Today's plan: 8.0 km."))
    }

    func testPaceBandKeepsBothEnds() {
        let original = "Today's plan: 8.0 km · 5:25–5:45/km."
        XCTAssertTrue(NarrationCheck.accepts("8.0 km between 5:25 and 5:45 per km.", for: original))
        XCTAssertFalse(NarrationCheck.accepts("8.0 km between 5:25 and 5:50 per km.", for: original))
        XCTAssertFalse(NarrationCheck.accepts("8.0 km at 5:25 per km.", for: original))
    }

    func testSentenceEndingAfterANumberDoesNotJoinIt() {
        XCTAssertEqual(NarrationCheck.numbers(in: "Run 6. Then rest 2."), ["2", "6"])
    }

    func testDistanceSuffixesKeepTheirDigits() {
        XCTAssertTrue(NarrationCheck.accepts("Your 10K is 4 weeks out.", for: "4 weeks to your 10K."))
    }

    func testLengthCap() {
        let original = "Run 6 km."
        let long = "Run 6 km " + String(repeating: "and keep it easy ", count: 10)
        XCTAssertFalse(NarrationCheck.accepts(long, for: original))
        XCTAssertTrue(NarrationCheck.accepts("Run 6 km, easy.", for: original, maxLength: 15))
        XCTAssertFalse(NarrationCheck.accepts("Run 6 km, nice and easy.", for: original, maxLength: 15))
    }

    func testEmptyRewriteIsRejected() {
        XCTAssertFalse(NarrationCheck.accepts("   ", for: "Rest today."))
    }
}
