import SwiftUI
import Core

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var backupManager: BackupManager
    @EnvironmentObject private var healthSyncManager: HealthSyncManager
    @State private var cutoffTime = Date()
    @State private var showingAddMeeting = false
    @State private var backupNote = ""

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

            Section("Configuration") {
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
                    .disabled(backupManager.isBackingUp)
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
                .disabled(healthSyncManager.isSyncing)
            }

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
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            cutoffTime = dateFromMinutes(store.settings.dayCutoffMinutes)
            backupManager.refreshStatus()
            healthSyncManager.refreshStatus()
        }
        .onChange(of: store.settings) { _, newValue in
            cutoffTime = dateFromMinutes(newValue.dayCutoffMinutes)
        }
        .sheet(isPresented: $showingAddMeeting) {
            CareMeetingSheet { meeting in
                Task { await store.saveCareMeeting(meeting) }
            }
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

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func updateSettingsValue(_ update: (inout Core.AppSettings) -> Void) {
        var updated = store.settings
        update(&updated)
        guard updated != store.settings else { return }
        Task { await store.updateSettings(updated) }
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
                    .disabled(trimmedNotes.isEmpty)
                }
            }
        }
    }
}
