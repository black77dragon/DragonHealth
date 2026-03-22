import Foundation
import XCTest
@testable import Core
@testable import CoreDB

final class DrugReviewTests: XCTestCase {
    private var databaseURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in databaseURLs {
            try? FileManager.default.removeItem(at: url)
        }
        databaseURLs.removeAll()
    }

    func testWeeklySummaryGeneratesAveragesAndIncludesObservationText() throws {
        let calendar = makeCalendar()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 22))!
        let weekStart = calendar.date(byAdding: .day, value: -6, to: referenceDate)!

        let entries = (0..<7).map { offset -> DrugReviewDailyEntry in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            return DrugReviewDailyEntry(
                day: day,
                timestamp: calendar.date(bySettingHour: 8 + offset, minute: 0, second: 0, of: day) ?? day,
                appetiteControl: 4 + offset,
                energyLevel: 5 + offset,
                sideEffects: 3,
                mood: 6,
                observation: offset >= 5 ? "Observation \(offset)" : nil
            )
        }

        let reflection = DrugReviewWeeklyReflection(
            weekStart: weekStart,
            whatWentWell: "Protein stayed steady.",
            whatDidNotWork: "Energy dipped after lunch.",
            whatToAdjust: "Move hydration earlier."
        )

        let summary = try XCTUnwrap(
            DrugReviewAnalytics().weeklySummary(
                referenceDate: referenceDate,
                entries: entries,
                reflection: reflection,
                calendar: calendar
            )
        )

        XCTAssertEqual(summary.entryCount, 7)
        XCTAssertEqual(try XCTUnwrap(summary.averages.appetiteControl), 7.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(summary.averages.energyLevel), 55.0 / 7.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(summary.averages.sideEffects), 3.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(summary.averages.mood), 6.0, accuracy: 0.01)
        XCTAssertEqual(summary.observationHighlights, ["Observation 6", "Observation 5"])
        XCTAssertEqual(summary.reflectionNotes.map(\.title), ["What Went Well", "What Didn't Work", "What To Adjust"])
    }

    func testSQLitePersistsDailyEntryAndWeeklyReflection() async throws {
        let db = try makeDatabase()
        let calendar = makeCalendar()
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 22))!
        let weekStart = calendar.date(byAdding: .day, value: -6, to: day)!

        let entry = DrugReviewDailyEntry(
            day: day,
            timestamp: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? day,
            appetiteControl: 8,
            energyLevel: 7,
            sideEffects: 2,
            mood: 6,
            observation: "Felt full earlier in the day."
        )
        let reflection = DrugReviewWeeklyReflection(
            weekStart: weekStart,
            whatWentWell: "Cravings were lower.",
            whatDidNotWork: "Skipped lunch once.",
            whatToAdjust: "Prep protein in advance."
        )

        try await db.upsertDrugReviewEntry(entry)
        try await db.upsertDrugReviewWeeklyReflection(reflection)

        let fetchedEntry = try await db.fetchDrugReviewEntry(for: day)
        let storedEntry = try XCTUnwrap(fetchedEntry)
        let storedEntries = try await db.fetchDrugReviewEntries(
            start: calendar.date(byAdding: .day, value: -6, to: day) ?? day,
            end: day
        )
        let fetchedReflection = try await db.fetchDrugReviewWeeklyReflection(for: day)
        let storedReflection = try XCTUnwrap(fetchedReflection)

        XCTAssertEqual(storedEntry.appetiteControl, 8)
        XCTAssertEqual(storedEntry.energyLevel, 7)
        XCTAssertEqual(storedEntry.sideEffects, 2)
        XCTAssertEqual(storedEntry.mood, 6)
        XCTAssertEqual(storedEntry.observation, "Felt full earlier in the day.")
        XCTAssertEqual(storedEntries.count, 1)
        XCTAssertEqual(storedReflection.whatWentWell, "Cravings were lower.")
        XCTAssertEqual(storedReflection.whatDidNotWork, "Skipped lunch once.")
        XCTAssertEqual(storedReflection.whatToAdjust, "Prep protein in advance.")
    }

    private func makeDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dragonhealth-drug-review-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        databaseURLs.append(url)
        return try SQLiteDatabase(path: url.path, calendar: makeCalendar())
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
