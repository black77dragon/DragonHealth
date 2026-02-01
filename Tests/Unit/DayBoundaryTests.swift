import XCTest
@testable import Core

final class DayBoundaryTests: XCTestCase {
    func testDayBoundaryBeforeCutoffShiftsToPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let boundary = DayBoundary(cutoffMinutes: 4 * 60)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 2, minute: 30))!
        let expected = calendar.date(from: DateComponents(year: 2025, month: 1, day: 14))!

        XCTAssertEqual(boundary.dayStart(for: date, calendar: calendar), expected)
    }

    func testDayBoundaryAfterCutoffStaysSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let boundary = DayBoundary(cutoffMinutes: 4 * 60)
        let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 8, minute: 0))!
        let expected = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        XCTAssertEqual(boundary.dayStart(for: date, calendar: calendar), expected)
    }
}
