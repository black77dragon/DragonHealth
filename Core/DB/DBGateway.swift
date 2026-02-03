import Foundation
import Core

public protocol DBGateway: Sendable {
    func fetchCategories() async throws -> [Core.Category]
    func upsertCategory(_ category: Core.Category) async throws
    func deleteCategory(id: UUID) async throws

    func fetchUnits() async throws -> [Core.FoodUnit]
    func upsertUnit(_ unit: Core.FoodUnit) async throws

    func fetchMealSlots() async throws -> [Core.MealSlot]
    func upsertMealSlot(_ mealSlot: Core.MealSlot) async throws
    func deleteMealSlot(id: UUID) async throws

    func fetchSettings() async throws -> Core.AppSettings
    func updateSettings(_ settings: Core.AppSettings) async throws

    func fetchFoodItems() async throws -> [Core.FoodItem]
    func upsertFoodItem(_ item: Core.FoodItem) async throws
    func deleteFoodItem(id: UUID) async throws

    func saveDailyLog(_ log: Core.DailyLog) async throws
    func fetchDailyLog(for date: Date) async throws -> Core.DailyLog?
    func fetchDailyTotalsByDay(start: Date, end: Date) async throws -> [String: [UUID: Double]]

    func fetchBodyMetrics() async throws -> [Core.BodyMetricEntry]
    func upsertBodyMetric(_ entry: Core.BodyMetricEntry) async throws

    func fetchCareMeetings() async throws -> [Core.CareMeeting]
    func upsertCareMeeting(_ meeting: Core.CareMeeting) async throws
    func deleteCareMeeting(id: UUID) async throws

    func fetchDocuments() async throws -> [Core.HealthDocument]
    func upsertDocument(_ document: Core.HealthDocument) async throws
    func deleteDocument(id: UUID) async throws

    func fetchScoreProfiles() async throws -> [UUID: Core.ScoreProfile]
    func upsertScoreProfile(categoryID: UUID, profile: Core.ScoreProfile) async throws
    func deleteScoreProfile(categoryID: UUID) async throws

    func fetchCompensationRules() async throws -> [Core.CompensationRule]
    func upsertCompensationRule(_ rule: Core.CompensationRule) async throws
    func deleteCompensationRule(_ rule: Core.CompensationRule) async throws
}
