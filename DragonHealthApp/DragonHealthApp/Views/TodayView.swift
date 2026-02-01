import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
#endif

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var dailyLog: DailyLog?
    @State private var totals: [UUID: Double] = [:]
    @State private var adherence: DailyAdherenceSummary?
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?
    @State private var showingDisplaySettings = false
    @AppStorage("today.categoryDisplayStyle") private var categoryDisplayStyleRaw: String = CategoryDisplayStyle.compactRings.rawValue
    @AppStorage("today.mealDisplayStyle") private var mealDisplayStyleRaw: String = MealDisplayStyle.miniCards.rawValue

    private let totalsCalculator = DailyTotalsCalculator()
    private let evaluator = DailyTotalEvaluator()
    private var categoryDisplayStyle: CategoryDisplayStyle {
        CategoryDisplayStyle(rawValue: categoryDisplayStyleRaw) ?? .compactRings
    }
    private var mealDisplayStyle: MealDisplayStyle {
        MealDisplayStyle(rawValue: mealDisplayStyleRaw) ?? .miniCards
    }
    private var categoryDisplayBinding: Binding<CategoryDisplayStyle> {
        Binding(
            get: { categoryDisplayStyle },
            set: { categoryDisplayStyleRaw = $0.rawValue }
        )
    }
    private var mealDisplayBinding: Binding<MealDisplayStyle> {
        Binding(
            get: { mealDisplayStyle },
            set: { mealDisplayStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodayHeaderView(date: store.currentDay, adherence: adherence)

                    let visibleCategories = store.categories.filter { $0.isEnabled }
                    if visibleCategories.isEmpty {
                        Text("No categories configured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        CategoryOverviewGrid(
                            categories: visibleCategories,
                            totals: totals,
                            style: categoryDisplayStyle
                        ) { category in
                            CategoryDayDetailView(category: category)
                        }
                    }

                    let mealEntries = dailyLog?.entries ?? []
                    TodayMealBreakdownView(
                        mealSlots: store.mealSlots,
                        entries: mealEntries,
                        categories: store.categories,
                        style: mealDisplayStyle,
                        onSelectMeal: { mealSlot in
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(mealSlot.id, anchor: .top)
                            }
                        }
                    )

                    TodayMealDetailsSection(
                        mealSlots: store.mealSlots,
                        entries: mealEntries,
                        categories: store.categories,
                        onEdit: { entry in
                            editingEntry = entry
                        },
                        onDelete: { entry in
                            Task {
                                await store.deleteEntry(entry)
                                await loadToday()
                            }
                        }
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingDisplaySettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Display settings")
                Button {
                    showingQuickAdd = true
                } label: {
                    Label("Quick Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingDisplaySettings) {
            TodayDisplaySettingsSheet(
                categorySelection: categoryDisplayBinding,
                mealSelection: mealDisplayBinding
            )
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: nil,
                contextDate: nil,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.logPortion(
                            date: Date(),
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadToday()
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
                        await loadToday()
                    }
                }
            )
        }
        .task(id: store.refreshToken) {
            await loadToday()
        }
    }

    private func loadToday() async {
        let log = await store.fetchDailyLog(for: Date())
        dailyLog = log
        let entries = log?.entries ?? []
        totals = totalsCalculator.totalsByCategory(entries: entries)
        adherence = evaluator.evaluate(categories: store.categories, totalsByCategoryID: totals)
    }
}

private struct TodayHeaderView: View {
    let date: Date
    let adherence: DailyAdherenceSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date, style: .date)
                .font(.headline)
            if let adherence {
                let metCount = adherence.categoryResults.filter { $0.targetMet }.count
                Text("\(metCount) of \(adherence.categoryResults.count) on track")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(adherence.allTargetsMet ? "All targets met" : "Targets in progress")
                    .font(.subheadline)
                    .foregroundStyle(adherence.allTargetsMet ? .green : .secondary)
            } else {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct CategoryOverviewGrid<Destination: View>: View {
    let categories: [Core.Category]
    let totals: [UUID: Double]
    let style: CategoryDisplayStyle
    let destination: (Core.Category) -> Destination
    private var columns: [GridItem] {
        switch style {
        case .compactRings:
            return [GridItem(.adaptive(minimum: 130), spacing: 12)]
        case .inlineLabel:
            return [GridItem(.adaptive(minimum: 200), spacing: 12)]
        case .capsuleRows:
            return [GridItem(.adaptive(minimum: 180), spacing: 12)]
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(categories) { category in
                let total = totals[category.id] ?? 0
                switch style {
                case .compactRings:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryRingTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                case .inlineLabel:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryInlineTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                case .capsuleRows:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryCapsuleTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CategoryDayDetailView: View {
    @EnvironmentObject private var store: AppStore
    let category: Core.Category
    @State private var dailyLog: DailyLog?
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?

    private var entries: [DailyLogEntry] {
        dailyLog?.entries.filter { $0.categoryID == category.id } ?? []
    }

    private var sortedEntries: [DailyLogEntry] {
        let order = Dictionary(uniqueKeysWithValues: store.mealSlots.map { ($0.id, $0.sortOrder) })
        return entries.sorted {
            let left = order[$0.mealSlotID] ?? 0
            let right = order[$1.mealSlotID] ?? 0
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                if sortedEntries.isEmpty {
                    Text("No items yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(sortedEntries) { entry in
                        CategoryDayEntryRow(
                            entry: entry,
                            category: category,
                            mealSlotName: mealSlotName(for: entry),
                            onEdit: { editingEntry = $0 },
                            onDelete: { entry in
                                Task {
                                    await store.deleteEntry(entry)
                                    await loadEntries()
                                }
                            }
                        )
                    }
                }
            } header: {
                Text(store.currentDay, style: .date)
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add entry")
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled && $0.id == category.id },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: category.id,
                contextDate: nil,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.logPortion(
                            date: Date(),
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadEntries()
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
                        await loadEntries()
                    }
                }
            )
        }
        .task(id: store.refreshToken) { await loadEntries() }
    }

    private func mealSlotName(for entry: DailyLogEntry) -> String {
        store.mealSlots.first(where: { $0.id == entry.mealSlotID })?.name ?? "Meal"
    }

    private func loadEntries() async {
        dailyLog = await store.fetchDailyLog(for: Date())
    }
}

private struct CategoryDayEntryRow: View {
    let entry: DailyLogEntry
    let category: Core.Category
    let mealSlotName: String
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(CategoryColorPalette.color(for: category))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(mealSlotName)
                    .font(.subheadline)
                if let note = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(entry.portion.value.cleanNumber) \(category.unitName)")
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Edit") {
                onEdit(entry)
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Edit") { onEdit(entry) }
            Button("Delete", role: .destructive) { onDelete(entry) }
        }
    }
}

private struct CategoryRingTile: View {
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let targetSummary = categoryTargetSummary(total: total, rule: category.targetRule)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ProgressRing(
                    progress: progress.ringProgress,
                    accent: accentColor,
                    iconName: iconName,
                    size: 40
                )
                Spacer()
                StatusBadge(status: progress.status)
            }
            Text(category.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(targetSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.name), \(progress.status.label), \(total.cleanNumber) \(category.unitName)")
    }
}

private struct CategoryInlineTile: View {
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let targetSummary = categoryTargetSummary(total: total, rule: category.targetRule)
        HStack(spacing: 10) {
            ProgressRing(progress: progress.ringProgress, accent: accentColor, iconName: iconName, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(targetSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: progress.status)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.name), \(progress.status.label), \(total.cleanNumber) \(category.unitName)")
    }
}

private struct CategoryCapsuleTile: View {
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let targetSummary = categoryTargetSummary(total: total, rule: category.targetRule)
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(accentColor)
            Text(category.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(targetSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            StatusBadge(status: progress.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(accentColor.opacity(0.12))
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.name), \(progress.status.label), \(total.cleanNumber) \(category.unitName)")
    }
}

private func categoryTargetSummary(total: Double, rule: TargetRule) -> String {
    let totalText = total.cleanNumber
    let targetText = targetTargetText(rule: rule)
    return "\(totalText)/\(targetText)"
}

private func targetTargetText(rule: TargetRule) -> String {
    switch rule {
    case .exact(let value):
        return value.cleanNumber
    case .atLeast(let value):
        return value.cleanNumber
    case .atMost(let value):
        return "<=\(value.cleanNumber)"
    case .range(let min, let max):
        return "\(min.cleanNumber)-\(max.cleanNumber)"
    }
}

private struct TodayMealBreakdownView: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let style: MealDisplayStyle
    let onSelectMeal: (MealSlot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Meal")
                .font(.headline)

            switch style {
            case .miniCards:
                MealOverviewGrid(
                    mealSlots: mealSlots,
                    entries: entries,
                    categories: categories,
                    onSelectMeal: onSelectMeal
                )
            case .stackedStrips:
                MealStripList(
                    mealSlots: mealSlots,
                    entries: entries,
                    categories: categories,
                    onSelectMeal: onSelectMeal
                )
            }
        }
    }
}

private struct MealOverviewGrid: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onSelectMeal: (MealSlot) -> Void
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        let enabledCategories = categories.filter { $0.isEnabled }
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                let total = slotEntries.reduce(0) { $0 + $1.portion.value }
                let loggedCategories = Set(slotEntries.filter { $0.portion.value > 0 }.map { $0.categoryID }).count
                MealOverviewCard(
                    mealSlot: slot,
                    total: total,
                    loggedCategories: loggedCategories,
                    totalCategories: enabledCategories.count,
                    onSelectMeal: { onSelectMeal(slot) }
                )
            }
        }
    }
}

private struct MealOverviewCard: View {
    let mealSlot: MealSlot
    let total: Double
    let loggedCategories: Int
    let totalCategories: Int
    let onSelectMeal: () -> Void
    private var iconName: String { MealIconPalette.iconName(for: mealSlot) }

    var body: some View {
        let progress = totalCategories > 0 ? Double(loggedCategories) / Double(totalCategories) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    onSelectMeal()
                } label: {
                    ProgressRing(
                        progress: progress,
                        accent: .blue,
                        iconName: iconName,
                        size: 40
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(mealSlot.name) details")
                Spacer()
            }
            Text(mealSlot.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(total.cleanNumber) total")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .contextMenu {
            Text(mealSlot.name)
            Text("Total: \(total.cleanNumber)")
            Text("Categories logged: \(loggedCategories)/\(totalCategories)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mealSlot.name), \(loggedCategories) of \(totalCategories) categories logged, \(total.cleanNumber) total")
    }
}

private struct MealStripList: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onSelectMeal: (MealSlot) -> Void

    var body: some View {
        let enabledCategories = categories.filter { $0.isEnabled }
        VStack(spacing: 8) {
            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                let total = slotEntries.reduce(0) { $0 + $1.portion.value }
                let loggedCategories = Set(slotEntries.filter { $0.portion.value > 0 }.map { $0.categoryID }).count
                MealStripRow(
                    mealSlot: slot,
                    total: total,
                    loggedCategories: loggedCategories,
                    totalCategories: enabledCategories.count,
                    onSelectMeal: { onSelectMeal(slot) }
                )
            }
        }
    }
}

private struct MealStripRow: View {
    let mealSlot: MealSlot
    let total: Double
    let loggedCategories: Int
    let totalCategories: Int
    let onSelectMeal: () -> Void
    private var iconName: String { MealIconPalette.iconName(for: mealSlot) }

    var body: some View {
        let progress = totalCategories > 0 ? Double(loggedCategories) / Double(totalCategories) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    onSelectMeal()
                } label: {
                    mealIcon
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(mealSlot.name) details")
                Text(mealSlot.name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(total.cleanNumber)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mealSlot.name), \(loggedCategories) of \(totalCategories) categories logged, \(total.cleanNumber) total")
    }

    @ViewBuilder
    private var mealIcon: some View {
        #if canImport(UIKit)
        if UIImage(systemName: iconName) != nil {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(.blue)
        } else {
            Text(iconName)
                .font(.system(size: 13))
        }
        #else
        Text(iconName)
            .font(.system(size: 13))
        #endif
    }
}

private struct TodayMealDetailsSection: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal Details")
                .font(.headline)

            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                MealSectionView(
                    mealSlot: slot,
                    entries: slotEntries,
                    categories: categories,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
                .id(slot.id)
            }
        }
    }
}

private struct MealSectionView: View {
    let mealSlot: MealSlot
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void
    private func categoryColor(for entry: DailyLogEntry) -> Color {
        if let category = categories.first(where: { $0.id == entry.categoryID }) {
            return CategoryColorPalette.color(for: category)
        }
        return CategoryColorPalette.fallback
    }

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

            if entries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    MealEntryRow(
                        entry: entry,
                        categoryName: categoryName(for: entry),
                        categoryColor: categoryColor(for: entry),
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
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
}

private struct MealEntryRow: View {
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

private struct ProgressRing: View {
    let progress: Double
    let accent: Color
    let iconName: String
    let size: CGFloat

    init(progress: Double, accent: Color, iconName: String, size: CGFloat = 46) {
        self.progress = progress
        self.accent = accent
        self.iconName = iconName
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
            iconView
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var iconView: some View {
        #if canImport(UIKit)
        if UIImage(systemName: iconName) != nil {
            Image(systemName: iconName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.primary)
        } else {
            Text(iconName)
                .font(.system(size: size * 0.5))
        }
        #else
        Text(iconName)
            .font(.system(size: size * 0.5))
        #endif
    }
}

private struct StatusBadge: View {
    let status: CategoryStatus

    var body: some View {
        Image(systemName: status.iconName)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(6)
            .background(
                Circle()
                    .fill(status.color.opacity(0.15))
            )
            .accessibilityHidden(true)
    }
}

private enum CategoryStatus: String {
    case met
    case onTrack
    case behind
    case over

    var label: String {
        switch self {
        case .met: return "Target met"
        case .onTrack: return "On track"
        case .behind: return "Behind"
        case .over: return "Over target"
        }
    }

    var iconName: String {
        switch self {
        case .met: return "checkmark.circle.fill"
        case .onTrack: return "circle.dashed"
        case .behind: return "exclamationmark.circle.fill"
        case .over: return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .met: return .green
        case .onTrack: return .orange
        case .behind: return .red
        case .over: return .red
        }
    }
}

private struct CategoryProgress {
    let status: CategoryStatus
    let ringProgress: Double

    static func make(category: Core.Category, total: Double, targetMet: Bool) -> CategoryProgress {
        let rule = category.targetRule
        var status: CategoryStatus
        var ringProgress: Double

        switch rule {
        case .exact(let target):
            if targetMet {
                status = .met
            } else if total > target + TargetRule.exactTolerance {
                status = .over
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            ringProgress = progress(current: total, target: target)
        case .atLeast(let target):
            if targetMet {
                status = .met
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            ringProgress = progress(current: total, target: target)
        case .atMost(let target):
            status = targetMet ? .met : .over
            ringProgress = progress(current: total, target: target)
        case .range(let minValue, let maxValue):
            if targetMet {
                status = .met
            } else if total > maxValue {
                status = .over
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            let target = minValue > 0 ? minValue : maxValue
            ringProgress = progress(current: total, target: target)
        }

        if targetMet {
            ringProgress = 1
        }

        return CategoryProgress(status: status, ringProgress: ringProgress)
    }

    private static func progress(current: Double, target: Double) -> Double {
        guard target > 0 else { return current > 0 ? 1 : 0 }
        return min(max(current / target, 0), 1)
    }
}

private enum CategoryDisplayStyle: String, CaseIterable, Identifiable {
    case compactRings
    case inlineLabel
    case capsuleRows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compactRings: return "Rings (A)"
        case .inlineLabel: return "Inline (B)"
        case .capsuleRows: return "Capsules (C)"
        }
    }
}

private enum MealDisplayStyle: String, CaseIterable, Identifiable {
    case miniCards
    case stackedStrips

    var id: String { rawValue }

    var label: String {
        switch self {
        case .miniCards: return "Cards (F)"
        case .stackedStrips: return "Strips (G)"
        }
    }
}

private struct TodayDisplaySettingsSheet: View {
    @Binding var categorySelection: CategoryDisplayStyle
    @Binding var mealSelection: MealDisplayStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Categories") {
                    Picker("Category style", selection: $categorySelection) {
                        ForEach(CategoryDisplayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Meals") {
                    Picker("Meal style", selection: $mealSelection) {
                        ForEach(MealDisplayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Display")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum EntryInputMode: String, CaseIterable, Identifiable {
    case portion
    case amount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portion: return "Portions"
        case .amount: return "Amount"
        }
    }
}

struct QuickAddSheet: View {
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]
    let preselectedCategoryID: UUID?
    let contextDate: Date?
    let onSave: (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID: UUID?
    @State private var selectedMealSlotID: UUID?
    @State private var selectedFoodID: UUID?
    @State private var portion: Double = 1.0
    @State private var inputMode: EntryInputMode = .portion
    @State private var amountText: String = ""
    @State private var isSyncing = false
    @State private var notes: String = ""
    private var selectedCategoryColor: Color {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID }) else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }
    private var availableFoodItems: [FoodItem] {
        let allowedCategoryIDs = Set(categories.map(\.id))
        return foodItems.filter { allowedCategoryIDs.contains($0.categoryID) }
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private var selectedFoodItem: FoodItem? {
        guard let selectedFoodID else { return nil }
        return availableFoodItems.first(where: { $0.id == selectedFoodID })
    }

    private var selectedUnit: Core.FoodUnit? {
        guard let unitID = selectedFoodItem?.unitID else { return nil }
        return units.first(where: { $0.id == unitID })
    }

    private var amountPerPortion: Double? {
        selectedFoodItem?.amountPerPortion
    }

    private var amountInputEnabled: Bool {
        amountPerPortion != nil && selectedUnit != nil
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard selectedMealSlotID != nil, selectedCategoryID != nil else { return false }
        if inputMode == .amount && amountInputEnabled {
            return parsedAmount != nil
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if let contextDate {
                    Section("Day") {
                        Text(contextDate, style: .date)
                            .font(.headline)
                    }
                }

                Section("Meal") {
                    Picker("Meal Slot", selection: $selectedMealSlotID) {
                        ForEach(mealSlots) { slot in
                            Text(slot.name).tag(Optional(slot.id))
                        }
                    }
                }

                Section("Food") {
                    if availableFoodItems.isEmpty {
                        Text("No foods in your library yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            FoodLibraryPicker(
                                items: availableFoodItems,
                                categories: categories,
                                units: units,
                                selectedCategoryID: selectedCategoryID,
                                selectedFoodID: $selectedFoodID
                            )
                        } label: {
                            if let selectedFoodID,
                               let item = availableFoodItems.first(where: { $0.id == selectedFoodID }) {
                                FoodItemRow(
                                    item: item,
                                    categoryName: categoryName(for: item.categoryID),
                                    unitSymbol: selectedUnit?.symbol,
                                    thumbnailSize: 34
                                )
                            } else {
                                Text("Choose a food")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(categories) { category in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(CategoryColorPalette.color(for: category))
                                    .frame(width: 10, height: 10)
                                Text(category.name)
                            }
                            .tag(Optional(category.id))
                        }
                    }
                }

                Section("Input Mode") {
                    Picker("Input Mode", selection: $inputMode) {
                        ForEach(EntryInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!amountInputEnabled)
                    if !amountInputEnabled {
                        Text("Select a food with a portion size to enter amounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Portion") {
                    PortionWheelControl(portion: $portion, accentColor: selectedCategoryColor)
                        .disabled(inputMode == .amount && amountInputEnabled)
                }

                Section("Amount") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(selectedUnit?.allowsDecimal == false ? .numberPad : .decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(inputMode == .portion || !amountInputEnabled)
                        if let unitSymbol = selectedUnit?.symbol {
                            Text(unitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let amountPerPortion, let unitSymbol = selectedUnit?.symbol {
                        Text("1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Quick Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let mealID = selectedMealSlotID,
                              let categoryID = selectedCategoryID,
                              let meal = mealSlots.first(where: { $0.id == mealID }),
                              let category = categories.first(where: { $0.id == categoryID }) else {
                            return
                        }
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let storedAmount = inputMode == .amount && amountInputEnabled ? roundedAmount(parsedAmount) : nil
                        let storedUnitID = storedAmount == nil ? nil : selectedUnit?.id
                        onSave(
                            meal,
                            category,
                            portion,
                            storedAmount,
                            storedUnitID,
                            trimmedNotes.isEmpty ? nil : trimmedNotes,
                            selectedFoodID
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedFoodID) { _, newValue in
                guard let foodID = newValue,
                      let item = availableFoodItems.first(where: { $0.id == foodID }) else {
                    amountText = ""
                    return
                }
                if categories.contains(where: { $0.id == item.categoryID }) {
                    selectedCategoryID = item.categoryID
                }
                portion = PortionWheelControl.roundedToIncrement(item.portionEquivalent)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onAppear {
                selectedMealSlotID = selectedMealSlotID ?? mealSlots.first?.id
                if selectedCategoryID == nil {
                    if let preselectedCategoryID,
                       categories.contains(where: { $0.id == preselectedCategoryID }) {
                        selectedCategoryID = preselectedCategoryID
                    } else {
                        selectedCategoryID = categories.first?.id
                    }
                }
                portion = PortionWheelControl.roundedToIncrement(portion)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onChange(of: portion) { _, _ in
                syncAmountFromPortion()
            }
            .onChange(of: amountText) { _, _ in
                guard inputMode == .amount else { return }
                syncPortionFromAmount()
            }
            .onChange(of: inputMode) { _, newValue in
                if newValue == .amount {
                    syncAmountFromPortion()
                }
            }
        }
    }

    private func roundedAmount(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return roundedAmountValue(value)
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if selectedUnit?.allowsDecimal == false {
            return value.rounded()
        }
        return Portion.roundToIncrement(value)
    }

    private func syncAmountFromPortion() {
        guard amountInputEnabled else {
            amountText = ""
            return
        }
        guard !isSyncing else { return }
        guard let amountPerPortion else { return }
        isSyncing = true
        let amount = roundedAmountValue(portion * amountPerPortion)
        amountText = amount.cleanNumber
        isSyncing = false
    }

    private func syncPortionFromAmount() {
        guard amountInputEnabled else { return }
        guard !isSyncing else { return }
        guard let amountPerPortion, let amount = parsedAmount else { return }
        isSyncing = true
        let normalizedAmount = roundedAmountValue(amount)
        let computed = Portion.roundToIncrement(normalizedAmount / amountPerPortion)
        let clamped = min(max(computed, 0.0), 6.0)
        portion = clamped
        let correctedAmount = roundedAmountValue(clamped * amountPerPortion)
        amountText = correctedAmount.cleanNumber
        isSyncing = false
    }
}

private struct FoodLibraryPicker: View {
    let items: [FoodItem]
    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let selectedCategoryID: UUID?
    @Binding var selectedFoodID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter: FoodLibraryFilter = .all

    var body: some View {
        List {
            Section("Filter") {
                Picker("Filter", selection: $filter) {
                    ForEach(FoodLibraryFilter.allCases) { option in
                        Text(option.label(selectedCategoryName: selectedCategoryName)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Library") {
                if items.isEmpty {
                    Text("No foods in your library yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        selectedFoodID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                            Spacer()
                            if selectedFoodID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if filteredItems.isEmpty {
                        Text("No foods match your search or filters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredItems) { item in
                            Button {
                                selectedFoodID = item.id
                                dismiss()
                            } label: {
                                FoodItemRow(
                                    item: item,
                                    categoryName: categoryName(for: item.categoryID),
                                    unitSymbol: unitSymbol(for: item.unitID),
                                    showsFavorite: false,
                                    thumbnailSize: 34
                                )
                                .overlay(alignment: .trailing) {
                                    if selectedFoodID == item.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Library Food")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search foods"
        )
    }

    private var selectedCategoryName: String? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id == selectedCategoryID })?.name
    }

    private var filteredItems: [FoodItem] {
        var results = items
        results = filter.apply(to: results, selectedCategoryID: selectedCategoryID)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return results }
        return results.filter { item in
            let category = categoryName(for: item.categoryID)
            let notes = item.notes ?? ""
            return item.name.localizedStandardContains(term)
                || category.localizedStandardContains(term)
                || notes.localizedStandardContains(term)
        }
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return units.first(where: { $0.id == id })?.symbol
    }
}

private enum FoodLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case selectedCategory

    var id: String { rawValue }

    func label(selectedCategoryName: String?) -> String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
        case .selectedCategory:
            return selectedCategoryName ?? "Category"
        }
    }

    func apply(to items: [FoodItem], selectedCategoryID: UUID?) -> [FoodItem] {
        switch self {
        case .all:
            return items
        case .favorites:
            return items.filter(\.isFavorite)
        case .selectedCategory:
            guard let selectedCategoryID else { return items }
            return items.filter { $0.categoryID == selectedCategoryID }
        }
    }
}

struct EntryEditSheet: View {
    let entry: DailyLogEntry
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]
    let onSave: (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID: UUID?
    @State private var selectedMealSlotID: UUID?
    @State private var selectedFoodID: UUID?
    @State private var portion: Double
    @State private var inputMode: EntryInputMode
    @State private var amountText: String
    @State private var isSyncing = false
    @State private var notes: String
    private var selectedCategoryColor: Color {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID }) else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }
    private var availableFoodItems: [FoodItem] {
        let allowedCategoryIDs = Set(categories.map(\.id))
        return foodItems.filter { allowedCategoryIDs.contains($0.categoryID) }
    }
    private var selectedFoodItem: FoodItem? {
        let foodID = selectedFoodID ?? entry.foodItemID
        guard let foodID else { return nil }
        return foodItems.first(where: { $0.id == foodID })
    }

    private var selectedUnit: Core.FoodUnit? {
        guard let unitID = selectedFoodItem?.unitID else { return nil }
        return units.first(where: { $0.id == unitID })
    }

    private var amountPerPortion: Double? {
        selectedFoodItem?.amountPerPortion
    }

    private var amountInputEnabled: Bool {
        amountPerPortion != nil && selectedUnit != nil
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard selectedMealSlotID != nil, selectedCategoryID != nil else { return false }
        if inputMode == .amount && amountInputEnabled {
            return parsedAmount != nil
        }
        return true
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    init(entry: DailyLogEntry, categories: [Core.Category], mealSlots: [MealSlot], foodItems: [FoodItem], units: [Core.FoodUnit], onSave: @escaping (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void) {
        self.entry = entry
        self.categories = categories
        self.mealSlots = mealSlots
        self.foodItems = foodItems
        self.units = units
        self.onSave = onSave
        _portion = State(initialValue: PortionWheelControl.roundedToIncrement(entry.portion.value))
        _inputMode = State(initialValue: entry.amountValue == nil ? .portion : .amount)
        _amountText = State(initialValue: entry.amountValue.map { $0.cleanNumber } ?? "")
        _selectedCategoryID = State(initialValue: entry.categoryID)
        _selectedMealSlotID = State(initialValue: entry.mealSlotID)
        _selectedFoodID = State(initialValue: entry.foodItemID)
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Meal Slot", selection: $selectedMealSlotID) {
                        ForEach(mealSlots) { slot in
                            Text(slot.name).tag(Optional(slot.id))
                        }
                    }
                }

                Section("Food") {
                    if availableFoodItems.isEmpty && selectedFoodItem == nil {
                        Text("No foods in your library yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            FoodLibraryPicker(
                                items: availableFoodItems,
                                categories: categories,
                                units: units,
                                selectedCategoryID: selectedCategoryID,
                                selectedFoodID: $selectedFoodID
                            )
                        } label: {
                            if let item = selectedFoodItem {
                                FoodItemRow(
                                    item: item,
                                    categoryName: categoryName(for: item.categoryID),
                                    unitSymbol: selectedUnit?.symbol,
                                    thumbnailSize: 34
                                )
                            } else {
                                Text("Choose a food")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(categories) { category in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(CategoryColorPalette.color(for: category))
                                    .frame(width: 10, height: 10)
                                Text(category.name)
                            }
                            .tag(Optional(category.id))
                        }
                    }
                }

                Section("Input Mode") {
                    Picker("Input Mode", selection: $inputMode) {
                        ForEach(EntryInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!amountInputEnabled)
                    if !amountInputEnabled {
                        Text("Select a food with a portion size to enter amounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Portion") {
                    PortionWheelControl(portion: $portion, accentColor: selectedCategoryColor)
                        .disabled(inputMode == .amount && amountInputEnabled)
                }

                Section("Amount") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(selectedUnit?.allowsDecimal == false ? .numberPad : .decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(inputMode == .portion || !amountInputEnabled)
                        if let unitSymbol = selectedUnit?.symbol {
                            Text(unitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let amountPerPortion, let unitSymbol = selectedUnit?.symbol {
                        Text("1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mealID = selectedMealSlotID,
                              let categoryID = selectedCategoryID,
                              let meal = mealSlots.first(where: { $0.id == mealID }),
                              let category = categories.first(where: { $0.id == categoryID }) else {
                            return
                        }
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let storedAmount = inputMode == .amount && amountInputEnabled ? roundedAmount(parsedAmount) : nil
                        let storedUnitID = storedAmount == nil ? nil : selectedUnit?.id
                        onSave(
                            meal,
                            category,
                            portion,
                            storedAmount,
                            storedUnitID,
                            trimmedNotes.isEmpty ? nil : trimmedNotes,
                            selectedFoodID
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedFoodID) { _, newValue in
                guard let foodID = newValue,
                      let item = availableFoodItems.first(where: { $0.id == foodID }) else {
                    amountText = ""
                    return
                }
                if categories.contains(where: { $0.id == item.categoryID }) {
                    selectedCategoryID = item.categoryID
                }
                portion = PortionWheelControl.roundedToIncrement(item.portionEquivalent)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onChange(of: portion) { _, _ in
                syncAmountFromPortion()
            }
            .onChange(of: amountText) { _, _ in
                guard inputMode == .amount else { return }
                syncPortionFromAmount()
            }
            .onChange(of: inputMode) { _, newValue in
                if newValue == .amount {
                    syncAmountFromPortion()
                }
            }
            .onAppear {
                if amountInputEnabled && entry.amountValue == nil {
                    syncAmountFromPortion()
                }
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
        }
    }

    private func roundedAmount(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return roundedAmountValue(value)
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if selectedUnit?.allowsDecimal == false {
            return value.rounded()
        }
        return Portion.roundToIncrement(value)
    }

    private func syncAmountFromPortion() {
        guard amountInputEnabled else {
            amountText = ""
            return
        }
        guard !isSyncing else { return }
        guard let amountPerPortion else { return }
        isSyncing = true
        let amount = roundedAmountValue(portion * amountPerPortion)
        amountText = amount.cleanNumber
        isSyncing = false
    }

    private func syncPortionFromAmount() {
        guard amountInputEnabled else { return }
        guard !isSyncing else { return }
        guard let amountPerPortion, let amount = parsedAmount else { return }
        isSyncing = true
        let normalizedAmount = roundedAmountValue(amount)
        let computed = Portion.roundToIncrement(normalizedAmount / amountPerPortion)
        let clamped = min(max(computed, 0.0), 6.0)
        portion = clamped
        let correctedAmount = roundedAmountValue(clamped * amountPerPortion)
        amountText = correctedAmount.cleanNumber
        isSyncing = false
    }
}

private struct PortionWheelControl: View {
    @Binding var portion: Double
    let accentColor: Color
    private let values: [Double] = {
        let steps = Int(6.0 / Portion.minimumIncrement)
        return (0...steps).map { Portion.roundToIncrement(Double($0) * Portion.minimumIncrement) }
    }()

    var body: some View {
        HStack(spacing: 16) {
            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Decrease by tenth portion")

            Picker("Portions", selection: $portion) {
                ForEach(values, id: \.self) { value in
                    Text(valueLabel(value))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 120, height: 120)
            .clipped()
            .accessibilityLabel("Portion picker")

            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Increase by tenth portion")
        }
    }

    private func decrement() {
        let next = max(0.0, portion - Portion.minimumIncrement)
        portion = Self.roundedToIncrement(next)
    }

    private func increment() {
        let next = min(6.0, portion + Portion.minimumIncrement)
        portion = Self.roundedToIncrement(next)
    }

    static func roundedToIncrement(_ value: Double) -> Double {
        Portion.roundToIncrement(value)
    }

    private func valueLabel(_ value: Double) -> String {
        value.cleanNumber
    }
}

enum CategoryColorPalette {
    static let fallback = Color(.systemGray5)

    static func color(for category: Core.Category) -> Color {
        color(forName: category.name)
    }

    static func color(forName name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("protein") {
            return Color(red: 0.81, green: 0.94, blue: 0.82)
        }
        if lower.contains("vegetable") {
            return Color(red: 0.60, green: 0.83, blue: 0.60)
        }
        if lower.contains("fruit") {
            return Color(red: 0.72, green: 0.89, blue: 0.90)
        }
        if lower.contains("starch") || lower.contains("grain") || lower.contains("side") {
            return Color(red: 0.91, green: 0.78, blue: 0.63)
        }
        if lower.contains("dairy") {
            return Color(red: 0.75, green: 0.84, blue: 0.96)
        }
        if lower.contains("oil") || lower.contains("fat") || lower.contains("nut") {
            return Color(red: 0.96, green: 0.77, blue: 0.60)
        }
        if lower.contains("treat") {
            return Color(red: 0.84, green: 0.76, blue: 0.96)
        }
        return fallback
    }
}

private enum CategoryIconPalette {
    static func iconName(for category: Core.Category) -> String {
        iconName(forName: category.name)
    }

    static func iconName(forName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("protein") {
            return "fish"
        }
        if lower.contains("vegetable") {
            return "leaf"
        }
        if lower.contains("fruit") {
            return "apple.logo"
        }
        if lower.contains("starch") || lower.contains("grain") || lower.contains("side") {
            return preferredSymbol(["bagel", "baguette", "fork.knife"], fallback: "fork.knife")
        }
        if lower.contains("dairy") {
            return preferredSymbol(["carton", "carton.fill", "cup.and.saucer"], fallback: "cup.and.saucer")
        }
        if lower.contains("oil") || lower.contains("fat") || lower.contains("nut") {
            return "drop.circle"
        }
        if lower.contains("treat") {
            return preferredSymbol(["candybar", "birthday.cake", "gift.fill"], fallback: "gift.fill")
        }
        return "circle"
    }

    private static func preferredSymbol(_ names: [String], fallback: String) -> String {
        #if canImport(UIKit)
        for name in names {
            if UIImage(systemName: name) != nil {
                return name
            }
        }
        #endif
        return fallback
    }
}

private enum MealIconPalette {
    static func iconName(for mealSlot: MealSlot) -> String {
        iconName(forName: mealSlot.name)
    }

    static func iconName(forName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("breakfast") {
            return "sunrise"
        }
        if lower.contains("lunch") {
            return "sun.max"
        }
        if lower.contains("dinner") {
            return "moon.stars"
        }
        if lower.contains("snack") {
            return "leaf"
        }
        if lower.contains("late") || lower.contains("evening") || lower.contains("midnight") {
            return "💀"
        }
        return "fork.knife"
    }
}
