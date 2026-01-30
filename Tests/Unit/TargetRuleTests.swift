import XCTest
@testable import Core

final class TargetRuleTests: XCTestCase {
    func testExactTargetWithinTolerance() {
        let rule = TargetRule.exact(3.0)

        XCTAssertTrue(rule.isSatisfied(by: 3.0))
        XCTAssertTrue(rule.isSatisfied(by: 2.75))
        XCTAssertTrue(rule.isSatisfied(by: 3.25))
        XCTAssertFalse(rule.isSatisfied(by: 3.5))
    }

    func testAtLeastTarget() {
        let rule = TargetRule.atLeast(2.0)

        XCTAssertTrue(rule.isSatisfied(by: 2.0))
        XCTAssertTrue(rule.isSatisfied(by: 2.5))
        XCTAssertFalse(rule.isSatisfied(by: 1.75))
    }

    func testAtMostTarget() {
        let rule = TargetRule.atMost(1.0)

        XCTAssertTrue(rule.isSatisfied(by: 0.0))
        XCTAssertTrue(rule.isSatisfied(by: 1.0))
        XCTAssertFalse(rule.isSatisfied(by: 1.25))
    }

    func testRangeTarget() {
        let rule = TargetRule.range(min: 1.0, max: 2.0)

        XCTAssertTrue(rule.isSatisfied(by: 1.0))
        XCTAssertTrue(rule.isSatisfied(by: 1.5))
        XCTAssertTrue(rule.isSatisfied(by: 2.0))
        XCTAssertFalse(rule.isSatisfied(by: 0.75))
        XCTAssertFalse(rule.isSatisfied(by: 2.5))
    }

    func testPortionRounding() {
        let portion = Portion(1.12)

        XCTAssertEqual(portion.value, 1.0)
        XCTAssertTrue(Portion.isValidIncrement(portion.value))
    }
}
