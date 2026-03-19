import Combine
import Core
import Foundation
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var dailyLog: DailyLog?
    @Published private(set) var totals: [UUID: Double] = [:]
    @Published private(set) var adherence: DailyAdherenceSummary?
    @Published private(set) var scoreSummary: DailyScoreSummary?
    @Published private(set) var visibleCategories: [Core.Category] = []
    @Published private(set) var currentMealSlotID: UUID?
    @Published private(set) var currentMealSlotName: String?
    @Published private(set) var currentDay: Date = Date()
    @Published var showingQuickAdd = false
    @Published var showingPhotoLog = false
    @Published var photoLogStartsWithCamera = false
    @Published var quickAddPrefillCategoryID: UUID?
    @Published var quickAddPrefillMealSlotID: UUID?
    @Published var editingEntry: DailyLogEntry?
    @Published var viewingEntry: DailyLogEntry?
    @Published private(set) var saveConfirmationMessage: String?

    private let totalsCalculator = DailyTotalsCalculator()
    private let evaluator = DailyTotalEvaluator()
    private let scoreEvaluator = DailyScoreEvaluator()
    private var saveConfirmationTask: Task<Void, Never>?

    var mealEntries: [DailyLogEntry] {
        dailyLog?.entries ?? []
    }

    var canExplainScore: Bool {
        scoreSummary != nil
    }

    deinit {
        saveConfirmationTask?.cancel()
    }

    func loadToday(store: AppStore) async {
        currentDay = store.currentDay
        visibleCategories = store.categories.filter { $0.isEnabled }
        currentMealSlotID = store.currentMealSlotID()
        currentMealSlotName = currentMealSlotID.flatMap { slotID in
            store.mealSlots.first(where: { $0.id == slotID })?.name
        }
        let log = await store.fetchDailyLog(for: Date())
        dailyLog = log
        let entries = log?.entries ?? []
        let totals = totalsCalculator.totalsByCategory(entries: entries)
        self.totals = totals
        adherence = evaluator.evaluate(categories: store.categories, totalsByCategoryID: totals)
        scoreSummary = scoreEvaluator.evaluate(
            categories: store.categories,
            totalsByCategoryID: totals,
            profilesByCategoryID: store.scoreProfiles,
            compensationRules: store.compensationRules
        )
    }

    func openQuickAdd(categoryID: UUID? = nil, mealSlotID: UUID? = nil) {
        quickAddPrefillCategoryID = categoryID
        quickAddPrefillMealSlotID = mealSlotID ?? currentMealSlotID
        showingQuickAdd = true
    }

    func clearQuickAddPrefill() {
        quickAddPrefillCategoryID = nil
        quickAddPrefillMealSlotID = nil
    }

    func openPhotoLog(startWithCamera: Bool = false) {
        photoLogStartsWithCamera = startWithCamera
        showingPhotoLog = true
    }

    func handlePhotoLogPresentationChange(isPresented: Bool) {
        if !isPresented {
            photoLogStartsWithCamera = false
        }
    }

    func logQuickAmount(
        store: AppStore,
        categoryID: UUID,
        amount: Double
    ) async {
        guard amount > 0 else { return }
        guard let category = store.categories.first(where: { $0.id == categoryID }) else { return }
        guard let mealSlotID = currentMealSlotID ?? store.mealSlots.first?.id else { return }

        let portion = Portion(amount, increment: DrinkRules.portionIncrement(for: category))
        await store.logPortion(
            date: Date(),
            mealSlotID: mealSlotID,
            categoryID: categoryID,
            portion: portion,
            notes: nil
        )
        await loadToday(store: store)
    }

    func deleteEntry(store: AppStore, _ entry: DailyLogEntry) async {
        await store.deleteEntry(entry)
        await loadToday(store: store)
    }

    func saveQuickAdd(
        store: AppStore,
        mealSlot: MealSlot,
        category: Core.Category,
        portion: Double,
        amountValue: Double?,
        amountUnitID: UUID?,
        notes: String?,
        foodItemID: UUID?
    ) async {
        await store.logFoodSelection(
            date: Date(),
            mealSlotID: mealSlot.id,
            categoryID: category.id,
            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
            amountValue: amountValue,
            amountUnitID: amountUnitID,
            notes: notes,
            foodItemID: foodItemID
        )
        await loadToday(store: store)
    }

    func savePhotoLog(
        store: AppStore,
        mealSlot: MealSlot,
        items: [MealPhotoDraftItem]
    ) async {
        let now = Date()
        let requests = items.compactMap { item -> AppStore.LogPortionRequest? in
            guard let categoryID = item.categoryID,
                  let portion = item.portion else { return nil }
            let category = store.categories.first(where: { $0.id == categoryID })
            let increment = DrinkRules.portionIncrement(for: category)
            let trimmedNotes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let notes = trimmedNotes.isEmpty && item.matchedFoodID == nil ? item.foodText : trimmedNotes

            return AppStore.LogPortionRequest(
                mealSlotID: mealSlot.id,
                categoryID: categoryID,
                portion: Portion(portion, increment: increment),
                amountValue: item.amountValue,
                amountUnitID: item.amountUnitID,
                notes: notes.isEmpty ? nil : notes,
                foodItemID: item.matchedFoodID
            )
        }
        await store.logPortions(date: now, requests: requests)
        await loadToday(store: store)
        if !requests.isEmpty {
            showSaveConfirmation("data is successfully stored")
        }
    }

    func saveEditedEntry(
        store: AppStore,
        entry: DailyLogEntry,
        mealSlot: MealSlot,
        category: Core.Category,
        portion: Double,
        amountValue: Double?,
        amountUnitID: UUID?,
        notes: String?,
        foodItemID: UUID?
    ) async {
        await store.updateEntry(
            entry,
            mealSlotID: mealSlot.id,
            categoryID: category.id,
            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
            amountValue: amountValue,
            amountUnitID: amountUnitID,
            notes: notes,
            foodItemID: foodItemID
        )
        await loadToday(store: store)
    }

    func showSaveConfirmation(_ message: String) {
        saveConfirmationMessage = message
        saveConfirmationTask?.cancel()
        saveConfirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                self.saveConfirmationMessage = nil
            }
        }
    }
}
