import SwiftUI
import Core
import PhotosUI
import UIKit

struct ManageView: View {
    var body: some View {
        Form {
            Section("Profile & Care Team") {
                NavigationLink {
                    ProfileDetailsView()
                } label: {
                    Label("Profile Details", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    CareTeamSettingsView()
                } label: {
                    Label("Care Team", systemImage: "person.2")
                }

                NavigationLink {
                    CareTeamLogView()
                } label: {
                    Label("Meeting Log", systemImage: "list.bullet.rectangle")
                }
            }

            Section("Plan & Meals") {
                NavigationLink {
                    DayBoundarySettingsView()
                } label: {
                    Label("Day Boundary", systemImage: "clock")
                }

                NavigationLink {
                    MealTimingSettingsView()
                } label: {
                    Label("Meal Timing", systemImage: "clock.arrow.circlepath")
                }

                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }

                NavigationLink {
                    ScoringSettingsView()
                } label: {
                    Label("Scoring", systemImage: "speedometer")
                }

                NavigationLink {
                    UnitsView()
                } label: {
                    Label("Units", systemImage: "ruler")
                }

                NavigationLink {
                    MealSlotsView()
                } label: {
                    Label("Meal Slots", systemImage: "fork.knife")
                }
            }

            Section("Data & Backup") {
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    Label("iCloud Backup", systemImage: "icloud")
                }

                NavigationLink {
                    RestoreBackupView()
                } label: {
                    Label("Restore Backup", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Integrations") {
                NavigationLink {
                    HealthSyncSettingsView()
                } label: {
                    Label("Apple Health", systemImage: "heart")
                }

                NavigationLink {
                    UnsplashSettingsView()
                } label: {
                    Label("Unsplash", systemImage: "photo")
                }
            }

            Section("Documents") {
                NavigationLink {
                    DocumentsView()
                } label: {
                    Label("Document Library", systemImage: "doc.text")
                }
            }

            Section("About") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("Privacy & Version", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Manage")
    }
}

private struct UnsplashSettingsView: View {
    @State private var applicationID = ""
    @State private var accessKey = ""
    @State private var showAccessKey = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Access Information") {
                TextField("Application ID", text: $applicationID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if showAccessKey {
                    TextField("Access Key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("Access Key", text: $accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Show Access Key", isOn: $showAccessKey)
            }

            Section {
                Button("Save") {
                    let trimmedID = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedID.isEmpty && trimmedKey.isEmpty {
                        statusMessage = "Enter an Application ID or Access Key."
                        return
                    }
                    if !trimmedID.isEmpty {
                        _ = KeychainStore.write(trimmedID, for: .unsplashApplicationID)
                    }
                    if !trimmedKey.isEmpty {
                        _ = KeychainStore.write(trimmedKey, for: .unsplashAccessKey)
                    }
                    statusMessage = "Saved to Keychain."
                }
                .glassButton(.text)

                Button("Clear Unsplash Keys", role: .destructive) {
                    _ = KeychainStore.delete(.unsplashApplicationID)
                    _ = KeychainStore.delete(.unsplashAccessKey)
                    applicationID = ""
                    accessKey = ""
                    statusMessage = "Cleared."
                }
                .glassButton(.text)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                Text("Keys are stored locally in the iOS Keychain. They are not synced or shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let appID = UnsplashConfig.applicationID(), !appID.isEmpty {
                    Text("Application ID loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let key = UnsplashConfig.accessKey(), !key.isEmpty {
                    Text("Access Key loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Unsplash")
        .onAppear {
            applicationID = KeychainStore.read(.unsplashApplicationID) ?? ""
            accessKey = KeychainStore.read(.unsplashAccessKey) ?? ""
        }
    }
}

struct ProfileDetailsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var heightCmText = ""
    @State private var targetWeightText = ""
    @State private var motivation = ""

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
            Section("Profile Photo") {
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
            }

            Section("Body") {
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
            }

            Section("Motivation") {
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
        .navigationTitle("Profile Details")
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

struct CareTeamSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var doctorName = ""
    @State private var nutritionistName = ""

    var body: some View {
        Form {
            Section("Providers") {
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
            }
        }
        .navigationTitle("Care Team")
        .onAppear {
            applySettings(store.settings)
        }
        .onChange(of: store.settings) { _, newValue in
            applySettings(newValue)
        }
    }

    private func applySettings(_ settings: Core.AppSettings) {
        doctorName = settings.doctorName ?? ""
        nutritionistName = settings.nutritionistName ?? ""
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
}

struct CareTeamLogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddMeeting = false

    var body: some View {
        Form {
            Section("Care Team Meetings") {
                if store.careMeetings.isEmpty {
                    Text("No meetings logged yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.careMeetings) { meeting in
                        CareMeetingRow(meeting: meeting)
                    }
                    .onDelete { indices in
                        for index in indices {
                            guard index < store.careMeetings.count else { continue }
                            let meeting = store.careMeetings[index]
                            Task { await store.deleteCareMeeting(meeting) }
                        }
                    }
                }

                Button {
                    showingAddMeeting = true
                } label: {
                    Label("Add Meeting", systemImage: "plus")
                }
                .glassButton(.text)
            }
        }
        .navigationTitle("Meeting Log")
        .sheet(isPresented: $showingAddMeeting) {
            CareMeetingSheet { meeting in
                Task { await store.saveCareMeeting(meeting) }
            }
        }
    }
}

struct DayBoundarySettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var cutoffTime = Date()

    var body: some View {
        Form {
            Section("Day Cutoff") {
                DatePicker("Day ends at", selection: $cutoffTime, displayedComponents: .hourAndMinute)
                    .onChange(of: cutoffTime) { _, newValue in
                        let minutes = minutesFromMidnight(newValue)
                        updateSettingsValue { $0.dayCutoffMinutes = minutes }
                    }

                Text("Entries before this time count toward the previous day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Day Boundary")
        .onAppear {
            cutoffTime = dateFromMinutes(store.settings.dayCutoffMinutes)
        }
        .onChange(of: store.settings) { _, newValue in
            cutoffTime = dateFromMinutes(newValue.dayCutoffMinutes)
        }
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return store.appCalendar.date(from: components) ?? Date()
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let components = store.appCalendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func updateSettingsValue(_ update: (inout Core.AppSettings) -> Void) {
        var updated = store.settings
        update(&updated)
        guard updated != store.settings else { return }
        Task { await store.updateSettings(updated) }
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddCategory = false

    var body: some View {
        Form {
            Section("Categories") {
                if store.categories.isEmpty {
                    Text("No categories yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
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
                }

                Button {
                    showingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .glassButton(.text)
            }
        }
        .navigationTitle("Categories")
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditorSheet { category in
                Task { await store.saveCategory(category) }
            }
        }
    }
}

struct MealSlotsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddMealSlot = false

    var body: some View {
        Form {
            Section("Meal Slots") {
                if store.mealSlots.isEmpty {
                    Text("No meal slots yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
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
                }

                Button {
                    showingAddMealSlot = true
                } label: {
                    Label("Add Meal Slot", systemImage: "plus")
                }
                .glassButton(.text)
            }
        }
        .navigationTitle("Meal Slots")
        .sheet(isPresented: $showingAddMealSlot) {
            MealSlotEditorSheet { slot in
                Task { await store.saveMealSlot(slot) }
            }
        }
    }
}

struct BackupSettingsView: View {
    @EnvironmentObject private var backupManager: BackupManager
    @State private var backupNote = ""

    var body: some View {
        Form {
            Section("iCloud Backup") {
                if backupManager.iCloudAvailable {
                    if let lastBackupDate = backupManager.lastBackupDate {
                        Text("Last backup: \(formatted(lastBackupDate))")
                    } else {
                        Text("No backups yet.")
                    }

                    if let errorMessage = backupManager.lastBackupError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Daily backups run when iCloud is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Backup note (optional)", text: $backupNote)
                        .textInputAutocapitalization(.sentences)

                    Button {
                        let trimmed = backupNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        backupManager.performManualBackup(note: trimmed.isEmpty ? nil : trimmed)
                        backupNote = ""
                    } label: {
                        Label(backupManager.isBackingUp ? "Backing Up..." : "Back Up Now", systemImage: "icloud.and.arrow.up")
                    }
                    .glassButton(.text)
                    .disabled(backupManager.isBackingUp || backupManager.isRestoring)
                } else {
                    Text("iCloud is not available. Sign in to iCloud to enable backups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To enable iCloud:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("1. Open Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("2. Tap your name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("3. Tap iCloud and sign in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("iCloud Backup")
        .onAppear {
            backupManager.refreshStatus()
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RestoreBackupView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var backupManager: BackupManager
    @State private var restoreCandidate: BackupRecord?

    var body: some View {
        Form {
            Section("Restore Backup") {
                if backupManager.iCloudAvailable {
                    if backupManager.backups.isEmpty {
                        Text("No backups available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backupManager.backups) { backup in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(formatted(backup.createdAt))
                                    Spacer()
                                    Text(backup.isCompatible ? "Compatible" : "Incompatible")
                                        .font(.caption)
                                        .foregroundStyle(backup.isCompatible ? .green : .red)
                                }
                                if let note = backup.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("DB version: \(backup.databaseVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    restoreCandidate = backup
                                } label: {
                                    Label(backupManager.isRestoring ? "Restoring..." : "Restore", systemImage: "arrow.counterclockwise")
                                }
                                .glassButton(.text)
                                .disabled(!backup.isCompatible || backupManager.isRestoring || backupManager.isBackingUp)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let restoreError = backupManager.lastRestoreError {
                        Text(restoreError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("iCloud is not available. Sign in to iCloud to view backups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Restore Backup")
        .onAppear {
            backupManager.refreshStatus()
            backupManager.refreshBackups()
        }
        .confirmationDialog(
            "Restore Backup",
            isPresented: Binding(
                get: { restoreCandidate != nil },
                set: { if !$0 { restoreCandidate = nil } }
            ),
            presenting: restoreCandidate
        ) { backup in
            Button("Restore", role: .destructive) {
                Task {
                    let success = await backupManager.restoreBackup(backup)
                    if success {
                        await store.reload()
                    }
                    restoreCandidate = nil
                }
            }
            Button("Cancel", role: .cancel) {
                restoreCandidate = nil
            }
        } message: { backup in
            Text("Restore backup from \(formatted(backup.createdAt))? This will replace your current data.")
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct HealthSyncSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var healthSyncManager: HealthSyncManager

    var body: some View {
        Form {
            Section("Apple Health") {
                if let lastSyncDate = healthSyncManager.lastSyncDate {
                    Text("Last sync: \(formatted(lastSyncDate))")
                } else {
                    Text("No Apple Health sync yet.")
                }

                if let errorMessage = healthSyncManager.lastSyncError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Syncs weight, body fat, lean mass, waist, steps, and active energy (Move kcal).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    healthSyncManager.performManualSync(store: store)
                } label: {
                    Label(healthSyncManager.isSyncing ? "Syncing..." : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .glassButton(.text)
                .disabled(healthSyncManager.isSyncing)
            }
        }
        .navigationTitle("Apple Health")
        .onAppear {
            healthSyncManager.refreshStatus()
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AboutView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
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
            }

            Section("Appearance") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { store.settings.appearance },
                        set: { newValue in
                            updateSettingsValue { $0.appearance = newValue }
                        }
                    )
                ) {
                    ForEach(Core.AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Automatic follows the system appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Launch Screen") {
                Toggle(
                    "Show launch screen",
                    isOn: Binding(
                        get: { store.settings.showLaunchSplash },
                        set: { newValue in
                            updateSettingsValue { $0.showLaunchSplash = newValue }
                        }
                    )
                )
                Text("Show the logo and version for 2 seconds when the app starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("All data stays on-device unless you enable iCloud backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy & Version")
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

    private func updateSettingsValue(_ update: (inout Core.AppSettings) -> Void) {
        var updated = store.settings
        update(&updated)
        guard updated != store.settings else { return }
        Task { await store.updateSettings(updated) }
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

private struct CareMeetingRow: View {
    let meeting: Core.CareMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.date, style: .date)
                Spacer()
                Text(meeting.providerType.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(meeting.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CareMeetingSheet: View {
    let onSave: (Core.CareMeeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var providerType: Core.CareProviderType = .doctor
    @State private var notes = ""

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Provider", selection: $providerType) {
                    ForEach(Core.CareProviderType.allCases, id: \.self) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Add Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Core.CareMeeting(
                                date: date,
                                providerType: providerType,
                                notes: trimmedNotes
                            )
                        )
                        dismiss()
                    }
                    .glassButton(.text)
                    .disabled(trimmedNotes.isEmpty)
                }
            }
        }
    }
}
