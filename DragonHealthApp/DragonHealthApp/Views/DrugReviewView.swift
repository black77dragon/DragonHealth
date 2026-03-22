import SwiftUI
import Core
#if canImport(Charts)
import Charts
#endif

struct DrugReviewView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = DrugReviewViewModel()
    @State private var showingWeekOverview = false

    private var currentWeekRangeText: String {
        guard let summary = viewModel.weeklySummary else { return "This week" }
        return weekRangeText(start: summary.weekStart, end: summary.weekEnd)
    }

    private var isSunday: Bool {
        store.appCalendar.component(.weekday, from: store.currentDay) == 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpacing.section) {
                DrugReviewHeaderCard(
                    weekRangeText: currentWeekRangeText,
                    savedEntry: viewModel.savedEntry,
                    isSunday: isSunday
                )

                DrugReviewDailyFormCard(
                    appetiteControl: $viewModel.appetiteControl,
                    energyLevel: $viewModel.energyLevel,
                    sideEffects: $viewModel.sideEffects,
                    mood: $viewModel.mood,
                    observation: $viewModel.observation,
                    savedTimestamp: viewModel.savedEntry?.timestamp,
                    isSaving: viewModel.isSavingDaily,
                    onSave: {
                        Task { await viewModel.saveDaily(store: store) }
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
                        updatedAt: viewModel.savedReflection?.updatedAt,
                        isSaving: viewModel.isSavingReflection,
                        onSave: {
                            Task { await viewModel.saveWeeklyReflection(store: store) }
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
        .task(id: store.drugReviewRefreshToken) {
            await viewModel.load(store: store)
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

private struct DrugReviewHeaderCard: View {
    let weekRangeText: String
    let savedEntry: DrugReviewDailyEntry?
    let isSunday: Bool

    private var statusText: String {
        if let savedEntry {
            return "Saved \(savedEntry.timestamp.formatted(date: .omitted, time: .shortened))."
        }
        return "Today's check-in takes about a minute."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.text) {
            HStack {
                VStack(alignment: .leading, spacing: ZenSpacing.text) {
                    Text("Medication Check-In")
                        .zenEyebrow()
                    Text("Fast daily review, simple weekly reflection.")
                        .zenHeroTitle()
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
                Text("1-10 ratings")
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
    let savedTimestamp: Date?
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("Today's Entry")
                .zenSectionTitle()

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
                TextField("Optional note for today", text: $observation, axis: .vertical)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        Text("Save Today's Check-In")
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
                Text("1")
                    .zenMetricLabel()
                    .frame(width: 10, alignment: .leading)

                Slider(value: sliderValue, in: 1...10, step: 1)

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
                Text("Start with today's check-in and the weekly summary will build automatically.")
                    .zenSupportText()
            }
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
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

private struct DrugReviewWeeklyReflectionCard: View {
    let isSunday: Bool
    @Binding var whatWentWell: String
    @Binding var whatDidNotWork: String
    @Binding var whatToAdjust: String
    let updatedAt: Date?
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text(isSunday ? "Sunday Reflection" : "Weekly Reflection")
                .zenSectionTitle()

            Text(isSunday ? "Capture what worked, what didn't, and what to adjust for next week." : "You can fill this in any day, then revisit it on Sunday.")
                .zenSupportText()

            DrugReviewReflectionField(title: "What went well", text: $whatWentWell)
            DrugReviewReflectionField(title: "What didn't work", text: $whatDidNotWork)
            DrugReviewReflectionField(title: "What to adjust", text: $whatToAdjust)

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
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(ZenStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

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
            .chartYScale(domain: 1...10)
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
