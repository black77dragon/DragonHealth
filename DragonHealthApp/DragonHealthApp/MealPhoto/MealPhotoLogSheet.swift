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
    let startWithCameraOnAppear: Bool
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
    @State private var didAutoLaunchCamera = false
    @ScaledMetric(relativeTo: .body) private var sectionSpacing = 18
    @ScaledMetric(relativeTo: .body) private var cardPadding = 16
    @ScaledMetric(relativeTo: .body) private var heroImageHeight = 250
    @ScaledMetric(relativeTo: .body) private var buttonMinHeight = 52
    @ScaledMetric(relativeTo: .body) private var chipMinWidth = 140
    @ScaledMetric(relativeTo: .body) private var bottomBarHeight = 88

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

    private var hasDetectedItems: Bool {
        !draftItems.isEmpty
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

    private var selectedMealSlotName: String {
        guard let selectedMealSlotID,
              let slot = mealSlots.first(where: { $0.id == selectedMealSlotID }) else {
            return "Choose meal"
        }
        return slot.name
    }

    private var imageStatusTitle: String {
        if isAnalyzing {
            return "Analyzing your photo"
        }
        if hasDetectedItems {
            return "Foods detected"
        }
        if selectedImage != nil {
            return "Ready to detect"
        }
        return "Start with a meal photo"
    }

    private var imageStatusDetail: String {
        if isAnalyzing {
            return "Detection starts automatically after you capture or choose a photo."
        }
        if let parseError {
            return parseError
        }
        if hasDetectedItems {
            return "Review the detected foods, adjust anything needed, then save to \(selectedMealSlotName)."
        }
        if MealPhotoAIConfig.client() == nil {
            return "OpenAI API key missing. Add it in Manage > Integrations > Meal Photo AI."
        }
        return "Take a photo or choose one from your library. DragonHealth will run AI detection automatically."
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: chipMinWidth), spacing: 10, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    photoActionRow
                    photoHeroCard
                    detectionStatusCard

                    if selectedImage != nil {
                        mealSlotCard
                    }

                    if hasDetectedItems {
                        detectedFoodsSummaryCard

                        if !lowConfidenceItems.isEmpty {
                            reviewNeededCard
                        }

                        detectedFoodEditorSection
                    } else if !isAnalyzing {
                        emptyDraftCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, bottomBarHeight)
            }
            .font(.body)
            .scrollDismissesKeyboard(.interactively)
            .dynamicTypeSize(.xSmall ... .large)
            .navigationTitle("Photo Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
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
                if startWithCameraOnAppear, !didAutoLaunchCamera, selectedImage == nil, hasCamera {
                    didAutoLaunchCamera = true
                    showingCamera = true
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
                        prepareForNewPhoto(image)
                        showingCamera = false
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
            }
            .overlay(alignment: .bottom) {
                saveBar
            }
        }
    }

    private var photoActionRow: some View {
        HStack(spacing: 12) {
            takePhotoButton
            choosePhotoButton
        }
    }

    private var photoHeroCard: some View {
        Group {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "camera.macro")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("Capture your food first")
                        .font(.body.weight(.semibold))
                    Text("AI starts automatically after a photo is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: heroImageHeight, alignment: .leading)
                .padding(cardPadding)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var takePhotoButton: some View {
        Button {
            showingCamera = true
        } label: {
            MealPhotoActionButtonLabel(
                title: "Take Photo",
                systemImage: "camera",
                style: .primary,
                minHeight: buttonMinHeight
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasCamera)
    }

    private var choosePhotoButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
            MealPhotoActionButtonLabel(
                title: "Choose Photo",
                systemImage: "photo",
                style: .primary,
                minHeight: buttonMinHeight
            )
        }
        .buttonStyle(.plain)
    }

    private var detectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAnalyzing ? "sparkles.rectangle.stack" : "fork.knife.circle")
                    .font(.title3)
                    .foregroundStyle(parseError == nil ? Color.accentColor : Color.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text(imageStatusTitle)
                        .font(.body.weight(.semibold))
                    Text(imageStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(parseError == nil ? Color.secondary : Color.red)
                }

                Spacer(minLength: 0)
            }

            if isAnalyzing {
                ProgressView("Running AI food detection...")
                    .font(.footnote)
            } else if selectedImage != nil {
                Button {
                    analyzePhoto()
                } label: {
                    Label(hasDetectedItems ? "Run Again" : "Retry Detection", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(canAnalyze ? Color.accentColor : Color.secondary)
                .disabled(!canAnalyze)
            }
        }
        .padding(cardPadding)
        .background(backgroundColor(forError: parseError != nil), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var mealSlotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meal")
                .font(.body.weight(.semibold))
            Picker("Meal Slot", selection: $selectedMealSlotID) {
                ForEach(mealSlots) { slot in
                    Text(slot.name).tag(Optional(slot.id))
                }
            }
            .pickerStyle(.menu)
            Text("Detected items will be saved into \(selectedMealSlotName).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(cardPadding)
        .background(backgroundColor(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var detectedFoodsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Foods")
                .font(.body.weight(.semibold))

            Text("AI found \(draftItems.count) possible food item\(draftItems.count == 1 ? "" : "s"). Tap any card below to refine the details.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                ForEach(draftItems) { item in
                    MealPhotoDetectedSummaryChip(item: item)
                }
            }
        }
        .padding(cardPadding)
        .background(backgroundColor(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var reviewNeededCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review Needed")
                .font(.body.weight(.semibold))

            Text("Some items are low confidence. Confirm those before saving.")
                .font(.footnote)
                .foregroundStyle(.orange)

            ForEach(lowConfidenceItems) { item in
                Text("\(item.foodText): \((item.confidence * 100).rounded().cleanNumber)% confidence (\(MealPhotoConfidenceRAG(confidence: item.confidence).label))")
                    .font(.caption)
                    .foregroundStyle(MealPhotoConfidenceRAG(confidence: item.confidence).color)
            }

            Toggle("I reviewed low-confidence items", isOn: $lowConfidenceReviewed)
        }
        .padding(cardPadding)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var detectedFoodEditorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Items")
                .font(.body.weight(.semibold))

            ForEach($draftItems) { $item in
                MealPhotoDraftRow(
                    item: $item,
                    categories: categories,
                    foodItems: availableFoods,
                    units: units,
                    onDelete: {
                        deleteDraftItem(id: item.id)
                    }
                )
                .padding(cardPadding)
                .background(backgroundColor(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var emptyDraftCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No detected items yet")
                .font(.body.weight(.semibold))
            Text("Choose a photo to let AI identify the foods and prefill the draft for review.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(cardPadding)
        .background(backgroundColor(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if selectedImage != nil {
                Menu {
                    ForEach(mealSlots) { slot in
                        Button {
                            selectedMealSlotID = slot.id
                        } label: {
                            if selectedMealSlotID == slot.id {
                                Label(slot.name, systemImage: "checkmark")
                            } else {
                                Text(slot.name)
                            }
                        }
                    }
                } label: {
                    MealPhotoActionButtonLabel(
                        title: "Meal timing: \(selectedMealSlotName)",
                        systemImage: "clock",
                        style: .secondary,
                        minHeight: buttonMinHeight
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                guard let mealSlotID = selectedMealSlotID,
                      let mealSlot = mealSlots.first(where: { $0.id == mealSlotID }) else {
                    return
                }
                onSave(mealSlot, draftItems)
                dismiss()
            } label: {
                MealPhotoActionButtonLabel(
                    title: hasDetectedItems ? "Save to \(selectedMealSlotName)" : "Save",
                    systemImage: "checkmark",
                    style: .primary,
                    minHeight: buttonMinHeight
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)

            if !canSave, hasDetectedItems {
                Text(saveHintText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color.clear)
        .ignoresSafeArea(edges: .bottom)
    }

    private var saveHintText: String {
        if requiresLowConfidenceReview {
            return "Review low-confidence items before saving."
        }
        if draftItems.contains(where: { !isItemValid($0) }) {
            return "Complete each detected item before saving."
        }
        if selectedMealSlotID == nil {
            return "Choose a meal slot before saving."
        }
        return "Save is unavailable."
    }

    private func backgroundColor(forError isError: Bool = false) -> Color {
        isError ? Color.red.opacity(0.08) : Color(.secondarySystemGroupedBackground)
    }

    @MainActor
    private func prepareForNewPhoto(_ image: UIImage) {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        selectedImage = image
        selectedPhotoItem = nil
        draftItems = []
        parseError = nil
        lowConfidenceReviewed = false
        analyzePhoto(image)
    }

    @MainActor
    private func analyzePhoto(_ image: UIImage? = nil) {
        guard let image = image ?? selectedImage else { return }
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
                    image: image,
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
                prepareForNewPhoto(image)
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

private struct MealPhotoDetectedSummaryChip: View {
    let item: MealPhotoDraftItem

    private var rag: MealPhotoConfidenceRAG {
        MealPhotoConfidenceRAG(confidence: item.confidence)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.foodText)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 6) {
                Circle()
                    .fill(rag.color)
                    .frame(width: 8, height: 8)
                Text("\((item.confidence * 100).rounded().cleanNumber)% \(rag.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(rag.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum MealPhotoActionButtonStyle {
    case primary
    case secondary
}

private struct MealPhotoActionButtonLabel: View {
    let title: String
    let systemImage: String
    let style: MealPhotoActionButtonStyle
    let minHeight: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
        )
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .primary
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return Color.accentColor
        case .secondary:
            return Color(.secondarySystemGroupedBackground)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return .clear
        case .secondary:
            return Color(.separator).opacity(0.25)
        }
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
                item.portion = Portion.roundToIncrement(food.portionEquivalent, increment: portionIncrement)
                if let amountPerPortion = food.amountPerPortion, let unitID = food.unitID {
                    item.amountValue = amountPerPortion
                    item.amountUnitID = unitID
                }
                ensureDrinkUnitSelection()
            }
            .onChange(of: item.categoryID) { _, newCategoryID in
                guard let selectedFoodID = item.matchedFoodID,
                      let selectedFood = foodItems.first(where: { $0.id == selectedFoodID }) else {
                    ensureDrinkUnitSelection()
                    return
                }
                if selectedFood.categoryID != newCategoryID {
                    item.matchedFoodID = nil
                }
                ensureDrinkUnitSelection()
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
                if let value = Double(normalized), value > 0 {
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

    private func ensureDrinkUnitSelection() {
        guard isDrinkCategory else { return }
        if let unitID = item.amountUnitID,
           let symbol = units.first(where: { $0.id == unitID })?.symbol,
           DrinkRules.isDrinkUnitSymbol(symbol) {
            return
        }
        item.amountUnitID = drinkUnits.first(where: { $0.symbol.lowercased() == "ml" })?.id ?? drinkUnits.first?.id
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
