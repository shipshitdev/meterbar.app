import XCTest
@testable import QuotaGuard

final class UsageLimitTests: XCTestCase {
    func testPercentageAndRemainingValues() {
        let limit = UsageLimit(used: 25, total: 100, resetTime: nil)

        XCTAssertEqual(limit.percentage, 25, accuracy: 0.01)
        XCTAssertEqual(limit.remaining, 75, accuracy: 0.01)
        XCTAssertFalse(limit.isNearLimit)
        XCTAssertFalse(limit.isAtLimit)
        XCTAssertEqual(limit.statusColor, .good)
    }

    func testClampsPercentageAtBounds() {
        let overLimit = UsageLimit(used: 120, total: 100, resetTime: nil)
        let zeroTotal = UsageLimit(used: 50, total: 0, resetTime: nil)

        XCTAssertEqual(overLimit.percentage, 100, accuracy: 0.01)
        XCTAssertEqual(overLimit.remaining, 0, accuracy: 0.01)
        XCTAssertTrue(overLimit.isAtLimit)
        XCTAssertEqual(overLimit.statusColor, .critical)

        XCTAssertEqual(zeroTotal.percentage, 0, accuracy: 0.01)
        XCTAssertEqual(zeroTotal.remaining, 0, accuracy: 0.01)
        XCTAssertFalse(zeroTotal.isNearLimit)
        XCTAssertEqual(zeroTotal.statusColor, .good)
    }

    func testWarningThreshold() {
        let nearLimit = UsageLimit(used: 85, total: 100, resetTime: nil)

        XCTAssertTrue(nearLimit.isNearLimit)
        XCTAssertFalse(nearLimit.isAtLimit)
        XCTAssertEqual(nearLimit.statusColor, .warning)
    }
}
