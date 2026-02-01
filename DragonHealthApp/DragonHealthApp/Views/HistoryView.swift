import SwiftUI
import Core

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date()
    @State private var dailyLog: DailyLog?
    @State private var totals: [UUID: Double] = [:]
    @State private var adherence: DailyAdherenceSummary?
    @State private var calendarIndicators: [String: HistoryDayIndicator] = [:]
    @State private var visibleMonthDate = Date()
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?

    private let totalsCalculator = DailyTotalsCalculator()
    private let evaluator = DailyTotalEvaluator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let entries = dailyLog?.entries ?? []

                HistoryCalendarView(
                    calendar: store.appCalendar,
                    selectedDate: $selectedDate,
                    indicators: calendarIndicators,
                    onVisibleMonthChanged: { newMonthDate in
                        let calendar = store.appCalendar
                        let newComponents = calendar.dateComponents([.year, .month], from: newMonthDate)
                        let currentComponents = calendar.dateComponents([.year, .month], from: visibleMonthDate)
                        guard newComponents != currentComponents else { return }
                        visibleMonthDate = newMonthDate
                    }
                )
                HistoryCalendarLegend()

                if let adherence {
                    HistorySummaryCard(adherence: adherence)
                }

                if !entries.isEmpty {
                    HistoryEntriesView(
                        mealSlots: store.mealSlots,
                        entries: entries,
                        categories: store.categories,
                        onEdit: { entry in editingEntry = entry },
                        onDelete: { entry in
                            Task {
                                await store.deleteEntry(entry)
                                await loadSelectedDay()
                            }
                        }
                    )
                } else {
                    Text("No entries for this day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.categories.filter { $0.isEnabled }) { category in
                    HistoryCategoryRow(
                        category: category,
                        total: totals[category.id] ?? 0,
                        targetMet: adherence?.categoryResults.first(where: { $0.categoryID == category.id })?.targetMet ?? false
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add entry")
            }
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: nil,
                contextDate: selectedDate,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        let calendar = store.appCalendar
                        let reference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                        await store.logPortion(
                            date: reference,
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadSelectedDay()
                    }
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.updateEntry(
                            entry,
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadSelectedDay()
                    }
                }
            )
        }
        .task { visibleMonthDate = selectedDate }
        .task(id: selectedDate) { await loadSelectedDay() }
        .task(id: visibleMonthDate) { await loadCalendarIndicators(for: visibleMonthDate) }
        .task(id: store.refreshToken) {
            await loadSelectedDay()
            await loadCalendarIndicators(for: visibleMonthDate)
        }
    }

    private func loadSelectedDay() async {
        let calendar = store.appCalendar
        let reference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let day = store.dayBoundary.dayStart(for: reference)
        selectedDate = day
        let log = await store.fetchDailyLog(for: reference)
        dailyLog = log
        let entries = log?.entries ?? []
        totals = totalsCalculator.totalsByCategory(entries: entries)
        adherence = evaluator.evaluate(categories: store.categories, totalsByCategoryID: totals)
    }

    private func loadCalendarIndicators(for referenceDate: Date) async {
        let range = calendarIndicatorRange(for: referenceDate)
        calendarIndicators = await store.fetchHistoryIndicators(start: range.start, end: range.end)
    }

    private func calendarIndicatorRange(for referenceDate: Date) -> DateInterval {
        let calendar = store.appCalendar
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            let start = calendar.startOfDay(for: referenceDate)
            return DateInterval(start: start, end: start)
        }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end
        let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let rangeEnd = calendar.date(byAdding: .day, value: 7, to: monthEnd) ?? monthEnd
        return DateInterval(start: rangeStart, end: rangeEnd)
    }
}

private struct HistorySummaryCard: View {
    let adherence: DailyAdherenceSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(adherence.allTargetsMet ? "On Target" : "Off Target")
                    .font(.headline)
                Text("\(adherence.categoryResults.filter { $0.targetMet }.count) of \(adherence.categoryResults.count) categories met")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: adherence.allTargetsMet ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(adherence.allTargetsMet ? .green : .orange)
                .font(.title2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HistoryCalendarLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Target met")
            legendItem(color: .red, label: "Target missed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

private struct HistoryCategoryRow: View {
    let category: Core.Category
    let total: Double
    let targetMet: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.subheadline)
                Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(total.cleanNumber) \(category.unitName)")
                    .font(.subheadline)
                Image(systemName: targetMet ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(targetMet ? .green : .secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct HistoryEntriesView: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entries")
                .font(.headline)

            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                if !slotEntries.isEmpty {
                    HistoryMealSectionView(
                        mealSlot: slot,
                        entries: slotEntries,
                        categories: categories,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
            }
        }
    }
}

private struct HistoryMealSectionView: View {
    let mealSlot: MealSlot
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mealSlot.name)
                    .font(.subheadline)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.portion.value }.cleanNumber) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(entries) { entry in
                HistoryEntryRow(
                    entry: entry,
                    categoryName: categoryName(for: entry),
                    categoryColor: categoryColor(for: entry),
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func categoryName(for entry: DailyLogEntry) -> String {
        categories.first(where: { $0.id == entry.categoryID })?.name ?? "Category"
    }

    private func categoryColor(for entry: DailyLogEntry) -> Color {
        guard let category = categories.first(where: { $0.id == entry.categoryID }) else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }
}

private struct HistoryEntryRow: View {
    let entry: DailyLogEntry
    let categoryName: String
    let categoryColor: Color
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName)
                    .font(.subheadline)
                if let note = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.portion.value.cleanNumber)
                .font(.subheadline)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
            Button("Edit") {
                onEdit(entry)
            }
        }
        .contextMenu {
            Button("Edit") { onEdit(entry) }
            Button("Delete", role: .destructive) { onDelete(entry) }
        }
    }
}
