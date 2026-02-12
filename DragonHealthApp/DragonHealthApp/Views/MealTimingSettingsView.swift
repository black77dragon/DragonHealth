import SwiftUI
import Core

struct MealTimingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var timings: [Core.MealSlotTiming] = []

    private var orderedSlots: [Core.MealSlot] {
        store.mealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    var body: some View {
        Form {
            Section("Auto Meal Slot") {
                Text("The + button uses these windows to pick the default meal slot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Timing Windows") {
                if orderedSlots.isEmpty {
                    Text("No meal slots available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sequence follows the meal slot order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(orderedSlots.indices, id: \.self) { index in
                        timingRow(for: index)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .glassButton(.text)
            }
        }
        .navigationTitle("Meal Timing")
        .onAppear {
            refreshTimings()
        }
        .onChange(of: store.mealSlots) { _, _ in
            refreshTimings()
        }
        .onChange(of: store.settings) { _, _ in
            refreshTimings()
        }
    }

    @ViewBuilder
    private func timingRow(for index: Int) -> some View {
        if index < timings.count {
            let slot = orderedSlots[index]
            let accent = accentColor(for: index)
            let includeInAuto = timings[index].includeInAuto

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(accent, in: Circle())
                        Label(slot.name, systemImage: "fork.knife")
                            .font(.headline)
                    }
                    Spacer()
                    if includeInAuto {
                        Text(formattedTime(timings[index].startMinutes))
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }

                Toggle("Include in auto meal slot", isOn: Binding(
                    get: { includeInAuto },
                    set: { newValue in
                        updateIncludeInAuto(index: index, value: newValue)
                    }
                ))
                .tint(accent)

                if includeInAuto {
                    let startMinutes = timings[index].startMinutes
                    let endMinutes = windowEndMinutes(for: index)
                    let range = sliderRange(for: index)
                    let span = range.upperBound - range.lowerBound
                    let isLockedRange = span < 1
                    let step = max(1, min(5, Int(span)))

                    HStack {
                        Text("Start time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { dateFromMinutes(startMinutes) },
                                set: { newValue in
                                    updateStartMinutes(index: index, value: minutesFromDate(newValue))
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }

                    if isLockedRange {
                        Slider(
                            value: Binding(
                                get: { Double(timings[index].startMinutes) },
                                set: { newValue in
                                    updateStartMinutes(index: index, value: Int(newValue.rounded()))
                                }
                            ),
                            in: range
                        )
                        .tint(accent)
                        .disabled(true)
                        Text("Tight window. Adjust neighboring meals to expand.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Slider(
                            value: Binding(
                                get: { Double(timings[index].startMinutes) },
                                set: { newValue in
                                    updateStartMinutes(index: index, value: Int(newValue.rounded()))
                                }
                            ),
                            in: range,
                            step: Double(step)
                        )
                        .tint(accent)
                    }

                    Text("Window: \(formattedTime(startMinutes)) - \(formattedTime(endMinutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Excluded from auto selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), accent.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
    }

    private func sliderRange(for index: Int) -> ClosedRange<Double> {
        guard timings.count > 1 else { return 0...1439 }
        if index == 0 {
            return 0...1439
        }
        let lower: Int
        let upper: Int

        if let previousIncluded = previousIncludedIndex(before: index) {
            lower = min(1439, timings[previousIncluded].startMinutes + 1)
        } else {
            lower = 0
        }

        if let nextIncluded = nextIncludedIndex(after: index) {
            upper = max(0, timings[nextIncluded].startMinutes - 1)
        } else {
            upper = 1439
        }

        let safeLower = min(max(lower, 0), 1439)
        let safeUpper = max(safeLower, min(max(upper, 0), 1439))
        return Double(safeLower)...Double(safeUpper)
    }

    private func previousIncludedIndex(before index: Int) -> Int? {
        guard index > 0 else { return nil }
        for idx in stride(from: index - 1, through: 0, by: -1) {
            if timings[idx].includeInAuto {
                return idx
            }
        }
        return nil
    }

    private func nextIncludedIndex(after index: Int) -> Int? {
        guard index + 1 < timings.count else { return nil }
        for idx in (index + 1)..<timings.count {
            if timings[idx].includeInAuto {
                return idx
            }
        }
        return nil
    }

    private func windowEndMinutes(for index: Int) -> Int {
        guard !timings.isEmpty else { return 0 }
        let includedIndices = timings.indices.filter { timings[$0].includeInAuto }
        guard let includedPosition = includedIndices.firstIndex(of: index) else {
            let nextIndex = min(index + 1, timings.count - 1)
            return timings[nextIndex].startMinutes
        }
        if includedIndices.count == 1 {
            return timings[index].startMinutes
        }
        let nextIncludedIndex = includedIndices[(includedPosition + 1) % includedIndices.count]
        return timings[nextIncludedIndex].startMinutes
    }

    private func refreshTimings() {
        timings = store.resolvedMealSlotTimings()
    }

    private func resetToDefaults() {
        let defaults = store.defaultMealSlotTimings()
        timings = defaults
        persistTimings()
    }

    private func updateStartMinutes(index: Int, value: Int) {
        guard index < timings.count else { return }
        if index == 0 {
            let clamped = min(max(value, 0), 1439)
            timings[index].startMinutes = clamped
            adjustFollowingStarts(from: index)
        } else {
            let range = sliderRange(for: index)
            let clamped = min(max(value, Int(range.lowerBound)), Int(range.upperBound))
            timings[index].startMinutes = clamped
        }
        persistTimings()
    }

    private func updateIncludeInAuto(index: Int, value: Bool) {
        guard index < timings.count else { return }
        timings[index].includeInAuto = value
        persistTimings()
    }

    private func adjustFollowingStarts(from index: Int) {
        guard index < timings.count else { return }
        var previous = timings[index].startMinutes
        let minimumGap = 1
        for nextIndex in (index + 1)..<timings.count {
            guard timings[nextIndex].includeInAuto else { continue }
            let minStart = min(previous + minimumGap, 1439)
            if timings[nextIndex].startMinutes < minStart {
                timings[nextIndex].startMinutes = minStart
            }
            previous = timings[nextIndex].startMinutes
        }
    }

    private func persistTimings() {
        let cleaned = timings.map { timing in
            Core.MealSlotTiming(
                slotID: timing.slotID,
                startMinutes: min(max(timing.startMinutes, 0), 1439),
                includeInAuto: timing.includeInAuto
            )
        }
        updateSettingsValue { $0.mealSlotTimings = cleaned }
    }

    private func updateSettingsValue(_ update: (inout Core.AppSettings) -> Void) {
        var updated = store.settings
        update(&updated)
        guard updated != store.settings else { return }
        Task { await store.updateSettings(updated) }
    }

    private func formattedTime(_ minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let date = store.appCalendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return store.appCalendar.date(from: components) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = store.appCalendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func accentColor(for index: Int) -> Color {
        let hues: [Double] = [0.05, 0.12, 0.18, 0.35, 0.55, 0.7, 0.9]
        let hue = hues[index % hues.count]
        return Color(hue: hue, saturation: 0.75, brightness: 0.9)
    }
}
