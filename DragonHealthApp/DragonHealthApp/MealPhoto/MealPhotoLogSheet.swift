import Core
import PhotosUI
import SwiftUI
import UIKit

private enum MealPhotoConfidencePolicy {
    static let reviewThreshold: Double = 0.60
    static let highConfidenceThreshold: Double = 0.80
}

private enum MealPhotoConfidenceRAG {
    case red
    case amber
    case green

    init(confidence: Double) {
        let clamped = min(max(confidence, 0), 1)
        if clamped < MealPhotoConfidencePolicy.reviewThreshold {
            self = .red
        } else if clamped < MealPhotoConfidencePolicy.highConfidenceThreshold {
            self = .amber
        } else {
            self = .green
        }
    }

    var label: String {
        switch self {
        case .red: return "RED"
        case .amber: return "AMBER"
        case .green: return "GREEN"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .amber: return .orange
        case .green: return .green
        }
    }
}

struct MealPhotoLogSheet: View {
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [FoodUnit]
    let preselectedMealSlotID: UUID?
    let onSave: (MealSlot, [MealPhotoDraftItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMealSlotID: UUID?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var draftItems: [MealPhotoDraftItem] = []
    @State private var parseError: String?
    @State private var isAnalyzing = false
    @State private var showingCamera = false
    @State private var lowConfidenceReviewed = false
    @State private var analysisTask: Task<Void, Never>?

    private var availableFoods: [FoodItem] {
        foodItems.filter { !$0.kind.isComposite }
    }

    private var canSave: Bool {
        guard selectedMealSlotID != nil else { return false }
        guard !draftItems.isEmpty else { return false }
        guard !requiresLowConfidenceReview else { return false }
        return draftItems.allSatisfy { isItemValid($0) }
    }

    private var canAnalyze: Bool {
        selectedImage != nil && !isAnalyzing && MealPhotoAIConfig.client() != nil
    }

    private var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var lowConfidenceItems: [MealPhotoDraftItem] {
        draftItems.filter { $0.confidence < MealPhotoConfidencePolicy.reviewThreshold }
    }

    private var requiresLowConfidenceReview: Bool {
        !lowConfidenceItems.isEmpty && !lowConfidenceReviewed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Take or choose a meal photo to start.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .glassButton(.text)
                        .disabled(!hasCamera)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Label("Choose Photo", systemImage: "photo")
                                .glassLabel(.text)
                        }
                    }
                }

                Section("AI Analysis") {
                    if MealPhotoAIConfig.client() == nil {
                        Text("OpenAI API key missing. Add it in Manage > Integrations > Meal Photo AI.")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button {
                        analyzePhoto()
                    } label: {
                        Label("AI Detect Foods", systemImage: "sparkles")
                    }
                    .glassButton(.text)
                    .disabled(!canAnalyze)

                    if isAnalyzing {
                        ProgressView("Analyzing image...")
                            .font(.footnote)
                    }

                    if let parseError {
                        Text(parseError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    if !draftItems.isEmpty {
                        Text("Detected \(draftItems.count) possible food item\(draftItems.count == 1 ? "" : "s").")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                if !draftItems.isEmpty {
                    if !lowConfidenceItems.isEmpty {
                        Section("Review Needed") {
                            Text("Some detected items are low confidence. Review before saving.")
                                .font(.footnote)
                                .foregroundStyle(.orange)

                            ForEach(lowConfidenceItems) { item in
                                Text("\(item.foodText): \((item.confidence * 100).rounded().cleanNumber)% confidence (\(MealPhotoConfidenceRAG(confidence: item.confidence).label))")
                                    .font(.caption)
                                    .foregroundStyle(MealPhotoConfidenceRAG(confidence: item.confidence).color)
                            }

                            Toggle("I reviewed low-confidence items", isOn: $lowConfidenceReviewed)
                        }
                    }

                    Section("Meal") {
                        Picker("Meal Slot", selection: $selectedMealSlotID) {
                            ForEach(mealSlots) { slot in
                                Text(slot.name).tag(Optional(slot.id))
                            }
                        }
                    }

                    ForEach($draftItems) { $item in
                        Section("Item") {
                            MealPhotoDraftRow(
                                item: $item,
                                categories: categories,
                                foodItems: availableFoods,
                                units: units,
                                onDelete: {
                                    deleteDraftItem(id: item.id)
                                }
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
            .navigationTitle("Photo Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mealSlotID = selectedMealSlotID,
                              let mealSlot = mealSlots.first(where: { $0.id == mealSlotID }) else {
                            return
                        }
                        onSave(mealSlot, draftItems)
                        dismiss()
                    }
                    .glassButton(.text)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedMealSlotID == nil {
                    if let preselectedMealSlotID,
                       mealSlots.contains(where: { $0.id == preselectedMealSlotID }) {
                        selectedMealSlotID = preselectedMealSlotID
                    } else {
                        selectedMealSlotID = mealSlots.first?.id
                    }
                }
            }
            .onDisappear {
                analysisTask?.cancel()
                analysisTask = nil
            }
            .task(id: selectedPhotoItem) {
                await loadSelectedPhoto()
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        analysisTask?.cancel()
                        analysisTask = nil
                        isAnalyzing = false
                        selectedImage = image
                        selectedPhotoItem = nil
                        showingCamera = false
                        draftItems = []
                        parseError = nil
                        lowConfidenceReviewed = false
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
            }
        }
    }

    private func analyzePhoto() {
        guard let selectedImage else { return }
        guard let client = MealPhotoAIConfig.client() else {
            parseError = "OpenAI API key missing."
            return
        }

        parseError = nil
        isAnalyzing = true

        analysisTask?.cancel()
        analysisTask = Task {
            do {
                let detections = try await client.analyzeMeal(
                    image: selectedImage,
                    foodNames: availableFoods.map(\.name),
                    categoryNames: categories.map(\.name)
                )
                let builder = MealPhotoDraftBuilder(categories: categories, foodItems: availableFoods, units: units)
                let resolvedItems = builder.makeDraftItems(from: detections)

                await MainActor.run {
                    analysisTask = nil
                    isAnalyzing = false
                    if resolvedItems.isEmpty {
                        parseError = "Could not detect any food items."
                        draftItems = []
                        lowConfidenceReviewed = false
                        return
                    }
                    draftItems = resolvedItems
                    lowConfidenceReviewed = false
                    if selectedMealSlotID == nil {
                        selectedMealSlotID = preselectedMealSlotID ?? mealSlots.first?.id
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    analysisTask = nil
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    analysisTask = nil
                    isAnalyzing = false
                    parseError = userMessage(for: error)
                }
            }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        analysisTask?.cancel()
        analysisTask = nil
        await MainActor.run {
            isAnalyzing = false
        }
        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    parseError = "Unable to load selected image."
                }
                return
            }
            await MainActor.run {
                selectedImage = image
                draftItems = []
                parseError = nil
                lowConfidenceReviewed = false
            }
        } catch {
            await MainActor.run {
                parseError = "Photo load failed: \(error.localizedDescription)"
            }
        }
    }

    private func userMessage(for error: Error) -> String {
        if let clientError = error as? OpenAIMealPhotoClient.ClientError {
            return clientError.errorDescription ?? "Photo analysis failed."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection. Please reconnect and retry."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return "Network error: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    private func isItemValid(_ item: MealPhotoDraftItem) -> Bool {
        guard !item.foodText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard item.categoryID != nil else { return false }
        guard let portion = item.portion, portion > 0 else { return false }
        return true
    }

    private func deleteDraftItem(id: UUID) {
        draftItems.removeAll { $0.id == id }
        lowConfidenceReviewed = false
    }
}

private struct MealPhotoDraftRow: View {
    @Binding var item: MealPhotoDraftItem
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let units: [FoodUnit]
    let onDelete: () -> Void
    @State private var showingFoodPicker = false
    private var isLowConfidence: Bool {
        item.confidence < MealPhotoConfidencePolicy.reviewThreshold
    }
    private var confidenceRAG: MealPhotoConfidenceRAG {
        MealPhotoConfidenceRAG(confidence: item.confidence)
    }
    private var selectedCategory: Core.Category? {
        guard let categoryID = item.categoryID else { return nil }
        return categories.first(where: { $0.id == categoryID })
    }
    private var selectedFoodItem: FoodItem? {
        guard let foodID = item.matchedFoodID else { return nil }
        return foodItems.first(where: { $0.id == foodID })
    }
    private var foodSelectionSummary: String {
        if let selectedFoodItem {
            return selectedFoodItem.name
        }
        let detected = item.foodText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detected.isEmpty {
            return detected
        }
        return selectedCategory == nil ? "Choose category first" : "Choose food"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Category", selection: $item.categoryID) {
                Text("Select").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 2)

            Button {
                showingFoodPicker = true
            } label: {
                HStack {
                    Text("Food Library")
                    Spacer()
                    Text(foodSelectionSummary)
                        .foregroundStyle(item.matchedFoodID == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(selectedCategory == nil)
            .padding(.vertical, 2)
            .sheet(isPresented: $showingFoodPicker) {
                NavigationStack {
                    MealPhotoFoodPicker(
                        category: selectedCategory,
                        foodItems: foodItems,
                        selectedFoodID: $item.matchedFoodID
                    )
                }
            }
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
            .onChange(of: item.categoryID) { _, newCategoryID in
                guard let selectedFoodID = item.matchedFoodID,
                      let selectedFood = foodItems.first(where: { $0.id == selectedFoodID }) else {
                    return
                }
                if selectedFood.categoryID != newCategoryID {
                    item.matchedFoodID = nil
                }
            }

            if item.matchedFoodID == nil {
                TextField("Custom Food Name", text: $item.foodText)
                    .padding(.vertical, 2)
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

            HStack(spacing: 8) {
                Text("AI confidence: \((item.confidence * 100).rounded().cleanNumber)%")
                Text(confidenceRAG.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(confidenceRAG.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(confidenceRAG.color.opacity(0.15), in: Capsule())
            }
            .font(.caption)
            .foregroundStyle(confidenceRAG.color)

            if isLowConfidence {
                Text("Low confidence: verify food and portion before saving.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !missingFields.isEmpty {
                Text("Missing: \(missingFields.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("⛔️ Delete Item")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { item.amountValue?.cleanNumber ?? "" },
            set: { newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized), value > 0 {
                    item.amountValue = Portion.roundToIncrement(value)
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
                if let value = Double(normalized), value > 0 {
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

private enum MealPhotoFoodPickerFilter: String, CaseIterable, Identifiable {
    case all
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
        }
    }
}

private struct MealPhotoFoodPicker: View {
    let category: Core.Category?
    let foodItems: [FoodItem]
    @Binding var selectedFoodID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter: MealPhotoFoodPickerFilter = .all

    private var categoryFoods: [FoodItem] {
        guard let categoryID = category?.id else { return [] }
        return foodItems
            .filter { $0.categoryID == categoryID }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private var filteredFoods: [FoodItem] {
        var results = categoryFoods
        if filter == .favorites {
            results = results.filter(\.isFavorite)
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return results }
        return results.filter { item in
            item.name.localizedStandardContains(term) || (item.notes ?? "").localizedStandardContains(term)
        }
    }

    var body: some View {
        List {
            if category == nil {
                Section {
                    Text("Select a category first. Food choices are filtered by the selected category.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Filter") {
                    Picker("Filter", selection: $filter) {
                        ForEach(MealPhotoFoodPickerFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Food Items") {
                    Button {
                        selectedFoodID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Custom")
                            Spacer()
                            if selectedFoodID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if filteredFoods.isEmpty {
                        Text("No foods match this category/filter.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredFoods) { food in
                            Button {
                                selectedFoodID = food.id
                                dismiss()
                            } label: {
                                HStack {
                                    Text(food.name)
                                    Spacer()
                                    if selectedFoodID == food.id {
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
        .environment(\.defaultMinListRowHeight, 50)
        .navigationTitle(category?.name ?? "Food Library")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search foods"
        )
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
