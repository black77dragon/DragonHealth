import Foundation
import Core
import CoreDB

@MainActor
struct DailyLogStore {
    let db: SQLiteDatabase?
    let calendar: Calendar
    let dayBoundary: DayBoundary
    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let foodItems: [Core.FoodItem]
    let onPersist: (Date) -> Void
    let onError: (String) -> Void

    func fetchDailyLog(for date: Date) async -> Core.DailyLog? {
        let day = normalizedDay(for: date)
        return await fetchDailyLogForDay(day)
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
                foodItemID: entry.foodItemID,
                compositeGroupID: entry.compositeGroupID,
                compositeFoodID: entry.compositeFoodID,
                compositeFoodName: entry.compositeFoodName
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
        let resolvedPortion = resolvedPortionForLogging(
            categoryID: categoryID,
            portion: portion,
            amountValue: amountValue,
            amountUnitID: amountUnitID
        )
        log.entries[index] = Core.DailyLogEntry(
            id: entry.id,
            date: day,
            mealSlotID: mealSlotID,
            categoryID: categoryID,
            portion: resolvedPortion,
            amountValue: amountValue,
            amountUnitID: amountUnitID,
            notes: normalizedNotes(notes),
            foodItemID: foodItemID,
            compositeGroupID: entry.compositeGroupID,
            compositeFoodID: entry.compositeFoodID,
            compositeFoodName: entry.compositeFoodName
        )
        await persistDailyLog(log)
    }

    func deleteEntry(_ entry: Core.DailyLogEntry) async {
        let day = normalizedDay(for: entry.date, treatStartOfDayAsDayOnly: true)
        guard var log = await fetchDailyLogForDay(day) else { return }
        log.entries.removeAll { $0.id == entry.id }
        await persistDailyLog(log)
    }

    func logPortions(
        date: Date,
        requests: [AppStore.LogPortionRequest]
    ) async {
        let day = normalizedDay(for: date)
        await appendLogRequests(requests, for: day)
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
        let selectedFood = foodItemID.flatMap { id in
            foodItems.first(where: { $0.id == id })
        }
        if let selectedFood, selectedFood.kind.isComposite {
            await logCompositeFood(
                selectedFood,
                date: date,
                mealSlotID: mealSlotID,
                basePortion: portion,
                notes: notes
            )
            return
        }

        let resolvedCategoryID = categoryID ?? selectedFood?.categoryID
        guard let resolvedCategoryID else { return }
        await logPortions(
            date: date,
            requests: [
                AppStore.LogPortionRequest(
                    mealSlotID: mealSlotID,
                    categoryID: resolvedCategoryID,
                    portion: portion,
                    amountValue: amountValue,
                    amountUnitID: amountUnitID,
                    notes: notes,
                    foodItemID: foodItemID
                )
            ]
        )
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

    private func resolvedPortionForLogging(
        categoryID: UUID,
        portion: Core.Portion,
        amountValue: Double?,
        amountUnitID: UUID?
    ) -> Core.Portion {
        guard let category = categories.first(where: { $0.id == categoryID }),
              DrinkRules.isDrinkCategory(category),
              let amountValue,
              amountValue.isFinite,
              amountValue >= 0 else {
            return portion
        }

        let liters = DrinkRules.liters(from: amountValue, unitID: amountUnitID, units: units)
        let resolvedLiters: Double
        if let liters {
            resolvedLiters = liters
        } else if amountUnitID == nil {
            resolvedLiters = amountValue
        } else {
            return portion
        }

        let rounded = DrinkRules.roundedLiters(resolvedLiters)
        return Core.Portion(rounded, increment: Portion.drinkIncrement)
    }

    private func logCompositeFood(
        _ composite: Core.FoodItem,
        date: Date,
        mealSlotID: UUID,
        basePortion: Core.Portion,
        notes: String?
    ) async {
        let resolvedComponents = composite.compositeComponents.compactMap { component -> (Core.FoodItem, Double)? in
            guard component.portionMultiplier > 0 else { return nil }
            guard let item = foodItems.first(where: { $0.id == component.foodItemID && !$0.kind.isComposite }) else {
                return nil
            }
            return (item, component.portionMultiplier)
        }
        guard !resolvedComponents.isEmpty else { return }

        let groupID = UUID()
        let requests = resolvedComponents.enumerated().map { index, component in
            AppStore.LogPortionRequest(
                mealSlotID: mealSlotID,
                categoryID: component.0.categoryID,
                portion: Core.Portion(basePortion.value * component.1),
                notes: index == 0 ? notes : nil,
                foodItemID: component.0.id,
                compositeGroupID: groupID,
                compositeFoodID: composite.id,
                compositeFoodName: composite.name
            )
        }
        await logPortions(date: date, requests: requests)
    }

    private func appendLogRequests(
        _ requests: [AppStore.LogPortionRequest],
        for day: Date
    ) async {
        guard !requests.isEmpty else { return }

        var log = await fetchDailyLogForDay(day) ?? Core.DailyLog(date: day, entries: [])
        for request in requests {
            let resolvedPortion = resolvedPortionForLogging(
                categoryID: request.categoryID,
                portion: request.portion,
                amountValue: request.amountValue,
                amountUnitID: request.amountUnitID
            )
            log.entries.append(
                Core.DailyLogEntry(
                    date: day,
                    mealSlotID: request.mealSlotID,
                    categoryID: request.categoryID,
                    portion: resolvedPortion,
                    amountValue: request.amountValue,
                    amountUnitID: request.amountUnitID,
                    notes: normalizedNotes(request.notes),
                    foodItemID: request.foodItemID,
                    compositeGroupID: request.compositeGroupID,
                    compositeFoodID: request.compositeFoodID,
                    compositeFoodName: request.compositeFoodName
                )
            )
        }
        await persistDailyLog(log)
    }

    private func fetchDailyLogForDay(_ day: Date) async -> Core.DailyLog? {
        guard let db else { return nil }
        do {
            return try await db.fetchDailyLog(for: day)
        } catch {
            onError("Log error: \(error.localizedDescription)")
            return nil
        }
    }

    private func persistDailyLog(_ log: Core.DailyLog) async {
        guard let db else { return }
        do {
            try await db.saveDailyLog(log)
            onPersist(log.date)
        } catch {
            onError("Log error: \(error.localizedDescription)")
        }
    }
}
