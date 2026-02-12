import SwiftUI
import Core
import PhotosUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
    @State private var showingAddTypePicker = false
    @State private var addKind: FoodItemKind = .single
    @State private var editingItem: FoodItem?
    @State private var searchText = ""

    var body: some View {
        List {
            if !filteredFavorites.isEmpty {
                Section("Favorites") {
                    ForEach(filteredFavorites) { item in
                        foodRow(for: item)
                    }
                    .onDelete { indices in
                        delete(indices, filter: { $0.isFavorite })
                    }
                }
            }

            Section("All Foods") {
                if store.foodItems.isEmpty {
                    Text("No foods yet. Add items to build your library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if filteredAllFoods.isEmpty {
                    Text("No foods match your search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAllFoods) { item in
                        foodRow(for: item)
                    }
                    .onDelete { indices in
                        delete(indices, filter: { _ in true })
                    }
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTypePicker = true
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .glassButton(.icon)
            }
        }
        .sheet(isPresented: $showingAdd) {
            FoodEntrySheet(
                categories: store.categories,
                units: store.units,
                allItems: store.foodItems,
                initialKind: addKind
            ) { item in
                Task { await store.saveFoodItem(item) }
            }
        }
        .sheet(item: $editingItem) { item in
            FoodEntrySheet(
                categories: store.categories,
                units: store.units,
                allItems: store.foodItems,
                item: item
            ) { updatedItem in
                Task { await store.saveFoodItem(updatedItem) }
            }
        }
        .confirmationDialog("New Library Item", isPresented: $showingAddTypePicker, titleVisibility: .visible) {
            Button("Food Item") {
                addKind = .single
                showingAdd = true
            }
            Button("Composite Food") {
                addKind = .composite
                showingAdd = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to add.")
        }
    }

    private func categoryName(for id: UUID) -> String {
        store.categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.units.first(where: { $0.id == id })?.symbol
    }

    private var filteredFavorites: [FoodItem] {
        store.foodItems.filter { $0.isFavorite }.filter(matchesSearch)
    }

    private var filteredAllFoods: [FoodItem] {
        store.foodItems.filter(matchesSearch)
    }

    private func matchesSearch(_ item: FoodItem) -> Bool {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categoryName(for: item.categoryID)
        let notes = item.notes ?? ""
        return item.name.localizedStandardContains(term)
            || category.localizedStandardContains(term)
            || notes.localizedStandardContains(term)
    }

    private func delete(_ indices: IndexSet, filter: (FoodItem) -> Bool) {
        let items = store.foodItems.filter(filter)
        for index in indices {
            guard index < items.count else { continue }
            let item = items[index]
            Task { await store.deleteFoodItem(item) }
        }
    }

    @ViewBuilder
    private func foodRow(for item: FoodItem) -> some View {
        FoodItemRow(item: item, categoryName: categoryName(for: item.categoryID), unitSymbol: unitSymbol(for: item.unitID))
            .contentShape(Rectangle())
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
            .onTapGesture {
                editingItem = item
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    editingItem = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }
}

struct FoodItemRow: View {
    let item: FoodItem
    let categoryName: String
    var unitSymbol: String? = nil
    var showsFavorite: Bool = true
    var thumbnailSize: CGFloat = 36
    var verticalPadding: CGFloat = 2
    @State private var showingPhotoCredit = false

    var body: some View {
        let detailText = detailLine()
        let showsUnsplashCredit = item.foodImageAttribution?.source == .unsplash
        HStack(spacing: 8) {
            FoodThumbnailView(imagePath: item.imagePath, remoteURL: item.imageRemoteURL, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout)
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if showsUnsplashCredit {
                Button {
                    showingPhotoCredit = true
                } label: {
                    Text("®")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .glassButton(.icon)
                .accessibilityLabel("Unsplash photo credit")
            }
            if showsFavorite, item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, verticalPadding)
        .sheet(isPresented: $showingPhotoCredit) {
            if let attribution = item.foodImageAttribution {
                FoodPhotoCreditSheet(attribution: attribution)
            }
        }
    }

    private func detailLine() -> String {
        if item.kind.isComposite {
            var parts: [String] = [
                "Composite",
                "\(item.compositeComponents.count) component\(item.compositeComponents.count == 1 ? "" : "s")"
            ]
            if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !notes.isEmpty {
                parts.append("Notes: \(notes)")
            }
            return parts.joined(separator: " • ")
        }
        var parts: [String] = [
            categoryName,
            "\(item.portionEquivalent.cleanNumber) portion"
        ]
        if let amountPerPortion = item.amountPerPortion,
           let unitSymbol {
            parts.append("1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)")
        }
        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            parts.append("Notes: \(notes)")
        }
        return parts.joined(separator: " • ")
    }
}

struct FoodThumbnailView: View {
    let imagePath: String?
    let remoteURL: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
            if let remoteURL, let url = URL(string: remoteURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackImageView()
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallbackImageView()
                    }
                }
            } else if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackImageView()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func loadImage() -> UIImage? {
        guard let imagePath else { return nil }
        let url = FoodImageStorage.url(for: imagePath)
        return UIImage(contentsOfFile: url.path)
    }

    @ViewBuilder
    private func fallbackImageView() -> some View {
        Image(systemName: "photo")
            .font(.system(size: size * 0.45, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

private struct FoodEntrySheet: View {
    private enum PhotoSelectionKind {
        case none
        case local
        case remote
    }

    private enum PhotoSource: String, CaseIterable, Identifiable {
        case local = "Local"
        case unsplash = "Unsplash"

        var id: String { rawValue }
    }

    private struct CompositeComponentDraft: Identifiable {
        let id: UUID
        var foodItemID: UUID?
        var portionMultiplier: Double

        init(id: UUID = UUID(), foodItemID: UUID? = nil, portionMultiplier: Double = 1.0) {
            self.id = id
            self.foodItemID = foodItemID
            self.portionMultiplier = portionMultiplier
        }
    }

    private struct ComponentPickerContext: Identifiable {
        let id: UUID
    }

    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let allItems: [FoodItem]
    let existingItem: FoodItem?
    let initialKind: FoodItemKind
    let onSave: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchModel = FoodImageSearchModel()
    @State private var name: String
    @State private var itemKind: FoodItemKind
    @State private var categoryID: UUID?
    @State private var portion: Double
    @State private var amountText: String
    @State private var unitID: UUID?
    @State private var components: [CompositeComponentDraft]
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var existingImagePath: String?
    @State private var existingAttribution: FoodImageAttribution?
    @State private var selectedAttribution: FoodImageAttribution?
    @State private var photoSelectionKind: PhotoSelectionKind = .none
    @State private var isDownloadingRemote = false
    @State private var downloadError: String?
    @State private var removeExistingImage = false
    @State private var photoSource: PhotoSource = .local
    @State private var componentPickerContext: ComponentPickerContext?
    private let compactRowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

    init(
        categories: [Core.Category],
        units: [Core.FoodUnit],
        allItems: [FoodItem],
        item: FoodItem? = nil,
        initialKind: FoodItemKind = .single,
        onSave: @escaping (FoodItem) -> Void
    ) {
        self.categories = categories
        self.units = units
        self.allItems = allItems
        self.existingItem = item
        self.initialKind = initialKind
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _itemKind = State(initialValue: item?.kind ?? initialKind)
        _categoryID = State(initialValue: item?.categoryID)
        _portion = State(initialValue: item?.portionEquivalent ?? 1.0)
        _amountText = State(initialValue: item?.amountPerPortion.map { $0.cleanNumber } ?? "")
        _unitID = State(initialValue: item?.unitID)
        _components = State(initialValue: item?.compositeComponents.map {
            CompositeComponentDraft(foodItemID: $0.foodItemID, portionMultiplier: max(0.1, $0.portionMultiplier))
        } ?? [])
        _notes = State(initialValue: item?.notes ?? "")
        _isFavorite = State(initialValue: item?.isFavorite ?? false)
        _existingImagePath = State(initialValue: item?.imagePath)
        _existingAttribution = State(initialValue: item?.foodImageAttribution)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            FoodPhotoPreview(
                                image: selectedImage,
                                remoteURL: (selectedAttribution ?? existingAttribution)?.remoteURL
                            )
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Source")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Source", selection: $photoSource) {
                                    ForEach(PhotoSource.allCases) { source in
                                        Text(source.rawValue).tag(source)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if photoSource == .local {
                            HStack(spacing: 10) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    Label("Choose Photo", systemImage: "photo")
                                        .glassLabel(.text)
                                }
                                if shouldShowRemovePhoto {
                                    Button(role: .destructive) {
                                        clearSelectedPhoto()
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    .glassButton(.text)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Search Unsplash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("Search food photos", text: $searchModel.query)
                                        .textInputAutocapitalization(.words)
                                        .autocorrectionDisabled()
                                        .submitLabel(.search)
                                        .onSubmit {
                                            Task { await searchModel.search() }
                                        }
                                        .textFieldStyle(.roundedBorder)
                                    Button("Search") {
                                        Task { await searchModel.search() }
                                    }
                                    .glassButton(.compact)
                                    .disabled(searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }

                                if !searchModel.isConfigured {
                                    Text("Unsplash API key is not configured.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if searchModel.isLoading {
                                    ProgressView("Searching…")
                                        .font(.caption)
                                } else if let errorMessage = searchModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if isDownloadingRemote {
                                    ProgressView("Downloading photo…")
                                        .font(.caption)
                                } else if let downloadError {
                                    Text(downloadError)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if !searchModel.results.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHGrid(rows: [GridItem(.fixed(80))], spacing: 12) {
                                            ForEach(searchModel.results) { photo in
                                                Button {
                                                    selectRemotePhoto(photo)
                                                } label: {
                                                    UnsplashResultCell(
                                                        photo: photo,
                                                        isSelected: selectedAttribution?.sourceID == photo.id
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(isDownloadingRemote)
                                            }
                                        }
                                        .frame(height: 90)
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        if let attribution = selectedAttribution ?? existingAttribution {
                            FoodPhotoAttributionView(attribution: attribution)
                        }
                    }
                }

                Section("Type") {
                    Picker("Item Type", selection: $itemKind) {
                        Text("Food").tag(FoodItemKind.single)
                        Text("Composite").tag(FoodItemKind.composite)
                    }
                    .pickerStyle(.segmented)
                    .disabled(existingItem != nil)
                }

                Section("Details") {
                    LabeledContent("Name") {
                        TextField("Required", text: $name)
                    }
                    .listRowInsets(compactRowInsets)
                    if !itemKind.isComposite {
                        LabeledContent("Category") {
                            Picker("", selection: $categoryID) {
                                ForEach(categories) { category in
                                    Text(category.name).tag(Optional(category.id))
                                }
                            }
                            .labelsHidden()
                        }
                        .listRowInsets(compactRowInsets)
                        LabeledContent("Portion") {
                            Stepper(value: $portion, in: 0.1...6.0, step: 0.1) {
                                Text(portion.cleanNumber)
                            }
                        }
                        .listRowInsets(compactRowInsets)
                    }
                    LabeledContent("Favorite") {
                        Toggle("", isOn: $isFavorite)
                            .labelsHidden()
                    }
                    .listRowInsets(compactRowInsets)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Add optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                    }
                    .listRowInsets(compactRowInsets)
                }

                if itemKind.isComposite {
                    componentsSection
                } else {
                    portionSizeSection
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let isComposite = itemKind.isComposite
                        let resolvedComponents = isComposite ? validatedComponents : []
                        guard !isComposite || !resolvedComponents.isEmpty else { return }
                        let fallbackCategoryID = categories.first?.id ?? UUID()
                        let resolvedCategoryID: UUID
                        if isComposite {
                            let componentCategoryID = resolvedComponents.first.flatMap { component in
                                componentFoods.first(where: { $0.id == component.foodItemID })?.categoryID
                            }
                            resolvedCategoryID = componentCategoryID ?? categoryID ?? fallbackCategoryID
                        } else {
                            guard let categoryID else { return }
                            resolvedCategoryID = categoryID
                        }
                        let amountValue = isComposite ? nil : parsedAmount
                        let resolvedUnitID = isComposite || amountValue == nil ? nil : unitID
                        let itemID = existingItem?.id ?? UUID()
                        var imagePath = removeExistingImage ? nil : existingImagePath
                        if let savedPath = saveImageIfNeeded(itemID: itemID) {
                            imagePath = savedPath
                            if let oldPath = existingImagePath, oldPath != savedPath {
                                try? FoodImageStorage.deleteImage(fileName: oldPath)
                            }
                        } else if removeExistingImage, let oldPath = existingImagePath {
                            try? FoodImageStorage.deleteImage(fileName: oldPath)
                        }
                        let attribution = resolvedAttribution()
                        onSave(
                            FoodItem(
                                id: itemID,
                                name: name,
                                categoryID: resolvedCategoryID,
                                portionEquivalent: isComposite ? 1.0 : Portion.roundToIncrement(portion),
                                amountPerPortion: amountValue,
                                unitID: resolvedUnitID,
                                notes: notes.isEmpty ? nil : notes,
                                isFavorite: isFavorite,
                                imagePath: imagePath,
                                imageRemoteURL: attribution?.remoteURL,
                                imageSource: attribution?.source,
                                imageSourceID: attribution?.sourceID,
                                imageAttributionName: attribution?.attributionName,
                                imageAttributionURL: attribution?.attributionURL,
                                imageSourceURL: attribution?.sourceURL,
                                kind: itemKind,
                                compositeComponents: resolvedComponents
                            )
                        )
                        dismiss()
                    }
                    .glassButton(.text)
                    .disabled(name.isEmpty || !isSaveValid)
                }
            }
            .onAppear {
                categoryID = categoryID ?? categories.first?.id
                loadExistingImageIfNeeded()
                if itemKind.isComposite {
                    amountText = ""
                    unitID = nil
                } else if parsedAmount == nil {
                    unitID = nil
                }
                if selectedImage == nil {
                    photoSelectionKind = .none
                }
                if (selectedAttribution ?? existingAttribution) != nil {
                    photoSource = .unsplash
                } else {
                    photoSource = .local
                }
            }
            .onChange(of: itemKind) { _, newValue in
                if newValue.isComposite {
                    amountText = ""
                    unitID = nil
                    portion = Portion.roundToIncrement(max(0.1, portion))
                } else if categoryID == nil {
                    categoryID = categories.first?.id
                }
            }
            .task(id: selectedPhotoItem) {
                await handleSelectedPhoto()
            }
            .sheet(item: $componentPickerContext, content: componentPickerSheet)
        }
    }

    private var availableUnits: [Core.FoodUnit] {
        units.filter { $0.isEnabled || $0.id == unitID }
    }

    @ViewBuilder
    private var componentsSection: some View {
        Section("Components") {
            if components.isEmpty {
                Text("Add at least one component food.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($components) { $component in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        componentPickerContext = ComponentPickerContext(id: component.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Food")
                            Spacer()
                            Text(selectedFoodName(for: component.foodItemID) ?? "Select food")
                                .foregroundStyle(component.foodItemID == nil ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Stepper(value: $component.portionMultiplier, in: 0.1...6.0, step: 0.1) {
                        Text("Multiplier: \(Portion.roundToIncrement(component.portionMultiplier).cleanNumber)x")
                    }
                }
                .listRowInsets(compactRowInsets)
            }
            .onDelete { offsets in
                let removedIDs: [UUID] = offsets.compactMap { index in
                    guard components.indices.contains(index) else { return nil }
                    return components[index].id
                }
                components.remove(atOffsets: offsets)
                if let activeID = componentPickerContext?.id, removedIDs.contains(activeID) {
                    componentPickerContext = nil
                }
            }
            Button {
                let component = CompositeComponentDraft()
                components.append(component)
                componentPickerContext = ComponentPickerContext(id: component.id)
            } label: {
                Label("Add Component", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var portionSizeSection: some View {
        Section("Portion Size") {
            LabeledContent("Amount/portion") {
                HStack(spacing: 8) {
                    TextField("Required", text: $amountText)
                        .keyboardType(unitAllowsDecimal ? .decimalPad : .numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 90)
                    Picker("", selection: $unitID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(availableUnits) { unit in
                            Text("\(unit.name) (\(unit.symbol))").tag(Optional(unit.id))
                        }
                    }
                    .labelsHidden()
                }
            }
            .listRowInsets(compactRowInsets)
            if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter the numeric amount for one portion (for example, 100).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowInsets(compactRowInsets)
            }
            if let amountValue = parsedAmount, let unitSymbol = unitSymbol(for: unitID) {
                Text("1 portion = \(amountValue.cleanNumber) \(unitSymbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowInsets(compactRowInsets)
            }
        }
    }

    private var navigationTitle: String {
        if existingItem == nil {
            return itemKind.isComposite ? "Add Composite" : "Add Food"
        }
        return itemKind.isComposite ? "Edit Composite" : "Edit Food"
    }

    private var componentFoods: [FoodItem] {
        allItems.filter { !$0.kind.isComposite && $0.id != existingItem?.id }
    }

    private func componentPickerSheet(context: ComponentPickerContext) -> some View {
        ComponentFoodPickerSheet(
            foods: componentFoods,
            selectedFoodID: selectedFoodID(for: context.id),
            onSelect: { selectedFoodID in
                updateSelectedFood(selectedFoodID, for: context.id)
            }
        )
    }

    private func selectedFoodID(for componentID: UUID) -> UUID? {
        components.first(where: { $0.id == componentID })?.foodItemID
    }

    private func updateSelectedFood(_ selectedFoodID: UUID?, for componentID: UUID) {
        guard let index = components.firstIndex(where: { $0.id == componentID }) else { return }
        components[index].foodItemID = selectedFoodID
    }

    private func selectedFoodName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return componentFoods.first(where: { $0.id == id })?.name
    }

    private var validatedComponents: [Core.FoodComponent] {
        components.compactMap { component in
            guard let foodItemID = component.foodItemID,
                  componentFoods.contains(where: { $0.id == foodItemID }) else {
                return nil
            }
            return Core.FoodComponent(
                foodItemID: foodItemID,
                portionMultiplier: max(0.1, component.portionMultiplier)
            )
        }
    }

    private var shouldShowRemovePhoto: Bool {
        selectedImage != nil || existingImagePath != nil
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        if unitAllowsDecimal {
            return Portion.roundToIncrement(value)
        }
        return value.rounded()
    }

    private var isAmountSelectionValid: Bool {
        if parsedAmount == nil { return true }
        return unitID != nil
    }

    private var isSaveValid: Bool {
        if itemKind.isComposite {
            return !validatedComponents.isEmpty
        }
        return categoryID != nil && isAmountSelectionValid
    }

    private var unitAllowsDecimal: Bool {
        guard let unitID else { return true }
        return units.first(where: { $0.id == unitID })?.allowsDecimal ?? true
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return units.first(where: { $0.id == id })?.symbol
    }

    private func handleSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        guard let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }
        let thumbnail = FoodImageStorage.thumbnailImage(from: image)
        await MainActor.run {
            selectedImage = thumbnail
            removeExistingImage = false
            selectedAttribution = nil
            photoSelectionKind = .local
        }
    }

    private func saveImageIfNeeded(itemID: UUID) -> String? {
        guard let selectedImage,
              let jpegData = FoodImageStorage.thumbnailData(from: selectedImage) else {
            return nil
        }
        let fileName = "food-\(itemID.uuidString).jpg"
        do {
            try FoodImageStorage.saveImageData(jpegData, fileName: fileName)
            return fileName
        } catch {
            return nil
        }
    }

    private func loadExistingImageIfNeeded() {
        guard selectedImage == nil, let existingImagePath else { return }
        let url = FoodImageStorage.url(for: existingImagePath)
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        selectedImage = image
    }

    private func selectRemotePhoto(_ photo: UnsplashPhoto) {
        guard searchModel.isConfigured else { return }
        downloadError = nil
        isDownloadingRemote = true
        Task {
            do {
                let image = try await searchModel.selectPhoto(photo)
                let thumbnail = FoodImageStorage.thumbnailImage(from: image)
                await MainActor.run {
                    selectedImage = thumbnail
                    selectedPhotoItem = nil
                    removeExistingImage = false
                    selectedAttribution = searchModel.attribution(for: photo)
                    photoSelectionKind = .remote
                }
            } catch {
                await MainActor.run {
                    downloadError = "Download failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isDownloadingRemote = false
            }
        }
    }

    private func clearSelectedPhoto() {
        selectedPhotoItem = nil
        selectedImage = nil
        selectedAttribution = nil
        if existingImagePath != nil {
            removeExistingImage = true
        }
        photoSelectionKind = .none
    }

    private func resolvedAttribution() -> FoodImageAttribution? {
        switch photoSelectionKind {
        case .remote:
            return selectedAttribution
        case .local:
            return nil
        case .none:
            return removeExistingImage ? nil : existingAttribution
        }
    }

    // Attribution comes from FoodItem via foodImageAttribution.
}

private struct ComponentFoodPickerSheet: View {
    let foods: [FoodItem]
    let selectedFoodID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                        Spacer()
                        if selectedFoodID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filteredFoods) { item in
                    Button {
                        onSelect(item.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if item.id == selectedFoodID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Food")
            .searchable(text: $searchText, prompt: "Search foods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filteredFoods: [FoodItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return foods }
        return foods.filter { item in
            item.name.localizedStandardContains(term)
                || (item.notes ?? "").localizedStandardContains(term)
        }
    }
}

private struct FoodPhotoPreview: View {
    let image: UIImage?
    let remoteURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
            if let remoteURL, let url = URL(string: remoteURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackView()
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallbackView()
                    }
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackView()
            }
        }
        .frame(width: 160, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fallbackView() -> some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 36, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

private struct UnsplashResultCell: View {
    let photo: UnsplashPhoto
    let isSelected: Bool

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: photo.urls.thumb)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color(.secondarySystemBackground)
                case .empty:
                    Color(.secondarySystemBackground)
                @unknown default:
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

private struct FoodPhotoAttributionView: View {
    let attribution: FoodImageAttribution

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FoodAttributionLine(attribution: attribution)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = URL(string: attribution.sourceURL) {
                Link("View photo on Unsplash", destination: url)
                    .font(.caption)
            }
        }
    }
}

private struct FoodInlineAttributionView: View {
    let attribution: FoodImageAttribution

    var body: some View {
        FoodAttributionLine(attribution: attribution)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct FoodAttributionLine: View {
    let attribution: FoodImageAttribution

    var body: some View {
        HStack(spacing: 4) {
            Text("Photo by")
            if let url = URL(string: attribution.attributionURL) {
                Link(attribution.attributionName, destination: url)
            } else {
                Text(attribution.attributionName)
            }
            Text("on")
            if let url = URL(string: attribution.sourceURL) {
                Link("Unsplash", destination: url)
            } else {
                Text("Unsplash")
            }
        }
    }
}

private struct FoodPhotoCreditSheet: View {
    let attribution: FoodImageAttribution

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                FoodAttributionLine(attribution: attribution)
                    .font(.callout)
                if let url = URL(string: attribution.sourceURL) {
                    Link("Open photo on Unsplash", destination: url)
                        .font(.callout)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Photo Credit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
