import SwiftUI
import Core
import InfraConfig
import InfraFeatureFlags
import InfraLogging

struct ContentView: View {
    let config: AppConfig
    let featureFlags: FeatureFlagService
    let logger: AppLogger

    @StateObject private var store = AppStore()
    @StateObject private var backupManager = BackupManager()
    @StateObject private var healthSyncManager = HealthSyncManager()
    @State private var hasResolvedLaunchSplash = false
    @State private var isSplashVisible = true

    var body: some View {
        ZStack {
            if shouldShowLaunchSplash {
                LaunchSplashView {
                    dismissLaunchSplash()
                }
            } else {
                mainContent
            }
        }
        .onAppear {
            resolveLaunchSplashIfNeeded()
        }
        .onChange(of: store.settings.showLaunchSplash) { _, _ in
            resolveLaunchSplashIfNeeded()
        }
        .preferredColorScheme(store.settings.appearance.colorScheme)
        .dynamicTypeSize(store.settings.fontSize.dynamicTypeSize)
    }

    private var shouldShowLaunchSplash: Bool {
        !hasResolvedLaunchSplash && store.settings.showLaunchSplash && isSplashVisible
    }

    @ViewBuilder
    private var mainContent: some View {
        switch store.loadState {
        case .loading:
            ProgressView("Loading DragonHealth")
                .accessibilityLabel("Loading DragonHealth")
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text("Unable to load data")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        case .ready:
            TabView {
                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sun.max") }
                NavigationStack { HistoryView() }
                    .tabItem { Label("History", systemImage: "calendar") }
                NavigationStack { BodyMetricsView() }
                    .tabItem { Label("Body", systemImage: "waveform.path.ecg") }
                NavigationStack { LibraryView() }
                    .tabItem { Label("Library", systemImage: "book") }
                NavigationStack { ManageView() }
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
            .environmentObject(store)
            .environmentObject(backupManager)
            .environmentObject(healthSyncManager)
            .onAppear {
                logger.info("app_ready", metadata: [
                    "environment": config.environmentName,
                    "schema_version": "\(config.targetSchema)",
                    "flags": "\(featureFlags.allFlags().count)"
                ])
                backupManager.performBackupIfNeeded()
                healthSyncManager.performSyncOnLaunch(store: store)
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { store.operationErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            store.clearOperationError()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    store.clearOperationError()
                }
            } message: {
                Text(store.operationErrorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func resolveLaunchSplashIfNeeded() {
        guard store.settings.showLaunchSplash else {
            isSplashVisible = false
            hasResolvedLaunchSplash = true
            return
        }
        isSplashVisible = true
    }

    private func dismissLaunchSplash() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isSplashVisible = false
            hasResolvedLaunchSplash = true
        }
    }
}

private extension Core.AppFontSize {
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:
            return .xSmall
        case .standard:
            return .large
        case .large:
            return .xLarge
        }
    }
}

#Preview {
    ContentView(
        config: AppConfig.defaultValue,
        featureFlags: InMemoryFeatureFlagService(flags: []),
        logger: AppLogger(category: .appUI)
    )
}

private struct LaunchSplashView: View {
    let onDismiss: () -> Void
    @State private var hasDismissed = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 2)
                .offset(x: -140, y: -260)

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 1)
                .offset(x: 160, y: 260)

            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image("AppIconBadge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 144, height: 144)

                    Text("DragonHealth")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.semibold)

                    Text("Your daily health dashboard is getting ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 16)

                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.accentColor)

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    Text(appVersionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Tap anywhere to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DragonHealth. \(appVersionText)")
        .task {
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        }
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

    private func dismiss() {
        guard !hasDismissed else { return }
        hasDismissed = true
        onDismiss()
    }
}

private extension Core.AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
