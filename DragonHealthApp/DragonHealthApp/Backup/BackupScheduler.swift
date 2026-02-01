import Foundation
import BackgroundTasks
import InfraLogging

final class BackupScheduler {
    static let shared = BackupScheduler()
    static let taskIdentifier = "com.blackdragon.DragonHealthApp.backup.refresh"

    private let logger = AppLogger(category: .backup)
    private var registered = false

    func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(refreshTask)
        }
    }

    func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextScheduledDate(from: Date())
        do {
            try BGTaskScheduler.shared.submit(request)
            if let beginDate = request.earliestBeginDate {
                logger.info("backup_scheduled", metadata: ["earliest": "\(beginDate)"])
            } else {
                logger.info("backup_scheduled", metadata: ["earliest": "unknown"])
            }
        } catch {
            logger.error("backup_schedule_failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleNext()
        let operation = Task.detached {
            await BackupWorker.shared.performBackupIfNeeded()
        }
        task.expirationHandler = {
            operation.cancel()
        }
        Task {
            let outcome = await operation.value
            task.setTaskCompleted(success: outcome.success)
        }
    }

    private func nextScheduledDate(from date: Date) -> Date {
        let calendar = Calendar.current
        let target = DateComponents(hour: 2, minute: 0)
        if let next = calendar.nextDate(after: date, matching: target, matchingPolicy: .nextTime) {
            return next
        }
        return date.addingTimeInterval(24 * 60 * 60)
    }
}
