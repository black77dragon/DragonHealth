import SwiftUI
import Core
import InfraConfig
import InfraFeatureFlags
import InfraLogging

@main
@MainActor
struct DragonHealthApp: App {
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

@MainActor
struct ContentView: View {
    let config: AppConfig
    let featureFlags: InMemoryFeatureFlagService
    let logger: AppLogger

    var body: some View {
        VStack(spacing: 12) {
            Text("DragonHealth iOS MVP")

                .font(.title)
            Text("Implementation in progress")
                .font(.body)
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DragonHealth MVP status")
        .onAppear {
            logger.info("App started", metadata: ["schema_version": "0"])
        }
    }
}
