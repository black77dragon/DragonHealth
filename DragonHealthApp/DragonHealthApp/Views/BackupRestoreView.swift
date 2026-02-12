import SwiftUI

struct BackupRestoreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var backupManager: BackupManager
    @State private var restoreCandidate: BackupRecord?
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
        .navigationTitle("Backup & Restore")
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
