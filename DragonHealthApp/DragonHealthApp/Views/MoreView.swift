import SwiftUI
import Core
import PhotosUI
import UIKit

struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var heightCmText = ""
    @State private var targetWeightText = ""
    @State private var doctorName = ""
    @State private var nutritionistName = ""
    @State private var motivation = ""
    @State private var showingAddCategory = false
    @State private var showingAddMealSlot = false

    private var latestWeight: (date: Date, value: Double)? {
        for entry in store.bodyMetrics {
            if let weight = entry.weightKg {
                return (entry.date, weight)
            }
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Profile & App Info") {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image("AppIconBadge")
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DragonHealth")
                            .font(.headline)
                        Text("Track meals, body metrics, and care team notes in one place.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(appVersionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    ProfileImageView(image: profileImage)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Label("Choose Photo", systemImage: "person.crop.circle.badge.plus")
                                .glassLabel(.text)
                        }
                        if profileImage != nil {
                            Button(role: .destructive) {
                                removeProfilePhoto()
                            } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                            .glassButton(.text)
                        }
                    }
                }

                HStack {
                    Text("Height (cm)")
                    Spacer()
                    TextField("--", text: $heightCmText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                .onChange(of: heightCmText) { _, newValue in
                    updateHeight(newValue)
                }

                HStack {
                    Text("Current Weight")
                    Spacer()
                    Text(latestWeight.map { "\($0.value.cleanNumber) kg" } ?? "Not recorded")
                        .foregroundStyle(.secondary)
                }
                if let latestWeight {
                    Text("Last logged \(latestWeight.date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Target Weight (kg)")
                    Spacer()
                    TextField("--", text: $targetWeightText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                .onChange(of: targetWeightText) { _, newValue in
                    updateTargetWeight(newValue)
                }

                DatePicker("Target Weight Date", selection: targetDateBinding, displayedComponents: .date)
                if store.settings.targetWeightDate != nil {
                    Button("Clear Target Date") {
                        updateSettingsValue { $0.targetWeightDate = nil }
                    }
                    .glassButton(.compact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TextField("Doctor Name", text: $doctorName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: doctorName) { _, newValue in
                        updateSettingsValue { $0.doctorName = normalizedText(newValue) }
                    }

                TextField("Nutrition Specialist", text: $nutritionistName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: nutritionistName) { _, newValue in
                        updateSettingsValue { $0.nutritionistName = normalizedText(newValue) }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Motivation / Mission")
                        .font(.subheadline)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $motivation)
                            .frame(minHeight: 110)
                            .textInputAutocapitalization(.sentences)
                            .onChange(of: motivation) { _, newValue in
                                updateSettingsValue { $0.motivation = normalizedText(newValue) }
                            }

                        if motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("What keeps you committed?")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }
                    }
                }
            }

            Section("Backup & Restore") {
                NavigationLink(destination: BackupRestoreView()) {
                    Label("Backup & Restore", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section("Categories") {
                ForEach(store.categories) { category in
                    NavigationLink(destination: CategoryDetailView(category: category)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                            Text(category.targetRule.displayText(unit: category.unitName))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indices in
                    for index in indices {
                        guard index < store.categories.count else { continue }
                        let category = store.categories[index]
                        Task { await store.deleteCategory(category) }
                    }
                }

                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .glassButton(.text)
            }

            Section("Meal Slots") {
                ForEach(store.mealSlots) { slot in
                    NavigationLink(destination: MealSlotDetailView(mealSlot: slot)) {
                        Text(slot.name)
                    }
                }
                .onDelete { indices in
                    for index in indices {
                        guard index < store.mealSlots.count else { continue }
                        let slot = store.mealSlots[index]
                        Task { await store.deleteMealSlot(slot) }
                    }
                }

                Button {
                    showingAddMealSlot = true
                } label: {
                    Label("Add Meal Slot", systemImage: "plus")
                }
                .glassButton(.text)
            }
        }
        .navigationTitle("Extras")
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditorSheet { category in
                Task { await store.saveCategory(category) }
            }
        }
        .sheet(isPresented: $showingAddMealSlot) {
            MealSlotEditorSheet { slot in
                Task { await store.saveMealSlot(slot) }
            }
        }
        .onAppear {
            applySettings(store.settings)
        }
        .onChange(of: store.settings) { _, newValue in
            applySettings(newValue)
        }
        .task(id: selectedPhotoItem) {
            await handleSelectedPhoto()
        }
    }

    private func applySettings(_ settings: Core.AppSettings) {
        heightCmText = settings.heightCm.map { $0.cleanNumber } ?? ""
        targetWeightText = settings.targetWeightKg.map { $0.cleanNumber } ?? ""
        doctorName = settings.doctorName ?? ""
        nutritionistName = settings.nutritionistName ?? ""
        motivation = settings.motivation ?? ""
        profileImage = loadProfileImage(from: settings.profileImagePath)
    }

    private var targetDateBinding: Binding<Date> {
        Binding(
            get: { store.settings.targetWeightDate ?? store.currentDay },
            set: { newValue in
                let normalized = store.appCalendar.startOfDay(for: newValue)
                updateSettingsValue { $0.targetWeightDate = normalized }
            }
        )
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where version != build:
            return "Version \(version) (\(build))"
        case let (version?, _):
            return "Version \(version)"
        case let (_, build?):
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }

    private func normalizedText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateSettingsValue(_ update: (inout Core.AppSettings) -> Void) {
        var updated = store.settings
        update(&updated)
        guard updated != store.settings else { return }
        Task { await store.updateSettings(updated) }
    }

    private func updateHeight(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            updateSettingsValue { $0.heightCm = nil }
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized) else { return }
        updateSettingsValue { $0.heightCm = number }
    }

    private func updateTargetWeight(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            updateSettingsValue { $0.targetWeightKg = nil }
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized) else { return }
        updateSettingsValue { $0.targetWeightKg = number }
    }

    private func profileImageURL(for path: String) -> URL? {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return directory?.appendingPathComponent(path)
    }

    private func loadProfileImage(from path: String?) -> UIImage? {
        guard let path, let url = profileImageURL(for: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func removeProfilePhoto() {
        if let path = store.settings.profileImagePath,
           let url = profileImageURL(for: path) {
            try? FileManager.default.removeItem(at: url)
        }
        profileImage = nil
        updateSettingsValue { $0.profileImagePath = nil }
    }

    private func handleSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        guard let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "profile-photo.jpg"
        guard let url = profileImageURL(for: fileName) else { return }
        do {
            try jpegData.write(to: url, options: .atomic)
            await MainActor.run {
                profileImage = image
            }
            updateSettingsValue { $0.profileImagePath = fileName }
        } catch {
            return
        }
    }
}

private struct ProfileImageView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}
