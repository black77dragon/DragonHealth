import Foundation
import Combine
import Core
import CoreDB

struct ScoreHistoryEntry: Hashable, Sendable {
    let date: Date
    let score: Double
}

@MainActor
final class AppStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    struct HistoryInvalidation: Equatable {
        let token: UUID
        let changedDay: Date?
        let reloadSelectedDay: Bool
        let reloadCalendarIndicators: Bool
        let reloadScoreHistory: Bool

        init(
            token: UUID = UUID(),
            changedDay: Date? = nil,
            reloadSelectedDay: Bool = false,
            reloadCalendarIndicators: Bool = false,
            reloadScoreHistory: Bool = false
        ) {
            self.token = token
            self.changedDay = changedDay
            self.reloadSelectedDay = reloadSelectedDay
            self.reloadCalendarIndicators = reloadCalendarIndicators
            self.reloadScoreHistory = reloadScoreHistory
        }
    }

    struct LogPortionRequest: Sendable {
        let mealSlotID: UUID
        let categoryID: UUID
        let portion: Core.Portion
        let amountValue: Double?
        let amountUnitID: UUID?
        let notes: String?
        let foodItemID: UUID?
        let compositeGroupID: UUID?
        let compositeFoodID: UUID?
        let compositeFoodName: String?

        init(
            mealSlotID: UUID,
            categoryID: UUID,
            portion: Core.Portion,
            amountValue: Double? = nil,
            amountUnitID: UUID? = nil,
            notes: String?,
            foodItemID: UUID? = nil,
            compositeGroupID: UUID? = nil,
            compositeFoodID: UUID? = nil,
            compositeFoodName: String? = nil
        ) {
            self.mealSlotID = mealSlotID
            self.categoryID = categoryID
            self.portion = portion
            self.amountValue = amountValue
            self.amountUnitID = amountUnitID
            self.notes = notes
            self.foodItemID = foodItemID
            self.compositeGroupID = compositeGroupID
            self.compositeFoodID = compositeFoodID
            self.compositeFoodName = compositeFoodName
        }
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
    @Published private(set) var drugReviewRefreshToken = UUID()
    @Published private(set) var historyInvalidation = HistoryInvalidation()
    @Published private(set) var operationErrorMessage: String?

    private let db: SQLiteDatabase?
    private let calendar: Calendar

    var appCalendar: Calendar {
        calendar
    }

    private var dailyLogStore: DailyLogStore {
        DailyLogStore(
            db: db,
            calendar: calendar,
            dayBoundary: dayBoundary,
            categories: categories,
            units: units,
            foodItems: foodItems,
            onPersist: { [self] day in
                self.invalidateForDailyLogChange(on: day)
            },
            onError: { [self] message in
                self.recordOperationError(message)
            }
        )
    }

    private var bodyMetricsStore: BodyMetricsStore? {
        guard let db else { return nil }
        return BodyMetricsStore(db: db, calendar: calendar)
    }

    private var foodLibraryStore: FoodLibraryStore? {
        guard let db else { return nil }
        return FoodLibraryStore(db: db)
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

    func clearOperationError() {
        operationErrorMessage = nil
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

    private func minuteOfDay(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func recordOperationError(_ message: String) {
        operationErrorMessage = message
    }

    private func handleOperationError(_ context: String, _ error: Error) {
        recordOperationError("\(context): \(error.localizedDescription)")
    }

    private func bumpRefreshToken() {
        refreshToken = UUID()
    }

    private func invalidateHistory(
        changedDay: Date? = nil,
        reloadSelectedDay: Bool = false,
        reloadCalendarIndicators: Bool = false,
        reloadScoreHistory: Bool = false
    ) {
        historyInvalidation = HistoryInvalidation(
            changedDay: changedDay,
            reloadSelectedDay: reloadSelectedDay,
            reloadCalendarIndicators: reloadCalendarIndicators,
            reloadScoreHistory: reloadScoreHistory
        )
    }

    private func invalidateForDailyLogChange(on day: Date) {
        bumpRefreshToken()
        invalidateHistory(
            changedDay: day,
            reloadSelectedDay: true,
            reloadCalendarIndicators: true,
            reloadScoreHistory: true
        )
    }

    private func invalidateDrugReview() {
        drugReviewRefreshToken = UUID()
    }

    private func invalidateHistoryGlobally() {
        bumpRefreshToken()
        invalidateHistory(
            reloadSelectedDay: true,
            reloadCalendarIndicators: true,
            reloadScoreHistory: true
        )
    }

    func loadAll() async {
        guard let db else { return }
        do {
            let snapshot = try await AppBootstrapLoader(
                db: db,
                resolveMealSlotTimings: Self.resolvedMealSlotTimings(mealSlots:settings:),
                normalizedCategoryName: Self.normalizedCategoryName(_:),
                isLegacyCarbCategoryName: Self.isLegacyCarbCategoryName(_:)
            ).load()

            apply(snapshot)

            if !snapshot.foodImagePaths.isEmpty {
                Task(priority: .utility) {
                    FoodImageStorage.resizeExistingImagesIfNeeded(imagePaths: snapshot.foodImagePaths)
                }
            }

            loadState = .ready
        } catch {
            loadState = .failed("Load error: \(error.localizedDescription)")
        }
    }

    func reload() async {
        await loadAll()
        invalidateHistoryGlobally()
    }

    private func apply(_ snapshot: AppBootstrapSnapshot) {
        categories = snapshot.categories
        units = snapshot.units
        mealSlots = snapshot.mealSlots
        settings = snapshot.settings
        foodItems = snapshot.foodItems
        bodyMetrics = snapshot.bodyMetrics
        careMeetings = snapshot.careMeetings
        documents = snapshot.documents
        scoreProfiles = snapshot.scoreProfiles
        compensationRules = snapshot.compensationRules
    }

    func saveCategory(_ category: Core.Category) async {
        guard let db else { return }
        do {
            try await db.upsertCategory(category)
            await loadAll()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Category error", error)
        }
    }

    func deleteCategory(_ category: Core.Category) async {
        guard let db else { return }
        do {
            try await db.deleteCategory(id: category.id)
            await loadAll()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Category error", error)
        }
    }

    func saveScoreProfile(categoryID: UUID, profile: Core.ScoreProfile) async {
        guard let db else { return }
        do {
            try await db.upsertScoreProfile(categoryID: categoryID, profile: profile)
            scoreProfiles = try await db.fetchScoreProfiles()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Scoring error", error)
        }
    }

    func deleteScoreProfile(categoryID: UUID) async {
        guard let db else { return }
        do {
            try await db.deleteScoreProfile(categoryID: categoryID)
            scoreProfiles = try await db.fetchScoreProfiles()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Scoring error", error)
        }
    }

    func saveCompensationRule(_ rule: Core.CompensationRule) async {
        guard let db else { return }
        do {
            try await db.upsertCompensationRule(rule)
            compensationRules = try await db.fetchCompensationRules()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Scoring error", error)
        }
    }

    func deleteCompensationRule(_ rule: Core.CompensationRule) async {
        guard let db else { return }
        do {
            try await db.deleteCompensationRule(rule)
            compensationRules = try await db.fetchCompensationRules()
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Scoring error", error)
        }
    }

    func saveUnit(_ unit: Core.FoodUnit) async {
        guard let db else { return }
        do {
            try await db.upsertUnit(unit)
            units = try await db.fetchUnits()
            bumpRefreshToken()
        } catch {
            handleOperationError("Unit error", error)
        }
    }

    func saveMealSlot(_ mealSlot: Core.MealSlot) async {
        guard let db else { return }
        do {
            try await db.upsertMealSlot(mealSlot)
            await loadAll()
            bumpRefreshToken()
        } catch {
            handleOperationError("Meal slot error", error)
        }
    }

    func deleteMealSlot(_ mealSlot: Core.MealSlot) async {
        guard let db else { return }
        do {
            try await db.deleteMealSlot(id: mealSlot.id)
            await loadAll()
            bumpRefreshToken()
        } catch {
            handleOperationError("Meal slot error", error)
        }
    }

    func updateSettings(_ settings: Core.AppSettings) async {
        guard let db else { return }
        do {
            try await db.updateSettings(settings)
            self.settings = settings
            invalidateHistoryGlobally()
        } catch {
            handleOperationError("Settings error", error)
        }
    }

    func saveFoodItem(_ item: Core.FoodItem) async {
        guard let foodLibraryStore else { return }
        do {
            foodItems = try await foodLibraryStore.save(item)
            bumpRefreshToken()
        } catch {
            handleOperationError("Food error", error)
        }
    }

    func saveFoodItemReturningError(_ item: Core.FoodItem) async -> String? {
        guard let foodLibraryStore else { return "Database is unavailable." }
        do {
            foodItems = try await foodLibraryStore.save(item)
            bumpRefreshToken()
            return nil
        } catch {
            let message = "Food error: \(error.localizedDescription)"
            recordOperationError(message)
            return message
        }
    }

    func upsertFoodItems(_ items: [Core.FoodItem]) async -> String? {
        guard let foodLibraryStore else { return "Database is unavailable." }
        guard !items.isEmpty else { return nil }
        do {
            foodItems = try await foodLibraryStore.saveAll(items)
            bumpRefreshToken()
            return nil
        } catch {
            let message = "Food import error: \(error.localizedDescription)"
            recordOperationError(message)
            return message
        }
    }

    func deleteFoodItem(_ item: Core.FoodItem) async {
        guard let foodLibraryStore else { return }
        do {
            foodItems = try await foodLibraryStore.delete(item)
            bumpRefreshToken()
        } catch {
            handleOperationError("Food error", error)
        }
    }

    func saveBodyMetric(_ entry: Core.BodyMetricEntry) async {
        guard let bodyMetricsStore else { return }
        do {
            bodyMetrics = try await bodyMetricsStore.save(entry)
            bumpRefreshToken()
        } catch {
            handleOperationError("Body metric error", error)
        }
    }

    func saveCareMeeting(_ meeting: Core.CareMeeting) async {
        guard let db else { return }
        do {
            try await db.upsertCareMeeting(meeting)
            careMeetings = try await db.fetchCareMeetings()
            bumpRefreshToken()
        } catch {
            handleOperationError("Care meeting error", error)
        }
    }

    func deleteCareMeeting(_ meeting: Core.CareMeeting) async {
        guard let db else { return }
        do {
            try await db.deleteCareMeeting(id: meeting.id)
            careMeetings = try await db.fetchCareMeetings()
            bumpRefreshToken()
        } catch {
            handleOperationError("Care meeting error", error)
        }
    }

    func saveDocument(_ document: Core.HealthDocument) async {
        guard let db else { return }
        do {
            try await db.upsertDocument(document)
            documents = try await db.fetchDocuments()
            bumpRefreshToken()
        } catch {
            handleOperationError("Document error", error)
        }
    }

    func deleteDocument(_ document: Core.HealthDocument) async {
        guard let db else { return }
        do {
            try await db.deleteDocument(id: document.id)
            documents = try await db.fetchDocuments()
            bumpRefreshToken()
        } catch {
            handleOperationError("Document error", error)
        }
    }

    func fetchDailyLog(for date: Date) async -> Core.DailyLog? {
        await dailyLogStore.fetchDailyLog(for: date)
    }

    func fetchHistoryIndicators(start: Date, end: Date) async -> [String: HistoryDayIndicator] {
        let totalsByDay = await fetchDailyTotalsByDay(start: start, end: end)
        guard !totalsByDay.isEmpty else { return [:] }
        let evaluator = DailyScoreEvaluator()
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
    }

    func fetchScoreHistory(start: Date, end: Date) async -> [ScoreHistoryEntry] {
        let totalsByDay = await fetchDailyTotalsByDay(start: start, end: end)
        guard !totalsByDay.isEmpty else { return [] }
        let evaluator = DailyScoreEvaluator()
        let calendar = appCalendar
        var entries: [ScoreHistoryEntry] = []
        for (dayKey, totalsByCategoryID) in totalsByDay {
            guard let day = DayKeyParser.date(from: dayKey, timeZone: calendar.timeZone) else { continue }
            let summary = evaluator.evaluate(
                categories: categories,
                totalsByCategoryID: totalsByCategoryID,
                profilesByCategoryID: scoreProfiles,
                compensationRules: compensationRules
            )
            entries.append(ScoreHistoryEntry(date: day, score: summary.overallScore))
        }
        return entries.sorted(by: { $0.date < $1.date })
    }

    func fetchDailyTotalsByDay(start: Date, end: Date) async -> [String: [UUID: Double]] {
        guard let db else { return [:] }
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        do {
            return try await db.fetchDailyTotalsByDay(start: rangeStart, end: rangeEnd)
        } catch {
            handleOperationError("Log error", error)
            return [:]
        }
    }

    func fetchDrugReviewEntry(for date: Date) async -> Core.DrugReviewDailyEntry? {
        guard let db else { return nil }
        do {
            return try await db.fetchDrugReviewEntry(for: date)
        } catch {
            handleOperationError("GLP-1 review error", error)
            return nil
        }
    }

    func fetchDrugReviewEntries(start: Date, end: Date) async -> [Core.DrugReviewDailyEntry] {
        guard let db else { return [] }
        do {
            return try await db.fetchDrugReviewEntries(start: start, end: end)
        } catch {
            handleOperationError("GLP-1 review error", error)
            return []
        }
    }

    func saveDrugReviewEntry(_ entry: Core.DrugReviewDailyEntry) async -> Bool {
        guard let db else { return false }
        do {
            try await db.upsertDrugReviewEntry(entry)
            invalidateDrugReview()
            return true
        } catch {
            handleOperationError("GLP-1 review error", error)
            return false
        }
    }

    func fetchDrugReviewWeeklyReflection(for date: Date) async -> Core.DrugReviewWeeklyReflection? {
        guard let db else { return nil }
        do {
            return try await db.fetchDrugReviewWeeklyReflection(for: date)
        } catch {
            handleOperationError("GLP-1 review error", error)
            return nil
        }
    }

    func fetchDrugReviewWeeklyReflections(start: Date, end: Date) async -> [Core.DrugReviewWeeklyReflection] {
        guard let db else { return [] }
        do {
            return try await db.fetchDrugReviewWeeklyReflections(start: start, end: end)
        } catch {
            handleOperationError("GLP-1 review error", error)
            return []
        }
    }

    func saveDrugReviewWeeklyReflection(_ reflection: Core.DrugReviewWeeklyReflection) async -> Bool {
        guard let db else { return false }
        do {
            try await db.upsertDrugReviewWeeklyReflection(reflection)
            invalidateDrugReview()
            return true
        } catch {
            handleOperationError("GLP-1 review error", error)
            return false
        }
    }

    func saveDailyLog(_ log: Core.DailyLog) async {
        await dailyLogStore.saveDailyLog(log)
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
        await dailyLogStore.updateEntry(
            entry,
            mealSlotID: mealSlotID,
            categoryID: categoryID,
            portion: portion,
            amountValue: amountValue,
            amountUnitID: amountUnitID,
            notes: notes,
            foodItemID: foodItemID
        )
    }

    func deleteEntry(_ entry: Core.DailyLogEntry) async {
        await dailyLogStore.deleteEntry(entry)
    }

    func logPortion(
        date: Date,
        mealSlotID: UUID,
        categoryID: UUID,
        portion: Core.Portion,
        amountValue: Double? = nil,
        amountUnitID: UUID? = nil,
        notes: String?,
        foodItemID: UUID? = nil,
        compositeGroupID: UUID? = nil,
        compositeFoodID: UUID? = nil,
        compositeFoodName: String? = nil
    ) async {
        await logPortions(
            date: date,
            requests: [
                LogPortionRequest(
                    mealSlotID: mealSlotID,
                    categoryID: categoryID,
                    portion: portion,
                    amountValue: amountValue,
                    amountUnitID: amountUnitID,
                    notes: notes,
                    foodItemID: foodItemID,
                    compositeGroupID: compositeGroupID,
                    compositeFoodID: compositeFoodID,
                    compositeFoodName: compositeFoodName
                )
            ]
        )
    }

    func logPortions(
        date: Date,
        requests: [LogPortionRequest]
    ) async {
        await dailyLogStore.logPortions(date: date, requests: requests)
    }

    func logFoodSelection(
        date: Date,
        mealSlotID: UUID,
        categoryID: UUID?,
        portion: Core.Portion,
        amountValue: Double? = nil,
        amountUnitID: UUID? = nil,
        notes: String?,
        foodItemID: UUID?
    ) async {
        await dailyLogStore.logFoodSelection(
            date: date,
            mealSlotID: mealSlotID,
            categoryID: categoryID,
            portion: portion,
            amountValue: amountValue,
            amountUnitID: amountUnitID,
            notes: notes,
            foodItemID: foodItemID
        )
    }

    static func resolvedMealSlotTimings(
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

    static func defaultMealSlotTimings(
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

    static func normalizedCategoryName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isLegacyCarbCategoryName(_ name: String) -> Bool {
        let normalized = normalizedCategoryName(name)
        return normalized == "starchy sides" || normalized == "starchy items"
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
        Core.FoodUnit(name: "Liter", symbol: "L", allowsDecimal: true, isEnabled: true, sortOrder: 2),
        Core.FoodUnit(name: "Piece", symbol: "pc", allowsDecimal: false, isEnabled: true, sortOrder: 3)
    ]

    static let categories: [Core.Category] = [
        Core.Category(name: "Unsweetened Drinks", unitName: "L", isEnabled: true, targetRule: .range(min: 1.0, max: 2.0), sortOrder: 0),
        Core.Category(name: "Vegetables", unitName: "portions", isEnabled: true, targetRule: .atLeast(3.0), sortOrder: 1),
        Core.Category(name: "Fruit", unitName: "portions", isEnabled: true, targetRule: .atLeast(2.0), sortOrder: 2),
        Core.Category(name: "Carb", unitName: "portions", isEnabled: true, targetRule: .exact(3.0), sortOrder: 3),
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
