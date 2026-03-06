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
                NavigationStack { DailyHubView() }
                    .tabItem { Label("Daily", systemImage: "sun.max") }
                NavigationStack { NightGuardView() }
                    .tabItem { Label("Night Guard", systemImage: "moon.stars") }
                NavigationStack { BodyMetricsView() }
                    .tabItem { Label("Body", systemImage: "waveform.path.ecg") }
                NavigationStack { LibraryView() }
                    .tabItem { Label("Library", systemImage: "book") }
                NavigationStack { ManageView() }
                    .tabItem { Label("Manage", systemImage: "slider.horizontal.3") }
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
    @AppStorage("launchSplash.lastNightGuardReminderIndex") private var lastReminderIndex = -1
    @State private var reminder = LaunchSplashReminder.defaultReminder
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

            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image("AppIconBadge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)

                    Text("DragonHealth")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.semibold)

                    VStack(spacing: 4) {
                        Text("Author")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("Rene W. Keller")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        Text("Black Dragon Software Inc.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                VStack(spacing: 10) {
                    Text("Night Guard Reminder")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text(reminder.text)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    Button("OK") {
                        dismiss()
                    }
                    .glassButton(.text)
                    .controlSize(.large)
                    .tint(Color.accentColor)

                    Text(appVersionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DragonHealth by Rene W. Keller. Black Dragon Software Inc. Night Guard reminder. \(reminder.text). \(appVersionText)")
        .onAppear {
            let selection = LaunchSplashReminder.pick(excluding: lastReminderIndex)
            reminder = selection.reminder
            lastReminderIndex = selection.index
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
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

private struct LaunchSplashReminder {
    let text: String

    private static let reminders: [LaunchSplashReminder] = [
        .init(text: "Night Guard matters. Midnight snacks are just breakfast wearing a fake mustache."),
        .init(text: "Protect the evening. Your fridge is not a therapist with interior lighting."),
        .init(text: "Night Guard is important. The kitchen closes earlier than your excuses do."),
        .init(text: "Respect Night Guard. Future-you enjoys sleeping more than negotiating with cookies."),
        .init(text: "A strong night routine beats a heroic morning apology to the scale."),
        .init(text: "Night Guard matters because peanut butter at 11 p.m. is rarely a strategic decision."),
        .init(text: "Be the adult in the room, especially when the room contains cereal."),
        .init(text: "The fork has no emergency powers after kitchen close."),
        .init(text: "Night Guard is your bouncer. If nachos show up late, they do not get in."),
        .init(text: "Your body likes consistency. Your snack drawer likes chaos. Pick a side."),
        .init(text: "Discipline at night is cheaper than regret in the morning."),
        .init(text: "If the craving has a dramatic monologue, give it water and no microphone."),
        .init(text: "Night Guard matters. Hunger whispers; boredom usually arrives in sweatpants."),
        .init(text: "Close the kitchen like a professional, not like a reality show cliffhanger."),
        .init(text: "A late snack promises comfort and delivers paperwork."),
        .init(text: "Tonight's victory is often one boring, brilliant decision repeated on purpose."),
        .init(text: "Night Guard: because willpower is easier before the first 'just one bite.'"),
        .init(text: "You do not need a snack sequel. The first dinner already had an ending."),
        .init(text: "Evening cravings are persuasive, but they do not have voting rights."),
        .init(text: "Guard the night. The pantry is innocent until proven delicious."),
        .init(text: "A closed kitchen is a love letter to tomorrow morning."),
        .init(text: "Night Guard is important. Sleep works best when digestion is not hosting a festival."),
        .init(text: "If it is late and shiny-wrapped, it is probably not your wisest advisor."),
        .init(text: "Be calm, be sharp, be slightly suspicious of late-night trail mix."),
        .init(text: "The mission is simple: brush teeth, drink water, retire undefeated."),
        .init(text: "Night Guard wins quietly. The snack attack arrives with a full marketing department."),
        .init(text: "Your goals deserve a bedtime, not a loophole."),
        .init(text: "Kitchen closed. The chef has gone home and took your rationalizations with him."),
        .init(text: "A smart evening beats a perfect Monday that never starts."),
        .init(text: "Night Guard matters. Mozzarella after dark is still a plot twist."),
        .init(text: "The refrigerator light is not divine guidance."),
        .init(text: "Make tonight boring in the most elite, high-performing way possible."),
        .init(text: "Late-night snacking is cardio for your regrets."),
        .init(text: "You are not missing out. Yogurt will still be there with normal business hours."),
        .init(text: "Night Guard is important. The spoon is not a licensed negotiator."),
        .init(text: "Treat the evening like a runway: close strong and land clean."),
        .init(text: "Small nightly wins build a body that does not need motivational speeches from muffins."),
        .init(text: "If you need drama tonight, make it a herbal tea with steam."),
        .init(text: "Hold the line. Cravings are temporary; dishwasher decisions are forever."),
        .init(text: "Night Guard protects progress from the charming nonsense of 10:47 p.m.")
    ]

    static var defaultReminder: LaunchSplashReminder {
        reminders.first ?? .init(text: "Night Guard is important.")
    }

    static func pick(excluding excludedIndex: Int?) -> (index: Int, reminder: LaunchSplashReminder) {
        guard !reminders.isEmpty else {
            return (0, .init(text: "Night Guard is important."))
        }

        let candidates = reminders.indices.filter { index in
            guard let excludedIndex else { return true }
            return reminders.count == 1 || index != excludedIndex
        }
        let chosenIndex = candidates.randomElement() ?? 0
        return (chosenIndex, reminders[chosenIndex])
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
