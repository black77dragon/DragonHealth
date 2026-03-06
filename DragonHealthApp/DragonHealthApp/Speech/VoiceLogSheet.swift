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
    @State private var autoDeleteOnPause: Bool = false
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
                            speech.autoDeleteOnPause = autoDeleteOnPause
                            speech.start(localeIdentifier: selectedLanguage.localeIdentifier)
                        } label: {
                            Label("Start", systemImage: "mic.circle.fill")
                        }
                        .glassButton(.text)
                        .disabled(speech.isRecording)

                        Button {
                            speech.stop()
                        } label: {
                            Label("End", systemImage: "stop.circle.fill")
                        }
                        .glassButton(.text)
                        .disabled(!speech.isRecording)

                        Button("Restart") {
                            transcriptText = ""
                            speech.autoDeleteOnPause = autoDeleteOnPause
                            speech.restart(localeIdentifier: selectedLanguage.localeIdentifier)
                        }
                        .glassButton(.text)
                        .disabled(speech.isRecording)
                    }

                    Toggle("Auto-delete on pause", isOn: $autoDeleteOnPause)
                        .disabled(speech.isRecording)

                    TextEditor(text: $transcriptText)
                        .frame(minHeight: 120)
                        .disabled(speech.isRecording)

                    Button("Parse Transcript") {
                        parseDraft()
                    }
                    .glassButton(.text)
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
                    .glassButton(.text)
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
                    .glassButton(.text)
                    .disabled(!canSave)
                }
            }
            .onReceive(speech.$transcript) { value in
                if speech.isRecording {
                    transcriptText = value
                }
            }
            .onAppear {
                speech.autoDeleteOnPause = autoDeleteOnPause
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

    private var selectedCategory: Core.Category? {
        guard let categoryID = item.categoryID else { return nil }
        return categories.first(where: { $0.id == categoryID })
    }

    private var isDrinkCategory: Bool {
        guard let selectedCategory else { return false }
        return DrinkRules.isDrinkCategory(selectedCategory)
    }

    private var drinkUnits: [FoodUnit] {
        DrinkRules.drinkUnits(from: units)
    }

    private var availableUnits: [FoodUnit] {
        isDrinkCategory ? drinkUnits : units
    }

    private var portionIncrement: Double {
        DrinkRules.portionIncrement(for: selectedCategory)
    }

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
                item.portion = Portion.roundToIncrement(food.portionEquivalent, increment: portionIncrement)
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
            .onChange(of: item.categoryID) { _, _ in
                guard isDrinkCategory else { return }
                if let unitID = item.amountUnitID,
                   let symbol = units.first(where: { $0.id == unitID })?.symbol,
                   DrinkRules.isDrinkUnitSymbol(symbol) {
                    return
                }
                item.amountUnitID = drinkUnits.first(where: { $0.symbol.lowercased() == "ml" })?.id ?? drinkUnits.first?.id
            }

            HStack {
                TextField("Amount", text: amountBinding)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $item.amountUnitID) {
                    Text("None").tag(UUID?.none)
                    ForEach(availableUnits) { unit in
                        Text(unit.symbol).tag(Optional(unit.id))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: item.amountUnitID) { _, _ in
                syncPortionFromAmount()
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
                    item.amountValue = roundedAmountValue(value)
                    syncPortionFromAmount()
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
                    item.portion = Portion.roundToIncrement(value, increment: portionIncrement)
                } else {
                    item.portion = nil
                }
            }
        )
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if isDrinkCategory {
            let symbol = units.first(where: { $0.id == item.amountUnitID })?.symbol.lowercased()
            if symbol == "ml" {
                return value.rounded()
            }
            return Portion.roundToIncrement(value, increment: Portion.drinkIncrement)
        }
        return Portion.roundToIncrement(value)
    }

    private func syncPortionFromAmount() {
        guard isDrinkCategory else { return }
        guard let amountValue = item.amountValue else { return }
        let symbol = units.first(where: { $0.id == item.amountUnitID })?.symbol
        guard let liters = DrinkRules.liters(from: amountValue, unitSymbol: symbol) else { return }
        item.portion = Portion.roundToIncrement(liters, increment: Portion.drinkIncrement)
    }

    private var missingFields: [String] {
        var missing: [String] = []
        if item.categoryID == nil { missing.append("category") }
        if item.portion == nil { missing.append("portion") }
        if item.foodText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("food") }
        return missing
    }
}
