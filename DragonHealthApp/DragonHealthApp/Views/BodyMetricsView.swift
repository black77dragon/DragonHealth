import SwiftUI
import Core
#if canImport(Charts)
import Charts
#endif

struct BodyMetricsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var healthSyncManager: HealthSyncManager
    @State private var showingAdd = false

    private let calculator = BodyTrendCalculator()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                let averages = calculator.sevenDayAverages(entries: store.bodyMetrics, referenceDate: store.currentDay)
                let sortedEntries = store.bodyMetrics.sorted(by: { $0.date < $1.date })
                let weightPoints = metricPoints(entries: sortedEntries, value: \.weightKg)
                let leanMassPoints = metricPoints(entries: sortedEntries, value: \.muscleMass)
                let bodyFatPoints = metricPoints(entries: sortedEntries, value: \.bodyFatPercent)
                let waistPoints = metricPoints(entries: sortedEntries, value: \.waistCm)
                let stepsPoints = metricPoints(entries: sortedEntries, value: \.steps)

                BodyMetricAveragesCard(averages: averages)
                AppleHealthSyncCard(
                    lastSyncDate: healthSyncManager.lastSyncDate,
                    lastSyncError: healthSyncManager.lastSyncError,
                    isSyncing: healthSyncManager.isSyncing,
                    onSync: { healthSyncManager.performManualSync(store: store) }
                )

                BodyMetricHistorySection(
                    weightPoints: weightPoints,
                    leanMassPoints: leanMassPoints,
                    bodyFatPoints: bodyFatPoints,
                    waistPoints: waistPoints,
                    stepsPoints: stepsPoints
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
}

private struct BodyMetricAveragesCard: View {
    let averages: BodyMetricAverages

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-Day Averages")
                .font(.headline)
            HStack(spacing: 12) {
                MetricChip(title: "Weight", value: averages.weightKg, unit: "kg")
                MetricChip(title: "Lean Mass", value: averages.muscleMass, unit: "kg")
            }
            HStack(spacing: 12) {
                MetricChip(title: "Body Fat", value: averages.bodyFatPercent, unit: "%")
                MetricChip(title: "Waist", value: averages.waistCm, unit: "cm")
            }
            MetricChip(title: "Steps", value: averages.steps, unit: "steps")
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
                Text("Syncs weight and steps from Apple Health (plus any available body measurements).")
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
    let weightPoints: [MetricPoint]
    let leanMassPoints: [MetricPoint]
    let bodyFatPoints: [MetricPoint]
    let waistPoints: [MetricPoint]
    let stepsPoints: [MetricPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
            BodyMetricChartCard(title: "Weight", unit: "kg", points: weightPoints, tint: .blue)
            BodyMetricChartCard(title: "Lean Mass", unit: "kg", points: leanMassPoints, tint: .teal)
            BodyMetricChartCard(title: "Body Fat", unit: "%", points: bodyFatPoints, tint: .orange)
            BodyMetricChartCard(title: "Waist", unit: "cm", points: waistPoints, tint: .red)
            BodyMetricChartCard(title: "Steps", unit: "steps", points: stepsPoints, tint: .green)
        }
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

    private func formattedValue(_ value: Double) -> String {
        if unit == "steps" {
            return "\(Int(value.rounded()))"
        }
        return value.cleanNumber
    }
}

private struct MetricChip: View {
    let title: String
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { "\($0.cleanNumber) \(unit)" } ?? "--")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
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
            BodyMetricValue(label: "Steps", value: entry.steps, unit: "steps")
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

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                MetricField(title: "Weight (kg)", value: $weightKg)
                MetricField(title: "Lean Mass (kg)", value: $muscleMass)
                MetricField(title: "Body Fat (%)", value: $bodyFat)
                MetricField(title: "Waist (cm)", value: $waist)
                MetricField(title: "Steps", value: $steps)
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
                                steps: Double(steps)
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
