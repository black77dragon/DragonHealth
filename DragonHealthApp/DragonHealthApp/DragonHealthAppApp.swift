import SwiftUI
import Core
import InfraConfig
import InfraFeatureFlags
import InfraLogging

@main
struct DragonHealthAppApp: App {
    @UIApplicationDelegateAdaptor(BackupAppDelegate.self) private var appDelegate
    private let logger = AppLogger(category: .appUI)
    private let config = AppConfig.defaultValue
    private let featureFlags = InMemoryFeatureFlagService(flags: [])

    var body: some Scene {
        WindowGroup {
            ContentView(
                config: config,
                featureFlags: featureFlags,
                logger: logger
            )
        }
    }
}
