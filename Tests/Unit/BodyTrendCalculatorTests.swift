import XCTest
@testable import Core

final class BodyTrendCalculatorTests: XCTestCase {
    func testSevenDayAverageUsesRecentEntries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDate = calendar.date(from: DateComponents(year: 2025, month: 1, day: 7))!

        let entries = (0..<7).map { offset -> BodyMetricEntry in
            let date = calendar.date(byAdding: .day, value: -offset, to: baseDate)!
            return BodyMetricEntry(date: date, weightKg: Double(70 + offset), muscleMass: nil, bodyFatPercent: nil, waistCm: nil)
        }

        let averages = BodyTrendCalculator().sevenDayAverages(entries: entries, referenceDate: baseDate, calendar: calendar)

        XCTAssertEqual(averages.weightKg, 73.0, accuracy: 0.01)
    }
}
