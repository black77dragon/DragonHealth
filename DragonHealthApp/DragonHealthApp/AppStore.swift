import Foundation
import Combine
import Core
import CoreDB

@MainActor
final class AppStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var categories: [Core.Category] = []
    @Published private(set) var mealSlots: [Core.MealSlot] = []
    @Published private(set) var foodItems: [Core.FoodItem] = []
    @Published private(set) var bodyMetrics: [Core.BodyMetricEntry] = []
    @Published private(set) var careMeetings: [Core.CareMeeting] = []
    @Published private(set) var documents: [Core.HealthDocument] = []
    @Published private(set) var settings: Core.AppSettings = .defaultValue
    @Published var refreshToken = UUID()

    private let db: SQLiteDatabase?
    private let calendar: Calendar

    var appCalendar: Calendar {
        calendar
    }

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        do {
            self.db = try SQLiteDatabase(path: Self.databaseURL().path, calendar: calendar)
        } catch {
            self.db = nil
            self.loadState = .failed("Database error: \(error.localizedDescription)")
            return
        }

        Task { await loadAll() }
    }

    var dayBoundary: Core.DayBoundary {
        Core.DayBoundary(cutoffMinutes: settings.dayCutoffMinutes)
    }

    var currentDay: Date {
        dayBoundary.dayStart(for: Date(), calendar: calendar)
    }

    private func normalizedDay(for date: Date) -> Date {
        normalizedDay(for: date, treatStartOfDayAsDayOnly: false)
    }

    private func normalizedDay(for date: Date, treatStartOfDayAsDayOnly: Bool) -> Date {
        guard treatStartOfDayAsDayOnly else {
            return dayBoundary.dayStart(for: date, calendar: calendar)
        }
        let dayStart = calendar.startOfDay(for: date)
        let referenceDate: Date
        if date.timeIntervalSince(dayStart) == 0,
           let safeReference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) {
            referenceDate = safeReference
        } else {
            referenceDate = date
        }
        return dayBoundary.dayStart(for: referenceDate, calendar: calendar)
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadAll() async {
        guard let db else { return }
        do {
            var loadedCategories = try await db.fetchCategories()
            if loadedCategories.isEmpty {
                loadedCategories = AppDefaults.categories
                for category in loadedCategories {
                    try await db.upsertCategory(category)
                }
            }

            var loadedMealSlots = try await db.fetchMealSlots()
            if loadedMealSlots.isEmpty {
                loadedMealSlots = AppDefaults.mealSlots
                for slot in loadedMealSlots {
                    try await db.upsertMealSlot(slot)
                }
            }

            var loadedSettings = try await db.fetchSettings()
            try await db.updateSettings(loadedSettings)

            var loadedFoodItems = try await db.fetchFoodItems()
            var didSeedFoodItems = false
            if loadedFoodItems.isEmpty {
                let defaults = AppDefaults.foodItems(categories: loadedCategories)
                if !defaults.isEmpty {
                    for item in defaults {
                        try await db.upsertFoodItem(item)
                    }
                    loadedFoodItems = try await db.fetchFoodItems()
                    didSeedFoodItems = true
                }
            } else if loadedSettings.foodSeedVersion < AppDefaults.foodSeedVersion {
                let missing = AppDefaults.missingFoodItems(existing: loadedFoodItems, categories: loadedCategories)
                if !missing.isEmpty {
                    for item in missing {
                        try await db.upsertFoodItem(item)
                    }
                    loadedFoodItems = try await db.fetchFoodItems()
                }
                didSeedFoodItems = true
            }
            if didSeedFoodItems, loadedSettings.foodSeedVersion < AppDefaults.foodSeedVersion {
                loadedSettings.foodSeedVersion = AppDefaults.foodSeedVersion
                try await db.updateSettings(loadedSettings)
            }
            let loadedMetrics = try await db.fetchBodyMetrics()
            let loadedMeetings = try await db.fetchCareMeetings()
            let loadedDocuments = try await db.fetchDocuments()

            categories = loadedCategories.sorted(by: { $0.sortOrder < $1.sortOrder })
            mealSlots = loadedMealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
            settings = loadedSettings
            foodItems = loadedFoodItems
            bodyMetrics = loadedMetrics.sorted(by: { $0.date > $1.date })
            careMeetings = loadedMeetings.sorted(by: { $0.date > $1.date })
            documents = loadedDocuments.sorted(by: { $0.createdAt > $1.createdAt })

            let foodImagePaths = loadedFoodItems.compactMap(\.imagePath)
            if !foodImagePaths.isEmpty {
                Task(priority: .utility) {
                    FoodImageStorage.resizeExistingImagesIfNeeded(imagePaths: foodImagePaths)
                }
            }

            loadState = .ready
        } catch {
            loadState = .failed("Load error: \(error.localizedDescription)")
        }
    }

    func reload() async {
        await loadAll()
        refreshToken = UUID()
    }

    func saveCategory(_ category: Core.Category) async {
        guard let db else { return }
        do {
            try await db.upsertCategory(category)
            await loadAll()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Category error: \(error.localizedDescription)")
        }
    }

    func deleteCategory(_ category: Core.Category) async {
        guard let db else { return }
        do {
            try await db.deleteCategory(id: category.id)
            await loadAll()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Category error: \(error.localizedDescription)")
        }
    }

    func saveMealSlot(_ mealSlot: Core.MealSlot) async {
        guard let db else { return }
        do {
            try await db.upsertMealSlot(mealSlot)
            await loadAll()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Meal slot error: \(error.localizedDescription)")
        }
    }

    func deleteMealSlot(_ mealSlot: Core.MealSlot) async {
        guard let db else { return }
        do {
            try await db.deleteMealSlot(id: mealSlot.id)
            await loadAll()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Meal slot error: \(error.localizedDescription)")
        }
    }

    func updateSettings(_ settings: Core.AppSettings) async {
        guard let db else { return }
        do {
            try await db.updateSettings(settings)
            self.settings = settings
            refreshToken = UUID()
        } catch {
            loadState = .failed("Settings error: \(error.localizedDescription)")
        }
    }

    func saveFoodItem(_ item: Core.FoodItem) async {
        guard let db else { return }
        do {
            try await db.upsertFoodItem(item)
            foodItems = try await db.fetchFoodItems()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Food error: \(error.localizedDescription)")
        }
    }

    func deleteFoodItem(_ item: Core.FoodItem) async {
        guard let db else { return }
        do {
            try await db.deleteFoodItem(id: item.id)
            if let imagePath = item.imagePath {
                try? FoodImageStorage.deleteImage(fileName: imagePath)
            }
            foodItems = try await db.fetchFoodItems()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Food error: \(error.localizedDescription)")
        }
    }

    func saveBodyMetric(_ entry: Core.BodyMetricEntry) async {
        guard let db else { return }
        do {
            try await db.upsertBodyMetric(entry)
            bodyMetrics = try await db.fetchBodyMetrics()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Body metric error: \(error.localizedDescription)")
        }
    }

    func saveCareMeeting(_ meeting: Core.CareMeeting) async {
        guard let db else { return }
        do {
            try await db.upsertCareMeeting(meeting)
            careMeetings = try await db.fetchCareMeetings()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Care meeting error: \(error.localizedDescription)")
        }
    }

    func deleteCareMeeting(_ meeting: Core.CareMeeting) async {
        guard let db else { return }
        do {
            try await db.deleteCareMeeting(id: meeting.id)
            careMeetings = try await db.fetchCareMeetings()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Care meeting error: \(error.localizedDescription)")
        }
    }

    func saveDocument(_ document: Core.HealthDocument) async {
        guard let db else { return }
        do {
            try await db.upsertDocument(document)
            documents = try await db.fetchDocuments()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Document error: \(error.localizedDescription)")
        }
    }

    func deleteDocument(_ document: Core.HealthDocument) async {
        guard let db else { return }
        do {
            try await db.deleteDocument(id: document.id)
            documents = try await db.fetchDocuments()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Document error: \(error.localizedDescription)")
        }
    }

    func fetchDailyLog(for date: Date) async -> Core.DailyLog? {
        let day = normalizedDay(for: date)
        return await fetchDailyLogForDay(day)
    }

    func fetchHistoryIndicators(start: Date, end: Date) async -> [String: HistoryDayIndicator] {
        guard let db else { return [:] }
        let evaluator = DailyTotalEvaluator()
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        do {
            let totalsByDay = try await db.fetchDailyTotalsByDay(start: rangeStart, end: rangeEnd)
            var indicators: [String: HistoryDayIndicator] = [:]
            for (dayKey, totalsByCategoryID) in totalsByDay {
                let summary = evaluator.evaluate(categories: categories, totalsByCategoryID: totalsByCategoryID)
                indicators[dayKey] = summary.allTargetsMet ? .onTarget : .offTarget
            }
            return indicators
        } catch {
            loadState = .failed("Log error: \(error.localizedDescription)")
            return [:]
        }
    }

    func saveDailyLog(_ log: Core.DailyLog) async {
        let day = normalizedDay(for: log.date, treatStartOfDayAsDayOnly: true)
        let normalizedEntries = log.entries.map { entry in
            Core.DailyLogEntry(
                id: entry.id,
                date: day,
                mealSlotID: entry.mealSlotID,
                categoryID: entry.categoryID,
                portion: entry.portion,
                notes: entry.notes,
                foodItemID: entry.foodItemID
            )
        }
        let normalizedLog = Core.DailyLog(id: log.id, date: day, entries: normalizedEntries)
        await persistDailyLog(normalizedLog)
    }

    func updateEntry(
        _ entry: Core.DailyLogEntry,
        mealSlotID: UUID,
        categoryID: UUID,
        portion: Core.Portion,
        notes: String?,
        foodItemID: UUID?
    ) async {
        let day = normalizedDay(for: entry.date, treatStartOfDayAsDayOnly: true)
        guard var log = await fetchDailyLogForDay(day) else { return }
        guard let index = log.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        log.entries[index] = Core.DailyLogEntry(
            id: entry.id,
            date: day,
            mealSlotID: mealSlotID,
            categoryID: categoryID,
            portion: portion,
            notes: normalizedNotes(notes),
            foodItemID: foodItemID
        )
        await persistDailyLog(log)
    }

    func deleteEntry(_ entry: Core.DailyLogEntry) async {
        let day = normalizedDay(for: entry.date, treatStartOfDayAsDayOnly: true)
        guard var log = await fetchDailyLogForDay(day) else { return }
        log.entries.removeAll { $0.id == entry.id }
        await persistDailyLog(log)
    }

    func logPortion(
        date: Date,
        mealSlotID: UUID,
        categoryID: UUID,
        portion: Core.Portion,
        notes: String?,
        foodItemID: UUID? = nil
    ) async {
        let day = normalizedDay(for: date)
        var log = await fetchDailyLogForDay(day) ?? Core.DailyLog(date: day, entries: [])
        log.entries.append(
            Core.DailyLogEntry(
                date: day,
                mealSlotID: mealSlotID,
                categoryID: categoryID,
                portion: portion,
                notes: normalizedNotes(notes),
                foodItemID: foodItemID
            )
        )
        await persistDailyLog(log)
    }

    private func fetchDailyLogForDay(_ day: Date) async -> Core.DailyLog? {
        guard let db else { return nil }
        do {
            return try await db.fetchDailyLog(for: day)
        } catch {
            loadState = .failed("Log error: \(error.localizedDescription)")
            return nil
        }
    }

    private func persistDailyLog(_ log: Core.DailyLog) async {
        guard let db else { return }
        do {
            try await db.saveDailyLog(log)
            refreshToken = UUID()
        } catch {
            loadState = .failed("Log error: \(error.localizedDescription)")
        }
    }

    nonisolated static func databaseURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("dragonhealth.sqlite")
    }
}

enum AppDefaults {
    static let categories: [Core.Category] = [
        Core.Category(name: "Unsweetened Drinks", unitName: "L", isEnabled: true, targetRule: .range(min: 1.0, max: 2.0), sortOrder: 0),
        Core.Category(name: "Vegetables", unitName: "portions", isEnabled: true, targetRule: .atLeast(3.0), sortOrder: 1),
        Core.Category(name: "Fruit", unitName: "portions", isEnabled: true, targetRule: .atLeast(2.0), sortOrder: 2),
        Core.Category(name: "Starchy Sides", unitName: "portions", isEnabled: true, targetRule: .exact(3.0), sortOrder: 3),
        Core.Category(name: "Protein Sources", unitName: "portions", isEnabled: true, targetRule: .exact(1.0), sortOrder: 4),
        Core.Category(name: "Dairy", unitName: "portions", isEnabled: true, targetRule: .exact(3.0), sortOrder: 5),
        Core.Category(name: "Oils / Fats / Nuts", unitName: "portions", isEnabled: true, targetRule: .range(min: 2.0, max: 3.0), sortOrder: 6),
        Core.Category(name: "Treats", unitName: "portions", isEnabled: true, targetRule: .atMost(1.0), sortOrder: 7),
        Core.Category(name: "Sports", unitName: "min", isEnabled: true, targetRule: .atLeast(30.0), sortOrder: 8)
    ]

    static let mealSlots: [Core.MealSlot] = [
        Core.MealSlot(name: "Breakfast", sortOrder: 0),
        Core.MealSlot(name: "Morning Snack", sortOrder: 1),
        Core.MealSlot(name: "Lunch", sortOrder: 2),
        Core.MealSlot(name: "Afternoon Snack", sortOrder: 3),
        Core.MealSlot(name: "Dinner", sortOrder: 4),
        Core.MealSlot(name: "Late Night", sortOrder: 5),
        Core.MealSlot(name: "Midnight", sortOrder: 6)
    ]
}
