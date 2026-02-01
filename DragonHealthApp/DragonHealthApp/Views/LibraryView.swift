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
            FoodEntrySheet(categories: store.categories) { item in
                Task { await store.saveFoodItem(item) }
            }
        }
        .sheet(item: $editingItem) { item in
            FoodEntrySheet(categories: store.categories, item: item) { updatedItem in
                Task { await store.saveFoodItem(updatedItem) }
            }
        }
    }

    private func categoryName(for id: UUID) -> String {
        store.categories.first(where: { $0.id == id })?.name ?? "Unassigned"
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
        FoodItemRow(item: item, categoryName: categoryName(for: item.categoryID))
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
    var showsFavorite: Bool = true
    var thumbnailSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnailView(imagePath: item.imagePath, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                Text("\(categoryName) - \(item.portionEquivalent.cleanNumber) portion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsFavorite, item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FoodThumbnailView: View {
    let imagePath: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.45, weight: .regular))
                    .foregroundStyle(.secondary)
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
}

private struct FoodEntrySheet: View {
    let categories: [Core.Category]
    let existingItem: FoodItem?
    let onSave: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var categoryID: UUID?
    @State private var portion: Double
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var existingImagePath: String?
    @State private var removeExistingImage = false

    init(categories: [Core.Category], item: FoodItem? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.categories = categories
        self.existingItem = item
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _categoryID = State(initialValue: item?.categoryID)
        _portion = State(initialValue: item?.portionEquivalent ?? 1.0)
        _notes = State(initialValue: item?.notes ?? "")
        _isFavorite = State(initialValue: item?.isFavorite ?? false)
        _existingImagePath = State(initialValue: item?.imagePath)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack(alignment: .center, spacing: 12) {
                        FoodPhotoPreview(image: selectedImage)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                Label("Choose Photo", systemImage: "photo")
                            }
                            if selectedImage != nil {
                                Button(role: .destructive) {
                                    selectedPhotoItem = nil
                                    selectedImage = nil
                                    if existingImagePath != nil {
                                        removeExistingImage = true
                                    }
                                } label: {
                                    Label("Remove Photo", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $categoryID) {
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    Stepper(value: $portion, in: 0.25...6.0, step: 0.25) {
                        Text("Portion: \(portion.cleanNumber)")
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
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
                        onSave(
                            FoodItem(
                                id: itemID,
                                name: name,
                                categoryID: categoryID,
                                portionEquivalent: portion,
                                notes: notes.isEmpty ? nil : notes,
                                isFavorite: isFavorite,
                                imagePath: imagePath
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || categoryID == nil)
                }
            }
            .onAppear {
                categoryID = categoryID ?? categories.first?.id
                loadExistingImageIfNeeded()
            }
            .task(id: selectedPhotoItem) {
                await handleSelectedPhoto()
            }
        }
    }

    private func handleSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        guard let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }
        let thumbnail = FoodImageStorage.thumbnailImage(from: image)
        await MainActor.run {
            selectedImage = thumbnail
            removeExistingImage = false
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
}

private struct FoodPhotoPreview: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}
