import SwiftUI
import Core
#if canImport(Charts)
import Charts
#endif

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date()
    @State private var dailyLog: DailyLog?
    @State private var totals: [UUID: Double] = [:]
    @State private var adherence: DailyAdherenceSummary?
    @State private var scoreSummary: DailyScoreSummary?
    @State private var calendarIndicators: [String: HistoryDayIndicator] = [:]
    @State private var scoreHistoryPoints: [ScoreHistoryPoint] = []
    @State private var visibleMonthDate = Date()
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?
    @AppStorage("history.scoreTimeFrame") private var scoreTimeFrameRaw: String = HistoryScoreTimeFrame.month.rawValue

    private let totalsCalculator = DailyTotalsCalculator()
    private let evaluator = DailyTotalEvaluator()
    private let scoreEvaluator = DailyScoreEvaluator()

    private var scoreTimeFrame: HistoryScoreTimeFrame {
        HistoryScoreTimeFrame(rawValue: scoreTimeFrameRaw) ?? .month
    }

    private var scoreTimeFrameBinding: Binding<HistoryScoreTimeFrame> {
        Binding(
            get: { HistoryScoreTimeFrame(rawValue: scoreTimeFrameRaw) ?? .month },
            set: { scoreTimeFrameRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let entries = dailyLog?.entries ?? []

                HistoryCalendarView(
                    calendar: store.appCalendar,
                    currentDay: store.currentDay,
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
                HistoryDailyScoreCard(
                    date: selectedDate,
                    adherence: adherence,
                    scoreSummary: scoreSummary
                )
                HistoryCalendarLegend()
                HistoryScoreHistorySection(
                    timeFrame: scoreTimeFrameBinding,
                    points: scoreHistoryPoints
                )

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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .glassLabel(.icon)
                }
                .buttonStyle(.plain)
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
                preselectedMealSlotID: store.currentMealSlotID(),
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
        .task(id: scoreTimeFrameRaw) { await loadScoreHistory() }
        .task(id: store.refreshToken) {
            await loadSelectedDay()
            await loadCalendarIndicators(for: visibleMonthDate)
            await loadScoreHistory()
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
        scoreSummary = scoreEvaluator.evaluate(
            categories: store.categories,
            totalsByCategoryID: totals,
            profilesByCategoryID: store.scoreProfiles,
            compensationRules: store.compensationRules
        )
    }

    private func loadScoreHistory() async {
        let calendar = store.appCalendar
        let referenceDate = store.currentDay
        let startDate = scoreTimeFrame.startDate(referenceDate: referenceDate, calendar: calendar) ?? Date.distantPast
        let entries = await store.fetchScoreHistory(start: startDate, end: referenceDate)
        scoreHistoryPoints = entries.map { ScoreHistoryPoint(date: $0.date, value: $0.score) }
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

private struct HistoryDailyScoreCard: View {
    let date: Date
    let adherence: DailyAdherenceSummary?
    let scoreSummary: DailyScoreSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Score")
                        .font(.headline)
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let scoreSummary {
                    ScoreBadge(score: scoreSummary.overallScore)
                } else {
                    Text("--")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let adherence {
                HStack {
                    Text(adherence.allTargetsMet ? "On Target" : "Off Target")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: adherence.allTargetsMet ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(adherence.allTargetsMet ? .green : .orange)
                }
                Text("\(adherence.categoryResults.filter { $0.targetMet }.count) of \(adherence.categoryResults.count) categories met")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No score yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            legendItem(color: ScoreColor.color(for: 100), label: "High score")
            legendItem(color: ScoreColor.color(for: 0), label: "Low score")
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

private struct HistoryScoreHistorySection: View {
    @Binding var timeFrame: HistoryScoreTimeFrame
    let points: [ScoreHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score History")
                .font(.headline)
            HistoryTimeFramePicker(timeFrame: $timeFrame)
            ScoreHistoryChartCard(points: points)
        }
    }
}

private struct HistoryTimeFramePicker: View {
    @Binding var timeFrame: HistoryScoreTimeFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time Frame")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Time Frame", selection: $timeFrame) {
                ForEach(HistoryScoreTimeFrame.allCases) { frame in
                    Text(frame.shortLabel)
                        .accessibilityLabel(frame.fullLabel)
                        .tag(frame)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private enum HistoryScoreTimeFrame: String, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case sixMonths
    case all

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .all: return "All"
        }
    }

    var fullLabel: String {
        switch self {
        case .week: return "1 week"
        case .month: return "1 month"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .all: return "All time"
        }
    }

    func startDate(referenceDate: Date, calendar: Calendar) -> Date? {
        guard let rangeComponent else { return nil }
        return calendar.date(
            byAdding: rangeComponent.0,
            value: rangeComponent.1,
            to: referenceDate
        )
    }

    private var rangeComponent: (Calendar.Component, Int)? {
        switch self {
        case .week: return (.day, -6)
        case .month: return (.month, -1)
        case .threeMonths: return (.month, -3)
        case .sixMonths: return (.month, -6)
        case .all: return nil
        }
    }
}

private struct ScoreHistoryPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

private struct ScoreHistoryChartCard: View {
    let points: [ScoreHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Score")
                    .font(.headline)
                Spacer()
                Text(points.last.map { "\(Int($0.value.rounded()))" } ?? "--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("No score history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                #if canImport(Charts)
                if #available(iOS 16.0, *) {
                    scoreChart()
                } else {
                    Text("Charts require iOS 16 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #else
                Text("Charts are unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func scoreChart() -> some View {
        let tint = ScoreColor.color(for: points.last?.value ?? 0)
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(tint)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 160)
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
