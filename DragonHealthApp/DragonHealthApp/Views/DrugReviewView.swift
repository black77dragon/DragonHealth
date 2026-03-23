import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Charts)
import Charts
#endif

struct DrugReviewView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = DrugReviewViewModel()
    @State private var showingWeekOverview = false
    @State private var selectedDailyDate: Date?
    @State private var selectedWeeklyReferenceDate: Date?
    @State private var showingMedicationEditor = false
    @State private var editingMedicationEntry: GLP1MedicationEntry?
    @State private var medicationPendingDelete: GLP1MedicationEntry?

    private let analytics = DrugReviewAnalytics()

    private var currentWeekRangeText: String {
        if let summary = viewModel.weeklySummary {
            return weekRangeText(start: summary.weekStart, end: summary.weekEnd)
        }
        guard let interval = analytics.weekInterval(containing: weeklyReferenceDate, calendar: store.appCalendar) else {
            return "This week"
        }
        return weekRangeText(start: interval.start, end: interval.end)
    }

    private var isSunday: Bool {
        store.appCalendar.component(.weekday, from: store.currentDay) == 1
    }

    private var defaultDailyReviewDate: Date {
        store.appCalendar.date(byAdding: .day, value: -1, to: store.currentDay) ?? store.currentDay
    }

    private var dailyReviewDate: Date {
        store.appCalendar.startOfDay(for: selectedDailyDate ?? defaultDailyReviewDate)
    }

    private var weeklyReferenceDate: Date {
        store.appCalendar.startOfDay(for: selectedWeeklyReferenceDate ?? store.currentDay)
    }

    private var isDefaultDailyReviewDate: Bool {
        store.appCalendar.isDate(dailyReviewDate, inSameDayAs: defaultDailyReviewDate)
    }

    private var dailyReviewDayText: String {
        let formatter = DateFormatter()
        formatter.calendar = store.appCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = store.appCalendar.timeZone
        formatter.dateFormat = "EEE d.M.yy"
        return formatter.string(from: dailyReviewDate)
    }

    private var dailyReviewDateBinding: Binding<Date> {
        Binding(
            get: { dailyReviewDate },
            set: { selectedDailyDate = store.appCalendar.startOfDay(for: $0) }
        )
    }

    private var weeklyReferenceDateBinding: Binding<Date> {
        Binding(
            get: { weeklyReferenceDate },
            set: { selectedWeeklyReferenceDate = store.appCalendar.startOfDay(for: $0) }
        )
    }

    private var loadKey: DrugReviewLoadKey {
        DrugReviewLoadKey(
            refreshToken: store.drugReviewRefreshToken,
            dailyDate: dailyReviewDate,
            weeklyReferenceDate: weeklyReferenceDate
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpacing.section) {
                DrugReviewHeaderCard(
                    weekRangeText: currentWeekRangeText,
                    dailyReviewDayText: dailyReviewDayText,
                    savedEntry: viewModel.savedEntry,
                    isSunday: isSunday,
                    isDefaultDailyReviewDate: isDefaultDailyReviewDate
                )

                DrugReviewMedicationPlannerCard(
                    preferredWeekday: viewModel.preferredMedicationWeekday,
                    entries: viewModel.medicationEntries,
                    saveConfirmationMessage: viewModel.medicationSaveConfirmationMessage,
                    today: store.currentDay,
                    calendar: store.appCalendar,
                    onWeekdaySelected: { weekday in
                        Task {
                            await viewModel.updatePreferredMedicationWeekday(
                                store: store,
                                weekday: weekday
                            )
                        }
                    },
                    onAdd: {
                        editingMedicationEntry = nil
                        showingMedicationEditor = true
                    },
                    onEdit: { entry in
                        editingMedicationEntry = entry
                        showingMedicationEditor = true
                    },
                    onDelete: { entry in
                        medicationPendingDelete = entry
                    }
                )

                DrugReviewDailyFormCard(
                    appetiteControl: $viewModel.appetiteControl,
                    energyLevel: $viewModel.energyLevel,
                    sideEffects: $viewModel.sideEffects,
                    mood: $viewModel.mood,
                    observation: $viewModel.observation,
                    reviewDate: dailyReviewDateBinding,
                    maximumReviewDate: defaultDailyReviewDate,
                    reviewDayText: dailyReviewDayText,
                    isDefaultReviewDate: isDefaultDailyReviewDate,
                    savedTimestamp: viewModel.savedEntry?.timestamp,
                    saveConfirmationMessage: viewModel.dailySaveConfirmationMessage,
                    isSaving: viewModel.isSavingDaily,
                    onUsePreviousDay: { selectedDailyDate = nil },
                    onSave: {
                        Task {
                            await viewModel.saveDaily(
                                store: store,
                                day: dailyReviewDate,
                                weeklyReferenceDate: weeklyReferenceDate
                            )
                        }
                    }
                )

                DrugReviewWeekToggleCard(
                    summary: viewModel.weeklySummary,
                    isExpanded: showingWeekOverview,
                    onToggle: { showingWeekOverview.toggle() }
                )

                if showingWeekOverview {
                    DrugReviewWeeklySummaryCard(
                        summary: viewModel.weeklySummary,
                        weekRangeText: currentWeekRangeText
                    )

                    DrugReviewWeeklyReflectionCard(
                        isSunday: isSunday,
                        whatWentWell: $viewModel.whatWentWell,
                        whatDidNotWork: $viewModel.whatDidNotWork,
                        whatToAdjust: $viewModel.whatToAdjust,
                        referenceDate: weeklyReferenceDateBinding,
                        maximumReferenceDate: store.currentDay,
                        weekRangeText: currentWeekRangeText,
                        updatedAt: viewModel.savedReflection?.updatedAt,
                        saveConfirmationMessage: viewModel.weeklySaveConfirmationMessage,
                        isSaving: viewModel.isSavingReflection,
                        onUseCurrentWeek: { selectedWeeklyReferenceDate = nil },
                        onSave: {
                            Task {
                                await viewModel.saveWeeklyReflection(
                                    store: store,
                                    dailyDate: dailyReviewDate,
                                    referenceDate: weeklyReferenceDate
                                )
                            }
                        }
                    )

                    DrugReviewTrendsCard(
                        selectedCriterion: $viewModel.selectedTrendCriterion,
                        points: viewModel.trendPoints
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 44)
        }
        .background(ZenStyle.pageBackground)
        .navigationTitle("GLP-1 Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMedicationEditor, onDismiss: {
            editingMedicationEntry = nil
        }) {
            NavigationStack {
                DrugReviewMedicationEditorSheet(
                    entry: editingMedicationEntry,
                    calendar: store.appCalendar,
                    today: store.currentDay,
                    preferredWeekday: viewModel.preferredMedicationWeekday
                ) { draft in
                    Task {
                        await viewModel.saveMedicationEntry(
                            store: store,
                            entryID: editingMedicationEntry?.id,
                            day: draft.date,
                            medication: draft.medication,
                            dose: draft.dose,
                            isTaken: draft.isTaken,
                            comment: draft.comment,
                            dailyDate: dailyReviewDate,
                            weeklyReferenceDate: weeklyReferenceDate
                        )
                    }
                    showingMedicationEditor = false
                }
            }
        }
        .confirmationDialog(
            "Delete medication entry?",
            isPresented: Binding(
                get: { medicationPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        medicationPendingDelete = nil
                    }
                }
            ),
            presenting: medicationPendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteMedicationEntry(
                        store: store,
                        entry: entry,
                        dailyDate: dailyReviewDate,
                        weeklyReferenceDate: weeklyReferenceDate
                    )
                }
                medicationPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                medicationPendingDelete = nil
            }
        } message: { entry in
            Text("Remove the \(entry.medication.title) \(entry.dose.title) entry on \(entry.day.formatted(date: .abbreviated, time: .omitted))?")
        }
        .task(id: loadKey) {
            await viewModel.load(
                store: store,
                dailyDate: dailyReviewDate,
                weeklyReferenceDate: weeklyReferenceDate
            )
        }
    }

    private func weekRangeText(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = store.appCalendar
        formatter.locale = store.appCalendar.locale ?? .current
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

private struct DrugReviewMedicationPlannerCard: View {
    let preferredWeekday: Int
    let entries: [GLP1MedicationEntry]
    let saveConfirmationMessage: String?
    let today: Date
    let calendar: Calendar
    let onWeekdaySelected: (Int) -> Void
    let onAdd: () -> Void
    let onEdit: (GLP1MedicationEntry) -> Void
    let onDelete: (GLP1MedicationEntry) -> Void

    private var normalizedToday: Date {
        calendar.startOfDay(for: today)
    }

    private var sortedEntries: [GLP1MedicationEntry] {
        entries.sorted { lhs, rhs in
            if lhs.day == rhs.day {
                return lhs.medication.title < rhs.medication.title
            }
            return lhs.day < rhs.day
        }
    }

    private var upcomingEntries: [GLP1MedicationEntry] {
        sortedEntries.filter { entry in
            let day = calendar.startOfDay(for: entry.day)
            return day >= normalizedToday
        }
    }

    private var pastEntries: [GLP1MedicationEntry] {
        Array(
            sortedEntries
            .filter { entry in
                let day = calendar.startOfDay(for: entry.day)
                return day < normalizedToday
            }
            .reversed()
        )
    }

    private var nextEntry: GLP1MedicationEntry? {
        upcomingEntries.first(where: { !$0.isTaken }) ?? upcomingEntries.first
    }

    private var latestTakenEntry: GLP1MedicationEntry? {
        sortedEntries
            .filter { $0.isTaken }
            .sorted { $0.day > $1.day }
            .first
    }

    private var summaryText: String {
        if let nextEntry {
            let prefix = nextEntry.isTaken ? "Next recorded dose" : "Next planned dose"
            return "\(prefix) is \(nextEntry.medication.title) \(nextEntry.dose.title) on \(nextEntry.day.formatted(date: .abbreviated, time: .omitted))."
        }
        if let latestTakenEntry {
            return "Last marked taken: \(latestTakenEntry.medication.title) \(latestTakenEntry.dose.title) on \(latestTakenEntry.day.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Plan upcoming injections here and keep a clean record of what was taken."
    }

    private var preferredWeekdayLabel: String {
        let symbols = calendar.weekdaySymbols
        let index = max(0, min(symbols.count - 1, preferredWeekday - 1))
        guard symbols.indices.contains(index) else { return "Sunday" }
        return symbols[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack(alignment: .top, spacing: ZenSpacing.group) {
                VStack(alignment: .leading, spacing: ZenSpacing.text) {
                    Text("Dose Planner")
                        .zenSectionTitle()
                    Text(summaryText)
                        .zenSupportText()
                }
                Spacer(minLength: 12)
                Button(action: onAdd) {
                    Label(entries.isEmpty ? "Plan Dose" : "Add Dose", systemImage: "plus")
                }
                .glassButton(.text)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferred dose day")
                        .zenMetricLabel()
                    Text("Use one weekday as your default rhythm.")
                        .zenSupportText()
                }
                Spacer()
                Menu {
                    ForEach(Array(calendar.weekdaySymbols.enumerated()), id: \.offset) { offset, symbol in
                        Button {
                            onWeekdaySelected(offset + 1)
                        } label: {
                            if preferredWeekday == offset + 1 {
                                Label(symbol, systemImage: "checkmark")
                            } else {
                                Text(symbol)
                            }
                        }
                    }
                } label: {
                    Label(preferredWeekdayLabel, systemImage: "calendar.badge.clock")
                }
                .glassLabel(.text)
            }

            if let nextEntry {
                DrugReviewMedicationSpotlight(entry: nextEntry, today: normalizedToday, calendar: calendar)
            }

            if let saveConfirmationMessage {
                DrugReviewSaveConfirmationView(message: saveConfirmationMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if sortedEntries.isEmpty {
                DrugReviewMedicationEmptyState(onAdd: onAdd)
            } else {
                VStack(alignment: .leading, spacing: ZenSpacing.group) {
                    if !upcomingEntries.isEmpty {
                        DrugReviewMedicationSection(
                            title: "Upcoming",
                            entries: upcomingEntries,
                            today: normalizedToday,
                            calendar: calendar,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }

                    if !pastEntries.isEmpty {
                        DrugReviewMedicationSection(
                            title: "History",
                            entries: pastEntries,
                            today: normalizedToday,
                            calendar: calendar,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }
}

private struct DrugReviewLoadKey: Hashable {
    let refreshToken: UUID
    let dailyDate: Date
    let weeklyReferenceDate: Date
}

private struct DrugReviewHeaderCard: View {
    let weekRangeText: String
    let dailyReviewDayText: String
    let savedEntry: DrugReviewDailyEntry?
    let isSunday: Bool
    let isDefaultDailyReviewDate: Bool

    private var statusText: String {
        if let savedEntry {
            return "Saved for \(dailyReviewDayText) at \(savedEntry.timestamp.formatted(date: .omitted, time: .shortened))."
        }
        if isDefaultDailyReviewDate {
            return "Yesterday's check-in takes about a minute."
        }
        return "Open any earlier day to review or update it."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.text) {
            HStack {
                VStack(alignment: .leading, spacing: ZenSpacing.text) {
                    Text("Medication Check-In")
                        .zenEyebrow()
                    Text("Fast daily review, simple weekly reflection.")
                        .zenHeroTitle()
                    Text("Daily check-in for \(dailyReviewDayText)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .zenSupportText()
                }
                Spacer()
                if isSunday {
                    Text("Sunday Prompt")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ZenStyle.subtleAccent, in: Capsule())
                }
            }

            HStack {
                Label(weekRangeText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("0-10 ratings")
                    .zenMetricLabel()
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 22)
    }
}

private struct DrugReviewDailyFormCard: View {
    @Binding var appetiteControl: Int
    @Binding var energyLevel: Int
    @Binding var sideEffects: Int
    @Binding var mood: Int
    @Binding var observation: String
    @Binding var reviewDate: Date
    let maximumReviewDate: Date
    let reviewDayText: String
    let isDefaultReviewDate: Bool
    let savedTimestamp: Date?
    let saveConfirmationMessage: String?
    let isSaving: Bool
    let onUsePreviousDay: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack(alignment: .center) {
                Text("Daily Check-In")
                    .zenSectionTitle()
                Spacer()
                Text(reviewDayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(isDefaultReviewDate ? "This review is always for the day before." : "Choose any previous day to review or update that entry.")
                .zenSupportText()

            HStack {
                DatePicker("Check-in day", selection: $reviewDate, in: ...maximumReviewDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Spacer()
                Button {
                    onUsePreviousDay()
                } label: {
                    Label("Use Yesterday", systemImage: "arrow.uturn.backward.circle")
                }
                .glassButton(.text)
            }

            DrugReviewScoreRow(
                criterion: .appetiteControl,
                value: $appetiteControl
            )
            DrugReviewScoreRow(
                criterion: .energyLevel,
                value: $energyLevel
            )
            DrugReviewScoreRow(
                criterion: .sideEffects,
                value: $sideEffects
            )
            DrugReviewScoreRow(
                criterion: .mood,
                value: $mood
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Observation")
                    .zenMetricLabel()
                DrugReviewMultilineInput(
                    text: $observation,
                    placeholder: "Optional note for \(reviewDayText)",
                    minHeight: 112
                )
            }

            if let saveConfirmationMessage {
                DrugReviewSaveConfirmationView(message: saveConfirmationMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack {
                if let savedTimestamp {
                    Text("Last saved \(savedTimestamp.formatted(date: .omitted, time: .shortened))")
                        .zenSupportText()
                } else {
                    Text("Save once and it is available in your weekly summary.")
                        .zenSupportText()
                }
                Spacer()
                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .frame(minWidth: 120)
                    } else {
                        Text("Save Daily Check-In")
                            .frame(minWidth: 120)
                    }
                }
                .disabled(isSaving)
                .glassButton(.text)
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }
}

private struct DrugReviewScoreRow: View {
    let criterion: DrugReviewCriterion
    @Binding var value: Int

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(criterion.title, systemImage: criterion.symbolName)
                    .font(.subheadline.weight(.medium))
            }

            HStack(spacing: 8) {
                Text("0")
                    .zenMetricLabel()
                    .frame(width: 10, alignment: .leading)

                Slider(value: sliderValue, in: 0...10, step: 1)

                Text("10")
                    .zenMetricLabel()
                    .frame(width: 18, alignment: .trailing)

                Text("\(value)")
                    .zenMetricValue()
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(criterion.title)
        .accessibilityValue("\(value) out of 10")
    }
}

private struct DrugReviewWeekToggleCard: View {
    let summary: DrugReviewWeeklySummary?
    let isExpanded: Bool
    let onToggle: () -> Void

    private var subtitle: String {
        let count = summary?.entryCount ?? 0
        return "\(count) of 7 daily check-ins saved this week."
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly View")
                    .zenSectionTitle()
                Text(subtitle)
                    .zenSupportText()
            }
            Spacer()
            Button(isExpanded ? "Hide My Week" : "View My Week", action: onToggle)
                .glassButton(.text)
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }
}

private struct DrugReviewMedicationSpotlight: View {
    let entry: GLP1MedicationEntry
    let today: Date
    let calendar: Calendar

    private var relativeText: String {
        let day = calendar.startOfDay(for: entry.day)
        if calendar.isDate(day, inSameDayAs: today) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return entry.day.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        HStack(alignment: .center, spacing: ZenSpacing.group) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.isTaken ? "Marked taken" : "Next up")
                    .zenMetricLabel()
                Text("\(entry.medication.title) \(entry.dose.title)")
                    .font(.subheadline.weight(.semibold))
                Text("\(relativeText), \(entry.day.formatted(date: .abbreviated, time: .omitted))")
                    .zenSupportText()
            }
            Spacer()
            DrugReviewMedicationStatusBadge(isTaken: entry.isTaken)
        }
        .padding(14)
        .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DrugReviewMedicationEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.text) {
            Text("No doses logged yet")
                .zenSectionTitle()
            Text("Start with the next planned injection so future and past entries stay in one timeline.")
                .zenSupportText()
            Button(action: onAdd) {
                Label("Plan First Dose", systemImage: "calendar.badge.plus")
            }
            .glassButton(.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DrugReviewMedicationSection: View {
    let title: String
    let entries: [GLP1MedicationEntry]
    let today: Date
    let calendar: Calendar
    let onEdit: (GLP1MedicationEntry) -> Void
    let onDelete: (GLP1MedicationEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .zenMetricLabel()
            ForEach(entries) { entry in
                DrugReviewMedicationRow(
                    entry: entry,
                    today: today,
                    calendar: calendar,
                    onEdit: { onEdit(entry) },
                    onDelete: { onDelete(entry) }
                )
            }
        }
    }
}

private struct DrugReviewMedicationRow: View {
    let entry: GLP1MedicationEntry
    let today: Date
    let calendar: Calendar
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var subtitleText: String {
        let day = calendar.startOfDay(for: entry.day)
        if calendar.isDate(day, inSameDayAs: today) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return entry.day.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(entry.day.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        DrugReviewMedicationStatusBadge(isTaken: entry.isTaken)
                    }
                    Text("\(entry.medication.title) • \(entry.dose.title)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitleText)
                        .zenMetricLabel()
                    if let comment = entry.comment {
                        Text(comment)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive, action: onDelete)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Edit", action: onEdit)
                .tint(.accentColor)
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

private struct DrugReviewMedicationStatusBadge: View {
    let isTaken: Bool

    var body: some View {
        Text(isTaken ? "Taken" : "Planned")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isTaken ? Color.green : Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (isTaken ? Color.green.opacity(0.12) : ZenStyle.subtleAccent),
                in: Capsule()
            )
    }
}

private struct DrugReviewWeeklySummaryCard: View {
    let summary: DrugReviewWeeklySummary?
    let weekRangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack {
                Text("Weekly Summary")
                    .zenSectionTitle()
                Spacer()
                Text(weekRangeText)
                    .zenMetricLabel()
            }

            if let summary {
                Text("\(summary.entryCount) of 7 check-ins logged")
                    .zenSupportText()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DrugReviewAverageChip(title: "Appetite", value: summary.averages.appetiteControl)
                    DrugReviewAverageChip(title: "Energy", value: summary.averages.energyLevel)
                    DrugReviewAverageChip(title: "Side Effects", value: summary.averages.sideEffects)
                    DrugReviewAverageChip(title: "Mood", value: summary.averages.mood)
                }

                if summary.observationHighlights.isEmpty {
                    Text("Daily observations will appear here as you add notes.")
                        .zenSupportText()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Observation Highlights")
                            .zenMetricLabel()
                        ForEach(summary.observationHighlights, id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                        }
                    }
                }

                if !summary.reflectionNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reflection Notes")
                            .zenMetricLabel()
                        ForEach(summary.reflectionNotes) { note in
                            Text("\(note.title): \(note.text)")
                                .font(.footnote)
                        }
                    }
                }
            } else {
                Text("Start with a daily check-in and the weekly summary will build automatically.")
                    .zenSupportText()
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }
}

private struct DrugReviewMedicationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: GLP1MedicationEntry?
    let calendar: Calendar
    let today: Date
    let preferredWeekday: Int
    let onSave: (DrugReviewMedicationDraft) -> Void

    @State private var draft: DrugReviewMedicationDraft

    init(
        entry: GLP1MedicationEntry?,
        calendar: Calendar,
        today: Date,
        preferredWeekday: Int,
        onSave: @escaping (DrugReviewMedicationDraft) -> Void
    ) {
        self.entry = entry
        self.calendar = calendar
        self.today = today
        self.preferredWeekday = preferredWeekday
        self.onSave = onSave
        _draft = State(
            initialValue: DrugReviewMedicationDraft(
                entry: entry,
                calendar: calendar,
                today: today,
                preferredWeekday: preferredWeekday
            )
        )
    }

    private var titleText: String {
        entry == nil ? "New Dose" : "Edit Dose"
    }

    private var helperText: String {
        if draft.isTaken {
            return "Use this when the injection has been completed."
        }
        return "Leave Taken off to keep a future dose planned."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpacing.section) {
                VStack(alignment: .leading, spacing: ZenSpacing.text) {
                    Text("GLP-1 medication")
                        .zenEyebrow()
                    Text(titleText)
                        .zenHeroTitle()
                    Text("Plan future doses or update past ones without leaving the review flow.")
                        .zenSupportText()
                }

                VStack(alignment: .leading, spacing: ZenSpacing.group) {
                    HStack {
                        Text("Date")
                            .zenMetricLabel()
                        Spacer()
                        DatePicker(
                            "Date",
                            selection: $draft.date,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Medication")
                            .zenMetricLabel()
                        Picker("Medication", selection: $draft.medication) {
                            ForEach(DrugReviewMedicationDraft.medicationOptions, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dose")
                            .zenMetricLabel()
                        Picker("Dose", selection: $draft.dose) {
                            ForEach(DrugReviewMedicationDraft.doseOptions, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle(isOn: $draft.isTaken) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taken")
                                .font(.subheadline.weight(.medium))
                            Text(helperText)
                                .zenSupportText()
                        }
                    }
                    .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comment")
                            .zenMetricLabel()
                        DrugReviewMultilineInput(
                            text: $draft.comment,
                            placeholder: "Optional note",
                            minHeight: 110
                        )
                    }
                }
                .padding(ZenSpacing.card)
                .zenCard(cornerRadius: 20)
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(ZenStyle.pageBackground)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? "Add" : "Save") {
                    onSave(draft)
                    dismiss()
                }
            }
        }
    }
}

private struct DrugReviewAverageChip: View {
    let title: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .zenMetricLabel()
            Text(value.map { String(format: "%.1f", $0) } ?? "--")
                .zenMetricValue()
        }
        .padding(12)
        .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DrugReviewMedicationDraft {
    static let medicationOptions = GLP1Medication.allCases
    static let doseOptions = GLP1Dose.allCases

    var date: Date
    var medication: GLP1Medication
    var dose: GLP1Dose
    var isTaken: Bool
    var comment: String

    init(
        date: Date,
        medication: GLP1Medication = Self.medicationOptions[0],
        dose: GLP1Dose = Self.doseOptions[0],
        isTaken: Bool = false,
        comment: String = ""
    ) {
        self.date = date
        self.medication = medication
        self.dose = dose
        self.isTaken = isTaken
        self.comment = comment
    }

    init(entry: GLP1MedicationEntry?, calendar: Calendar, today: Date, preferredWeekday: Int) {
        let normalizedToday = calendar.startOfDay(for: today)
        self.date = entry?.day ?? Self.defaultDate(
            calendar: calendar,
            today: normalizedToday,
            preferredWeekday: preferredWeekday
        )
        self.medication = entry?.medication ?? Self.medicationOptions[0]
        self.dose = entry?.dose ?? Self.doseOptions[0]
        self.isTaken = entry?.isTaken ?? false
        self.comment = entry?.comment ?? ""
    }

    private static func defaultDate(calendar: Calendar, today: Date, preferredWeekday: Int) -> Date {
        let normalizedWeekday = min(max(preferredWeekday, 1), 7)
        let todayWeekday = calendar.component(.weekday, from: today)
        let delta = (normalizedWeekday - todayWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }
}

private struct DrugReviewWeeklyReflectionCard: View {
    let isSunday: Bool
    @Binding var whatWentWell: String
    @Binding var whatDidNotWork: String
    @Binding var whatToAdjust: String
    @Binding var referenceDate: Date
    let maximumReferenceDate: Date
    let weekRangeText: String
    let updatedAt: Date?
    let saveConfirmationMessage: String?
    let isSaving: Bool
    let onUseCurrentWeek: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack(alignment: .center) {
                Text(isSunday ? "Sunday Reflection" : "Weekly Reflection")
                    .zenSectionTitle()
                Spacer()
                Text(weekRangeText)
                    .zenMetricLabel()
            }

            Text(isSunday ? "Capture what worked, what didn't, and what to adjust for next week." : "Pick any date in the week you want to review or update.")
                .zenSupportText()

            HStack {
                DatePicker("Week date", selection: $referenceDate, in: ...maximumReferenceDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                Spacer()
                Button {
                    onUseCurrentWeek()
                } label: {
                    Label("Use This Week", systemImage: "arrow.uturn.backward.circle")
                }
                .glassButton(.text)
            }

            DrugReviewReflectionField(title: "What went well", text: $whatWentWell)
            DrugReviewReflectionField(title: "What didn't work", text: $whatDidNotWork)
            DrugReviewReflectionField(title: "What to adjust", text: $whatToAdjust)

            if let saveConfirmationMessage {
                DrugReviewSaveConfirmationView(message: saveConfirmationMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack {
                if let updatedAt {
                    Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .zenSupportText()
                } else {
                    Text("Reflection notes will show up in your weekly trends.")
                        .zenSupportText()
                }
                Spacer()
                Button(action: onSave) {
                    if isSaving {
                        ProgressView()
                            .frame(minWidth: 96)
                    } else {
                        Text("Save Reflection")
                            .frame(minWidth: 96)
                    }
                }
                .disabled(isSaving)
                .glassButton(.text)
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }
}

private struct DrugReviewReflectionField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .zenMetricLabel()
            DrugReviewMultilineInput(
                text: $text,
                placeholder: title,
                minHeight: 92
            )
        }
    }
}

private struct DrugReviewSaveConfirmationView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.12), in: Capsule())
    }
}

private struct DrugReviewMultilineInput: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DrugReviewScrollableTextEditor(text: $text)
                .frame(height: minHeight)

            if isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#if canImport(UIKit)
private struct DrugReviewScrollableTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .sentences
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        DispatchQueue.main.async {
            let isOverflowing = uiView.contentSize.height > uiView.bounds.height + 1
            if isOverflowing && !context.coordinator.isOverflowing {
                uiView.flashScrollIndicators()
            }
            context.coordinator.isOverflowing = isOverflowing
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var isOverflowing = false

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text

            let isOverflowing = textView.contentSize.height > textView.bounds.height + 1
            if isOverflowing && !self.isOverflowing {
                textView.flashScrollIndicators()
            }
            self.isOverflowing = isOverflowing
        }
    }
}
#else
private struct DrugReviewScrollableTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}
#endif

private struct DrugReviewTrendsCard: View {
    @Binding var selectedCriterion: DrugReviewCriterion
    let points: [DrugReviewTrendPoint]

    private var reflectionPoints: [DrugReviewTrendPoint] {
        points.filter { !$0.reflectionNotes.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("Weekly Trends")
                .zenSectionTitle()

            Picker("Trend Metric", selection: $selectedCriterion) {
                ForEach(DrugReviewCriterion.allCases) { criterion in
                    Text(criterion.shortTitle).tag(criterion)
                }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                Text("Trends appear after you build up weekly check-ins.")
                    .zenSupportText()
            } else {
                DrugReviewTrendChart(
                    criterion: selectedCriterion,
                    points: points
                )
            }

            if !reflectionPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flagged Reflection Notes")
                        .zenMetricLabel()
                    ForEach(reflectionPoints) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weekRangeText(start: point.weekStart, end: point.weekEnd))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            ForEach(point.reflectionNotes) { note in
                                Text("\(note.title): \(note.text)")
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }

    private func weekRangeText(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

private struct DrugReviewTrendChart: View {
    let criterion: DrugReviewCriterion
    let points: [DrugReviewTrendPoint]

    var body: some View {
        #if canImport(Charts)
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(points) { point in
                    if let value = point.value(for: criterion) {
                        LineMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Average", value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)

                        PointMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Average", value)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYScale(domain: 0...10)
            .frame(height: 170)
        } else {
            Text("Charts require iOS 16 or later.")
                .zenSupportText()
        }
        #else
        Text("Charts are unavailable on this device.")
            .zenSupportText()
        #endif
    }
}
