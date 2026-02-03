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
    @Published private(set) var units: [Core.FoodUnit] = []
    @Published private(set) var mealSlots: [Core.MealSlot] = []
    @Published private(set) var foodItems: [Core.FoodItem] = []
    @Published private(set) var bodyMetrics: [Core.BodyMetricEntry] = []
    @Published private(set) var careMeetings: [Core.CareMeeting] = []
    @Published private(set) var documents: [Core.HealthDocument] = []
    @Published private(set) var scoreProfiles: [UUID: Core.ScoreProfile] = [:]
    @Published private(set) var compensationRules: [Core.CompensationRule] = []
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

    func currentMealSlotID(for date: Date = Date()) -> UUID? {
        let timings = resolvedMealSlotTimings().filter(\.includeInAuto)
        guard !timings.isEmpty else { return mealSlots.first?.id }
        if timings.count == 1 {
            return timings[0].slotID
        }
        let minute = minuteOfDay(for: date)
        for index in 0..<(timings.count - 1) {
            let start = timings[index].startMinutes
            let end = timings[index + 1].startMinutes
            if minute >= start && minute < end {
                return timings[index].slotID
            }
        }
        if let last = timings.last {
            if minute >= last.startMinutes || minute < timings[0].startMinutes {
                return last.slotID
            }
        }
        return mealSlots.first?.id
    }

    func resolvedMealSlotTimings() -> [Core.MealSlotTiming] {
        Self.resolvedMealSlotTimings(mealSlots: mealSlots, settings: settings)
    }

    func defaultMealSlotTimings() -> [Core.MealSlotTiming] {
        Self.defaultMealSlotTimings(mealSlots: mealSlots, dayCutoffMinutes: settings.dayCutoffMinutes)
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

    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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

            var loadedUnits = try await db.fetchUnits()
            if loadedUnits.isEmpty {
                loadedUnits = AppDefaults.units
                for unit in loadedUnits {
                    try await db.upsertUnit(unit)
                }
                loadedUnits = try await db.fetchUnits()
            }

            var loadedSettings = try await db.fetchSettings()
            let resolvedTimings = Self.resolvedMealSlotTimings(mealSlots: loadedMealSlots, settings: loadedSettings)
            if resolvedTimings != loadedSettings.mealSlotTimings {
                loadedSettings.mealSlotTimings = resolvedTimings
                try await db.updateSettings(loadedSettings)
            } else {
                try await db.updateSettings(loadedSettings)
            }

            var loadedFoodItems = try await db.fetchFoodItems()
            var didSeedFoodItems = false
            if loadedFoodItems.isEmpty {
                let defaults = AppDefaults.foodItems(categories: loadedCategories, units: loadedUnits)
                if !defaults.isEmpty {
                    for item in defaults {
                        try await db.upsertFoodItem(item)
                    }
                    loadedFoodItems = try await db.fetchFoodItems()
                    didSeedFoodItems = true
                }
            } else if loadedSettings.foodSeedVersion < AppDefaults.foodSeedVersion {
                let missing = AppDefaults.missingFoodItems(existing: loadedFoodItems, categories: loadedCategories, units: loadedUnits)
                if !missing.isEmpty {
                    for item in missing {
                        try await db.upsertFoodItem(item)
                    }
                    loadedFoodItems = try await db.fetchFoodItems()
                }
                let enriched = AppDefaults.enrichFoodItems(existing: loadedFoodItems, categories: loadedCategories, units: loadedUnits)
                if !enriched.isEmpty {
                    for item in enriched {
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
            let loadedScoreProfiles = try await db.fetchScoreProfiles()
            var loadedCompensationRules = try await db.fetchCompensationRules()
            if loadedCompensationRules.isEmpty {
                let defaults = Core.CompensationRule.defaultRules(for: loadedCategories)
                if !defaults.isEmpty {
                    for rule in defaults {
                        try await db.upsertCompensationRule(rule)
                    }
                    loadedCompensationRules = try await db.fetchCompensationRules()
                }
            }

            categories = loadedCategories.sorted(by: { $0.sortOrder < $1.sortOrder })
            units = loadedUnits.sorted(by: { $0.sortOrder < $1.sortOrder })
            mealSlots = loadedMealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
            settings = loadedSettings
            foodItems = loadedFoodItems
            bodyMetrics = loadedMetrics.sorted(by: { $0.date > $1.date })
            careMeetings = loadedMeetings.sorted(by: { $0.date > $1.date })
            documents = loadedDocuments.sorted(by: { $0.createdAt > $1.createdAt })
            let categoryIDs = Set(categories.map(\.id))
            scoreProfiles = loadedScoreProfiles.filter { categoryIDs.contains($0.key) }
            compensationRules = loadedCompensationRules.filter { categoryIDs.contains($0.fromCategoryID) && categoryIDs.contains($0.toCategoryID) }

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

    func saveScoreProfile(categoryID: UUID, profile: Core.ScoreProfile) async {
        guard let db else { return }
        do {
            try await db.upsertScoreProfile(categoryID: categoryID, profile: profile)
            scoreProfiles = try await db.fetchScoreProfiles()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Scoring error: \(error.localizedDescription)")
        }
    }

    func deleteScoreProfile(categoryID: UUID) async {
        guard let db else { return }
        do {
            try await db.deleteScoreProfile(categoryID: categoryID)
            scoreProfiles = try await db.fetchScoreProfiles()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Scoring error: \(error.localizedDescription)")
        }
    }

    func saveCompensationRule(_ rule: Core.CompensationRule) async {
        guard let db else { return }
        do {
            try await db.upsertCompensationRule(rule)
            compensationRules = try await db.fetchCompensationRules()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Scoring error: \(error.localizedDescription)")
        }
    }

    func deleteCompensationRule(_ rule: Core.CompensationRule) async {
        guard let db else { return }
        do {
            try await db.deleteCompensationRule(rule)
            compensationRules = try await db.fetchCompensationRules()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Scoring error: \(error.localizedDescription)")
        }
    }

    func saveUnit(_ unit: Core.FoodUnit) async {
        guard let db else { return }
        do {
            try await db.upsertUnit(unit)
            units = try await db.fetchUnits()
            refreshToken = UUID()
        } catch {
            loadState = .failed("Unit error: \(error.localizedDescription)")
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
        let evaluator = DailyScoreEvaluator()
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        do {
            let totalsByDay = try await db.fetchDailyTotalsByDay(start: rangeStart, end: rangeEnd)
            var indicators: [String: HistoryDayIndicator] = [:]
            for (dayKey, totalsByCategoryID) in totalsByDay {
                let summary = evaluator.evaluate(
                    categories: categories,
                    totalsByCategoryID: totalsByCategoryID,
                    profilesByCategoryID: scoreProfiles,
                    compensationRules: compensationRules
                )
                indicators[dayKey] = .score(summary.overallScore)
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
                amountValue: entry.amountValue,
                amountUnitID: entry.amountUnitID,
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
        amountValue: Double?,
        amountUnitID: UUID?,
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
            amountValue: amountValue,
            amountUnitID: amountUnitID,
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
        amountValue: Double? = nil,
        amountUnitID: UUID? = nil,
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
                amountValue: amountValue,
                amountUnitID: amountUnitID,
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

    private static func resolvedMealSlotTimings(
        mealSlots: [Core.MealSlot],
        settings: Core.AppSettings
    ) -> [Core.MealSlotTiming] {
        let orderedSlots = mealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard !orderedSlots.isEmpty else { return [] }

        let sanitizedStored = settings.mealSlotTimings
            .filter { (0..<1440).contains($0.startMinutes) }
            .reduce(into: [UUID: Core.MealSlotTiming]()) { partialResult, timing in
                partialResult[timing.slotID] = timing
            }

        let defaults = defaultMealSlotTimings(mealSlots: orderedSlots, dayCutoffMinutes: settings.dayCutoffMinutes)
        let defaultByID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.slotID, $0.startMinutes) })

        var resolved: [Core.MealSlotTiming] = []

        for slot in orderedSlots {
            let stored = sanitizedStored[slot.id]
            let include = stored?.includeInAuto ?? true
            var start = stored?.startMinutes ?? defaultByID[slot.id] ?? 0
            start = min(max(start, 0), 1439)
            resolved.append(Core.MealSlotTiming(slotID: slot.id, startMinutes: start, includeInAuto: include))
        }

        var lastIncludedStart: Int? = nil
        for index in resolved.indices {
            guard resolved[index].includeInAuto else { continue }
            if let lastIncludedStart, resolved[index].startMinutes <= lastIncludedStart {
                resolved[index].startMinutes = min(lastIncludedStart + 1, 1439)
            }
            lastIncludedStart = resolved[index].startMinutes
        }
        return resolved
    }

    private static func defaultMealSlotTimings(
        mealSlots: [Core.MealSlot],
        dayCutoffMinutes: Int
    ) -> [Core.MealSlotTiming] {
        let orderedSlots = mealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard !orderedSlots.isEmpty else { return [] }

        var inferred: [Core.MealSlotTiming] = []
        var allInferred = true
        for slot in orderedSlots {
            if let start = inferredStartMinutes(for: slot, dayCutoffMinutes: dayCutoffMinutes) {
                inferred.append(Core.MealSlotTiming(slotID: slot.id, startMinutes: start, includeInAuto: true))
            } else {
                allInferred = false
                break
            }
        }

        if allInferred, isStrictlyIncreasing(inferred.map(\.startMinutes)) {
            return inferred
        }

        let step = max(1, 1440 / orderedSlots.count)
        return orderedSlots.enumerated().map { index, slot in
            let start = min(1439, index * step)
            return Core.MealSlotTiming(slotID: slot.id, startMinutes: start, includeInAuto: true)
        }
    }

    private static func inferredStartMinutes(
        for slot: Core.MealSlot,
        dayCutoffMinutes: Int
    ) -> Int? {
        let name = slot.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.contains("breakfast") {
            return min(max(dayCutoffMinutes, 0), 1439)
        }
        if name.contains("morning") && name.contains("snack") {
            return 8 * 60
        }
        if name.contains("lunch") {
            return 12 * 60
        }
        if name.contains("afternoon") && name.contains("snack") {
            return 14 * 60
        }
        if name.contains("dinner") {
            return 18 * 60
        }
        if name.contains("late") && name.contains("night") {
            return 20 * 60
        }
        if name.contains("midnight") {
            return 23 * 60
        }
        return nil
    }

    private static func isStrictlyIncreasing(_ values: [Int]) -> Bool {
        guard values.count > 1 else { return true }
        for index in 1..<values.count where values[index] <= values[index - 1] {
            return false
        }
        return true
    }

    nonisolated static func databaseURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("dragonhealth.sqlite")
    }
}

enum AppDefaults {
    static let units: [Core.FoodUnit] = [
        Core.FoodUnit(name: "Gram", symbol: "g", allowsDecimal: true, isEnabled: true, sortOrder: 0),
        Core.FoodUnit(name: "Milliliter", symbol: "ml", allowsDecimal: true, isEnabled: true, sortOrder: 1),
        Core.FoodUnit(name: "Piece", symbol: "pc", allowsDecimal: false, isEnabled: true, sortOrder: 2)
    ]

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
