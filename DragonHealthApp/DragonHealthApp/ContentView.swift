import Foundation
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
    @State private var showingRestoreBackup = false
    @State private var showingGlobalQuickAdd = false
    @State private var showingGlobalPhotoLog = false
    @State private var globalPhotoLogLaunchSource: MealPhotoLaunchSource?
    @AppStorage("today.quickAddStyle") private var quickAddStyleRaw: String = QuickAddStyle.standard.rawValue

    var body: some View {
        mainContent
        .sheet(isPresented: $showingRestoreBackup) {
            NavigationStack {
                RestoreBackupView()
            }
            .environmentObject(store)
            .environmentObject(backupManager)
        }
        .sheet(isPresented: $showingGlobalQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: nil,
                preselectedMealSlotID: store.currentMealSlotID(),
                contextDate: nil,
                style: globalQuickAddStyle,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.logFoodSelection(
                            date: Date(),
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                    }
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showingGlobalPhotoLog, onDismiss: {
            globalPhotoLogLaunchSource = nil
        }) {
            MealPhotoLogSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems.filter { !$0.kind.isComposite },
                units: store.units,
                preselectedMealSlotID: store.currentMealSlotID(),
                launchSourceOnAppear: globalPhotoLogLaunchSource,
                onSave: { mealSlot, items in
                    Task {
                        let requests = items.compactMap { item -> AppStore.LogPortionRequest? in
                            guard let categoryID = item.categoryID,
                                  let portion = item.portion else {
                                return nil
                            }
                            let category = store.categories.first(where: { $0.id == categoryID })
                            let increment = DrinkRules.portionIncrement(for: category)
                            let trimmedNotes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let notes = trimmedNotes.isEmpty && item.matchedFoodID == nil ? item.foodText : trimmedNotes
                            return AppStore.LogPortionRequest(
                                mealSlotID: mealSlot.id,
                                categoryID: categoryID,
                                portion: Portion(portion, increment: increment),
                                amountValue: item.amountValue,
                                amountUnitID: item.amountUnitID,
                                notes: notes.isEmpty ? nil : notes,
                                foodItemID: item.matchedFoodID
                            )
                        }
                        guard !requests.isEmpty else { return }
                        await store.logPortions(date: Date(), requests: requests)
                    }
                }
            )
            .environmentObject(store)
        }
        .applyPreferredColorScheme(store.settings.appearance.colorScheme)
        .dynamicTypeSize(store.settings.fontSize.dynamicTypeSize)
    }

    private var globalQuickAddStyle: QuickAddStyle {
        QuickAddStyle(rawValue: quickAddStyleRaw) ?? .standard
    }

    private var shouldPerformLaunchHealthSync: Bool {
#if targetEnvironment(simulator)
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("--skip-launch-health-sync") {
            return false
        }
        if processInfo.environment["DRAGONHEALTH_SKIP_LAUNCH_HEALTH_SYNC"] == "1" {
            return false
        }
#endif
        return true
    }

    @ViewBuilder
    private var mainContent: some View {
        switch store.loadState {
        case .loading:
            LaunchLoadingView()
        case .failed(let message):
            VStack(spacing: ZenSpacing.card) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ZenStyle.surface)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                VStack(spacing: ZenSpacing.text) {
                    Text("Unable to load DragonHealth")
                        .zenHeroTitle()
                    Text(message)
                        .zenSupportText()
                        .multilineTextAlignment(.center)
                    Text("You can retry now or restore a backup if the database needs recovery.")
                        .zenSupportText()
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)

                    Button {
                        showingRestoreBackup = true
                    } label: {
                        Label("Restore Backup", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .zenCard(cornerRadius: 24)
        case .ready:
            TabView {
                rootNavigation { DailyHubView() }
                    .tabItem { Label("Journal", systemImage: "calendar") }
                rootNavigation { BodyMetricsView() }
                    .tabItem { Label("Body", systemImage: "waveform.path.ecg") }
                rootNavigation { LibraryView() }
                    .tabItem { Label("Library", systemImage: "book") }
                rootNavigation { ManageView() }
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
                if shouldPerformLaunchHealthSync {
                    healthSyncManager.performSyncOnLaunch(store: store)
                }
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

    private func rootNavigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        globalFoodLogMenu
                    }
                }
        }
    }

    private var globalFoodLogMenu: some View {
        Menu {
            Button("Add Food Manually", systemImage: "plus") {
                showingGlobalQuickAdd = true
            }
            Button("Take Photo", systemImage: "camera") {
                globalPhotoLogLaunchSource = .camera
                showingGlobalPhotoLog = true
            }
            Button("Load Photo", systemImage: "photo.on.rectangle") {
                globalPhotoLogLaunchSource = .library
                showingGlobalPhotoLog = true
            }
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Add food")
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text("Opening DragonHealth")
                    .zenHeroTitle()
                Text("Preparing your data and loading today so you can start right away.")
                    .zenSupportText()
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .zenCard(cornerRadius: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZenStyle.pageBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening DragonHealth. Preparing your data and loading today.")
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

struct StoicLaunchQuote {
    let text: String
    let author: String
    let relevance: String

    static let all: [StoicLaunchQuote] = [
        StoicLaunchQuote(
            text: "The impediment to action advances action. What stands in the way becomes the way.",
            author: "Marcus Aurelius",
            relevance: "A missed meal target or rough day is still usable data. You recover faster when you turn setbacks into the next disciplined choice."
        ),
        StoicLaunchQuote(
            text: "You have power over your mind, not outside events. Realize this, and you will find strength.",
            author: "Marcus Aurelius",
            relevance: "Cravings, schedules, and stress will not fully obey you. Your leverage is the next food decision, the next workout, and the next thought."
        ),
        StoicLaunchQuote(
            text: "The happiness of your life depends upon the quality of your thoughts.",
            author: "Marcus Aurelius",
            relevance: "Health habits get lighter when your inner talk is steady instead of dramatic. Better thoughts make better choices easier to repeat."
        ),
        StoicLaunchQuote(
            text: "Waste no more time arguing what a good man should be. Be one.",
            author: "Marcus Aurelius",
            relevance: "Results come from logged meals, controlled portions, and consistent routines, not from thinking about discipline in the abstract."
        ),
        StoicLaunchQuote(
            text: "Very little is needed to make a happy life.",
            author: "Marcus Aurelius",
            relevance: "Health usually improves through simple repeats: enough protein, sensible portions, regular movement, enough sleep, and fewer extremes."
        ),
        StoicLaunchQuote(
            text: "If it is not right, do not do it; if it is not true, do not say it.",
            author: "Marcus Aurelius",
            relevance: "This keeps nutrition honest. Log what you actually ate, skip the rationalizing, and let clear facts drive the next adjustment."
        ),
        StoicLaunchQuote(
            text: "The soul becomes dyed with the color of its thoughts.",
            author: "Marcus Aurelius",
            relevance: "Repeated self-talk becomes identity. If you keep thinking like a disciplined person, disciplined eating becomes more natural."
        ),
        StoicLaunchQuote(
            text: "The art of living is more like wrestling than dancing.",
            author: "Marcus Aurelius",
            relevance: "Health is not a perfect performance. It is contact work against hunger, convenience, fatigue, and temptation, repeated every day."
        ),
        StoicLaunchQuote(
            text: "Concentrate every minute like a Roman, like a man, on doing what's in front of you.",
            author: "Marcus Aurelius",
            relevance: "You do not need a life overhaul at once. You need the next meal, next log entry, and next training session handled properly."
        ),
        StoicLaunchQuote(
            text: "When you arise in the morning, think of what a privilege it is to be alive, to breathe, to think, to enjoy, to love.",
            author: "Marcus Aurelius",
            relevance: "Gratitude lowers the urge to self-sabotage. Caring for your body is easier when you treat being alive as something worth stewarding."
        ),
        StoicLaunchQuote(
            text: "Do every act of your life as though it were the very last act of your life.",
            author: "Marcus Aurelius",
            relevance: "That mindset sharpens small decisions. One snack, one portion, and one workout each deserve full intention instead of autopilot."
        ),
        StoicLaunchQuote(
            text: "Objective judgment, now, at this very moment. Unselfish action, now, at this very moment. Willing acceptance, now.",
            author: "Marcus Aurelius",
            relevance: "Good health requires honest assessment, immediate action, and calm acceptance of today's reality instead of resentment about it."
        ),
        StoicLaunchQuote(
            text: "Today I escaped from anxiety. Or no, I discarded it, because it was within me.",
            author: "Marcus Aurelius",
            relevance: "Stress eating often starts in interpretation before appetite. When you calm the story, you usually calm the urge."
        ),
        StoicLaunchQuote(
            text: "You always own the option of having no opinion.",
            author: "Marcus Aurelius",
            relevance: "Not every craving deserves a speech. Sometimes the cleanest move is to notice it, refuse to dramatize it, and move on."
        ),
        StoicLaunchQuote(
            text: "Look well into thyself; there is a source of strength which will always spring up.",
            author: "Marcus Aurelius",
            relevance: "Discipline becomes durable when it stops depending on mood. The reserve you need is built inside repeated self-command."
        ),
        StoicLaunchQuote(
            text: "Nothing happens to anyone that he cannot endure.",
            author: "Marcus Aurelius",
            relevance: "Hunger between meals, a missed indulgence, or training discomfort are usually tolerable. Remembering that keeps impulses smaller."
        ),
        StoicLaunchQuote(
            text: "The cucumber is bitter? Then throw it out. There are brambles in the path? Then go around them.",
            author: "Marcus Aurelius",
            relevance: "Make health practical. Remove foods that repeatedly derail you and design easier routes instead of debating them."
        ),
        StoicLaunchQuote(
            text: "Receive without pride, let go without attachment.",
            author: "Marcus Aurelius",
            relevance: "This helps with both progress and slips. Accept a good week calmly, and let one bad meal pass without clinging to it."
        ),
        StoicLaunchQuote(
            text: "No carelessness in your actions. No confusion in your words. No imprecision in your thoughts.",
            author: "Marcus Aurelius",
            relevance: "Health improves when your logging, portions, and self-assessment become precise. Vagueness is where drift hides."
        ),
        StoicLaunchQuote(
            text: "Of my mother I learned to live simply and to avoid the ways of the rich.",
            author: "Marcus Aurelius",
            relevance: "Simple eating is usually easier to repeat than elaborate eating. Basic meals beat fancy plans that collapse under real life."
        ),
        StoicLaunchQuote(
            text: "First say to yourself what you would be; and then do what you have to do.",
            author: "Epictetus",
            relevance: "If the goal is to be healthy and steady, your calendar, portions, and evening choices need to match that identity."
        ),
        StoicLaunchQuote(
            text: "Practice yourself, for heaven's sake, in little things; and then proceed to greater.",
            author: "Epictetus",
            relevance: "Big body changes usually come from small reps: one measured serving, one planned breakfast, one walk, one honest log."
        ),
        StoicLaunchQuote(
            text: "It is difficulties that show what men are.",
            author: "Epictetus",
            relevance: "Anyone can be disciplined when life is easy. Your real standard appears when you are tired, rushed, social, or stressed."
        ),
        StoicLaunchQuote(
            text: "No great thing is created suddenly.",
            author: "Epictetus",
            relevance: "Lasting health is a construction project, not a rescue mission. Slow consistency beats aggressive swings."
        ),
        StoicLaunchQuote(
            text: "Every habit and faculty is maintained and increased by corresponding actions.",
            author: "Epictetus",
            relevance: "Each repeat matters. Every measured meal strengthens restraint, and every impulsive one strengthens the opposite pattern."
        ),
        StoicLaunchQuote(
            text: "Whatever you would make habitual, practice it.",
            author: "Epictetus",
            relevance: "If you want discipline to feel natural, rehearse it daily. Habits are built by action, not preference."
        ),
        StoicLaunchQuote(
            text: "Freedom is secured not by the fulfilling of men's desires, but by the removal of desire.",
            author: "Epictetus",
            relevance: "Food freedom is not eating every impulse. It is needing less from food emotionally and becoming harder to control through appetite."
        ),
        StoicLaunchQuote(
            text: "If you want to improve, be content to be thought foolish and stupid.",
            author: "Epictetus",
            relevance: "Health sometimes means declining drinks, skipping dessert, or leaving early to sleep. Social approval is a weak reason to self-betray."
        ),
        StoicLaunchQuote(
            text: "We are not troubled by things, but by the opinions which we have of things.",
            author: "Epictetus",
            relevance: "A craving, a weigh-in, or a missed target hurts most when you turn it into a verdict about yourself instead of a fact to manage."
        ),
        StoicLaunchQuote(
            text: "On the occasion of every accident that befalls you, remember to turn to yourself and inquire what power you have for turning it to use.",
            author: "Epictetus",
            relevance: "An overeating episode can still become a better grocery list, a clearer trigger map, or a stronger evening routine."
        ),
        StoicLaunchQuote(
            text: "Who then is invincible? He whom nothing external can dismay.",
            author: "Epictetus",
            relevance: "Restaurants, travel, stress, and celebrations matter less when your standards come from within and not from the environment."
        ),
        StoicLaunchQuote(
            text: "No man is free who is not master of himself.",
            author: "Epictetus",
            relevance: "Real autonomy shows up in appetite. If every urge gets obedience, your schedule owns you less than your impulses do."
        ),
        StoicLaunchQuote(
            text: "If you seek truth, you will not seek victory by dishonest means.",
            author: "Epictetus",
            relevance: "Do not try to win against the app or the plan. Honest logging is more useful than flattering numbers."
        ),
        StoicLaunchQuote(
            text: "Bear in mind that you should conduct yourself in life as at a feast.",
            author: "Epictetus",
            relevance: "Take what fits, pass on what does not, and do not lunge. That is a solid operating system for food."
        ),
        StoicLaunchQuote(
            text: "Don't demand that things happen as you wish, but wish that they happen as they do happen, and you will go on well.",
            author: "Epictetus",
            relevance: "The day will not always suit your ideal plan. Accepting reality quickly helps you make the best available choice."
        ),
        StoicLaunchQuote(
            text: "If you would cure anger, do not feed the habit.",
            author: "Epictetus",
            relevance: "The same pattern applies to overeating. Every unchallenged impulse trains the next one, so interruption matters."
        ),
        StoicLaunchQuote(
            text: "Any person capable of angering you becomes your master.",
            author: "Epictetus",
            relevance: "Applied to health, anything that can automatically trigger your eating owns a piece of your behavior until you take it back."
        ),
        StoicLaunchQuote(
            text: "You may fetter my leg, but not even Zeus has power over my will.",
            author: "Epictetus",
            relevance: "Even when energy is low or circumstances are messy, your will still decides honesty, restraint, and the next deliberate act."
        ),
        StoicLaunchQuote(
            text: "In theory there is nothing to hinder our following what we are taught; in life there are many things to draw us aside.",
            author: "Epictetus",
            relevance: "Knowing nutrition is not the same as living it. This quote keeps the focus on execution under friction."
        ),
        StoicLaunchQuote(
            text: "How long are you going to wait before you demand the best for yourself?",
            author: "Epictetus",
            relevance: "Health usually stalls in delay. Start with the next action instead of waiting for a cleaner week or a better mood."
        ),
        StoicLaunchQuote(
            text: "We suffer more often in imagination than in reality.",
            author: "Seneca",
            relevance: "Many feared healthy choices are milder than they look. The skipped snack, the workout, or the honest weigh-in is usually manageable."
        ),
        StoicLaunchQuote(
            text: "Difficulties strengthen the mind, as labor does the body.",
            author: "Seneca",
            relevance: "Repeated effort does double work. Training strengthens your body while restraint under pressure strengthens your character."
        ),
        StoicLaunchQuote(
            text: "Most powerful is he who has himself in his own power.",
            author: "Seneca",
            relevance: "Self-command matters more than motivation. When you can direct yourself, food and mood stop steering the day."
        ),
        StoicLaunchQuote(
            text: "It is not the man who has too little, but the man who craves more, that is poor.",
            author: "Seneca",
            relevance: "Endless wanting keeps eating noisy. Enough becomes easier when you stop treating desire as a command."
        ),
        StoicLaunchQuote(
            text: "True happiness is to enjoy the present, without anxious dependence upon the future.",
            author: "Seneca",
            relevance: "Do today's basics well instead of bargaining with some future perfect body. Presence is better for both adherence and peace."
        ),
        StoicLaunchQuote(
            text: "While we are postponing, life speeds by.",
            author: "Seneca",
            relevance: "Deferring sleep, movement, or meal structure has a cost. Use today instead of imagining that discipline starts later."
        ),
        StoicLaunchQuote(
            text: "As is a tale, so is life: not how long it is, but how good it is, is what matters.",
            author: "Seneca",
            relevance: "Health is not only about extending years. It is also about making daily life clearer, stronger, and more capable."
        ),
        StoicLaunchQuote(
            text: "It is not because things are difficult that we do not dare; it is because we do not dare that things are difficult.",
            author: "Seneca",
            relevance: "The routine feels intimidating mostly before it starts. Action makes structure feel normal much faster than hesitation does."
        ),
        StoicLaunchQuote(
            text: "Begin at once to live, and count each separate day as a separate life.",
            author: "Seneca",
            relevance: "This helps after slips. Today does not need to wait for Monday; it can still be a complete reset."
        ),
        StoicLaunchQuote(
            text: "The body should be treated more rigorously, that it may not be disobedient to the mind.",
            author: "Seneca",
            relevance: "Comfort cannot always set policy. A little chosen hardship makes the body a better partner instead of a demanding ruler."
        )
    ]
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

private extension View {
    @ViewBuilder
    func applyPreferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        if let colorScheme {
            preferredColorScheme(colorScheme)
        } else {
            self
        }
    }
}
