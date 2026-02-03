import SwiftUI
import Core
import PhotosUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
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
                    showingAdd = true
                } label: {
                    Label("Add Food", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            FoodEntrySheet(categories: store.categories, units: store.units) { item in
                Task { await store.saveFoodItem(item) }
            }
        }
        .sheet(item: $editingItem) { item in
            FoodEntrySheet(categories: store.categories, units: store.units, item: item) { updatedItem in
                Task { await store.saveFoodItem(updatedItem) }
            }
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
    var thumbnailSize: CGFloat = 44
    var verticalPadding: CGFloat = 4
    @State private var showingPhotoCredit = false

    var body: some View {
        let detailText = detailLine()
        HStack(spacing: 12) {
            FoodThumbnailView(imagePath: item.imagePath, remoteURL: item.imageRemoteURL, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let attribution = item.foodImageAttribution {
                    FoodInlineAttributionView(attribution: attribution)
                }
            }
            Spacer()
            if item.foodImageAttribution != nil {
                Button {
                    showingPhotoCredit = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo credit")
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
        var detail = "\(categoryName) - \(item.portionEquivalent.cleanNumber) portion"
        if let amountPerPortion = item.amountPerPortion,
           let unitSymbol {
            detail += " • 1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)"
        }
        return detail
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

    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let existingItem: FoodItem?
    let onSave: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchModel = FoodImageSearchModel()
    @State private var name: String
    @State private var categoryID: UUID?
    @State private var portion: Double
    @State private var amountText: String
    @State private var unitID: UUID?
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

    init(categories: [Core.Category], units: [Core.FoodUnit], item: FoodItem? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.categories = categories
        self.units = units
        self.existingItem = item
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _categoryID = State(initialValue: item?.categoryID)
        _portion = State(initialValue: item?.portionEquivalent ?? 1.0)
        _amountText = State(initialValue: item?.amountPerPortion.map { $0.cleanNumber } ?? "")
        _unitID = State(initialValue: item?.unitID)
        _notes = State(initialValue: item?.notes ?? "")
        _isFavorite = State(initialValue: item?.isFavorite ?? false)
        _existingImagePath = State(initialValue: item?.imagePath)
        _existingAttribution = State(initialValue: item?.foodImageAttribution)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack(alignment: .center, spacing: 12) {
                        FoodPhotoPreview(
                            image: selectedImage,
                            remoteURL: (selectedAttribution ?? existingAttribution)?.remoteURL
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                Label("Choose Photo", systemImage: "photo")
                            }
                            if selectedImage != nil {
                                Button(role: .destructive) {
                                    clearSelectedPhoto()
                                } label: {
                                    Label("Remove Photo", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Divider()

                    Text("Search Unsplash")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("Search food photos", text: $searchModel.query)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    Task { await searchModel.search() }
                                }
                            Button("Search") {
                                Task { await searchModel.search() }
                            }
                            .buttonStyle(.bordered)
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

                    if let attribution = selectedAttribution ?? existingAttribution {
                        FoodPhotoAttributionView(attribution: attribution)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $categoryID) {
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    Stepper(value: $portion, in: 0.1...6.0, step: 0.1) {
                        Text("Portion: \(portion.cleanNumber)")
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Portion Size") {
                    HStack {
                        Text("Amount per portion")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(unitAllowsDecimal ? .decimalPad : .numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 80)
                    }
                    Picker("Unit", selection: $unitID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(availableUnits) { unit in
                            Text("\(unit.name) (\(unit.symbol))").tag(Optional(unit.id))
                        }
                    }
                    if let amountValue = parsedAmount, let unitSymbol = unitSymbol(for: unitID) {
                        Text("1 portion = \(amountValue.cleanNumber) \(unitSymbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "Add Food" : "Edit Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let categoryID else { return }
                        let amountValue = parsedAmount
                        let resolvedUnitID = amountValue == nil ? nil : unitID
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
                                categoryID: categoryID,
                                portionEquivalent: Portion.roundToIncrement(portion),
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
                                imageSourceURL: attribution?.sourceURL
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || categoryID == nil || !isAmountSelectionValid)
                }
            }
            .onAppear {
                categoryID = categoryID ?? categories.first?.id
                loadExistingImageIfNeeded()
                if parsedAmount == nil {
                    unitID = nil
                }
                if selectedImage == nil {
                    photoSelectionKind = .none
                }
            }
            .task(id: selectedPhotoItem) {
                await handleSelectedPhoto()
            }
        }
    }

    private var availableUnits: [Core.FoodUnit] {
        units.filter { $0.isEnabled || $0.id == unitID }
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

private struct FoodPhotoPreview: View {
    let image: UIImage?
    let remoteURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
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
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fallbackView() -> some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 28, weight: .regular))
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
