import SwiftUI
import Core
#if canImport(Charts)
import Charts
#endif

struct BodyMetricsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var healthSyncManager: HealthSyncManager
    @State private var showingAdd = false
    @AppStorage("bodyMetrics.timeFrame") private var timeFrameRaw: String = BodyMetricsTimeFrame.month.rawValue

    private let calculator = BodyTrendCalculator()

    private var timeFrame: BodyMetricsTimeFrame {
        BodyMetricsTimeFrame(rawValue: timeFrameRaw) ?? .month
    }

    private var timeFrameBinding: Binding<BodyMetricsTimeFrame> {
        Binding(
            get: { BodyMetricsTimeFrame(rawValue: timeFrameRaw) ?? .month },
            set: { timeFrameRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                let averages = calculator.sevenDayAverages(entries: store.bodyMetrics, referenceDate: store.currentDay)
                let sortedEntries = store.bodyMetrics.sorted(by: { $0.date < $1.date })
                let weightValues = metricValues(entries: sortedEntries, value: \.weightKg)
                let latestWeight = weightValues.last
                let previousWeight = weightValues.dropLast().last
                let lastWeekDate = store.appCalendar.date(byAdding: .day, value: -7, to: store.currentDay) ?? store.currentDay
                let lastMonthDate = store.appCalendar.date(byAdding: .month, value: -1, to: store.currentDay) ?? store.currentDay
                let lastWeekWeight = latestMetricValue(
                    entries: sortedEntries,
                    value: \.weightKg,
                    onOrBefore: lastWeekDate
                )
                let lastMonthWeight = latestMetricValue(
                    entries: sortedEntries,
                    value: \.weightKg,
                    onOrBefore: lastMonthDate
                )
                let latestValues = BodyMetricLatestValues(
                    weightKg: latestWeight,
                    muscleMass: latestMetricValue(entries: sortedEntries, value: \.muscleMass),
                    bodyFatPercent: latestMetricValue(entries: sortedEntries, value: \.bodyFatPercent),
                    waistCm: latestMetricValue(entries: sortedEntries, value: \.waistCm),
                    steps: latestMetricValue(entries: sortedEntries, value: \.steps),
                    activeEnergyKcal: latestMetricValue(entries: sortedEntries, value: \.activeEnergyKcal)
                )
                let filteredEntries = timeFrame.filteredEntries(
                    from: sortedEntries,
                    referenceDate: store.currentDay,
                    calendar: store.appCalendar
                )
                let weightPoints = metricPoints(entries: filteredEntries, value: \.weightKg)
                let leanMassPoints = metricPoints(entries: filteredEntries, value: \.muscleMass)
                let bodyFatPoints = metricPoints(entries: filteredEntries, value: \.bodyFatPercent)
                let waistPoints = metricPoints(entries: filteredEntries, value: \.waistCm)
                let stepsPoints = metricPoints(entries: filteredEntries, value: \.steps)
                let activeEnergyPoints = metricPoints(entries: filteredEntries, value: \.activeEnergyKcal)
                CurrentWeightCanvas(
                    latestWeight: latestWeight,
                    previousWeight: previousWeight,
                    lastWeekWeight: lastWeekWeight,
                    lastMonthWeight: lastMonthWeight
                )
                TargetWeightCanvas(
                    targetWeight: store.settings.targetWeightKg,
                    targetDate: store.settings.targetWeightDate
                )
                TargetProgressCanvas(
                    currentWeight: latestWeight,
                    targetWeight: store.settings.targetWeightKg,
                    targetDate: store.settings.targetWeightDate,
                    referenceDate: store.currentDay,
                    calendar: store.appCalendar
                )
                BodyMetricAveragesCard(averages: averages, latestValues: latestValues)
                AppleHealthSyncCard(
                    lastSyncDate: healthSyncManager.lastSyncDate,
                    lastSyncError: healthSyncManager.lastSyncError,
                    isSyncing: healthSyncManager.isSyncing,
                    onSync: { healthSyncManager.performManualSync(store: store) }
                )

                BodyMetricHistorySection(
                    timeFrame: timeFrameBinding,
                    weightPoints: weightPoints,
                    leanMassPoints: leanMassPoints,
                    bodyFatPoints: bodyFatPoints,
                    waistPoints: waistPoints,
                    stepsPoints: stepsPoints,
                    activeEnergyPoints: activeEnergyPoints
                )

                if store.bodyMetrics.isEmpty {
                    Text("No body metrics logged yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Entries")
                        .font(.headline)
                    ForEach(store.bodyMetrics, id: \.date) { entry in
                        BodyMetricRow(entry: entry)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Body Metrics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            BodyMetricEntrySheet { entry in
                Task {
                    await store.saveBodyMetric(entry)
                }
            }
        }
        .onAppear {
            healthSyncManager.refreshStatus()
        }
    }

    private func metricPoints(entries: [BodyMetricEntry], value: KeyPath<BodyMetricEntry, Double?>) -> [MetricPoint] {
        entries.compactMap { entry in
            guard let metricValue = entry[keyPath: value] else { return nil }
            return MetricPoint(date: entry.date, value: metricValue)
        }
    }

    private func metricValues(entries: [BodyMetricEntry], value: KeyPath<BodyMetricEntry, Double?>) -> [Double] {
        entries.compactMap { $0[keyPath: value] }
    }

    private func latestMetricValue(entries: [BodyMetricEntry], value: KeyPath<BodyMetricEntry, Double?>) -> Double? {
        entries.reversed().compactMap { $0[keyPath: value] }.first
    }

    private func latestMetricValue(
        entries: [BodyMetricEntry],
        value: KeyPath<BodyMetricEntry, Double?>,
        onOrBefore date: Date
    ) -> Double? {
        entries.reversed().first { entry in
            entry.date <= date && entry[keyPath: value] != nil
        }?[keyPath: value]
    }
}

private struct CurrentWeightCanvas: View {
    let latestWeight: Double?
    let previousWeight: Double?
    let lastWeekWeight: Double?
    let lastMonthWeight: Double?

    var body: some View {
        CanvasCard(accent: .blue, secondary: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                CanvasTitle(text: "Current Weight", accent: .blue)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(latestWeight.map { "\($0.cleanNumber) kg" } ?? "--")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        DeltaRow(label: "Last weight", delta: deltaValue(reference: previousWeight))
                        DeltaRow(label: "Last week", delta: deltaValue(reference: lastWeekWeight))
                        DeltaRow(label: "Last month", delta: deltaValue(reference: lastMonthWeight))
                    }
                    .frame(minWidth: 160)
                }
            }
        }
    }

    private func deltaValue(reference: Double?) -> DeltaValue? {
        guard let latestWeight, let reference else { return nil }
        let delta = latestWeight - reference
        if delta < 0 {
            return DeltaValue(value: delta, color: .green)
        }
        if delta > 0 {
            return DeltaValue(value: delta, color: .red)
        }
        return DeltaValue(value: delta, color: .secondary)
    }

}

private struct DeltaValue {
    let value: Double
    let color: Color
}

private struct DeltaRow: View {
    let label: String
    let delta: DeltaValue?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(deltaText)
                .font(.caption)
                .foregroundStyle(delta?.color ?? .secondary)
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)
        }
    }

    private var deltaText: String {
        guard let delta else { return "--" }
        if delta.value > 0 {
            return "+\(delta.value.cleanNumber) kg"
        }
        if delta.value < 0 {
            return "\(delta.value.cleanNumber) kg"
        }
        return "0 kg"
    }
}

private struct CanvasTitle: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(
                LinearGradient(
                    colors: [accent, accent.opacity(0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

private struct CanvasCard<Content: View>: View {
    let accent: Color
    let secondary: Color
    let content: Content

    init(accent: Color, secondary: Color = .teal, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.secondary = secondary
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(cardBackground)
            .overlay(cardStroke)
            .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private var cardBackground: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.18),
                                secondary.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: size.width * 0.12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size.width * 0.6, height: size.height * 1.35)
                    .rotationEffect(.degrees(-18))
                    .offset(x: size.width * 0.28, y: -size.height * 0.35)
                    .blendMode(.softLight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
    }
}

private struct CanvasMetricRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var valueFont: Font = .callout

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

private struct TargetWeightCanvas: View {
    let targetWeight: Double?
    let targetDate: Date?

    var body: some View {
        CanvasCard(accent: .purple, secondary: .pink) {
            VStack(alignment: .leading, spacing: 12) {
                CanvasTitle(text: "Target Weight", accent: .purple)
                CanvasMetricRow(
                    label: "Target Weight",
                    value: targetWeightText,
                    valueFont: .system(size: 30, weight: .semibold, design: .rounded)
                )
                CanvasMetricRow(label: "Target Date", value: targetDateText)
            }
        }
    }

    private var targetWeightText: String {
        guard let targetWeight else { return "--" }
        return "\(targetWeight.cleanNumber) kg"
    }

    private var targetDateText: String {
        targetDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "--"
    }
}

private struct TargetProgressCanvas: View {
    let currentWeight: Double?
    let targetWeight: Double?
    let targetDate: Date?
    let referenceDate: Date
    let calendar: Calendar

    var body: some View {
        CanvasCard(accent: .teal, secondary: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                CanvasTitle(text: "Target Progress", accent: .teal)
                CanvasMetricRow(label: "Target Weight", value: targetWeightText)
                CanvasMetricRow(label: "Target Date", value: targetDateText)
                CanvasMetricRow(label: "Difference", value: differenceText, valueColor: differenceColor)
                CanvasMetricRow(label: "Days remaining", value: daysRemainingText, valueColor: daysRemainingColor)
                CanvasMetricRow(
                    label: "Weekly reduction required",
                    value: weeklyReductionText,
                    valueColor: weeklyReductionColor
                )
            }
        }
    }

    private var targetWeightText: String {
        guard let targetWeight else { return "--" }
        return "\(targetWeight.cleanNumber) kg"
    }

    private var targetDateText: String {
        targetDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "--"
    }

    private var difference: Double? {
        guard let currentWeight, let targetWeight else { return nil }
        return targetWeight - currentWeight
    }

    private var differenceText: String {
        guard let difference else { return "--" }
        if difference > 0 {
            return "+\(difference.cleanNumber) kg"
        }
        if difference < 0 {
            return "\(difference.cleanNumber) kg"
        }
        return "0 kg"
    }

    private var differenceColor: Color {
        guard let difference else { return .secondary }
        if difference < 0 { return .green }
        if difference > 0 { return .orange }
        return .secondary
    }

    private var daysRemaining: Int? {
        guard let targetDate else { return nil }
        let start = calendar.startOfDay(for: referenceDate)
        let target = calendar.startOfDay(for: targetDate)
        let delta = calendar.dateComponents([.day], from: start, to: target).day
        guard let delta else { return nil }
        return max(0, delta)
    }

    private var daysRemainingText: String {
        guard let daysRemaining else { return "--" }
        if daysRemaining == 1 {
            return "1 day"
        }
        return "\(daysRemaining) days"
    }

    private var daysRemainingColor: Color {
        guard let daysRemaining else { return .secondary }
        if daysRemaining == 0 { return .red }
        if daysRemaining <= 14 { return .orange }
        return .primary
    }

    private var weeklyReduction: Double? {
        guard let difference, let daysRemaining, daysRemaining > 0 else { return nil }
        let weeks = Double(daysRemaining) / 7.0
        guard weeks > 0 else { return nil }
        return difference / weeks
    }

    private var weeklyReductionText: String {
        guard let weeklyReduction else { return "--" }
        let sign = weeklyReduction > 0 ? "+" : ""
        return "\(sign)\(weeklyReduction.cleanNumber) kg/wk"
    }

    private var weeklyReductionColor: Color {
        guard let weeklyReduction else { return .secondary }
        if weeklyReduction < 0 { return .green }
        if weeklyReduction > 0 { return .orange }
        return .secondary
    }
}

private struct BodyMetricLatestValues {
    let weightKg: Double?
    let muscleMass: Double?
    let bodyFatPercent: Double?
    let waistCm: Double?
    let steps: Double?
    let activeEnergyKcal: Double?
}

private struct BodyMetricAveragesCard: View {
    let averages: BodyMetricAverages
    let latestValues: BodyMetricLatestValues

    var body: some View {
        let weightDisplay = MetricDisplay(average: averages.weightKg, latest: latestValues.weightKg)
        let leanMassDisplay = MetricDisplay(average: averages.muscleMass, latest: latestValues.muscleMass)
        let bodyFatDisplay = MetricDisplay(average: averages.bodyFatPercent, latest: latestValues.bodyFatPercent)
        let waistDisplay = MetricDisplay(average: averages.waistCm, latest: latestValues.waistCm)
        let stepsDisplay = MetricDisplay(average: averages.steps, latest: latestValues.steps)
        let activeEnergyDisplay = MetricDisplay(average: averages.activeEnergyKcal, latest: latestValues.activeEnergyKcal)
        let fallbackTitles = [
            weightDisplay.fallbackTitle(label: "Weight"),
            leanMassDisplay.fallbackTitle(label: "Lean Mass"),
            bodyFatDisplay.fallbackTitle(label: "Body Fat"),
            waistDisplay.fallbackTitle(label: "Waist"),
            stepsDisplay.fallbackTitle(label: "Steps"),
            activeEnergyDisplay.fallbackTitle(label: "Active Energy")
        ].compactMap { $0 }

        VStack(alignment: .leading, spacing: 8) {
            Text("7-Day Averages")
                .font(.headline)
            HStack(spacing: 12) {
                MetricChip(title: "Weight", value: weightDisplay.value, unit: "kg", note: weightDisplay.note)
                MetricChip(title: "Lean Mass", value: leanMassDisplay.value, unit: "kg", note: leanMassDisplay.note)
            }
            HStack(spacing: 12) {
                MetricChip(title: "Body Fat", value: bodyFatDisplay.value, unit: "%", note: bodyFatDisplay.note)
                MetricChip(title: "Waist", value: waistDisplay.value, unit: "cm", note: waistDisplay.note)
            }
            HStack(spacing: 12) {
                MetricChip(title: "Steps", value: stepsDisplay.value, unit: "steps", note: stepsDisplay.note)
                MetricChip(title: "Active Energy", value: activeEnergyDisplay.value, unit: "kcal", note: activeEnergyDisplay.note)
            }
            if !fallbackTitles.isEmpty {
                Text("No 7-day average for \(fallbackTitles.joined(separator: ", ")). Showing latest value.")
                    .font(.caption2)
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

private struct AppleHealthSyncCard: View {
    let lastSyncDate: Date?
    let lastSyncError: String?
    let isSyncing: Bool
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Health")
                .font(.headline)

            if let lastSyncDate {
                Text("Last sync: \(formatted(lastSyncDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Apple Health sync yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastSyncError {
                Text(lastSyncError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Syncs weight, steps, and active energy (Move kcal) from Apple Health (plus any available body measurements).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                onSync()
            } label: {
                Label(isSyncing ? "Syncing..." : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isSyncing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct BodyMetricHistorySection: View {
    @Binding var timeFrame: BodyMetricsTimeFrame
    let weightPoints: [MetricPoint]
    let leanMassPoints: [MetricPoint]
    let bodyFatPoints: [MetricPoint]
    let waistPoints: [MetricPoint]
    let stepsPoints: [MetricPoint]
    let activeEnergyPoints: [MetricPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
            TimeFramePicker(timeFrame: $timeFrame)
            BodyMetricChartCard(title: "Weight", unit: "kg", points: weightPoints, tint: .blue, clampsToZero: true)
            BodyMetricChartCard(title: "Lean Mass", unit: "kg", points: leanMassPoints, tint: .teal, clampsToZero: true)
            BodyMetricChartCard(title: "Body Fat", unit: "%", points: bodyFatPoints, tint: .orange, clampsToZero: true)
            BodyMetricChartCard(title: "Waist", unit: "cm", points: waistPoints, tint: .red, clampsToZero: true)
            BodyMetricChartCard(title: "Steps", unit: "steps", points: stepsPoints, tint: .green, clampsToZero: true)
            BodyMetricChartCard(title: "Active Energy", unit: "kcal", points: activeEnergyPoints, tint: .pink, clampsToZero: true)
        }
    }
}

private struct TimeFramePicker: View {
    @Binding var timeFrame: BodyMetricsTimeFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time Frame")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Time Frame", selection: $timeFrame) {
                ForEach(BodyMetricsTimeFrame.allCases) { frame in
                    Text(frame.shortLabel)
                        .accessibilityLabel(frame.fullLabel)
                        .tag(frame)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private enum BodyMetricsTimeFrame: String, CaseIterable, Identifiable {
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

    func filteredEntries(
        from entries: [BodyMetricEntry],
        referenceDate: Date,
        calendar: Calendar
    ) -> [BodyMetricEntry] {
        guard let startDate = startDate(referenceDate: referenceDate, calendar: calendar) else { return entries }
        return entries.filter { $0.date >= startDate && $0.date <= referenceDate }
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

    private func startDate(referenceDate: Date, calendar: Calendar) -> Date? {
        guard let rangeComponent else { return nil }
        return calendar.date(
            byAdding: rangeComponent.0,
            value: rangeComponent.1,
            to: referenceDate
        )
    }
}
private struct MetricPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

private struct BodyMetricChartCard: View {
    let title: String
    let unit: String
    let points: [MetricPoint]
    let tint: Color
    let clampsToZero: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(points.last.map { "\(formattedValue($0.value)) \(unit)" } ?? "--")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                #if canImport(Charts)
                if #available(iOS 16.0, *) {
                    metricChart()
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
    private func metricChart() -> some View {
        let domain = yDomain(for: points)
        if let domain {
            baseChart()
                .chartYScale(domain: domain)
        } else {
            baseChart()
        }
    }

    @ViewBuilder
    private func baseChart() -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
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
        .frame(height: 160)
    }

    private func formattedValue(_ value: Double) -> String {
        if unit == "steps" || unit == "kcal" {
            return "\(Int(value.rounded()))"
        }
        return value.cleanNumber
    }

    private func yDomain(for points: [MetricPoint]) -> ClosedRange<Double>? {
        guard let minValue = points.map(\.value).min(),
              let maxValue = points.map(\.value).max() else {
            return nil
        }
        let lowerPadding = abs(minValue) * 0.1
        let upperPadding = abs(maxValue) * 0.1
        var lowerBound = minValue - lowerPadding
        var upperBound = maxValue + upperPadding
        if lowerBound == upperBound {
            let fallbackPadding = max(1, abs(minValue) * 0.1)
            lowerBound = minValue - fallbackPadding
            upperBound = maxValue + fallbackPadding
        }
        if clampsToZero {
            lowerBound = max(0, lowerBound)
        }
        return lowerBound...upperBound
    }
}

private struct MetricChip: View {
    let title: String
    let value: Double?
    let unit: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { "\($0.cleanNumber) \(unit)" } ?? "--")
                .font(.subheadline)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
    }
}

private struct MetricDisplay {
    let value: Double?
    let note: String?
    let usesLatest: Bool

    init(average: Double?, latest: Double?) {
        if let average {
            self.value = average
            self.note = nil
            self.usesLatest = false
        } else if let latest {
            self.value = latest
            self.note = "Latest"
            self.usesLatest = true
        } else {
            self.value = nil
            self.note = nil
            self.usesLatest = false
        }
    }

    func fallbackTitle(label: String) -> String? {
        usesLatest ? label : nil
    }
}

private struct BodyMetricRow: View {
    let entry: BodyMetricEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, style: .date)
                .font(.subheadline)
            HStack(spacing: 12) {
                BodyMetricValue(label: "Weight", value: entry.weightKg, unit: "kg")
                BodyMetricValue(label: "Lean Mass", value: entry.muscleMass, unit: "kg")
            }
            HStack(spacing: 12) {
                BodyMetricValue(label: "Body Fat", value: entry.bodyFatPercent, unit: "%")
                BodyMetricValue(label: "Waist", value: entry.waistCm, unit: "cm")
            }
            HStack(spacing: 12) {
                BodyMetricValue(label: "Steps", value: entry.steps, unit: "steps")
                BodyMetricValue(label: "Active Energy", value: entry.activeEnergyKcal, unit: "kcal")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct BodyMetricValue: View {
    let label: String
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\($0.cleanNumber) \(unit)" } ?? "--")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BodyMetricEntrySheet: View {
    let onSave: (BodyMetricEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var weightKg = ""
    @State private var muscleMass = ""
    @State private var bodyFat = ""
    @State private var waist = ""
    @State private var steps = ""
    @State private var activeEnergy = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                MetricField(title: "Weight (kg)", value: $weightKg)
                MetricField(title: "Lean Mass (kg)", value: $muscleMass)
                MetricField(title: "Body Fat (%)", value: $bodyFat)
                MetricField(title: "Waist (cm)", value: $waist)
                MetricField(title: "Steps", value: $steps)
                MetricField(title: "Active Energy (kcal)", value: $activeEnergy)
            }
            .navigationTitle("Add Metrics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            BodyMetricEntry(
                                date: date,
                                weightKg: Double(weightKg),
                                muscleMass: Double(muscleMass),
                                bodyFatPercent: Double(bodyFat),
                                waistCm: Double(waist),
                                steps: Double(steps),
                                activeEnergyKcal: Double(activeEnergy)
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MetricField: View {
    let title: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("--", text: $value)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        }
    }
}
