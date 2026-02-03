import Core
import SwiftUI

private enum VoiceLogLanguage: String, CaseIterable, Identifiable {
    case englishUS
    case englishUK
    case german

    var id: String { rawValue }

    var label: String {
        switch self {
        case .englishUS: return "English (US)"
        case .englishUK: return "English (UK)"
        case .german: return "Deutsch"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .englishUS: return "en-US"
        case .englishUK: return "en-GB"
        case .german: return "de-DE"
        }
    }
}

struct VoiceLogSheet: View {
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [FoodUnit]
    let onSave: (MealSlot, [VoiceDraftItem], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCaptureService()
    @State private var selectedLanguage: VoiceLogLanguage = .englishUS
    @State private var transcriptText: String = ""
    @State private var draftItems: [VoiceDraftItem] = []
    @State private var selectedMealSlotID: UUID?
    @State private var parseError: String?

    private let parser = VoiceDraftParser()

    private var canSave: Bool {
        guard selectedMealSlotID != nil else { return false }
        guard !draftItems.isEmpty else { return false }
        return draftItems.allSatisfy { isItemValid($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Recognition", selection: $selectedLanguage) {
                        ForEach(VoiceLogLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(speech.isRecording)
                }

                Section("Recording") {
                    HStack(spacing: 12) {
                        Button {
                            if speech.isRecording {
                                speech.stop()
                            } else {
                                speech.start(localeIdentifier: selectedLanguage.localeIdentifier)
                            }
                        } label: {
                            Label(speech.isRecording ? "Stop" : "Start", systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Re-start") {
                            transcriptText = ""
                            speech.restart(localeIdentifier: selectedLanguage.localeIdentifier)
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(text: $transcriptText)
                        .frame(minHeight: 120)
                        .disabled(speech.isRecording)

                    Button("Parse Transcript") {
                        parseDraft()
                    }
                    .disabled(speech.isRecording || transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let errorMessage = speech.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    if let parseError {
                        Text(parseError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if !draftItems.isEmpty {
                    Section("Meal") {
                        Picker("Meal Slot", selection: $selectedMealSlotID) {
                            ForEach(mealSlots) { slot in
                                Text(slot.name).tag(Optional(slot.id))
                            }
                        }
                    }

                    ForEach($draftItems) { $item in
                        Section("Item") {
                            VoiceDraftRow(
                                item: $item,
                                categories: categories,
                                foodItems: foodItems,
                                units: units
                            )
                        }
                    }
                } else {
                    Section("Draft") {
                        Text("No draft items yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Voice Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mealSlotID = selectedMealSlotID,
                              let mealSlot = mealSlots.first(where: { $0.id == mealSlotID }) else {
                            return
                        }
                        onSave(mealSlot, draftItems, transcriptText)
                        speech.stop()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onReceive(speech.$transcript) { value in
                if speech.isRecording {
                    transcriptText = value
                }
            }
            .onAppear {
                if selectedMealSlotID == nil {
                    selectedMealSlotID = mealSlots.first?.id
                }
            }
            .onDisappear {
                speech.stop()
            }
        }
    }

    private func parseDraft() {
        parseError = nil
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parseError = "Transcript is empty."
            return
        }

        let draft = parser.parse(
            transcript: trimmed,
            categories: categories,
            foodItems: foodItems,
            units: units,
            mealSlots: mealSlots
        )

        guard !draft.items.isEmpty else {
            parseError = "Could not detect any food items."
            return
        }

        draftItems = draft.items
        selectedMealSlotID = draft.mealSlotID ?? selectedMealSlotID ?? mealSlots.first?.id
    }

    private func isItemValid(_ item: VoiceDraftItem) -> Bool {
        guard !item.foodText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard item.categoryID != nil else { return false }
        guard let portion = item.portion, portion > 0 else { return false }
        return true
    }
}

private struct VoiceDraftRow: View {
    @Binding var item: VoiceDraftItem
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let units: [FoodUnit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Food", text: $item.foodText)

            Picker("Food Library", selection: $item.matchedFoodID) {
                Text("Custom").tag(UUID?.none)
                ForEach(foodItems) { food in
                    Text(food.name).tag(Optional(food.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: item.matchedFoodID) { _, newValue in
                guard let newValue,
                      let food = foodItems.first(where: { $0.id == newValue }) else { return }
                item.foodText = food.name
                item.categoryID = food.categoryID
                item.portion = Portion.roundToIncrement(food.portionEquivalent)
                if let amountPerPortion = food.amountPerPortion, let unitID = food.unitID {
                    item.amountValue = amountPerPortion
                    item.amountUnitID = unitID
                }
            }

            Picker("Category", selection: $item.categoryID) {
                Text("Select").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }

            HStack {
                TextField("Amount", text: amountBinding)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $item.amountUnitID) {
                    Text("None").tag(UUID?.none)
                    ForEach(units) { unit in
                        Text(unit.symbol).tag(Optional(unit.id))
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Portion", text: portionBinding)
                .keyboardType(.decimalPad)

            if !missingFields.isEmpty {
                Text("Missing: \(missingFields.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { item.amountValue?.cleanNumber ?? "" },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized) {
                    item.amountValue = value
                } else {
                    item.amountValue = nil
                }
            }
        )
    }

    private var portionBinding: Binding<String> {
        Binding(
            get: { item.portion?.cleanNumber ?? "" },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized) {
                    item.portion = Portion.roundToIncrement(value)
                } else {
                    item.portion = nil
                }
            }
        )
    }

    private var missingFields: [String] {
        var missing: [String] = []
        if item.categoryID == nil { missing.append("category") }
        if item.portion == nil { missing.append("portion") }
        if item.foodText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("food") }
        return missing
    }
}
