import Foundation
import XCTest
@testable import Core
@testable import CoreDB

final class SQLiteDatabaseDeletionGuardsTests: XCTestCase {
    private var databaseURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in databaseURLs {
            try? FileManager.default.removeItem(at: url)
        }
        databaseURLs.removeAll()
    }

    func testDeleteCategoryFailsWhenCategoryHasLoggedEntries() async throws {
        let db = try makeDatabase()
        let category = Category(
            name: "Vegetables",
            unitName: "portion",
            isEnabled: true,
            targetRule: .atLeast(3.0),
            sortOrder: 0
        )
        let mealSlot = MealSlot(name: "Breakfast", sortOrder: 0)

        try await db.upsertCategory(category)
        try await db.upsertMealSlot(mealSlot)

        let day = Date(timeIntervalSince1970: 1_735_171_200)
        let entry = DailyLogEntry(
            date: day,
            mealSlotID: mealSlot.id,
            categoryID: category.id,
            portion: Portion(1.0)
        )
        try await db.saveDailyLog(DailyLog(date: day, entries: [entry]))

        try await expectExecutionFailure(messageContains: "logged entries") {
            try await db.deleteCategory(id: category.id)
        }
    }

    func testDeleteCategoryFailsWhenCategoryIsUsedByFoodItem() async throws {
        let db = try makeDatabase()
        let category = Category(
            name: "Fruit",
            unitName: "portion",
            isEnabled: true,
            targetRule: .atLeast(2.0),
            sortOrder: 0
        )
        let foodItem = FoodItem(name: "Apple", categoryID: category.id, portionEquivalent: 1.0)

        try await db.upsertCategory(category)
        try await db.upsertFoodItem(foodItem)

        try await expectExecutionFailure(messageContains: "food library items") {
            try await db.deleteCategory(id: category.id)
        }
    }

    func testDeleteMealSlotFailsWhenOnlyOneSlotExists() async throws {
        let db = try makeDatabase()
        let mealSlot = MealSlot(name: "Lunch", sortOrder: 0)
        try await db.upsertMealSlot(mealSlot)

        try await expectExecutionFailure(messageContains: "At least one meal slot is required") {
            try await db.deleteMealSlot(id: mealSlot.id)
        }
    }

    func testDeleteMealSlotFailsWhenSlotHasLoggedEntries() async throws {
        let db = try makeDatabase()
        let category = Category(
            name: "Protein",
            unitName: "portion",
            isEnabled: true,
            targetRule: .exact(1.0),
            sortOrder: 0
        )
        let breakfast = MealSlot(name: "Breakfast", sortOrder: 0)
        let dinner = MealSlot(name: "Dinner", sortOrder: 1)

        try await db.upsertCategory(category)
        try await db.upsertMealSlot(breakfast)
        try await db.upsertMealSlot(dinner)

        let day = Date(timeIntervalSince1970: 1_735_171_200)
        let entry = DailyLogEntry(
            date: day,
            mealSlotID: breakfast.id,
            categoryID: category.id,
            portion: Portion(1.0)
        )
        try await db.saveDailyLog(DailyLog(date: day, entries: [entry]))

        try await expectExecutionFailure(messageContains: "logged entries") {
            try await db.deleteMealSlot(id: breakfast.id)
        }
    }

    private func makeDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dragonhealth-tests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        databaseURLs.append(url)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return try SQLiteDatabase(path: url.path, calendar: calendar)
    }

    private func expectExecutionFailure(
        messageContains expectedFragment: String,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected SQLite execution failure containing '\(expectedFragment)'")
        } catch let error as SQLiteDatabaseError {
            guard case .executionFailed(let message) = error else {
                XCTFail("Expected executionFailed, got \(error)")
                return
            }
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains(expectedFragment),
                "Expected message containing '\(expectedFragment)', got '\(message)'"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
