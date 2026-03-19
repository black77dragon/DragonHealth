import XCTest
@testable import Core

final class DailyTotalsCalculatorTests: XCTestCase {
    func testTotalsByCategoryAggregatesPortions() throws {
        let categoryID = UUID()
        let mealID = UUID()
        let date = Date()

        let entries = [
            DailyLogEntry(date: date, mealSlotID: mealID, categoryID: categoryID, portion: Portion(1.0)),
            DailyLogEntry(date: date, mealSlotID: mealID, categoryID: categoryID, portion: Portion(0.5))
        ]

        let totals = DailyTotalsCalculator().totalsByCategory(entries: entries)
        let total = try XCTUnwrap(totals[categoryID])
        XCTAssertEqual(total, 1.5, accuracy: 0.001)
    }
}
