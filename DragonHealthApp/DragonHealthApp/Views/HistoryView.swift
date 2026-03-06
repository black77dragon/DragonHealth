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
    @State private var weeklyReflection: WeeklyReflection?
    @State private var visibleMonthDate = Date()
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?
    @AppStorage("history.scoreTimeFrame") private var scoreTimeFrameRaw: String = HistoryScoreTimeFrame.month.rawValue
    @AppStorage(NightGuardTracking.recordsStorageKey) private var nightGuardRecordsJSON: String = ""

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

    private var nightGuardStatusesByDayKey: [String: NightGuardStatus] {
        NightGuardTracking.statusByDayKey(from: nightGuardRecordsJSON)
    }

    private var nightGuardHistoryPoints: [NightGuardHistoryPoint] {
        let calendar = store.appCalendar
        let referenceDate = store.currentDay
        let startDate = scoreTimeFrame.startDate(referenceDate: referenceDate, calendar: calendar) ?? Date.distantPast
        let records = NightGuardTracking.decodeRecords(from: nightGuardRecordsJSON)
        let latestByDay = Dictionary(grouping: records, by: \.dayKey).compactMapValues { dayRecords in
            dayRecords.max(by: { $0.updatedAt < $1.updatedAt })
        }
        return latestByDay.values
            .compactMap { record in
                guard record.status != .pending,
                      let date = DayKeyParser.date(from: record.dayKey, timeZone: calendar.timeZone),
                      date >= startDate,
                      date <= referenceDate else {
                    return nil
                }
                return NightGuardHistoryPoint(date: date, didKeepRule: record.status.isCompliant)
            }
            .sorted(by: { $0.date < $1.date })
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
                    nightGuardStatusesByDayKey: nightGuardStatusesByDayKey,
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
                HistoryNightGuardHistorySection(points: nightGuardHistoryPoints)
                if let weeklyReflection {
                    HistoryWeeklyReflectionCard(reflection: weeklyReflection)
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
                            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
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
                            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
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
        await loadWeeklyReflection()
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

    private func loadWeeklyReflection() async {
        let calendar = store.appCalendar
        let endDay = store.dayBoundary.dayStart(for: selectedDate, calendar: calendar)
        guard let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) else {
            weeklyReflection = nil
            return
        }

        let enabledCategories = store.categories.filter { $0.isEnabled }
        var metCounts: [UUID: Int] = [:]
        var missCounts: [UUID: Int] = [:]
        var scores: [Double] = []

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let reference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            let log = await store.fetchDailyLog(for: reference)
            let entries = log?.entries ?? []
            let totalsByCategory = totalsCalculator.totalsByCategory(entries: entries)
            let adherence = evaluator.evaluate(categories: store.categories, totalsByCategoryID: totalsByCategory)
            let score = scoreEvaluator.evaluate(
                categories: store.categories,
                totalsByCategoryID: totalsByCategory,
                profilesByCategoryID: store.scoreProfiles,
                compensationRules: store.compensationRules
            )
            scores.append(score.overallScore)
            for result in adherence.categoryResults {
                if result.targetMet {
                    metCounts[result.categoryID, default: 0] += 1
                } else {
                    missCounts[result.categoryID, default: 0] += 1
                }
            }
        }

        let wins = enabledCategories
            .map { category in
                (category, metCounts[category.id, default: 0])
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.sortOrder < rhs.0.sortOrder
            }
            .prefix(3)
            .map { item in
                "\(item.0.name): \(item.1)/7 days on target"
            }

        let frictions = enabledCategories
            .map { category in
                (category, missCounts[category.id, default: 0])
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.sortOrder < rhs.0.sortOrder
            }
            .prefix(2)
            .map { item in
                "\(item.0.name): missed \(item.1)/7 days"
            }

        let scoreDelta: Double? = {
            guard let first = scores.first, let last = scores.last else { return nil }
            return last - first
        }()

        let adjustment: String = {
            guard let topFriction = enabledCategories
                .map({ ($0, missCounts[$0.id, default: 0]) })
                .max(by: { $0.1 < $1.1 }),
                  topFriction.1 > 0 else {
                return "Keep the current routine and repeat your strongest meal pattern."
            }
            if DrinkRules.isDrinkCategory(topFriction.0) {
                return "Set a fixed hydration checkpoint in the morning and one in the afternoon."
            }
            if topFriction.0.name.lowercased().contains("sport") {
                return "Anchor one short activity block right after your most stable meal."
            }
            return "Add one pre-committed \(topFriction.0.name.lowercased()) entry in your earliest meal window."
        }()

        weeklyReflection = WeeklyReflection(
            rangeText: WeeklyReflection.rangeText(start: startDay, end: endDay, calendar: calendar),
            wins: wins,
            frictions: frictions,
            adjustment: adjustment,
            scoreDelta: scoreDelta
        )
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
            symbolLegendItem(symbol: "moon.stars.fill", color: .green, label: "Night Guard kept")
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

    private func symbolLegendItem(symbol: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
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

private struct HistoryNightGuardHistorySection: View {
    let points: [NightGuardHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Guard History")
                .font(.headline)
            NightGuardHistoryChartCard(points: points)
        }
    }
}

private struct HistoryWeeklyReflectionCard: View {
    let reflection: WeeklyReflection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekly Reflection")
                    .font(.headline)
                Spacer()
                Text(reflection.rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let scoreDelta = reflection.scoreDelta {
                Text(scoreDelta >= 0 ? "Score trend +\(scoreDelta.cleanNumber)" : "Score trend \(scoreDelta.cleanNumber)")
                    .font(.subheadline)
                    .foregroundStyle(scoreDelta >= 0 ? .green : .orange)
            }

            reflectionSection(title: "3 wins", lines: reflection.wins, emptyState: "No wins logged yet.")
            reflectionSection(title: "2 friction points", lines: reflection.frictions, emptyState: "No major friction detected.")

            VStack(alignment: .leading, spacing: 4) {
                Text("1 adjustment")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reflection.adjustment)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func reflectionSection(title: String, lines: [String], emptyState: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if lines.isEmpty {
                Text(emptyState)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct WeeklyReflection {
    let rangeText: String
    let wins: [String]
    let frictions: [String]
    let adjustment: String
    let scoreDelta: Double?

    static func rangeText(start: Date, end: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
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

private struct NightGuardHistoryPoint: Identifiable {
    let date: Date
    let didKeepRule: Bool

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

private struct NightGuardHistoryChartCard: View {
    let points: [NightGuardHistoryPoint]

    private var complianceText: String {
        guard !points.isEmpty else { return "No logged Night Guard events in this time frame." }
        let kept = points.filter(\.didKeepRule).count
        let rate = Int((Double(kept) / Double(points.count) * 100).rounded())
        return "\(rate)% kept over \(points.count) logged nights"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Compliance")
                    .font(.headline)
                Spacer()
                Text(complianceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("Mark nights as respected, violated, or protein-exception in Night Guard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                #if canImport(Charts)
                if #available(iOS 16.0, *) {
                    complianceChart()
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
    private func complianceChart() -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Kept", point.didKeepRule ? 1.0 : 0.0)
                )
                .foregroundStyle(point.didKeepRule ? Color.green : Color.red.opacity(0.7))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .frame(height: 120)
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
