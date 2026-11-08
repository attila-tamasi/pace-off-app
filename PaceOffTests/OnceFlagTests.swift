// OnceFlagTests.swift
// The flag a background task's work and its expiration handler share, so
// only one of them reports the task complete.

import XCTest
@testable import PaceOff

final class OnceFlagTests: XCTestCase {

    func test_onlyTheFirstClaimWins() {
        let flag = OnceFlag()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    func test_concurrentClaims_exactlyOneWins() {
        let flag = OnceFlag()
        let wins = OnceFlagTestsCounter()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if flag.claim() { wins.increment() }
        }
        XCTAssertEqual(wins.value, 1)
    }
}

private final class OnceFlagTestsCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
