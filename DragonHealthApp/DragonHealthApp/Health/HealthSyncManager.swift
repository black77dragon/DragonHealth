import Foundation
import Combine
import InfraLogging

@MainActor
final class HealthSyncManager: ObservableObject {
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var isSyncing = false

    private let worker: HealthSyncWorker
    private let logger = AppLogger(category: .health)
    private var hasPerformedLaunchSync = false

    init(worker: HealthSyncWorker = .shared) {
        self.worker = worker
        refreshStatus()
    }

    func refreshStatus() {
        Task {
            let status = await worker.loadStatus()
            apply(status)
        }
    }

    func performSyncOnLaunch(store: AppStore) {
        guard !hasPerformedLaunchSync else { return }
        hasPerformedLaunchSync = true
        performSync(store: store, allowAuthorization: true)
    }

    func performManualSync(store: AppStore) {
        performSync(store: store, allowAuthorization: true)
    }

    private func performSync(store: AppStore, allowAuthorization: Bool) {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            let outcome = await worker.sync(allowAuthorization: allowAuthorization)
            let status = await worker.loadStatus()
            await MainActor.run {
                apply(status)
                isSyncing = false
            }
            if outcome.performed, outcome.success {
                await store.reload()
            } else if let message = outcome.errorMessage {
                logger.error("health_sync_failed", metadata: ["error": message])
            }
        }
    }

    private func apply(_ status: HealthSyncStatus) {
        lastSyncDate = status.lastSyncDate
        lastSyncError = status.lastSyncError
    }
}
