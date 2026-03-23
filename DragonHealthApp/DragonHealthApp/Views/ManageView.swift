import SwiftUI
import Core
import PhotosUI
import UIKit

struct ManageView: View {
    @EnvironmentObject private var store: AppStore

    private var latestWeight: Double? {
        store.bodyMetrics.compactMap(\.weightKg).first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MoreHeroCard(
                    targetWeightKg: store.settings.targetWeightKg,
                    latestWeightKg: latestWeight,
                    doctorName: store.settings.doctorName,
                    nutritionistName: store.settings.nutritionistName
                )

                MoreSectionCard(title: "Daily support", subtitle: "Frequent actions and routines.") {
                    MoreLinkRow(title: "Night Guard", subtitle: "Evening routine and reminders", systemImage: "moon.stars") {
                        NightGuardView()
                    }
                    MoreLinkRow(title: "GLP-1 Review", subtitle: "Dose planner, intake log, and weekly reflection", systemImage: "pills") {
                        DrugReviewView()
                    }
                    MoreLinkRow(title: "Today", subtitle: "Customize the Today screen", systemImage: "sun.max") {
                        TodayViewSettingsView()
                    }
                    MoreLinkRow(title: "Documents", subtitle: "Store PDFs and images for reference", systemImage: "doc.text") {
                        DocumentsView()
                    }
                }

                MoreSectionCard(title: "Profile & care", subtitle: "Your personal context and support team.") {
                    MoreLinkRow(title: "Profile Details", subtitle: "Photo, goals, motivation, and body targets", systemImage: "person.crop.circle") {
                        ProfileDetailsView()
                    }
                    MoreLinkRow(title: "Care Team", subtitle: "Doctor and nutrition specialist details", systemImage: "person.2") {
                        CareTeamSettingsView()
                    }
                    MoreLinkRow(title: "Meeting Log", subtitle: "Track care visits and notes", systemImage: "list.bullet.rectangle") {
                        CareTeamLogView()
                    }
                    MoreLinkRow(title: "Care Team Brief", subtitle: "Generate a concise summary for visits", systemImage: "doc.text.magnifyingglass") {
                        CareTeamBriefView()
                    }
                }

                MoreSectionCard(title: "Plan & targets", subtitle: "How DragonHealth interprets your routine.") {
                    MoreLinkRow(title: "Day Boundary", subtitle: "Define when a day starts and ends", systemImage: "clock") {
                        DayBoundarySettingsView()
                    }
                    MoreLinkRow(title: "Meal Timing", subtitle: "Control automatic meal-slot selection", systemImage: "clock.arrow.circlepath") {
                        MealTimingSettingsView()
                    }
                    MoreLinkRow(title: "Categories", subtitle: "Edit what you track and each target rule", systemImage: "square.grid.2x2") {
                        CategoriesView()
                    }
                    MoreLinkRow(title: "Scoring", subtitle: "Adjust score behavior and compensation rules", systemImage: "speedometer") {
                        ScoringSettingsView()
                    }
                    MoreLinkRow(title: "Units", subtitle: "Manage measurement units used in the app", systemImage: "ruler") {
                        UnitsView()
                    }
                    MoreLinkRow(title: "Meal Slots", subtitle: "Organize meals and their order", systemImage: "fork.knife") {
                        MealSlotsView()
                    }
                }

                MoreSectionCard(title: "Data & integrations", subtitle: "Connections, backup, and recovery.") {
                    MoreLinkRow(title: "Food Library Transfer", subtitle: "Import or move library content", systemImage: "arrow.up.arrow.down.square") {
                        FoodLibraryTransferView()
                    }
                    MoreLinkRow(title: "iCloud Backup", subtitle: "Review backup status and create backups", systemImage: "icloud") {
                        BackupSettingsView()
                    }
                    MoreLinkRow(title: "Restore Backup", subtitle: "Recover tracked database data from iCloud", systemImage: "arrow.counterclockwise") {
                        RestoreBackupView()
                    }
                    MoreLinkRow(title: "Apple Health", subtitle: "Sync weight, movement, and body metrics", systemImage: "heart") {
                        HealthSyncSettingsView()
                    }
                    MoreLinkRow(title: "Meal Photo AI", subtitle: "Configure photo-assisted logging", systemImage: "sparkles") {
                        MealPhotoAISettingsView()
                    }
                    MoreLinkRow(title: "Unsplash", subtitle: "Manage food image search access", systemImage: "photo") {
                        UnsplashSettingsView()
                    }
                }

                MoreSectionCard(title: "App", subtitle: "Appearance, privacy, and version info.") {
                    MoreLinkRow(title: "Privacy & Version", subtitle: "Theme, font size, and app details", systemImage: "info.circle") {
                        AboutView()
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Manage")
        .background(Color(.systemGroupedBackground))
    }
}

private struct MoreHeroCard: View {
    let targetWeightKg: Double?
    let latestWeightKg: Double?
    let doctorName: String?
    let nutritionistName: String?

    private var targetSummary: String {
        switch (latestWeightKg, targetWeightKg) {
        case let (current?, target?):
            return "\(current.cleanNumber) kg now -> \(target.cleanNumber) kg goal"
        case let (_, target?):
            return "Target weight \(target.cleanNumber) kg"
        case let (current?, _):
            return "Latest weight \(current.cleanNumber) kg"
        default:
            return "Set up your profile and goals to personalize DragonHealth."
        }
    }

    private var careSummary: String {
        let names = [doctorName, nutritionistName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if names.isEmpty {
            return "No care team linked yet."
        }
        return names.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.text) {
            Text("Personal setup")
                .zenEyebrow()
            Text(targetSummary)
                .zenHeroTitle()
            Text(careSummary)
                .zenSupportText()
        }
        .padding(ZenSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zenCard(cornerRadius: 22)
    }
}

private struct MoreSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            VStack(alignment: .leading, spacing: ZenSpacing.compact) {
                Text(title)
                    .zenSectionTitle()
                Text(subtitle)
                    .zenSupportText()
            }
            VStack(spacing: 0) {
                Divider()
                content
            }
        }
    }
}

private struct MoreLinkRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: Destination

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ZenStyle.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .zenSectionTitle()
                    Text(subtitle)
                        .zenSupportText()
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Divider()
                    .padding(.leading, 50)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum TodayMealDisplayStyleOption: String, CaseIterable, Identifiable {
    case miniCards
    case stackedStrips

    var id: String { rawValue }

    var label: String {
        switch self {
        case .miniCards: return "Mini cards"
        case .stackedStrips: return "Stacked strips"
        }
    }
}

private enum TodayQuickAddStyleOption: String, CaseIterable, Identifiable {
    case standard
    case categoryFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .categoryFirst: return "Category guided"
        }
    }
}

private struct TodayViewSettingsView: View {
    @AppStorage("today.mealDisplayStyle") private var mealDisplayStyleRaw: String = TodayMealDisplayStyleOption.miniCards.rawValue
    @AppStorage("today.quickAddStyle") private var quickAddStyleRaw: String = TodayQuickAddStyleOption.standard.rawValue

    private var mealSelection: Binding<TodayMealDisplayStyleOption> {
        Binding(
            get: { TodayMealDisplayStyleOption(rawValue: mealDisplayStyleRaw) ?? .miniCards },
            set: { mealDisplayStyleRaw = $0.rawValue }
        )
    }

    private var quickAddStyleSelection: Binding<TodayQuickAddStyleOption> {
        Binding(
            get: { TodayQuickAddStyleOption(rawValue: quickAddStyleRaw) ?? .standard },
            set: { quickAddStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Categories") {
                HStack {
                    Text("Dashboard style")
                    Spacer()
                    Text("Athletic bars")
                        .foregroundStyle(.secondary)
                }
                Text("The Today food dashboard uses bottom-up thermometer bars for the 8 food categories.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Meals") {
                Picker("Meal style", selection: mealSelection) {
                    ForEach(TodayMealDisplayStyleOption.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Quick Add") {
                Picker("Flow", selection: quickAddStyleSelection) {
                    ForEach(TodayQuickAddStyleOption.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Today")
    }
}

private struct MealPhotoAISettingsView: View {
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("API Key") {
                if showAPIKey {
                    TextField("OpenAI API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Show API Key", isOn: $showAPIKey)
            }

            Section {
                Button("Save") {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        statusMessage = "Enter an API key."
                        return
                    }
                    _ = KeychainStore.write(trimmed, for: .openAIApiKey)
                    statusMessage = "Saved to Keychain."
                }
                .glassButton(.text)

                Button("Clear API Key", role: .destructive) {
                    _ = KeychainStore.delete(.openAIApiKey)
                    apiKey = ""
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
                Text("This key is used for meal photo analysis. It is stored locally in the iOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Optional Info.plist fallback keys: OPENAI_API_KEY and OPENAI_VISION_MODEL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let loadedKey = MealPhotoAIConfig.apiKey(), !loadedKey.isEmpty {
                    Text("API key loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Model: \(MealPhotoAIConfig.model())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Meal Photo AI")
        .onAppear {
            apiKey = KeychainStore.read(.openAIApiKey) ?? ""
        }
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
                VStack(alignment: .leading, spacing: 6) {
                    Label(Core.CareProviderType.doctor.label, systemImage: Core.CareProviderType.doctor.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Doctor Name", text: $doctorName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: doctorName) { _, newValue in
                            updateSettingsValue { $0.doctorName = normalizedText(newValue) }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(Core.CareProviderType.nutritionist.label, systemImage: Core.CareProviderType.nutritionist.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Nutrition Specialist", text: $nutritionistName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: nutritionistName) { _, newValue in
                            updateSettingsValue { $0.nutritionistName = normalizedText(newValue) }
                        }
                }
            }

            Section("Current Team") {
                providerSummaryRow(providerType: .doctor, name: doctorName)
                providerSummaryRow(providerType: .nutritionist, name: nutritionistName)
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

    @ViewBuilder
    private func providerSummaryRow(providerType: Core.CareProviderType, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: providerType.symbolName)
                .font(.body.weight(.semibold))
                .frame(width: 20)
                .foregroundStyle(providerTint(for: providerType))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(name))
                    .font(.subheadline.weight(.semibold))
                Text(providerType.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Name not set" : trimmed
    }

    private func providerTint(for providerType: Core.CareProviderType) -> Color {
        switch providerType {
        case .doctor:
            return .blue
        case .nutritionist:
            return .green
        }
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
    @State private var meetingToEdit: Core.CareMeeting?
    @State private var meetingsPendingDeletion: [Core.CareMeeting] = []

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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                meetingToEdit = meeting
                            }
                    }
                    .onDelete { indices in
                        let selectedMeetings: [Core.CareMeeting] = indices.compactMap { index in
                            guard index < store.careMeetings.count else { return nil }
                            return store.careMeetings[index]
                        }
                        guard !selectedMeetings.isEmpty else { return }
                        meetingsPendingDeletion = selectedMeetings
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
        .sheet(item: $meetingToEdit) { meeting in
            CareMeetingSheet(existingMeeting: meeting) { updatedMeeting in
                Task { await store.saveCareMeeting(updatedMeeting) }
            }
        }
        .alert(
            meetingsPendingDeletion.count > 1 ? "Delete Meetings?" : "Delete Meeting?",
            isPresented: Binding(
                get: { !meetingsPendingDeletion.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        meetingsPendingDeletion = []
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                let pendingMeetings = meetingsPendingDeletion
                meetingsPendingDeletion = []
                Task {
                    for meeting in pendingMeetings {
                        await store.deleteCareMeeting(meeting)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                meetingsPendingDeletion = []
            }
        } message: {
            if meetingsPendingDeletion.count > 1 {
                Text("Delete \(meetingsPendingDeletion.count) meetings? This action cannot be undone.")
            } else {
                Text("Delete this meeting? This action cannot be undone.")
            }
        }
    }
}

private struct CareTeamBriefView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedRange: CareBriefRange = .fourWeeks
    @State private var generatedBrief: CareTeamBrief?
    @State private var isGenerating = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingError = false

    private let totalsCalculator = DailyTotalsCalculator()
    private let evaluator = DailyTotalEvaluator()
    private let scoreEvaluator = DailyScoreEvaluator()

    var body: some View {
        Form {
            Section("Range") {
                Picker("Time Window", selection: $selectedRange) {
                    ForEach(CareBriefRange.allCases) { range in
                        Text(range.shortLabel).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                Text("Generates a plain-language one-page brief for care team visits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brief") {
                if isGenerating {
                    ProgressView("Generating brief...")
                } else if let generatedBrief {
                    Text(generatedBrief.body)
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    Text("No brief yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button("Refresh Brief") {
                    Task { await generateBrief() }
                }
                .glassButton(.text)
                .disabled(isGenerating)

                Button("Copy Brief Text") {
                    guard let generatedBrief else { return }
                    UIPasteboard.general.string = generatedBrief.body
                    statusMessage = "Brief copied."
                }
                .glassButton(.text)
                .disabled(generatedBrief == nil || isGenerating)

                Button("Share Brief") {
                    guard let generatedBrief else { return }
                    shareItems = [generatedBrief.body]
                    showingShareSheet = true
                }
                .glassButton(.text)
                .disabled(generatedBrief == nil || isGenerating)

                Button("Save to Documents (PDF)") {
                    Task { await saveBriefToDocuments() }
                }
                .glassButton(.text)
                .disabled(generatedBrief == nil || isGenerating)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Care Team Brief")
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(activityItems: shareItems)
        }
        .alert("Unable to Complete Action", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task(id: selectedRange) {
            await generateBrief()
        }
    }

    private func generateBrief() async {
        await MainActor.run {
            isGenerating = true
            statusMessage = nil
        }

        let calendar = store.appCalendar
        let endDay = store.currentDay
        guard let startDay = calendar.date(byAdding: .day, value: -(selectedRange.days - 1), to: endDay) else {
            await MainActor.run {
                generatedBrief = nil
                isGenerating = false
            }
            return
        }

        let enabledCategories = store.categories.filter { $0.isEnabled }
        var metCounts: [UUID: Int] = [:]
        var missCounts: [UUID: Int] = [:]
        var scoreValues: [Double] = []
        var fullyOnTargetDays = 0

        for offset in 0..<selectedRange.days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let reference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            let log = await store.fetchDailyLog(for: reference)
            let entries = log?.entries ?? []
            let totalsByCategory = totalsCalculator.totalsByCategory(entries: entries)
            let adherence = evaluator.evaluate(categories: store.categories, totalsByCategoryID: totalsByCategory)
            if adherence.allTargetsMet {
                fullyOnTargetDays += 1
            }
            for result in adherence.categoryResults {
                if result.targetMet {
                    metCounts[result.categoryID, default: 0] += 1
                } else {
                    missCounts[result.categoryID, default: 0] += 1
                }
            }
            let score = scoreEvaluator.evaluate(
                categories: store.categories,
                totalsByCategoryID: totalsByCategory,
                profilesByCategoryID: store.scoreProfiles,
                compensationRules: store.compensationRules
            )
            scoreValues.append(score.overallScore)
        }

        let scoreAverage = scoreValues.isEmpty ? nil : scoreValues.reduce(0, +) / Double(scoreValues.count)
        let scoreStart = scoreValues.first
        let scoreEnd = scoreValues.last
        let scoreDelta = (scoreStart != nil && scoreEnd != nil) ? (scoreEnd! - scoreStart!) : nil

        let topMisses = enabledCategories
            .map { ($0, missCounts[$0.id, default: 0]) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.sortOrder < rhs.0.sortOrder
            }
            .prefix(3)

        let topWins = enabledCategories
            .map { ($0, metCounts[$0.id, default: 0]) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.sortOrder < rhs.0.sortOrder
            }
            .prefix(3)

        let metricsInRange = store.bodyMetrics
            .filter { $0.date >= startDay && $0.date <= endDay }
            .sorted(by: { $0.date < $1.date })
        let weightTrendText = weightTrend(metricsInRange: metricsInRange)
        let stepTrendText = stepTrend(metricsInRange: metricsInRange)
        let meetingsInRange = store.careMeetings.filter { $0.date >= startDay && $0.date <= endDay }.count

        let providerNames = [
            store.settings.doctorName.map { "Doctor: \($0)" },
            store.settings.nutritionistName.map { "Nutrition Specialist: \($0)" }
        ].compactMap { $0 }.joined(separator: " | ")

        let questions = buildDiscussionQuestions(topMisses: Array(topMisses), scoreDelta: scoreDelta, meetingsInRange: meetingsInRange)
        let periodText = "\(formattedDate(startDay, calendar: calendar)) to \(formattedDate(endDay, calendar: calendar))"
        let scoreTrajectoryText = scoreTrajectoryLine(start: scoreStart, end: scoreEnd, delta: scoreDelta, average: scoreAverage)

        let lines = [
            "DragonHealth Care Team Brief",
            "Generated: \(formattedDate(Date(), calendar: calendar))",
            "Period: \(periodText)",
            providerNames.isEmpty ? "Care Team: not listed" : "Care Team: \(providerNames)",
            "",
            "Trend highlights",
            "- \(weightTrendText)",
            "- \(stepTrendText)",
            "- Logged meetings in this period: \(meetingsInRange)",
            "",
            "Adherence and score trajectory",
            "- Days fully on target: \(fullyOnTargetDays)/\(selectedRange.days)",
            "- \(scoreTrajectoryText)",
            "",
            "Persistent misses",
            topMisses.isEmpty ? "- No persistent misses detected." : topMisses.map { "- \($0.0.name): missed \($0.1)/\(selectedRange.days) days" }.joined(separator: "\n"),
            "",
            "Top wins",
            topWins.isEmpty ? "- No consistent wins recorded yet." : topWins.map { "- \($0.0.name): met \($0.1)/\(selectedRange.days) days" }.joined(separator: "\n"),
            "",
            "Suggested discussion questions",
            questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        ]

        await MainActor.run {
            generatedBrief = CareTeamBrief(
                title: "Care Team Brief \(formattedDate(Date(), calendar: calendar))",
                body: lines.joined(separator: "\n")
            )
            isGenerating = false
        }
    }

    private func saveBriefToDocuments() async {
        guard let generatedBrief else { return }
        do {
            let temporaryURL = try renderBriefPDF(title: generatedBrief.title, body: generatedBrief.body)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let imported = try DocumentStorage.importDocument(from: temporaryURL)
            let document = Core.HealthDocument(
                title: generatedBrief.title,
                fileName: imported.fileName,
                fileType: imported.fileType,
                createdAt: Date()
            )
            await store.saveDocument(document)
            await MainActor.run {
                statusMessage = "Saved to Documents."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func renderBriefPDF(title: String, body: String) throws -> URL {
        let fileName = "care-team-brief-\(UUID().uuidString).pdf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: fileURL) { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18)
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]

            let titleRect = CGRect(x: 32, y: 28, width: pageRect.width - 64, height: 24)
            NSString(string: title).draw(in: titleRect, withAttributes: titleAttributes)

            let bodyRect = CGRect(x: 32, y: 60, width: pageRect.width - 64, height: pageRect.height - 92)
            NSString(string: body).draw(in: bodyRect, withAttributes: bodyAttributes)
        }
        return fileURL
    }

    private func scoreTrajectoryLine(start: Double?, end: Double?, delta: Double?, average: Double?) -> String {
        let startText = start.map { Int($0.rounded()) } ?? 0
        let endText = end.map { Int($0.rounded()) } ?? 0
        let avgText = average.map { Int($0.rounded()) } ?? 0
        if let delta {
            let deltaText = delta >= 0 ? "+\(delta.cleanNumber)" : delta.cleanNumber
            return "Score moved from \(startText) to \(endText) (\(deltaText)), average \(avgText)."
        }
        return "Score data is limited for this window."
    }

    private func weightTrend(metricsInRange: [Core.BodyMetricEntry]) -> String {
        let weights = metricsInRange.compactMap { entry -> (Date, Double)? in
            guard let weight = entry.weightKg else { return nil }
            return (entry.date, weight)
        }
        guard let first = weights.first, let last = weights.last else {
            return "No weight trend available in this period."
        }
        let delta = last.1 - first.1
        let direction = delta < 0 ? "decrease" : (delta > 0 ? "increase" : "no change")
        return "Weight \(direction): \(first.1.cleanNumber) kg to \(last.1.cleanNumber) kg (\(delta.cleanNumber) kg)."
    }

    private func stepTrend(metricsInRange: [Core.BodyMetricEntry]) -> String {
        let steps = metricsInRange.compactMap(\.steps)
        guard !steps.isEmpty else {
            return "No step trend available in this period."
        }
        let average = steps.reduce(0, +) / Double(steps.count)
        return "Average daily steps: \(Int(average.rounded()))."
    }

    private func buildDiscussionQuestions(
        topMisses: [(Core.Category, Int)],
        scoreDelta: Double?,
        meetingsInRange: Int
    ) -> [String] {
        var questions: [String] = []
        if let leadingMiss = topMisses.first {
            questions.append("What barrier most often led to missing \(leadingMiss.0.name.lowercased()) this period?")
        }
        if let scoreDelta {
            if scoreDelta < 0 {
                questions.append("Which daily routine change most likely contributed to the score decline?")
            } else {
                questions.append("Which recent habit drove the score improvement and can be formalized?")
            }
        } else {
            questions.append("Which one behavior should be prioritized to stabilize next week's score?")
        }
        if meetingsInRange == 0 {
            questions.append("Should we schedule a check-in cadence for the next month?")
        } else {
            questions.append("Which action from prior meetings should be reviewed for measurable progress?")
        }
        return Array(questions.prefix(3))
    }

    private func formattedDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

private struct CareTeamBrief {
    let title: String
    let body: String
}

private enum CareBriefRange: String, CaseIterable, Identifiable {
    case twoWeeks
    case fourWeeks
    case eightWeeks

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .twoWeeks: return 14
        case .fourWeeks: return 28
        case .eightWeeks: return 56
        }
    }

    var shortLabel: String {
        switch self {
        case .twoWeeks: return "2W"
        case .fourWeeks: return "4W"
        case .eightWeeks: return "8W"
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
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
                BackupScopeInfoRow()

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

                    if let statusMessage = backupManager.manualBackupStatusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(backupManager.manualBackupStatusIsError ? .red : .green)
                    }
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
                BackupScopeInfoRow()

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
            Text(
                "Restore backup from \(formatted(backup.createdAt))? "
                + "This replaces your current tracked database data (meals, body metrics, food library, settings). "
                + "Documents, food photos, and profile photo files are not part of backup/restore."
            )
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct BackupScopeInfoRow: View {
    @State private var showingScopeDetails = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Backup scope: database only")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingScopeDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Backup scope details")
        }
        .alert("Backup Scope", isPresented: $showingScopeDetails) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud backup and restore include only DragonHealth database data. Document files, food images, and profile photo files are not included.")
        }
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
                            .fill(ZenStyle.elevatedSurface)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
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

            Section("Display") {
                Picker(
                    "Font size",
                    selection: Binding(
                        get: { store.settings.fontSize },
                        set: { newValue in
                            updateSettingsValue { $0.fontSize = newValue }
                        }
                    )
                ) {
                    ForEach(Core.AppFontSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Text("Small fits more content on screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Morning Reflection") {
                Toggle(
                    "Show morning reflection",
                    isOn: Binding(
                        get: { store.settings.showLaunchSplash },
                        set: { newValue in
                            updateSettingsValue { $0.showLaunchSplash = newValue }
                        }
                    )
                )
                Text("Show a short stoic reflection inside Today instead of interrupting launch.")
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
    @EnvironmentObject private var store: AppStore
    let meeting: Core.CareMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: meeting.providerType.symbolName)
                    .font(.body.weight(.semibold))
                    .frame(width: 20)
                    .foregroundStyle(providerTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(providerName)
                        .font(.subheadline.weight(.semibold))
                    Text(meeting.providerType.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(meeting.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(meeting.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var providerName: String {
        let rawName: String?
        switch meeting.providerType {
        case .doctor:
            rawName = store.settings.doctorName
        case .nutritionist:
            rawName = store.settings.nutritionistName
        }
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Name not set" : trimmed
    }

    private var providerTint: Color {
        switch meeting.providerType {
        case .doctor:
            return .blue
        case .nutritionist:
            return .green
        }
    }
}

private struct CareMeetingSheet: View {
    let existingMeeting: Core.CareMeeting?
    let onSave: (Core.CareMeeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var providerType: Core.CareProviderType
    @State private var notes: String

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEditing: Bool {
        existingMeeting != nil
    }

    init(existingMeeting: Core.CareMeeting? = nil, onSave: @escaping (Core.CareMeeting) -> Void) {
        self.existingMeeting = existingMeeting
        self.onSave = onSave
        _date = State(initialValue: existingMeeting?.date ?? Date())
        _providerType = State(initialValue: existingMeeting?.providerType ?? .doctor)
        _notes = State(initialValue: existingMeeting?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Provider", selection: $providerType) {
                    ForEach(Core.CareProviderType.allCases, id: \.self) { provider in
                        Label(provider.label, systemImage: provider.symbolName).tag(provider)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle(isEditing ? "Edit Meeting" : "Add Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Core.CareMeeting(
                                id: existingMeeting?.id ?? UUID(),
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
