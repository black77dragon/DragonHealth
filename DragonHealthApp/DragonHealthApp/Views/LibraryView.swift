import SwiftUI
import Combine
import Core
import PhotosUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
    @State private var showingAddTypePicker = false
    @State private var addKind: FoodItemKind = .single
    @State private var editingItem: FoodItem?
    @State private var itemPendingDelete: FoodItem?
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @AppStorage("library.surface") private var surfaceRaw: String = LibrarySurface.browse.rawValue

    private var selectedSurface: LibrarySurface {
        LibrarySurface(rawValue: surfaceRaw) ?? .browse
    }

    private var selectedSurfaceBinding: Binding<LibrarySurface> {
        Binding(
            get: { LibrarySurface(rawValue: surfaceRaw) ?? .browse },
            set: { surfaceRaw = $0.rawValue }
        )
    }

    var body: some View {
        let content = buildLibraryContent()
        List {
            Section {
                LibraryHeroCard(
                    selectedSurface: selectedSurfaceBinding,
                    totalCount: content.totalCount,
                    favoriteCount: content.favoriteCount,
                    compositeCount: content.compositeCount
                )
                .listRowBackground(Color.clear)
            }

            Section {
                LibraryCategoryFilterBar(
                    categories: store.categories,
                    selectedCategoryID: $selectedCategoryID
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            if content.sections.isEmpty {
                Section {
                    LibraryEmptyStateCard(
                        title: content.emptyStateTitle,
                        message: content.emptyStateMessage
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(content.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            foodRow(for: item, content: content)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Library")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddTypePicker = true
                } label: {
                    Label("Add Food", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .glassLabel(.icon)
                }
                .buttonStyle(.plain)
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
        .confirmationDialog(
            "Delete Item?",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        itemPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: itemPendingDelete
        ) { item in
            Button("Delete \(item.name)", role: .destructive) {
                Task { await store.deleteFoodItem(item) }
                itemPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: { item in
            Text("This removes \(item.name) from your library.")
        }
    }

    private func buildLibraryContent() -> LibraryContent {
        let categoryNamesByID = Dictionary(
            uniqueKeysWithValues: store.categories.map { ($0.id, $0.name) }
        )
        let unitSymbolsByID = Dictionary(
            uniqueKeysWithValues: store.units.map { ($0.id, $0.symbol) }
        )
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filteredItems = store.foodItems
            .filter { item in
                guard let selectedCategoryID else { return true }
                return item.categoryID == selectedCategoryID
            }
            .filter { item in
                guard !trimmedSearch.isEmpty else { return true }
                let category = categoryNamesByID[item.categoryID] ?? "Unassigned"
                let notes = item.notes ?? ""
                return item.name.localizedStandardContains(trimmedSearch)
                    || category.localizedStandardContains(trimmedSearch)
                    || notes.localizedStandardContains(trimmedSearch)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let sections: [LibrarySection]
        switch selectedSurface {
        case .browse:
            let grouped = Dictionary(grouping: filteredItems) { item in
                categoryNamesByID[item.categoryID] ?? "Unassigned"
            }
            sections = grouped.keys.sorted().compactMap { category in
                guard let items = grouped[category], !items.isEmpty else { return nil }
                return LibrarySection(title: category, items: items)
            }
        case .favorites:
            let favorites = filteredItems.filter(\.isFavorite)
            sections = favorites.isEmpty ? [] : [LibrarySection(title: "Favorites", items: favorites)]
        case .recipes:
            let composites = filteredItems.filter { $0.kind.isComposite }
            sections = composites.isEmpty ? [] : [LibrarySection(title: "Composite foods", items: composites)]
        }

        let emptyStateTitle: String
        switch selectedSurface {
        case .browse:
            emptyStateTitle = store.foodItems.isEmpty ? "No foods yet" : "No foods match this view"
        case .favorites:
            emptyStateTitle = "No favorites yet"
        case .recipes:
            emptyStateTitle = "No composite foods yet"
        }

        let emptyStateMessage: String
        switch selectedSurface {
        case .browse:
            emptyStateMessage = store.foodItems.isEmpty
                ? "Add foods or recipes to start building your library."
                : "Try a different search term or clear the category filter."
        case .favorites:
            emptyStateMessage = "Star the foods you use most so they are easier to find from quick add."
        case .recipes:
            emptyStateMessage = "Create composite foods for meals you repeat often."
        }

        return LibraryContent(
            totalCount: store.foodItems.count,
            favoriteCount: store.foodItems.filter(\.isFavorite).count,
            compositeCount: store.foodItems.filter { $0.kind.isComposite }.count,
            sections: sections,
            emptyStateTitle: emptyStateTitle,
            emptyStateMessage: emptyStateMessage,
            categoryNamesByID: categoryNamesByID,
            unitSymbolsByID: unitSymbolsByID
        )
    }

    @ViewBuilder
    private func foodRow(for item: FoodItem, content: LibraryContent) -> some View {
        FoodItemRow(
            item: item,
            categoryName: content.categoryNamesByID[item.categoryID] ?? "Unassigned",
            unitSymbol: item.unitID.flatMap { content.unitSymbolsByID[$0] }
        )
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    itemPendingDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

private struct LibraryContent {
    let totalCount: Int
    let favoriteCount: Int
    let compositeCount: Int
    let sections: [LibrarySection]
    let emptyStateTitle: String
    let emptyStateMessage: String
    let categoryNamesByID: [UUID: String]
    let unitSymbolsByID: [UUID: String]
}

private enum LibrarySurface: String, CaseIterable, Identifiable {
    case browse
    case favorites
    case recipes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .browse: return "Browse"
        case .favorites: return "Favorites"
        case .recipes: return "Recipes"
        }
    }
}

private struct LibrarySection: Identifiable {
    let title: String
    let items: [FoodItem]

    var id: String { title }
}

private struct LibraryHeroCard: View {
    @Binding var selectedSurface: LibrarySurface
    let totalCount: Int
    let favoriteCount: Int
    let compositeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.section) {
            VStack(alignment: .leading, spacing: ZenSpacing.text) {
                Text("Food library")
                    .zenEyebrow()
                Text("Browse by purpose instead of scanning one long list.")
                    .zenHeroTitle()
                HStack(spacing: 12) {
                    LibraryHeroMetric(label: "Foods", value: "\(totalCount)")
                    LibraryHeroMetric(label: "Favorites", value: "\(favoriteCount)")
                    LibraryHeroMetric(label: "Recipes", value: "\(compositeCount)")
                }
            }

            Picker("Library Surface", selection: $selectedSurface) {
                ForEach(LibrarySurface.allCases) { surface in
                    Text(surface.label).tag(surface)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 22)
    }
}

private struct LibraryHeroMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .zenMetricLabel()
            Text(value)
                .zenMetricValue()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct LibraryCategoryFilterBar: View {
    let categories: [Core.Category]
    @Binding var selectedCategoryID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "All", categoryID: nil)
                ForEach(categories) { category in
                    categoryButton(title: category.name, categoryID: category.id)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryButton(title: String, categoryID: UUID?) -> some View {
        let isSelected = selectedCategoryID == categoryID
        return Button {
            selectedCategoryID = categoryID
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? ZenStyle.elevatedSurface : ZenStyle.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .zenSectionTitle()
            Text(message)
                .zenSupportText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .zenCard()
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
                        .glassLabel(.icon)
                }
                .buttonStyle(.plain)
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
    @StateObject private var loader: FoodThumbnailLoader

    init(imagePath: String?, remoteURL: String?, size: CGFloat = 44) {
        self.imagePath = imagePath
        self.remoteURL = remoteURL
        self.size = size
        _loader = StateObject(wrappedValue: FoodThumbnailLoader(imagePath: imagePath))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if imagePath != nil && !loader.didFinishLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let remoteURL, let url = URL(string: remoteURL) {
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
        .onAppear {
            loader.load(imagePath: imagePath)
        }
        .onChange(of: imagePath) { _, newValue in
            loader.load(imagePath: newValue)
        }
    }

    @ViewBuilder
    private func fallbackImageView() -> some View {
        Image(systemName: "photo")
            .font(.system(size: size * 0.45, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

private final class FoodThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFinishLoading: Bool

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private var currentImagePath: String?
    private var isLoading = false

    init(imagePath: String?) {
        currentImagePath = imagePath
        if let imagePath,
           let cached = Self.cache.object(forKey: imagePath as NSString) {
            image = cached
            didFinishLoading = true
        } else {
            didFinishLoading = imagePath == nil
        }
    }

    func load(imagePath: String?) {
        if currentImagePath != imagePath {
            currentImagePath = imagePath
            isLoading = false
            image = nil
            didFinishLoading = imagePath == nil
        }

        guard let imagePath else { return }

        if let cached = Self.cache.object(forKey: imagePath as NSString) {
            image = cached
            didFinishLoading = true
            return
        }

        guard !isLoading else { return }
        isLoading = true
        didFinishLoading = false

        DispatchQueue.global(qos: .utility).async {
            let url = FoodImageStorage.url(for: imagePath)
            let loadedImage = UIImage(contentsOfFile: url.path)
            if let loadedImage {
                Self.cache.setObject(loadedImage, forKey: imagePath as NSString)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.currentImagePath == imagePath else { return }
                self.image = loadedImage
                self.didFinishLoading = true
                self.isLoading = false
            }
        }
    }
}

struct FoodEntrySheet: View {
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
    let suggestionRequest: FoodDetailSuggestionRequest?
    let autoSuggestOnAppear: Bool
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
    @State private var isSuggestingDetails = false
    @State private var suggestionError: String?
    @State private var suggestionConfidence: Double?
    @State private var didAutoSuggest = false
    private let compactRowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

    private var selectedCategory: Core.Category? {
        guard let categoryID else { return nil }
        return categories.first(where: { $0.id == categoryID })
    }

    private var isDrinkCategory: Bool {
        guard let selectedCategory else { return false }
        return DrinkRules.isDrinkCategory(selectedCategory)
    }

    private var drinkUnits: [Core.FoodUnit] {
        DrinkRules.drinkUnits(from: units)
    }

    init(
        categories: [Core.Category],
        units: [Core.FoodUnit],
        allItems: [FoodItem],
        item: FoodItem? = nil,
        initialKind: FoodItemKind = .single,
        suggestionRequest: FoodDetailSuggestionRequest? = nil,
        autoSuggestOnAppear: Bool = false,
        onSave: @escaping (FoodItem) -> Void
    ) {
        self.categories = categories
        self.units = units
        self.allItems = allItems
        self.existingItem = item
        self.initialKind = initialKind
        self.suggestionRequest = suggestionRequest
        self.autoSuggestOnAppear = autoSuggestOnAppear
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? suggestionRequest?.enteredName ?? "")
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
        _selectedImage = State(initialValue: suggestionRequest?.referenceImage)
        _existingImagePath = State(initialValue: item?.imagePath)
        _existingAttribution = State(initialValue: item?.foodImageAttribution)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Food name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .listRowInsets(compactRowInsets)

                    if shouldShowSuggestionSection {
                        Text(shouldRevealEntryDetails ? "Use Smart Fill to prefill the rest, then review and adjust the details below." : "Start with the food name. The rest of the details will appear after you enter it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowInsets(compactRowInsets)

                        Button {
                            requestSuggestedDetails()
                        } label: {
                            Label(isSuggestingDetails ? "Preparing Details..." : "Smart Fill Details", systemImage: "sparkles")
                        }
                        .glassButton(.text)
                        .disabled(!canRequestSuggestedDetails)
                        .listRowInsets(compactRowInsets)

                        if isSuggestingDetails {
                            ProgressView("Preparing food proposal…")
                                .font(.caption)
                                .listRowInsets(compactRowInsets)
                        } else if let suggestionError {
                            Text(suggestionError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .listRowInsets(compactRowInsets)
                        } else if let suggestionConfidence {
                            Text("AI prepared this food entry for review. Confidence: \((suggestionConfidence * 100).rounded().cleanNumber)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowInsets(compactRowInsets)
                        } else if MealPhotoAIConfig.client() == nil {
                            Text("OpenAI API key missing. Add it in Manage > Integrations > Meal Photo AI.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowInsets(compactRowInsets)
                        }
                    } else if !shouldRevealEntryDetails {
                        Text("Enter the food name first. The rest of the fields will appear next.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowInsets(compactRowInsets)
                    }
                }

                if shouldRevealEntryDetails {
                    Section("Type") {
                        Picker("Item Type", selection: $itemKind) {
                            Text("Food").tag(FoodItemKind.single)
                            Text("Composite").tag(FoodItemKind.composite)
                        }
                        .pickerStyle(.segmented)
                        .disabled(existingItem != nil)
                    }

                    Section("Details") {
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
                            if isDrinkCategory {
                                LabeledContent("Portion") {
                                    Text(portion.cleanNumber)
                                }
                                .listRowInsets(compactRowInsets)
                                Text("Derived from amount (ml/L).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .listRowInsets(compactRowInsets)
                            } else {
                                LabeledContent("Portion") {
                                    Stepper(value: $portion, in: 0.1...6.0, step: 0.1) {
                                        Text(portion.cleanNumber)
                                    }
                                }
                                .listRowInsets(compactRowInsets)
                            }
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

                    photoSection
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
                        let resolvedPortionEquivalent: Double
                        if isComposite {
                            resolvedPortionEquivalent = 1.0
                        } else if isDrinkCategory,
                                  let amountValue,
                                  let unitSymbol = unitSymbol(for: resolvedUnitID),
                                  let liters = DrinkRules.liters(from: amountValue, unitSymbol: unitSymbol) {
                            resolvedPortionEquivalent = DrinkRules.roundedLiters(liters)
                        } else {
                            let increment = isDrinkCategory ? Portion.drinkIncrement : Portion.defaultIncrement
                            resolvedPortionEquivalent = Portion.roundToIncrement(portion, increment: increment)
                        }
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
                                name: trimmedName,
                                categoryID: resolvedCategoryID,
                                portionEquivalent: resolvedPortionEquivalent,
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
                    .disabled(trimmedName.isEmpty || !isSaveValid)
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
                ensureDrinkUnitSelection()
                syncDrinkPortionFromAmount()
                if selectedImage == nil {
                    photoSelectionKind = .none
                } else if photoSelectionKind == .none {
                    photoSelectionKind = .local
                }
                if (selectedAttribution ?? existingAttribution) != nil {
                    photoSource = .unsplash
                } else {
                    photoSource = .local
                }
                if autoSuggestOnAppear, !didAutoSuggest, shouldShowSuggestionSection {
                    didAutoSuggest = true
                    requestSuggestedDetails()
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
            .onChange(of: categoryID) { _, _ in
                ensureDrinkUnitSelection()
                syncDrinkPortionFromAmount()
            }
            .onChange(of: amountText) { _, _ in
                syncDrinkPortionFromAmount()
            }
            .onChange(of: unitID) { _, _ in
                syncDrinkPortionFromAmount()
            }
            .task(id: selectedPhotoItem) {
                await handleSelectedPhoto()
            }
            .sheet(item: $componentPickerContext, content: componentPickerSheet)
        }
    }

    private var availableUnits: [Core.FoodUnit] {
        let base = units.filter { $0.isEnabled || $0.id == unitID }
        guard isDrinkCategory else { return base }
        var allowed = DrinkRules.drinkUnits(from: base)
        if let unitID,
           let existing = base.first(where: { $0.id == unitID }),
           !allowed.contains(existing) {
            allowed.append(existing)
        }
        return allowed
    }

    private var shouldShowSuggestionSection: Bool {
        existingItem == nil && !itemKind.isComposite
    }

    private var canRequestSuggestedDetails: Bool {
        guard shouldShowSuggestionSection else { return false }
        guard !isSuggestingDetails else { return false }
        guard MealPhotoAIConfig.client() != nil else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldRevealEntryDetails: Bool {
        existingItem != nil || !trimmedName.isEmpty
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

    @ViewBuilder
    private var photoSection: some View {
        Section("Photo (Optional)") {
            VStack(alignment: .leading, spacing: 16) {
                FoodPhotoPreview(
                    image: selectedImage,
                    remoteURL: displayedRemoteURL
                )

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label(selectedImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                            .glassLabel(.text)
                    }

                    if searchModel.isConfigured {
                        Button {
                            photoSource = photoSource == .unsplash ? .local : .unsplash
                        } label: {
                            Label(photoSource == .unsplash ? "Use Library Photo" : "Search Unsplash", systemImage: photoSource == .unsplash ? "photo.on.rectangle" : "magnifyingglass")
                        }
                        .glassButton(.text)
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

                if photoSource == .unsplash {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Search Unsplash")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !searchModel.isConfigured {
                            Text("Unsplash API key is not configured.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

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
                            .disabled(!searchModel.isConfigured || searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if searchModel.isLoading {
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

                if let attribution = displayedAttribution {
                    FoodPhotoAttributionView(attribution: attribution)
                }
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

    private var displayedAttribution: FoodImageAttribution? {
        guard photoSource == .unsplash else { return nil }
        return resolvedAttribution()
    }

    private var displayedRemoteURL: String? {
        guard photoSelectionKind != .local else { return nil }
        return displayedAttribution?.remoteURL
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return roundedAmountValue(value)
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

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requestSuggestedDetails() {
        let enteredName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enteredName.isEmpty else { return }
        guard let apiKey = MealPhotoAIConfig.apiKey() else {
            suggestionError = "OpenAI API key missing."
            return
        }

        let request = FoodDetailSuggestionRequest(
            enteredName: enteredName,
            referenceImage: selectedImage ?? suggestionRequest?.referenceImage,
            referenceNotes: suggestionRequest?.referenceNotes ?? trimmedNotes
        )

        suggestionError = nil
        isSuggestingDetails = true

        Task {
            do {
                let client = OpenAIFoodDetailClient(apiKey: apiKey, model: MealPhotoAIConfig.model())
                let suggestion = try await client.suggestFood(
                    request: request,
                    categories: categories,
                    units: units
                )
                await MainActor.run {
                    applySuggestion(suggestion)
                    isSuggestingDetails = false
                }
            } catch {
                await MainActor.run {
                    suggestionError = suggestionErrorMessage(for: error)
                    isSuggestingDetails = false
                }
            }
        }
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if isDrinkCategory {
            let symbol = unitSymbol(for: unitID)?.lowercased()
            if symbol == "ml" {
                return value.rounded()
            }
            return Portion.roundToIncrement(value, increment: Portion.drinkIncrement)
        }
        if unitAllowsDecimal {
            return Portion.roundToIncrement(value)
        }
        return value.rounded()
    }

    private func applySuggestion(_ suggestion: FoodDetailSuggestion) {
        name = suggestion.name
        if let categoryID = suggestion.categoryID {
            self.categoryID = categoryID
        }
        amountText = suggestion.amountPerPortion?.cleanNumber ?? ""
        unitID = suggestion.amountPerPortion == nil ? nil : suggestion.unitID
        portion = suggestion.portionEquivalent
        if let notes = suggestion.notes {
            self.notes = notes
        }
        suggestionConfidence = suggestion.confidence
        ensureDrinkUnitSelection()
        syncDrinkPortionFromAmount()
    }

    private func suggestionErrorMessage(for error: Error) -> String {
        if let clientError = error as? OpenAIMealPhotoClient.ClientError {
            return clientError.errorDescription ?? "Food suggestion failed."
        }
        return error.localizedDescription
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return units.first(where: { $0.id == id })?.symbol
    }

    private func ensureDrinkUnitSelection() {
        guard isDrinkCategory else { return }
        if let unitID,
           let symbol = unitSymbol(for: unitID),
           DrinkRules.isDrinkUnitSymbol(symbol) {
            return
        }
        unitID = drinkUnits.first(where: { $0.symbol.lowercased() == "ml" })?.id ?? drinkUnits.first?.id
    }

    private func syncDrinkPortionFromAmount() {
        guard isDrinkCategory else { return }
        guard let amountValue = parsedAmount else { return }
        let unitSymbol = unitSymbol(for: unitID)
        guard let liters = DrinkRules.liters(from: amountValue, unitSymbol: unitSymbol) else { return }
        portion = DrinkRules.roundedLiters(liters)
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
            photoSource = .local
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
                    photoSource = .unsplash
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
        photoSource = .local
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
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL, let url = URL(string: remoteURL) {
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
