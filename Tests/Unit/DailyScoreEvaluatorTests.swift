import XCTest
@testable import Core

final class DailyScoreEvaluatorTests: XCTestCase {
    func testScoreIsHundredWithinRange() {
        let category = Category(
            name: "Vegetables",
            unitName: "portions",
            isEnabled: true,
            targetRule: .range(min: 1.0, max: 2.0),
            sortOrder: 0
        )
        let totals: [UUID: Double] = [category.id: 1.5]
        let summary = DailyScoreEvaluator().evaluate(categories: [category], totalsByCategoryID: totals)

        XCTAssertEqual(summary.overallScore, 100, accuracy: 0.01)
    }

    func testTreatsOverageIsOffsetBySportsSurplus() {
        let treats = Category(
            name: "Treats",
            unitName: "portions",
            isEnabled: true,
            targetRule: .atMost(1.0),
            sortOrder: 0
        )
        let sports = Category(
            name: "Sports",
            unitName: "min",
            isEnabled: true,
            targetRule: .atLeast(30.0),
            sortOrder: 1
        )
        let totals: [UUID: Double] = [
            treats.id: 3.0,
            sports.id: 60.0
        ]

        let noCompSummary = DailyScoreEvaluator().evaluate(
            categories: [treats, sports],
            totalsByCategoryID: totals,
            compensationRules: []
        )
        XCTAssertLessThan(noCompSummary.overallScore, 100)

        let withCompSummary = DailyScoreEvaluator().evaluate(
            categories: [treats, sports],
            totalsByCategoryID: totals
        )
        XCTAssertEqual(withCompSummary.overallScore, 100, accuracy: 0.01)
    }
}
