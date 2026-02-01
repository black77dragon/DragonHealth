import UIKit

final class BackupAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackupScheduler.shared.register()
        BackupScheduler.shared.scheduleNext()
        HealthSyncScheduler.shared.register()
        HealthSyncScheduler.shared.scheduleNext()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackupScheduler.shared.scheduleNext()
        HealthSyncScheduler.shared.scheduleNext()
    }
}
