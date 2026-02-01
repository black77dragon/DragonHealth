import Foundation
import Combine
import InfraLogging

@MainActor
final class BackupManager: ObservableObject {
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var lastBackupError: String?
    @Published private(set) var lastBackupPath: String?
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var isBackingUp = false
    @Published private(set) var backups: [BackupRecord] = []
    @Published private(set) var isRestoring = false
    @Published private(set) var lastRestoreError: String?

    private let worker: BackupWorker
    private let logger = AppLogger(category: .backup)

    init(worker: BackupWorker = .shared) {
        self.worker = worker
        refreshStatus()
        refreshBackups()
    }

    func refreshStatus() {
        Task {
            let status = await worker.loadStatus()
            apply(status)
        }
    }

    func refreshBackups() {
        Task {
            let fetched = await worker.fetchBackups()
            backups = fetched
        }
    }

    func performBackupIfNeeded() {
        guard !isBackingUp else { return }
        isBackingUp = true
        Task {
            _ = await worker.performBackupIfNeeded()
            let status = await worker.loadStatus()
            apply(status)
            backups = await worker.fetchBackups()
            isBackingUp = false
        }
    }

    func performManualBackup(note: String?) {
        guard !isBackingUp else { return }
        isBackingUp = true
        Task {
            let outcome = await worker.performBackupIfNeeded(force: true, note: note)
            let status = await worker.loadStatus()
            apply(status)
            backups = await worker.fetchBackups()
            isBackingUp = false
            if let errorMessage = outcome.errorMessage {
                logger.error("backup_manual_failed", metadata: ["error": errorMessage])
            }
        }
    }

    func restoreBackup(_ record: BackupRecord) async -> Bool {
        guard !isRestoring, !isBackingUp else { return false }
        isRestoring = true
        let outcome = await worker.restoreBackup(record)
        let status = await worker.loadStatus()
        apply(status)
        backups = await worker.fetchBackups()
        isRestoring = false
        if let errorMessage = outcome.errorMessage {
            lastRestoreError = errorMessage
            logger.error("backup_restore_failed", metadata: ["error": errorMessage])
            return false
        }
        lastRestoreError = nil
        return outcome.success
    }

    private func apply(_ status: BackupStatus) {
        lastBackupDate = status.lastBackupDate
        lastBackupError = status.lastBackupError
        lastBackupPath = status.lastBackupPath
        iCloudAvailable = status.iCloudAvailable
    }
}
