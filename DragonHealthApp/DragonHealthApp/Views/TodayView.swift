import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
#endif

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = TodayViewModel()
    @State private var showingScoreExplain = false
    @State private var showingDailyOverview = false
    @State private var showingMealsAndEntries = false
    @State private var showingMorningReflection = false
    @State private var didResolveMorningReflectionForSession = false
    @AppStorage("today.mealDisplayStyle") private var mealDisplayStyleRaw: String = MealDisplayStyle.miniCards.rawValue
    @AppStorage("today.quickAddStyle") private var quickAddStyleRaw: String = QuickAddStyle.standard.rawValue
    @AppStorage("launchSplash.stoicQuoteIndex") private var stoicQuoteIndex = 0

    private var mealDisplayStyle: MealDisplayStyle {
        MealDisplayStyle(rawValue: mealDisplayStyleRaw) ?? .miniCards
    }
    private var quickAddStyle: QuickAddStyle {
        QuickAddStyle(rawValue: quickAddStyleRaw) ?? .standard
    }

    private var categoriesNeedingAttentionCount: Int {
        guard let adherence = viewModel.adherence else { return 0 }
        return adherence.categoryResults.filter { !$0.targetMet }.count
    }

    private var dailyOverviewSubtitle: String {
        if viewModel.visibleFoodCategories.isEmpty {
            return "Set up food categories to see score and progress."
        }
        if let scoreSummary = viewModel.scoreSummary {
            let roundedScore = Int(scoreSummary.overallScore.rounded())
            if categoriesNeedingAttentionCount > 0 {
                let noun = categoriesNeedingAttentionCount == 1 ? "category" : "categories"
                return "Score \(roundedScore) with \(categoriesNeedingAttentionCount) \(noun) needing attention."
            }
            return "Score \(roundedScore) and category progress for today."
        }
        return "Track category progress and what needs attention next."
    }

    private var mealsAndEntriesSubtitle: String {
        let entryCount = viewModel.mealEntries.count
        if entryCount == 0 {
            return "Nothing logged yet. Your meals will collect here after the first entry."
        }
        let noun = entryCount == 1 ? "entry" : "entries"
        return "\(entryCount) \(noun) logged today."
    }

    private var normalizedQuoteIndex: Int {
        guard !StoicLaunchQuote.all.isEmpty else { return 0 }
        let count = StoicLaunchQuote.all.count
        return ((stoicQuoteIndex % count) + count) % count
    }

    private var currentReflectionQuote: StoicLaunchQuote? {
        guard !StoicLaunchQuote.all.isEmpty else { return nil }
        return StoicLaunchQuote.all[normalizedQuoteIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let mealEntries = viewModel.mealEntries

                TodayPhotoHeroCard(
                    mealSlotName: viewModel.currentMealSlotName,
                    onQuickAdd: {
                        viewModel.openQuickAdd()
                    },
                    onTakePhoto: {
                        viewModel.openPhotoLog(launchSource: .camera)
                    },
                    onLoadPhoto: {
                        viewModel.openPhotoLog(launchSource: .library)
                    }
                )

                if !viewModel.visibleFoodCategories.isEmpty {
                    FoodCategoryDashboardView(
                        categories: viewModel.visibleFoodCategories,
                        totals: viewModel.totals,
                        scoreSummary: viewModel.scoreSummary,
                        mealSlots: store.mealSlots,
                        currentMealSlotID: viewModel.currentMealSlotID
                    ) { category in
                        CategoryDayDetailView(category: category)
                    }
                }

                if !viewModel.visibleCategories.isEmpty {
                    TodayPriorityStackView(
                        categories: viewModel.visibleCategories,
                        totals: viewModel.totals,
                        scoreSummary: viewModel.scoreSummary,
                        onQuickAddAmount: { categoryID, amount in
                            Task {
                                await viewModel.logQuickAmount(
                                    store: store,
                                    categoryID: categoryID,
                                    amount: amount
                                )
                            }
                        },
                        onLogNow: { categoryID in
                            viewModel.openQuickAdd(categoryID: categoryID)
                        }
                    )

                    TodayMealTimelineRail(
                        mealSlots: store.mealSlots,
                        entries: mealEntries,
                        currentMealSlotID: viewModel.currentMealSlotID,
                        onQuickAddForMeal: { mealSlotID in
                            viewModel.openQuickAdd(mealSlotID: mealSlotID)
                        }
                    )
                }

                if store.settings.showLaunchSplash,
                   showingMorningReflection,
                   let quote = currentReflectionQuote {
                    MorningReflectionCard(
                        quote: quote,
                        onHide: { hideMorningReflection() },
                        onNext: { advanceMorningReflection() }
                    )
                }

                TodaySectionDisclosureCard(
                    title: "Score & coaching",
                    subtitle: dailyOverviewSubtitle,
                    isExpanded: $showingDailyOverview
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        TodayHeaderView(
                            adherence: viewModel.adherence,
                            scoreSummary: viewModel.scoreSummary,
                            categories: store.categories,
                            totals: viewModel.totals,
                            onExplainScore: viewModel.canExplainScore ? { showingScoreExplain = true } : nil
                        )

                        if viewModel.visibleFoodCategories.isEmpty {
                            Text("No food categories configured yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TodaySectionDisclosureCard(
                    title: "Meals & entries",
                    subtitle: mealsAndEntriesSubtitle,
                    isExpanded: $showingMealsAndEntries
                ) {
                    if mealEntries.isEmpty {
                        Text("Your meal timeline, breakdown, and entry details will appear here after your first log.")
                            .zenSupportText()
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            TodayMealBreakdownView(
                                mealSlots: store.mealSlots,
                                entries: mealEntries,
                                categories: store.categories,
                                style: mealDisplayStyle
                            )

                            TodayMealDetailsSection(
                                mealSlots: store.mealSlots,
                                entries: mealEntries,
                                categories: store.categories,
                                foodItems: store.foodItems,
                                onViewDetails: { entry in
                                    viewModel.viewingEntry = entry
                                },
                                onEdit: { entry in
                                    viewModel.editingEntry = entry
                                },
                                onDelete: { entry in
                                    Task { await viewModel.deleteEntry(store: store, entry) }
                                }
                            )
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 108)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TodayNavTitleView(date: viewModel.currentDay)
            }
        }
        .sheet(isPresented: $showingScoreExplain) {
            if let scoreSummary = viewModel.scoreSummary {
                TodayScoreExplainSheet(
                    scoreSummary: scoreSummary,
                    categories: store.categories,
                    totals: viewModel.totals
                )
            }
        }
        .sheet(isPresented: $viewModel.showingQuickAdd, onDismiss: {
            viewModel.clearQuickAddPrefill()
        }) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: viewModel.quickAddPrefillCategoryID,
                preselectedMealSlotID: viewModel.quickAddPrefillMealSlotID ?? store.currentMealSlotID(),
                contextDate: nil,
                style: quickAddStyle,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await self.viewModel.saveQuickAdd(
                            store: store,
                            mealSlot: mealSlot,
                            category: category,
                            portion: portion,
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showingPhotoLog) {
            MealPhotoLogSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems.filter { !$0.kind.isComposite },
                units: store.units,
                preselectedMealSlotID: viewModel.currentMealSlotID,
                launchSourceOnAppear: viewModel.photoLogLaunchSource,
                onSave: { mealSlot, items in
                    Task { await viewModel.savePhotoLog(store: store, mealSlot: mealSlot, items: items) }
                }
            )
        }
        .onChange(of: viewModel.showingPhotoLog) { _, isPresented in
            viewModel.handlePhotoLogPresentationChange(isPresented: isPresented)
        }
        .sheet(item: $viewModel.editingEntry) { entry in
            EntryEditSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await self.viewModel.saveEditedEntry(
                            store: store,
                            entry: entry,
                            mealSlot: mealSlot,
                            category: category,
                            portion: portion,
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                    }
                }
            )
        }
        .sheet(item: $viewModel.viewingEntry) { entry in
            EntryDetailSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units
            )
        }
        .task(id: store.refreshToken) {
            await viewModel.loadToday(store: store)
        }
        .onAppear {
            if !didResolveMorningReflectionForSession {
                showingMorningReflection = store.settings.showLaunchSplash
                didResolveMorningReflectionForSession = true
            }
            showingMealsAndEntries = !viewModel.mealEntries.isEmpty
        }
        .onChange(of: viewModel.mealEntries.count) { _, newCount in
            if newCount > 0 {
                showingMealsAndEntries = true
            }
        }
        .onChange(of: store.settings.showLaunchSplash) { _, newValue in
            showingMorningReflection = newValue
            didResolveMorningReflectionForSession = true
        }
        .overlay(alignment: .top) {
            if let message = viewModel.saveConfirmationMessage {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func hideMorningReflection() {
        showingMorningReflection = false
        if !StoicLaunchQuote.all.isEmpty {
            stoicQuoteIndex = (normalizedQuoteIndex + 1) % StoicLaunchQuote.all.count
        }
    }

    private func advanceMorningReflection() {
        guard !StoicLaunchQuote.all.isEmpty else { return }
        stoicQuoteIndex = (normalizedQuoteIndex + 1) % StoicLaunchQuote.all.count
    }
}

private struct MorningReflectionCard: View {
    let quote: StoicLaunchQuote
    let onHide: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Morning reflection")
                        .zenEyebrow()
                    Text("A quiet thought for the day.")
                        .zenSupportText()
                }
                Spacer()
                Button("Hide for now") {
                    onHide()
                }
                .glassButton(.compact)
                .font(.caption)
            }

            Text("\"\(quote.text)\"")
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(quote.author)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(quote.relevance)
                .zenSupportText()
                .fixedSize(horizontal: false, vertical: true)

            Button("Next thought") {
                onNext()
            }
            .glassButton(.compact)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .zenCard(cornerRadius: 18)
    }
}

private struct TodaySectionDisclosureCard<Content: View>: View {
    let title: String
    let subtitle: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .zenSupportText()
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zenCard(cornerRadius: 18)
    }
}

private struct TodayPhotoHeroCard: View {
    let mealSlotName: String?
    let onQuickAdd: () -> Void
    let onTakePhoto: () -> Void
    let onLoadPhoto: () -> Void

    private var cardContext: String {
        if let mealSlotName {
            return "Ready to log \(mealSlotName.lowercased())."
        }
        return "Choose the fastest way to log food."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log food")
                .zenEyebrow()

            Label(cardContext, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                TodayLoggingActionButton(
                    title: "Add manually",
                    systemImage: "plus",
                    style: .secondary,
                    action: onQuickAdd
                )
                TodayLoggingActionButton(
                    title: "Take photo",
                    systemImage: "camera",
                    style: .primary,
                    action: onTakePhoto
                )
                TodayLoggingActionButton(
                    title: "Load photo",
                    systemImage: "photo.on.rectangle",
                    style: .secondary,
                    action: onLoadPhoto
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZenSpacing.card)
        .zenCard()
    }
}

private enum TodayLoggingActionStyle {
    case primary
    case secondary
}

private struct TodayLoggingActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    let style: TodayLoggingActionStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: borderLineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return colorScheme == .dark ? .black : .white
        case .secondary:
            return .primary
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary
        case .secondary:
            return ZenStyle.surface
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return .clear
        case .secondary:
            return Color.primary.opacity(0.08)
        }
    }

    private var borderLineWidth: CGFloat {
        switch style {
        case .primary:
            return 0
        case .secondary:
            return 1
        }
    }
}

private enum TodayDateFormatter {
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE"
        return formatter
    }()
    static let restFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "d MMM yy"
        return formatter
    }()

    static func string(from date: Date) -> String {
        let weekday = weekdayFormatter.string(from: date)
        let rest = restFormatter.string(from: date)
        return "\(weekday), \(rest)"
    }
}

private struct TodayNavTitleView: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Today")
                .font(.headline)
            Text(TodayDateFormatter.string(from: date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today, \(TodayDateFormatter.string(from: date))")
    }
}

private struct TodayHeaderView: View {
    let adherence: DailyAdherenceSummary?
    let scoreSummary: DailyScoreSummary?
    let categories: [Core.Category]
    let totals: [UUID: Double]
    let onExplainScore: (() -> Void)?

    private struct GoalAction {
        let text: String
        let severity: Double
    }

    private var focusPoints: [String] {
        guard let adherence else { return [] }
        guard !adherence.categoryResults.isEmpty else { return [] }

        let actions = goalActions(for: adherence)
        if actions.isEmpty {
            return ["Repeat what is working at your next meal."]
        }

        return actions
            .prefix(3)
            .map(\.text)
    }

    private var emptyGoalsText: String? {
        guard let adherence else { return nil }
        guard adherence.categoryResults.isEmpty else { return nil }
        return "No category goals configured yet."
    }

    private var microCoachingText: String? {
        guard let scoreSummary else { return nil }
        let score = Int(scoreSummary.overallScore.rounded())
        if score >= 85 {
            return "Score \(score)/100: on track."
        }
        if score >= 70 {
            return "Score \(score)/100: close to green. Focus on the priorities below."
        }
        return "Score \(score)/100: recovery mode. Focus on the priorities below."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.text) {
            if let scoreSummary {
                if let onExplainScore {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ScoreBadge(score: scoreSummary.overallScore)
                            Spacer(minLength: 12)
                            explainScoreButton(onExplainScore: onExplainScore)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ScoreBadge(score: scoreSummary.overallScore)
                            explainScoreButton(onExplainScore: onExplainScore)
                        }
                    }
                } else {
                    ScoreBadge(score: scoreSummary.overallScore)
                }
                if let microCoachingText {
                    Text(microCoachingText)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !focusPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Focus now")
                            .zenMetricLabel()
                        ForEach(Array(focusPoints.enumerated()), id: \.offset) { index, point in
                            Text("\(index + 1). \(point)")
                                .font(.footnote)
                                .foregroundStyle(Color.primary.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if let emptyGoalsText {
                    Text(emptyGoalsText)
                        .zenSupportText()
                }
            } else if !focusPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Focus now")
                        .zenMetricLabel()
                    ForEach(Array(focusPoints.enumerated()), id: \.offset) { index, point in
                        Text("\(index + 1). \(point)")
                            .font(.footnote)
                            .foregroundStyle(Color.primary.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let emptyGoalsText {
                Text(emptyGoalsText)
                    .zenSupportText()
            } else {
                Text("No data yet")
                    .zenSupportText()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    @ViewBuilder
    private func explainScoreButton(onExplainScore: @escaping () -> Void) -> some View {
        Button("Explain Score") {
            onExplainScore()
        }
        .glassButton(.compact)
        .font(.caption)
    }

    private func goalActions(for adherence: DailyAdherenceSummary) -> [GoalAction] {
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return adherence.categoryResults
            .compactMap { result in
                guard !result.targetMet else { return nil }
                guard let category = categoriesByID[result.categoryID] else { return nil }
                return goalAction(for: category, total: result.total)
            }
            .sorted { $0.severity > $1.severity }
    }

    private func goalAction(for category: Core.Category, total: Double) -> GoalAction? {
        switch category.targetRule {
        case .exact(let target):
            let minValue = max(0, target - TargetRule.exactTolerance)
            let maxValue = target + TargetRule.exactTolerance
            if total < minValue {
                return underTargetAction(category: category, missing: minValue - total, targetReference: minValue)
            }
            if total > maxValue {
                return overTargetAction(category: category, excess: total - maxValue, targetReference: maxValue)
            }
        case .atLeast(let target):
            if total < target {
                return underTargetAction(category: category, missing: target - total, targetReference: target)
            }
        case .atMost(let target):
            if total > target {
                return overTargetAction(category: category, excess: total - target, targetReference: target)
            }
        case .range(let minValue, let maxValue):
            if total < minValue {
                return underTargetAction(category: category, missing: minValue - total, targetReference: minValue)
            }
            if total > maxValue {
                return overTargetAction(category: category, excess: total - maxValue, targetReference: maxValue)
            }
        }
        return nil
    }

    private func underTargetAction(category: Core.Category, missing: Double, targetReference: Double) -> GoalAction {
        let displayName = displayCategoryName(category.name)
        let intensity = intensityText(for: missing)
        let safeTarget = max(targetReference, 0.1)
        let severity = missing / safeTarget

        if isDrinkCategory(category) {
            return GoalAction(text: "drink \(missing.cleanNumber) \(category.unitName.lowercased())", severity: severity)
        }
        if isSportsCategory(category) {
            return GoalAction(text: "add \(missing.cleanNumber) \(category.unitName) activity", severity: severity)
        }
        if isCarbCategory(displayName) {
            return GoalAction(text: "add \(intensity)carbs", severity: severity)
        }
        if isProteinCategory(displayName) {
            return GoalAction(text: "add \(intensity)protein", severity: severity)
        }
        return GoalAction(text: "add \(intensity)\(displayName.lowercased())", severity: severity)
    }

    private func overTargetAction(category: Core.Category, excess: Double, targetReference: Double) -> GoalAction {
        let displayName = displayCategoryName(category.name).lowercased()
        let safeTarget = max(targetReference, 0.1)
        let severity = excess / safeTarget
        return GoalAction(
            text: "reduce \(displayName) by \(excess.cleanNumber) \(category.unitName)",
            severity: severity
        )
    }

    private func intensityText(for amount: Double) -> String {
        if amount >= 1 {
            return "much more "
        }
        if amount >= 0.4 {
            return "more "
        }
        return "a bit more "
    }

    private func displayCategoryName(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "starchy sides" || normalized == "starchy items" {
            return "Carb"
        }
        return name
    }

    private func isCarbCategory(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "carb" || lower.contains("starch")
    }

    private func isProteinCategory(_ name: String) -> Bool {
        name.lowercased().contains("protein")
    }

    private func isDrinkCategory(_ category: Core.Category) -> Bool {
        DrinkRules.isDrinkCategory(category)
    }

    private func isSportsCategory(_ category: Core.Category) -> Bool {
        category.name.lowercased().contains("sport")
    }
}

private struct TodayPriorityStackView: View {
    let categories: [Core.Category]
    let totals: [UUID: Double]
    let scoreSummary: DailyScoreSummary?
    let onQuickAddAmount: (UUID, Double) -> Void
    let onLogNow: (UUID) -> Void

    private var priorities: [TodayPriorityItem] {
        let scoreByID = Dictionary(uniqueKeysWithValues: (scoreSummary?.categoryScores ?? []).map { ($0.categoryID, $0.score) })
        return categories
            .compactMap { category in
                let total = totals[category.id] ?? 0
                let missing = missingAmount(rule: category.targetRule, total: total)
                let excess = excessAmount(rule: category.targetRule, total: total)
                guard missing > 0 || excess > 0 else { return nil }
                let direction: TodayPriorityDirection = missing > 0 ? .under : .over
                let gap = max(missing, excess)
                let scorePenalty = max(0, 100 - (scoreByID[category.id] ?? 100))
                let impact = gap + (scorePenalty / 40.0)
                return TodayPriorityItem(
                    category: category,
                    direction: direction,
                    gap: gap,
                    impact: impact,
                    score: scoreByID[category.id]
                )
            }
            .sorted { $0.impact > $1.impact }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Priority Stack")
                .font(.headline)
            if priorities.isEmpty {
                Text("You are on track across categories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
            } else {
                ForEach(priorities.prefix(3)) { item in
                    priorityCard(for: item)
                }
            }
        }
    }

    private func priorityCard(for item: TodayPriorityItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.category.name)
                        .font(.subheadline.weight(.semibold))
                    if let score = item.score {
                        Text("Category score \(Int(score.rounded()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: item.direction == .under ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(item.direction == .under ? .orange : .red)
            }

            if item.direction == .under {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.primaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        priorityActions(for: item)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.primaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        priorityActions(for: item)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.primaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Review this category before adding more today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func priorityActions(for item: TodayPriorityItem) -> some View {
        HStack(spacing: 6) {
            ForEach(item.quickAmounts, id: \.self) { amount in
                Button("+\(amount.cleanNumber)") {
                    onQuickAddAmount(item.category.id, amount)
                }
                .glassButton(.compact)
                .font(.caption)
            }
            Button("Log") {
                onLogNow(item.category.id)
            }
            .glassButton(.compact)
            .font(.caption)
        }
    }
}

private struct TodayMealTimelineRail: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let currentMealSlotID: UUID?
    let onQuickAddForMeal: (UUID) -> Void

    private var countsByMealSlotID: [UUID: Int] {
        Dictionary(grouping: entries, by: \.mealSlotID).mapValues(\.count)
    }

    private var showsOverflowHint: Bool {
        mealSlots.count > 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meal Timeline")
                    .font(.headline)
                Spacer()
                if showsOverflowHint {
                    Label("More", systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(mealSlots) { slot in
                            let count = countsByMealSlotID[slot.id] ?? 0
                            VStack(spacing: 8) {
                                NavigationLink {
                                    MealDayDetailView(mealSlot: slot)
                                } label: {
                                    TodayMealTimelineCell(
                                        mealSlot: slot,
                                        loggedCount: count,
                                        isCurrent: slot.id == currentMealSlotID
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onQuickAddForMeal(slot.id)
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .glassButton(.compact)
                                .accessibilityLabel("Add entry for \(slot.name)")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if showsOverflowHint {
                    LinearGradient(
                        colors: [
                            ZenStyle.pageBackground.opacity(0),
                            ZenStyle.pageBackground
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                    .allowsHitTesting(false)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.9))
                            .padding(.trailing, 4)
                    }
                }
            }
        }
    }
}

private struct TodayMealTimelineCell: View {
    let mealSlot: MealSlot
    let loggedCount: Int
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(loggedCount > 0 ? Color.green : Color(.systemGray4))
                    .frame(width: 8, height: 8)
                Text(mealSlot.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(loggedCount == 0 ? "No logs" : "\(loggedCount) entries")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 118, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? ZenStyle.elevatedSurface : ZenStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
        )
    }
}

private struct TodayScoreExplainSheet: View {
    let scoreSummary: DailyScoreSummary
    let categories: [Core.Category]
    let totals: [UUID: Double]
    @Environment(\.dismiss) private var dismiss

    private var rows: [TodayScoreExplainRow] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return scoreSummary.categoryScores
            .compactMap { categoryScore in
                guard let category = categoryByID[categoryScore.categoryID] else { return nil }
                let effectiveTotal = totals[category.id] ?? categoryScore.adjustedTotal
                let missing = missingAmount(rule: category.targetRule, total: effectiveTotal)
                let excess = excessAmount(rule: category.targetRule, total: effectiveTotal)
                let driver: String
                let recommendation: String
                if missing > 0 {
                    driver = "Below target by \(missing.cleanNumber) \(category.unitName)"
                    recommendation = "Add a small log in \(category.name.lowercased()) next."
                } else if excess > 0 {
                    driver = "Over target by \(excess.cleanNumber) \(category.unitName)"
                    recommendation = "Pause \(category.name.lowercased()) for the next meal window."
                } else {
                    driver = "On target"
                    recommendation = "Keep current pace."
                }
                return TodayScoreExplainRow(
                    categoryName: category.name,
                    score: categoryScore.score,
                    driver: driver,
                    recommendation: recommendation,
                    isOnTarget: missing == 0 && excess == 0
                )
            }
            .sorted { $0.score < $1.score }
    }

    private var bestNextMove: String {
        if let underTarget = rows.first(where: { !$0.isOnTarget && $0.driver.hasPrefix("Below target") }) {
            return "Fastest gain: \(underTarget.recommendation)"
        }
        if let offTarget = rows.first(where: { !$0.isOnTarget }) {
            return "Fastest gain: \(offTarget.recommendation)"
        }
        return "All categories are aligned. Keep consistency through the next meal."
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    HStack {
                        Text("Overall Score")
                        Spacer()
                        ScoreBadge(score: scoreSummary.overallScore)
                    }
                    Text(bestNextMove)
                        .font(.subheadline)
                }

                Section("Drivers") {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.categoryName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(row.score.rounded()))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ScoreColor.color(for: row.score))
                            }
                            Text(row.driver)
                                .font(.caption)
                            Text(row.recommendation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("Score Explain")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .glassButton(.text)
                }
            }
        }
    }
}

private struct TodayPriorityItem: Identifiable {
    let category: Core.Category
    let direction: TodayPriorityDirection
    let gap: Double
    let impact: Double
    let score: Double?

    var id: UUID { category.id }

    var primaryText: String {
        switch direction {
        case .under:
            return "Need \(gap.cleanNumber) \(category.unitName)"
        case .over:
            return "Over by \(gap.cleanNumber) \(category.unitName)"
        }
    }

    var quickAmounts: [Double] {
        if DrinkRules.isDrinkCategory(category) {
            return [0.25, 0.5]
        }
        if category.name.lowercased().contains("sport") {
            return [10, 20]
        }
        return [0.5, 1.0]
    }
}

private struct TodayScoreExplainRow: Identifiable {
    let id = UUID()
    let categoryName: String
    let score: Double
    let driver: String
    let recommendation: String
    let isOnTarget: Bool
}

private enum TodayPriorityDirection {
    case under
    case over
}

private struct FoodCategoryDashboardView<Destination: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let footerHeight: CGFloat = 36
    let categories: [Core.Category]
    let totals: [UUID: Double]
    let scoreSummary: DailyScoreSummary?
    let mealSlots: [MealSlot]
    let currentMealSlotID: UUID?
    let destination: (Core.Category) -> Destination

    private var dashboardScaleMax: Double {
        let targetMax = categories.map { FoodBarMetric.upperBound(for: $0) }.max() ?? 1
        let valueMax = categories.map { max(totals[$0.id] ?? 0, 0) }.max() ?? 1
        return max(targetMax, valueMax) * 1.08
    }

    private var mealProgress: Double {
        let orderedMealSlots = mealSlots.sorted { $0.sortOrder < $1.sortOrder }
        guard !orderedMealSlots.isEmpty else { return 0.5 }
        guard let currentMealSlotID,
              let index = orderedMealSlots.firstIndex(where: { $0.id == currentMealSlotID }) else {
            return 0.5
        }
        return min(max(Double(index + 1) / Double(orderedMealSlots.count), 0.12), 1.0)
    }

    private var metrics: [FoodBarMetric] {
        categories.map { category in
            FoodBarMetric.make(
                category: category,
                total: totals[category.id] ?? 0,
                mealProgress: mealProgress
            )
        }
    }

    private var summaryText: String {
        let safe = metrics.filter { $0.status == .safe }.count
        let risk = metrics.filter { $0.status == .risk }.count
        let over = metrics.filter { $0.status == .over }.count
        let building = max(metrics.count - safe - risk - over, 0)

        var parts: [String] = []
        if safe > 0 { parts.append("\(safe) SAFE") }
        if risk > 0 { parts.append("\(risk) RISK") }
        if over > 0 { parts.append("\(over) OVER") }
        if building > 0 { parts.append("\(building) BUILD") }
        return parts.joined(separator: "  ·  ")
    }

    private var panelGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.17, blue: 0.20),
                Color(red: 0.08, green: 0.09, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var roundedOverallScore: Int? {
        scoreSummary.map { Int($0.overallScore.rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FOOD CATEGORIES")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(summaryText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let roundedOverallScore {
                        HStack(spacing: 8) {
                            Text("SCORE")
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(Color.white.opacity(0.66))
                            Text("\(roundedOverallScore)")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Text("BOTTOM-UP")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(Color.white.opacity(0.84))
                }
            }

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
                    .padding(.bottom, footerHeight + 8)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(categories) { category in
                        let total = totals[category.id] ?? 0
                        NavigationLink {
                            destination(category)
                        } label: {
                            AthleticFoodBarTile(
                                metric: FoodBarMetric.make(
                                    category: category,
                                    total: total,
                                    mealProgress: mealProgress
                                ),
                                scaleMax: dashboardScaleMax,
                                footerHeight: footerHeight
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(panelGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 1)
        )
    }
}

private struct AthleticFoodBarTile: View {
    let metric: FoodBarMetric
    let scaleMax: Double
    let footerHeight: CGFloat

    private let chartHeight: CGFloat = 162

    private var targetHeight: CGFloat {
        let ratio = metric.upperBound / max(scaleMax, 0.1)
        return max(18, chartHeight * ratio)
    }

    private var currentHeight: CGFloat {
        let ratio = max(metric.total, 0) / max(scaleMax, 0.1)
        return min(chartHeight, chartHeight * ratio)
    }

    var body: some View {
        VStack(spacing: 8) {
            AthleticFoodBarShell(
                metric: metric,
                targetHeight: targetHeight,
                currentHeight: currentHeight
            )
            .frame(height: chartHeight, alignment: .bottom)

            VStack(spacing: 2) {
                Text(metric.shortLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.97))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Text(metric.valueText)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: footerHeight, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: chartHeight + footerHeight + 8, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityLabel)
    }
}

private struct AthleticFoodBarShell: View {
    let metric: FoodBarMetric
    let targetHeight: CGFloat
    let currentHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let innerWidth = max(10, width - 8)
            let lowerBandHeight = CGFloat(metric.lowerBoundRatio) * targetHeight
            let safeBandHeight = max(0, CGFloat(metric.safeBandHeightRatio) * targetHeight)
            let markerPadding = max(2, CGFloat(metric.markerRatio) * targetHeight - 1)

            ZStack(alignment: .bottom) {
                Color.clear

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.22, blue: 0.26))
                    .frame(height: targetHeight)

                if currentHeight > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(metric.fillGradient)
                        .frame(width: innerWidth, height: currentHeight)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            if metric.status == .risk {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color(red: 0.94, green: 0.73, blue: 0.19), style: StrokeStyle(lineWidth: 1.6, dash: [4, 2]))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 3)
                            }
                        }
                }

                if metric.safeBandHeightRatio > 0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.33, green: 0.90, blue: 0.47).opacity(0.22))
                        .frame(width: innerWidth, height: safeBandHeight)
                        .padding(.bottom, lowerBandHeight + 3)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .padding(.bottom, markerPadding)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                    .frame(height: targetHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )
        }
    }
}

private enum FoodBarStatus: Equatable {
    case building
    case safe
    case risk
    case over
}

private struct FoodBarMetric {
    let category: Core.Category
    let total: Double
    let upperBound: Double
    let lowerBound: Double
    let fillRatio: Double
    let overflowRatio: Double
    let markerRatio: Double
    let lowerBoundRatio: Double
    let safeBandHeightRatio: Double
    let status: FoodBarStatus

    var shortLabel: String {
        let lower = category.name.lowercased()
        if lower.contains("drink") { return "DRK" }
        if lower.contains("vegetable") { return "VEG" }
        if lower.contains("fruit") { return "FRT" }
        if lower.contains("carb") || lower.contains("starch") { return "CRB" }
        if lower.contains("protein") { return "PRT" }
        if lower.contains("dairy") { return "DAI" }
        if lower.contains("nut") { return "NUT" }
        if lower.contains("oil") { return "OIL" }
        if lower.contains("fat") { return "FAT" }
        if lower.contains("treat") { return "TRT" }
        return String(category.name.prefix(3)).uppercased()
    }

    var valueText: String {
        "\(total.cleanNumber)/\(targetText)"
    }

    var targetText: String {
        switch category.targetRule {
        case .exact(let target):
            return target.cleanNumber
        case .atLeast(let target):
            return target.cleanNumber
        case .atMost(let target):
            return target.cleanNumber
        case .range(let minValue, let maxValue):
            return "\(minValue.cleanNumber)-\(maxValue.cleanNumber)"
        }
    }

    var statusColor: Color {
        switch status {
        case .building:
            return Color(red: 0.58, green: 0.80, blue: 1.00)
        case .safe:
            return Color(red: 0.34, green: 0.89, blue: 0.46)
        case .risk:
            return Color(red: 0.99, green: 0.76, blue: 0.24)
        case .over:
            return Color(red: 0.98, green: 0.38, blue: 0.31)
        }
    }

    var fillGradient: LinearGradient {
        LinearGradient(
            colors: [statusColor.opacity(0.95), statusColor.opacity(status == .building ? 0.72 : 0.82)],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    var accessibilityLabel: String {
        let statusText: String
        switch status {
        case .building:
            statusText = "building toward target"
        case .safe:
            statusText = "safe"
        case .risk:
            statusText = "pacing risk"
        case .over:
            statusText = "over target"
        }
        return "\(category.name), \(total.cleanNumber) \(category.unitName), target \(targetText), \(statusText)"
    }

    static func upperBound(for category: Core.Category) -> Double {
        switch category.targetRule {
        case .exact(let target),
             .atLeast(let target),
             .atMost(let target):
            return max(target, 0.1)
        case .range(_, let maxValue):
            return max(maxValue, 0.1)
        }
    }

    static func make(category: Core.Category, total: Double, mealProgress: Double) -> FoodBarMetric {
        let upperBound = upperBound(for: category)
        let lowerBound: Double
        let markerRatio: Double
        let lowerBoundRatio: Double
        let safeBandHeightRatio: Double

        switch category.targetRule {
        case .exact(let target):
            lowerBound = target
            markerRatio = 0.92
            lowerBoundRatio = 0
            safeBandHeightRatio = 0
        case .atLeast(let target):
            lowerBound = target
            markerRatio = 0.92
            lowerBoundRatio = 0
            safeBandHeightRatio = 0
        case .atMost:
            lowerBound = 0
            markerRatio = 0.92
            lowerBoundRatio = 0
            safeBandHeightRatio = 0
        case .range(let minValue, let maxValue):
            lowerBound = minValue
            markerRatio = 0.92
            lowerBoundRatio = max(0, minValue / max(maxValue, 0.1))
            safeBandHeightRatio = max(0, (maxValue - minValue) / max(maxValue, 0.1))
        }

        let clampedFill = min(max(total, 0), upperBound)
        let fillRatio = max(0, min(clampedFill / upperBound, 1))
        let overflowRatio = max(0, min((total - upperBound) / upperBound, 0.35))
        let consumedShare = max(0, total / upperBound)
        let riskThreshold = min(0.95, max(mealProgress + 0.24, 0.58))

        let status: FoodBarStatus
        switch category.targetRule {
        case .exact(let target):
            if total > target + TargetRule.exactTolerance {
                status = .over
            } else if mealProgress < 0.86 && consumedShare >= riskThreshold {
                status = .risk
            } else if abs(total - target) <= TargetRule.exactTolerance {
                status = .safe
            } else {
                status = .building
            }
        case .atLeast(let target):
            status = total >= target ? .safe : .building
        case .atMost(let target):
            if total > target + TargetRule.exactTolerance {
                status = .over
            } else if total > 0 && mealProgress < 0.86 && consumedShare >= riskThreshold {
                status = .risk
            } else if total > 0 {
                status = .safe
            } else {
                status = .building
            }
        case .range(let minValue, let maxValue):
            if total > maxValue + TargetRule.exactTolerance {
                status = .over
            } else if total >= minValue && mealProgress < 0.86 && consumedShare >= riskThreshold {
                status = .risk
            } else if total >= minValue && total <= maxValue {
                status = .safe
            } else {
                status = .building
            }
        }

        return FoodBarMetric(
            category: category,
            total: total,
            upperBound: upperBound,
            lowerBound: lowerBound,
            fillRatio: fillRatio,
            overflowRatio: overflowRatio,
            markerRatio: markerRatio,
            lowerBoundRatio: lowerBoundRatio,
            safeBandHeightRatio: safeBandHeightRatio,
            status: status
        )
    }
}

private enum TodayTileMetrics {
    static func scale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 0.82
        case .large:
            return 1.0
        case .xLarge, .xxLarge:
            return 1.1
        default:
            return 1.2
        }
    }

    static func gridSpacing(for scale: CGFloat) -> CGFloat {
        max(6, 10 * scale)
    }

    static func compactHeight(for scale: CGFloat) -> CGFloat {
        max(92, 124 * scale)
    }

    static func capsuleHeight(for scale: CGFloat) -> CGFloat {
        max(44, 60 * scale)
    }

    static func tilePadding(for scale: CGFloat) -> CGFloat {
        max(5, 8 * scale)
    }

    static func capsulePadding(for scale: CGFloat) -> CGFloat {
        max(4, 6 * scale)
    }

    static func borderWidth(for scale: CGFloat) -> CGFloat {
        max(0.8, 1.0 * scale)
    }

    static func cornerRadius(for scale: CGFloat) -> CGFloat {
        max(4, 6 * scale)
    }

    static func missingStackedFontSize(for scale: CGFloat) -> CGFloat {
        max(14, 19 * scale)
    }

    static func missingInlineFontSize(for scale: CGFloat) -> CGFloat {
        max(12, 16 * scale)
    }
}

private struct CategoryOverviewGrid<Destination: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let categories: [Core.Category]
    let totals: [UUID: Double]
    let style: CategoryDisplayStyle
    let destination: (Core.Category) -> Destination

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    private var columns: [GridItem] {
        switch style {
        case .compactRings:
            return [GridItem(.adaptive(minimum: 130 * metricScale), spacing: TodayTileMetrics.gridSpacing(for: metricScale))]
        case .inlineLabel:
            return [GridItem(.adaptive(minimum: 200 * metricScale), spacing: TodayTileMetrics.gridSpacing(for: metricScale))]
        case .capsuleRows:
            return [GridItem(.adaptive(minimum: 180 * metricScale), spacing: TodayTileMetrics.gridSpacing(for: metricScale))]
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: TodayTileMetrics.gridSpacing(for: metricScale)) {
            ForEach(categories) { category in
                let total = totals[category.id] ?? 0
                switch style {
                case .compactRings:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryRingTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                case .inlineLabel:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryInlineTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                case .capsuleRows:
                    NavigationLink {
                        destination(category)
                    } label: {
                        CategoryCapsuleTile(
                            category: category,
                            total: total,
                            targetMet: category.targetRule.isSatisfied(by: total)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CategoryDayDetailView: View {
    @EnvironmentObject private var store: AppStore
    let category: Core.Category
    @State private var dailyLog: DailyLog?
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?
    @AppStorage("today.quickAddStyle") private var quickAddStyleRaw: String = QuickAddStyle.standard.rawValue

    private var quickAddStyle: QuickAddStyle {
        QuickAddStyle(rawValue: quickAddStyleRaw) ?? .standard
    }

    private var entries: [DailyLogEntry] {
        dailyLog?.entries.filter { $0.categoryID == category.id } ?? []
    }

    private var sortedEntries: [DailyLogEntry] {
        let order = Dictionary(uniqueKeysWithValues: store.mealSlots.map { ($0.id, $0.sortOrder) })
        return entries.sorted {
            let left = order[$0.mealSlotID] ?? 0
            let right = order[$1.mealSlotID] ?? 0
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                if sortedEntries.isEmpty {
                    Text("No items yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(sortedEntries) { entry in
                        CategoryDayEntryRow(
                            entry: entry,
                            category: category,
                            mealSlotName: mealSlotName(for: entry),
                            onEdit: { editingEntry = $0 },
                            onDelete: { entry in
                                Task {
                                    await store.deleteEntry(entry)
                                    await loadEntries()
                                }
                            }
                        )
                    }
                }
            } header: {
                Text(store.currentDay, style: .date)
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add entry")
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled && $0.id == category.id },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: category.id,
                preselectedMealSlotID: store.currentMealSlotID(),
                contextDate: nil,
                style: quickAddStyle,
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
                        await loadEntries()
                    }
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.updateEntry(
                            entry,
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadEntries()
                    }
                }
            )
        }
        .task(id: store.refreshToken) { await loadEntries() }
    }

    private func mealSlotName(for entry: DailyLogEntry) -> String {
        store.mealSlots.first(where: { $0.id == entry.mealSlotID })?.name ?? "Meal"
    }

    private func loadEntries() async {
        dailyLog = await store.fetchDailyLog(for: Date())
    }
}

private struct CategoryDayEntryRow: View {
    let entry: DailyLogEntry
    let category: Core.Category
    let mealSlotName: String
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(CategoryColorPalette.color(for: category))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(mealSlotName)
                    .font(.subheadline)
                if let compositeName = entry.compositeFoodName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !compositeName.isEmpty {
                    Text("from \(compositeName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(entry.portion.value.cleanNumber) \(category.unitName)")
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Edit") {
                onEdit(entry)
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Edit") { onEdit(entry) }
            Button("Delete", role: .destructive) { onDelete(entry) }
        }
    }
}

private struct MealDayDetailView: View {
    @EnvironmentObject private var store: AppStore
    let mealSlot: MealSlot
    @State private var dailyLog: DailyLog?
    @State private var showingQuickAdd = false
    @State private var editingEntry: DailyLogEntry?
    @State private var viewingEntry: DailyLogEntry?
    @AppStorage("today.quickAddStyle") private var quickAddStyleRaw: String = QuickAddStyle.standard.rawValue

    private var quickAddStyle: QuickAddStyle {
        QuickAddStyle(rawValue: quickAddStyleRaw) ?? .standard
    }

    private var entries: [DailyLogEntry] {
        dailyLog?.entries.filter { $0.mealSlotID == mealSlot.id } ?? []
    }

    private var sortedEntries: [DailyLogEntry] {
        let order = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0.sortOrder) })
        return entries.sorted {
            let left = order[$0.categoryID] ?? 0
            let right = order[$1.categoryID] ?? 0
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                if sortedEntries.isEmpty {
                    Text("No items yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(sortedEntries) { entry in
                        MealDayEntryRow(
                            entry: entry,
                            categories: store.categories,
                            foodItems: store.foodItems,
                            units: store.units
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { viewingEntry = entry }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await store.deleteEntry(entry)
                                    await loadEntries()
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("Edit") {
                                editingEntry = entry
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button("Edit") { editingEntry = entry }
                            Button("Delete", role: .destructive) {
                                Task {
                                    await store.deleteEntry(entry)
                                    await loadEntries()
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(store.currentDay, style: .date)
            }
        }
        .navigationTitle(mealSlot.name)
        .toolbar {
            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add entry")
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet(
                categories: store.categories.filter { $0.isEnabled },
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                preselectedCategoryID: nil,
                preselectedMealSlotID: mealSlot.id,
                contextDate: nil,
                style: quickAddStyle,
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
                        await loadEntries()
                    }
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units,
                onSave: { mealSlot, category, portion, amountValue, amountUnitID, notes, foodItemID in
                    Task {
                        await store.updateEntry(
                            entry,
                            mealSlotID: mealSlot.id,
                            categoryID: category.id,
                            portion: Portion(portion, increment: DrinkRules.portionIncrement(for: category)),
                            amountValue: amountValue,
                            amountUnitID: amountUnitID,
                            notes: notes,
                            foodItemID: foodItemID
                        )
                        await loadEntries()
                    }
                }
            )
        }
        .sheet(item: $viewingEntry) { entry in
            EntryDetailSheet(
                entry: entry,
                categories: store.categories,
                mealSlots: store.mealSlots,
                foodItems: store.foodItems,
                units: store.units
            )
        }
        .task(id: store.refreshToken) { await loadEntries() }
    }

    private func loadEntries() async {
        dailyLog = await store.fetchDailyLog(for: Date())
    }
}

private struct MealDayEntryRow: View {
    let entry: DailyLogEntry
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]

    private var category: Core.Category? {
        categories.first(where: { $0.id == entry.categoryID })
    }

    private var foodItem: FoodItem? {
        guard let foodID = entry.foodItemID else { return nil }
        return foodItems.first(where: { $0.id == foodID })
    }

    private var amountUnitSymbol: String? {
        guard let unitID = entry.amountUnitID else { return nil }
        return units.first(where: { $0.id == unitID })?.symbol
    }

    private var notesText: String? {
        let trimmed = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var compositeName: String? {
        let trimmed = entry.compositeFoodName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var portionText: String {
        let unitName = category?.unitName ?? ""
        return unitName.isEmpty ? entry.portion.value.cleanNumber : "\(entry.portion.value.cleanNumber) \(unitName)"
    }

    private var categoryColor: Color {
        guard let category else { return CategoryColorPalette.fallback }
        return CategoryColorPalette.color(for: category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 10, height: 10)
                Text(category?.name ?? "Category")
                    .font(.subheadline)
                Spacer()
                Text(portionText)
                    .font(.subheadline)
            }
            if let foodItem {
                Text("Food: \(foodItem.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let compositeName {
                Text("From composite: \(compositeName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let amountValue = entry.amountValue {
                let unit = amountUnitSymbol ?? ""
                let amountText = unit.isEmpty ? amountValue.cleanNumber : "\(amountValue.cleanNumber) \(unit)"
                Text("Amount: \(amountText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let notesText {
                Text("Notes: \(notesText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryRingTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let missing = missingAmount(rule: category.targetRule, total: total)
        let missingText = "\(missing.cleanNumber) \(category.unitName)"
        let showMissing = !targetMet && missing > 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ProgressRing(
                    progress: progress.ringProgress,
                    accent: accentColor,
                    iconName: iconName,
                    size: 40 * metricScale
                )
                Spacer()
                StatusBadge(status: progress.status)
            }
            Text(category.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if showMissing {
                MissingTargetValue(text: missingText, style: .stacked)
            }
        }
        .padding(TodayTileMetrics.tilePadding(for: metricScale))
        .frame(
            maxWidth: .infinity,
            minHeight: TodayTileMetrics.compactHeight(for: metricScale),
            maxHeight: TodayTileMetrics.compactHeight(for: metricScale),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius(for: metricScale), style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: TodayTileMetrics.borderWidth(for: metricScale))
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            if showMissing {
                Text("Missing: \(missingText)")
            }
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showMissing ? "\(category.name), \(progress.status.label), missing \(missingText)" : "\(category.name), \(progress.status.label)")
    }
}

private struct CategoryInlineTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let missing = missingAmount(rule: category.targetRule, total: total)
        let missingText = "\(missing.cleanNumber) \(category.unitName)"
        let showMissing = !targetMet && missing > 0
        HStack(spacing: 10) {
            ProgressRing(progress: progress.ringProgress, accent: accentColor, iconName: iconName, size: 34 * metricScale)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                if showMissing {
                    MissingTargetValue(text: missingText, style: .inline)
                }
            }
            Spacer()
            StatusBadge(status: progress.status)
        }
        .padding(TodayTileMetrics.tilePadding(for: metricScale))
        .frame(
            maxWidth: .infinity,
            minHeight: TodayTileMetrics.compactHeight(for: metricScale),
            maxHeight: TodayTileMetrics.compactHeight(for: metricScale),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius(for: metricScale), style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: TodayTileMetrics.borderWidth(for: metricScale))
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            if showMissing {
                Text("Missing: \(missingText)")
            }
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showMissing ? "\(category.name), \(progress.status.label), missing \(missingText)" : "\(category.name), \(progress.status.label)")
    }
}

private struct CategoryCapsuleTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let category: Core.Category
    let total: Double
    let targetMet: Bool
    private var accentColor: Color { CategoryColorPalette.color(for: category) }
    private var iconName: String { CategoryIconPalette.iconName(for: category) }

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    var body: some View {
        let progress = CategoryProgress.make(category: category, total: total, targetMet: targetMet)
        let missing = missingAmount(rule: category.targetRule, total: total)
        let missingText = "\(missing.cleanNumber) \(category.unitName)"
        let showMissing = !targetMet && missing > 0
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                if showMissing {
                    MissingTargetValue(text: missingText, style: .inline)
                }
            }
            Spacer()
            StatusBadge(status: progress.status)
        }
        .padding(.horizontal, TodayTileMetrics.tilePadding(for: metricScale))
        .padding(.vertical, TodayTileMetrics.capsulePadding(for: metricScale))
        .frame(
            maxWidth: .infinity,
            minHeight: TodayTileMetrics.capsuleHeight(for: metricScale),
            maxHeight: TodayTileMetrics.capsuleHeight(for: metricScale),
            alignment: .center
        )
        .background(
            RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius(for: metricScale), style: .continuous)
                .fill(ZenStyle.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius(for: metricScale), style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            Text(category.name)
            Text("Target: \(category.targetRule.displayText(unit: category.unitName))")
            Text("Total: \(total.cleanNumber) \(category.unitName)")
            if showMissing {
                Text("Missing: \(missingText)")
            }
            Text(progress.status.label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showMissing ? "\(category.name), \(progress.status.label), missing \(missingText)" : "\(category.name), \(progress.status.label)")
    }
}

private enum MissingTargetStyle {
    case stacked
    case inline
}

private struct MissingTargetValue: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let text: String
    let style: MissingTargetStyle

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    var body: some View {
        switch style {
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                Text("Missing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: TodayTileMetrics.missingStackedFontSize(for: metricScale), weight: .semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        case .inline:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Missing ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: TodayTileMetrics.missingInlineFontSize(for: metricScale), weight: .semibold))
                    .foregroundStyle(.red)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

private func missingAmount(rule: TargetRule, total: Double) -> Double {
    switch rule {
    case .exact(let target):
        return max(0, target - total)
    case .atLeast(let target):
        return max(0, target - total)
    case .atMost(let target):
        return max(0, target - total)
    case .range(let minValue, let maxValue):
        if total < minValue { return Swift.max(0, minValue - total) }
        if total > maxValue { return 0 }
        return 0
    }
}

private func excessAmount(rule: TargetRule, total: Double) -> Double {
    switch rule {
    case .exact(let target):
        return max(0, total - (target + TargetRule.exactTolerance))
    case .atLeast:
        return 0
    case .atMost(let target):
        return max(0, total - target)
    case .range(_, let maxValue):
        return max(0, total - maxValue)
    }
}

private struct TodayMealBreakdownView: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let style: MealDisplayStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Meal")
                .font(.headline)

            switch style {
            case .miniCards:
                MealOverviewGrid(
                    mealSlots: mealSlots,
                    entries: entries,
                    categories: categories
                )
            case .stackedStrips:
                MealStripList(
                    mealSlots: mealSlots,
                    entries: entries,
                    categories: categories
                )
            }
        }
    }
}

private struct MealOverviewGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 130 * metricScale), spacing: TodayTileMetrics.gridSpacing(for: metricScale))]
    }

    var body: some View {
        let enabledCategories = categories.filter { $0.isEnabled }
        LazyVGrid(columns: columns, spacing: TodayTileMetrics.gridSpacing(for: metricScale)) {
            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                let total = slotEntries.reduce(0) { $0 + $1.portion.value }
                let loggedCategories = Set(slotEntries.filter { $0.portion.value > 0 }.map { $0.categoryID }).count
                NavigationLink {
                    MealDayDetailView(mealSlot: slot)
                } label: {
                    MealOverviewCard(
                        mealSlot: slot,
                        total: total,
                        loggedCategories: loggedCategories,
                        totalCategories: enabledCategories.count
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MealOverviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let mealSlot: MealSlot
    let total: Double
    let loggedCategories: Int
    let totalCategories: Int
    private var iconName: String { MealIconPalette.iconName(for: mealSlot) }

    private var metricScale: CGFloat {
        TodayTileMetrics.scale(for: dynamicTypeSize)
    }

    var body: some View {
        let progress = totalCategories > 0 ? Double(loggedCategories) / Double(totalCategories) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressRing(
                    progress: progress,
                    accent: .blue,
                    iconName: iconName,
                    size: 40 * metricScale
                )
                Spacer()
            }
            Text(mealSlot.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(total.cleanNumber) total")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(TodayTileMetrics.tilePadding(for: metricScale))
        .frame(
            maxWidth: .infinity,
            minHeight: TodayTileMetrics.compactHeight(for: metricScale),
            maxHeight: TodayTileMetrics.compactHeight(for: metricScale),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: TodayTileMetrics.cornerRadius(for: metricScale), style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: TodayTileMetrics.borderWidth(for: metricScale))
        )
        .contextMenu {
            Text(mealSlot.name)
            Text("Total: \(total.cleanNumber)")
            Text("Categories logged: \(loggedCategories)/\(totalCategories)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mealSlot.name), \(loggedCategories) of \(totalCategories) categories logged, \(total.cleanNumber) total")
    }
}

private struct MealStripList: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]

    var body: some View {
        let enabledCategories = categories.filter { $0.isEnabled }
        VStack(spacing: 8) {
            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                let total = slotEntries.reduce(0) { $0 + $1.portion.value }
                let loggedCategories = Set(slotEntries.filter { $0.portion.value > 0 }.map { $0.categoryID }).count
                NavigationLink {
                    MealDayDetailView(mealSlot: slot)
                } label: {
                    MealStripRow(
                        mealSlot: slot,
                        total: total,
                        loggedCategories: loggedCategories,
                        totalCategories: enabledCategories.count
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MealStripRow: View {
    let mealSlot: MealSlot
    let total: Double
    let loggedCategories: Int
    let totalCategories: Int
    private var iconName: String { MealIconPalette.iconName(for: mealSlot) }

    var body: some View {
        let progress = totalCategories > 0 ? Double(loggedCategories) / Double(totalCategories) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                mealIcon
                Text(mealSlot.name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(total.cleanNumber)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mealSlot.name), \(loggedCategories) of \(totalCategories) categories logged, \(total.cleanNumber) total")
    }

    @ViewBuilder
    private var mealIcon: some View {
        #if canImport(UIKit)
        if UIImage(systemName: iconName) != nil {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(.blue)
        } else {
            Text(iconName)
                .font(.system(size: 13))
        }
        #else
        Text(iconName)
            .font(.system(size: 13))
        #endif
    }
}

private struct TodayMealDetailsSection: View {
    let mealSlots: [MealSlot]
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let onViewDetails: (DailyLogEntry) -> Void
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal Details")
                .font(.headline)

            ForEach(mealSlots) { slot in
                let slotEntries = entries.filter { $0.mealSlotID == slot.id }
                MealSectionView(
                    mealSlot: slot,
                    entries: slotEntries,
                    categories: categories,
                    foodItems: foodItems,
                    onViewDetails: onViewDetails,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
                .id(slot.id)
            }
        }
    }
}

private struct MealSectionView: View {
    private struct CompositeGroup: Identifiable {
        let id: UUID
        let name: String
        let entries: [DailyLogEntry]
    }

    private enum DisplayItem: Identifiable {
        case entry(DailyLogEntry)
        case composite(CompositeGroup)

        var id: String {
            switch self {
            case .entry(let entry):
                return "entry-\(entry.id.uuidString)"
            case .composite(let group):
                return "composite-\(group.id.uuidString)"
            }
        }
    }

    let mealSlot: MealSlot
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let onViewDetails: (DailyLogEntry) -> Void
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void
    private func categoryColor(for entry: DailyLogEntry) -> Color {
        if let category = categories.first(where: { $0.id == entry.categoryID }) {
            return CategoryColorPalette.color(for: category)
        }
        return CategoryColorPalette.fallback
    }

    private var displayItems: [DisplayItem] {
        var items: [DisplayItem] = []
        var seenGroupIDs = Set<UUID>()
        for entry in entries {
            guard let groupID = entry.compositeGroupID else {
                items.append(.entry(entry))
                continue
            }
            guard !seenGroupIDs.contains(groupID) else { continue }
            seenGroupIDs.insert(groupID)
            let groupedEntries = entries.filter { $0.compositeGroupID == groupID }
            let fallbackName = groupedEntries.first?.compositeFoodID
                .flatMap { id in foodItems.first(where: { $0.id == id })?.name }
            let name = groupedEntries.first?.compositeFoodName ?? fallbackName ?? "Composite food"
            items.append(.composite(CompositeGroup(id: groupID, name: name, entries: groupedEntries)))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mealSlot.name)
                    .font(.subheadline)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.portion.value }.cleanNumber) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text("No entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayItems) { item in
                    switch item {
                    case .entry(let entry):
                        MealEntryRow(
                            entry: entry,
                            categoryName: categoryName(for: entry),
                            foodName: foodName(for: entry),
                            categoryColor: categoryColor(for: entry),
                            onViewDetails: onViewDetails,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    case .composite(let group):
                        CompositeMealGroupRow(
                            groupName: group.name,
                            entries: group.entries,
                            categories: categories,
                            foodItems: foodItems,
                            onViewDetails: onViewDetails,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func categoryName(for entry: DailyLogEntry) -> String {
        categories.first(where: { $0.id == entry.categoryID })?.name ?? "Category"
    }

    private func foodName(for entry: DailyLogEntry) -> String? {
        guard let foodID = entry.foodItemID else { return nil }
        let name = foodItems.first(where: { $0.id == foodID })?.name ?? ""
        return name.isEmpty ? nil : name
    }
}

private struct CompositeMealGroupRow: View {
    let groupName: String
    let entries: [DailyLogEntry]
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let onViewDetails: (DailyLogEntry) -> Void
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries) { entry in
                    MealEntryRow(
                        entry: entry,
                        categoryName: categoryName(for: entry),
                        foodName: foodName(for: entry),
                        categoryColor: categoryColor(for: entry),
                        onViewDetails: onViewDetails,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName)
                        .font(.subheadline)
                    Text("\(entries.count) components")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entries.reduce(0) { $0 + $1.portion.value }.cleanNumber)
                    .font(.subheadline)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
    }

    private func categoryColor(for entry: DailyLogEntry) -> Color {
        guard let category = categories.first(where: { $0.id == entry.categoryID }) else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }

    private func categoryName(for entry: DailyLogEntry) -> String {
        categories.first(where: { $0.id == entry.categoryID })?.name ?? "Category"
    }

    private func foodName(for entry: DailyLogEntry) -> String? {
        guard let foodID = entry.foodItemID else { return nil }
        let name = foodItems.first(where: { $0.id == foodID })?.name ?? ""
        return name.isEmpty ? nil : name
    }
}

private struct MealEntryRow: View {
    let entry: DailyLogEntry
    let categoryName: String
    let foodName: String?
    let categoryColor: Color
    let onViewDetails: (DailyLogEntry) -> Void
    let onEdit: (DailyLogEntry) -> Void
    let onDelete: (DailyLogEntry) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName)
                    .font(.subheadline)
                if let foodName {
                    Text(foodName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.portion.value.cleanNumber)
                .font(.subheadline)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onViewDetails(entry)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                onDelete(entry)
            }
            Button("Edit") {
                onEdit(entry)
            }
        }
        .contextMenu {
            Button("Edit") { onEdit(entry) }
            Button("Delete", role: .destructive) { onDelete(entry) }
        }
    }
}

private struct EntryDetailSheet: View {
    let entry: DailyLogEntry
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]

    @Environment(\.dismiss) private var dismiss

    private var category: Core.Category? {
        categories.first(where: { $0.id == entry.categoryID })
    }

    private var mealSlot: MealSlot? {
        mealSlots.first(where: { $0.id == entry.mealSlotID })
    }

    private var foodItem: FoodItem? {
        guard let foodID = entry.foodItemID else { return nil }
        return foodItems.first(where: { $0.id == foodID })
    }

    private var amountUnitSymbol: String? {
        guard let unitID = entry.amountUnitID else { return nil }
        return units.first(where: { $0.id == unitID })?.symbol
    }

    private var foodUnitSymbol: String? {
        guard let unitID = foodItem?.unitID else { return nil }
        return units.first(where: { $0.id == unitID })?.symbol
    }

    private var notesText: String? {
        let trimmed = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var compositeName: String? {
        let trimmed = entry.compositeFoodName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var portionText: String {
        let unitName = category?.unitName ?? ""
        return unitName.isEmpty ? entry.portion.value.cleanNumber : "\(entry.portion.value.cleanNumber) \(unitName)"
    }

    private var amountText: String? {
        guard let amountValue = entry.amountValue else { return nil }
        guard let unit = amountUnitSymbol, !unit.isEmpty else { return amountValue.cleanNumber }
        return "\(amountValue.cleanNumber) \(unit)"
    }

    private var categoryColor: Color {
        guard let category else { return CategoryColorPalette.fallback }
        return CategoryColorPalette.color(for: category)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Meal") {
                    Text(mealSlot?.name ?? "Meal")
                }

                Section("Category") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(categoryColor)
                            .frame(width: 10, height: 10)
                        Text(category?.name ?? "Category")
                    }
                }

                Section("Portion") {
                    Text(portionText)
                }

                Section("Amount") {
                    if let amountText {
                        Text(amountText)
                    } else {
                        Text("No amount")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Food") {
                    if let item = foodItem {
                        FoodItemRow(
                            item: item,
                            categoryName: category?.name ?? "Category",
                            unitSymbol: foodUnitSymbol,
                            showsFavorite: false,
                            thumbnailSize: 34
                        )
                    } else {
                        Text("No food selected")
                            .foregroundStyle(.secondary)
                    }
                }

                if let compositeName {
                    Section("Composite") {
                        Text(compositeName)
                    }
                }

                Section("Comments") {
                    if let notesText {
                        Text(notesText)
                    } else {
                        Text("No comments")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Entry Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .glassButton(.text)
                }
            }
        }
    }
}

private struct ProgressRing: View {
    let progress: Double
    let accent: Color
    let iconName: String
    let size: CGFloat

    init(progress: Double, accent: Color, iconName: String, size: CGFloat = 46) {
        self.progress = progress
        self.accent = accent
        self.iconName = iconName
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
            iconView
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var iconView: some View {
        #if canImport(UIKit)
        if UIImage(systemName: iconName) != nil {
            Image(systemName: iconName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.primary)
        } else {
            Text(iconName)
                .font(.system(size: size * 0.5))
        }
        #else
        Text(iconName)
            .font(.system(size: size * 0.5))
        #endif
    }
}

private struct StatusBadge: View {
    let status: CategoryStatus

    var body: some View {
        Image(systemName: status.iconName)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(6)
            .background(
                Circle()
                    .fill(ZenStyle.elevatedSurface)
            )
            .overlay(
                Circle()
                    .stroke(status.color.opacity(0.28), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private enum CategoryStatus: String {
    case met
    case onTrack
    case behind
    case over

    var label: String {
        switch self {
        case .met: return "Target met"
        case .onTrack: return "On track"
        case .behind: return "Behind"
        case .over: return "Over target"
        }
    }

    var iconName: String {
        switch self {
        case .met: return "checkmark.circle.fill"
        case .onTrack: return "circle.dashed"
        case .behind: return "exclamationmark.circle.fill"
        case .over: return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .met: return .green
        case .onTrack: return .orange
        case .behind: return .red
        case .over: return .red
        }
    }
}

private struct CategoryProgress {
    let status: CategoryStatus
    let ringProgress: Double

    static func make(category: Core.Category, total: Double, targetMet: Bool) -> CategoryProgress {
        let rule = category.targetRule
        var status: CategoryStatus
        var ringProgress: Double

        switch rule {
        case .exact(let target):
            if targetMet {
                status = .met
            } else if total > target + TargetRule.exactTolerance {
                status = .over
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            ringProgress = progress(current: total, target: target)
        case .atLeast(let target):
            if targetMet {
                status = .met
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            ringProgress = progress(current: total, target: target)
        case .atMost(let target):
            status = targetMet ? .met : .over
            ringProgress = progress(current: total, target: target)
        case .range(let minValue, let maxValue):
            if targetMet {
                status = .met
            } else if total > maxValue {
                status = .over
            } else if total == 0 {
                status = .behind
            } else {
                status = .onTrack
            }
            let target = minValue > 0 ? minValue : maxValue
            ringProgress = progress(current: total, target: target)
        }

        if targetMet {
            ringProgress = 1
        }

        return CategoryProgress(status: status, ringProgress: ringProgress)
    }

    private static func progress(current: Double, target: Double) -> Double {
        guard target > 0 else { return current > 0 ? 1 : 0 }
        return min(max(current / target, 0), 1)
    }
}

private enum CategoryDisplayStyle: String, CaseIterable, Identifiable {
    case compactRings
    case inlineLabel
    case capsuleRows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compactRings: return "Rings (A)"
        case .inlineLabel: return "Inline (B)"
        case .capsuleRows: return "Capsules (C)"
        }
    }
}

enum QuickAddStyle: String, CaseIterable, Identifiable {
    case standard
    case categoryFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .categoryFirst: return "Category-first (Alt)"
        }
    }
}

private struct QuickAddLibraryEntryContext: Identifiable {
    let id = UUID()
    let suggestionRequest: FoodDetailSuggestionRequest
}

private enum MealDisplayStyle: String, CaseIterable, Identifiable {
    case miniCards
    case stackedStrips

    var id: String { rawValue }

    var label: String {
        switch self {
        case .miniCards: return "Cards (F)"
        case .stackedStrips: return "Strips (G)"
        }
    }
}

private enum EntryInputMode: String, CaseIterable, Identifiable {
    case portion
    case amount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portion: return "Portions"
        case .amount: return "Amount"
        }
    }
}

struct QuickAddSheet: View {
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]
    let preselectedCategoryID: UUID?
    let preselectedMealSlotID: UUID?
    let contextDate: Date?
    let style: QuickAddStyle
    let onSave: (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selectedCategoryID: UUID?
    @State private var selectedMealSlotID: UUID?
    @State private var selectedFoodID: UUID?
    @State private var portion: Double = 1.0
    @State private var inputMode: EntryInputMode = .portion
    @State private var amountText: String = ""
    @State private var manualAmountPerPortion: Double?
    @State private var manualUnitID: UUID?
    @State private var drinkUnitID: UUID?
    @State private var isSyncing = false
    @State private var notes: String = ""
    @State private var manualFoodName: String = ""
    @State private var showsManualDetails = false
    @State private var hasManualFoodProposal = false
    @State private var pendingSuggestedManualFoodName: String?
    @State private var isSuggestingManualFood = false
    @State private var manualFoodSuggestionError: String?
    @State private var manualFoodSuggestionConfidence: Double?
    @State private var libraryOfferContext: QuickAddLibraryEntryContext?
    @State private var pendingLibraryEntry: QuickAddLibraryEntryContext?
    @State private var shouldCompleteSaveAfterLibraryEntry = false
    @State private var libraryEntryErrorMessage: String?
    @State private var showingLibraryEntryError = false

    init(
        categories: [Core.Category],
        mealSlots: [MealSlot],
        foodItems: [FoodItem],
        units: [Core.FoodUnit],
        preselectedCategoryID: UUID?,
        preselectedMealSlotID: UUID?,
        contextDate: Date?,
        style: QuickAddStyle = .standard,
        onSave: @escaping (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void
    ) {
        self.categories = categories
        self.mealSlots = mealSlots
        self.foodItems = foodItems
        self.units = units
        self.preselectedCategoryID = preselectedCategoryID
        self.preselectedMealSlotID = preselectedMealSlotID
        self.contextDate = contextDate
        self.style = style
        self.onSave = onSave
    }
    private var selectedCategory: Core.Category? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id == selectedCategoryID })
    }

    private var selectedCategoryColor: Color {
        guard let category = selectedCategory else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }
    private var isCategoryFirst: Bool {
        style == .categoryFirst
    }
    private var availableFoodItems: [FoodItem] {
        let allowedCategoryIDs = Set(categories.map(\.id))
        return store.foodItems.filter { item in
            allowedCategoryIDs.contains(item.categoryID) && (preselectedCategoryID == nil || !item.kind.isComposite)
        }
    }

    private var selectedFoodItem: FoodItem? {
        guard let selectedFoodID else { return nil }
        return availableFoodItems.first(where: { $0.id == selectedFoodID })
    }

    private var isCompositeFoodSelected: Bool {
        selectedFoodItem?.kind.isComposite == true
    }

    private var isDrinkCategory: Bool {
        guard let selectedCategory else { return false }
        return DrinkRules.isDrinkCategory(selectedCategory)
    }

    private var drinkUnits: [Core.FoodUnit] {
        DrinkRules.drinkUnits(from: units)
    }

    private var selectedUnit: Core.FoodUnit? {
        let unitID = selectedFoodItem?.unitID ?? manualUnitID
        guard let unitID else { return nil }
        return units.first(where: { $0.id == unitID })
    }

    private var selectedDrinkUnit: Core.FoodUnit? {
        guard let drinkUnitID else { return nil }
        return drinkUnits.first(where: { $0.id == drinkUnitID }) ?? units.first(where: { $0.id == drinkUnitID })
    }

    private var activeUnit: Core.FoodUnit? {
        isDrinkCategory ? selectedDrinkUnit : selectedUnit
    }

    private var amountPerPortion: Double? {
        selectedFoodItem?.amountPerPortion ?? manualAmountPerPortion
    }

    private var amountInputEnabled: Bool {
        if isDrinkCategory {
            return selectedDrinkUnit != nil
        }
        return amountPerPortion != nil && selectedUnit != nil
    }

    private var portionIncrement: Double {
        DrinkRules.portionIncrement(for: selectedCategory)
    }

    private var fallbackMealSlot: MealSlot? {
        if let preselectedMealSlotID,
           let slot = mealSlots.first(where: { $0.id == preselectedMealSlotID }) {
            return slot
        }
        return mealSlots.first
    }

    private var resolvedMealSlot: MealSlot? {
        if let mealID = selectedMealSlotID,
           let meal = mealSlots.first(where: { $0.id == mealID }) {
            return meal
        }
        return isCategoryFirst ? fallbackMealSlot : nil
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private var trimmedManualFoodName: String {
        manualFoodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowQuickAddDetails: Bool {
        selectedFoodID != nil || hasManualFoodProposal
    }

    private var matchingLibraryFood: FoodItem? {
        guard !trimmedManualFoodName.isEmpty else { return nil }
        return availableFoodItems.first { item in
            item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedManualFoodName) == .orderedSame
        }
    }

    private var shouldOfferFoodLibraryEntry: Bool {
        selectedFoodID == nil && !trimmedManualFoodName.isEmpty && matchingLibraryFood == nil
    }

    private var isManualEntryFlowActive: Bool {
        availableFoodItems.isEmpty || showsManualDetails
    }

    private var canSave: Bool {
        guard selectedCategoryID != nil, resolvedMealSlot != nil else { return false }
        if isSuggestingManualFood { return false }
        if selectedFoodID == nil && isManualEntryFlowActive && !hasManualFoodProposal {
            return false
        }
        if inputMode == .amount && amountInputEnabled {
            return parsedAmount != nil
        }
        return true
    }

    private var selectedMealSlotName: String? {
        guard let selectedMealSlotID else { return nil }
        return mealSlots.first(where: { $0.id == selectedMealSlotID })?.name
    }

    private var mealSelectionSummary: String {
        if let selectedMealSlotName {
            return selectedMealSlotName
        }
        if isCategoryFirst, let fallbackMealSlot {
            return "Auto (\(fallbackMealSlot.name))"
        }
        return "Choose meal"
    }

    private var foodSelectionSummary: String {
        guard let selectedFoodID,
              let item = availableFoodItems.first(where: { $0.id == selectedFoodID }) else {
            return "Choose food"
        }
        return item.name
    }

    private var categorySelectionSummary: String {
        if isCompositeFoodSelected {
            return "Composite Food"
        }
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID }) else {
            return "Choose category"
        }
        return category.name
    }

    private var foodSelectionHelpText: String {
        if isManualEntryFlowActive && !hasManualFoodProposal {
            return "Enter a food name and DragonHealth will identify it, propose the category, portion, amount, and notes, then ask you to confirm before saving."
        }
        if availableFoodItems.isEmpty {
            return "No foods are saved in your library yet. Enter a food name and DragonHealth will prepare the rest."
        }
        if selectedFoodID != nil {
            return "Review the meal, category, and amount below before saving."
        }
        if hasManualFoodProposal {
            return "Confirm the AI proposal below, adjust anything needed, then save."
        }
        if let mealName = resolvedMealSlot?.name ?? fallbackMealSlot?.name {
            return "Start with a food. The rest of the fields will appear after you choose one, and it will save to \(mealName) unless you change it."
        }
        return "Start with a food. The rest of the fields will appear after you choose one."
    }

    var body: some View {
        NavigationStack {
            Form {
                if let contextDate {
                    Section("Day") {
                        Text(contextDate, style: .date)
                            .font(.headline)
                    }
                }

                foodSelectionSection

                if isManualEntryFlowActive && selectedFoodID == nil {
                    manualFoodSuggestionSection
                }

                if shouldShowQuickAddDetails {
                    logContextSection
                    inputModeSection
                    portionSection
                    amountSection
                    notesSection
                }
            }
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSaveAction()
                    }
                    .glassButton(.text)
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedFoodID) { _, newValue in
                guard let foodID = newValue,
                      let item = availableFoodItems.first(where: { $0.id == foodID }) else {
                    amountText = ""
                    ensureDrinkUnitSelection(preferredUnitID: nil)
                    return
                }
                showsManualDetails = false
                manualFoodName = item.name
                hasManualFoodProposal = false
                manualFoodSuggestionConfidence = nil
                manualFoodSuggestionError = nil
                manualAmountPerPortion = nil
                manualUnitID = nil
                if categories.contains(where: { $0.id == item.categoryID }) {
                    selectedCategoryID = item.categoryID
                }
                portion = PortionWheelControl.roundedToIncrement(item.portionEquivalent, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: item.unitID)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onAppear {
                if selectedMealSlotID == nil {
                    if let preselectedMealSlotID,
                       mealSlots.contains(where: { $0.id == preselectedMealSlotID }) {
                        selectedMealSlotID = preselectedMealSlotID
                    } else if !isCategoryFirst {
                        selectedMealSlotID = mealSlots.first?.id
                    }
                }
                if selectedCategoryID == nil {
                    if let preselectedCategoryID,
                       categories.contains(where: { $0.id == preselectedCategoryID }) {
                        selectedCategoryID = preselectedCategoryID
                    }
                }
                portion = PortionWheelControl.roundedToIncrement(portion, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: selectedFoodItem?.unitID)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onChange(of: portion) { _, _ in
                syncAmountFromPortion()
            }
            .onChange(of: selectedCategoryID) { _, _ in
                portion = PortionWheelControl.roundedToIncrement(portion, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: selectedFoodItem?.unitID)
                if !amountInputEnabled {
                    inputMode = .portion
                }
                syncAmountFromPortion()
            }
            .onChange(of: amountText) { _, _ in
                guard inputMode == .amount else { return }
                syncPortionFromAmount()
            }
            .onChange(of: inputMode) { _, newValue in
                if newValue == .amount {
                    syncAmountFromPortion()
                }
            }
            .onChange(of: manualFoodName) { oldValue, newValue in
                guard selectedFoodID == nil else { return }
                if pendingSuggestedManualFoodName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    == newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                    pendingSuggestedManualFoodName = nil
                    return
                }
                if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) == newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return
                }
                hasManualFoodProposal = false
                manualFoodSuggestionConfidence = nil
                manualFoodSuggestionError = nil
                selectedCategoryID = nil
                manualAmountPerPortion = nil
                manualUnitID = nil
                amountText = ""
                notes = ""
                portion = 1.0
                inputMode = .portion
                ensureDrinkUnitSelection(preferredUnitID: nil)
            }
            .sheet(item: $pendingLibraryEntry, onDismiss: {
                shouldCompleteSaveAfterLibraryEntry = false
            }) { context in
                FoodEntrySheet(
                    categories: categories,
                    units: units,
                    allItems: store.foodItems,
                    suggestionRequest: context.suggestionRequest,
                    autoSuggestOnAppear: true
                ) { item in
                    Task {
                        await saveQuickAddLibraryFood(item)
                    }
                }
            }
            .confirmationDialog(
                "Add to Library?",
                isPresented: Binding(
                    get: { libraryOfferContext != nil },
                    set: { isPresented in
                        if !isPresented {
                            libraryOfferContext = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: libraryOfferContext
            ) { context in
                Button("Yes, add to library") {
                    pendingLibraryEntry = context
                    libraryOfferContext = nil
                }
                Button("Not now", role: .cancel) {
                    shouldCompleteSaveAfterLibraryEntry = false
                    libraryOfferContext = nil
                    completeSave()
                }
            } message: { context in
                Text("Shall I add \(context.suggestionRequest.enteredName) to your library first? DragonHealth will prepare the new food with AI, then return here and finish logging it.")
            }
            .alert("Food Library Error", isPresented: $showingLibraryEntryError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(libraryEntryErrorMessage ?? "Food save failed.")
            }
        }
        .dynamicTypeSize(quickAddDynamicTypeSize)
    }

    @ViewBuilder
    private var foodSelectionSection: some View {
        Section {
            if availableFoodItems.isEmpty {
                unavailableFoodRow
            } else {
                NavigationLink {
                    FoodLibraryPicker(
                        items: availableFoodItems,
                        categories: categories,
                        units: units,
                        selectedCategoryID: selectedCategoryID,
                        selectedFoodID: $selectedFoodID
                    )
                } label: {
                    prominentFoodSelectorRow
                }
            }

            Text(foodSelectionHelpText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !shouldShowQuickAddDetails && !availableFoodItems.isEmpty {
                Button {
                    showsManualDetails = true
                    hasManualFoodProposal = false
                    manualFoodSuggestionError = nil
                    manualFoodSuggestionConfidence = nil
                } label: {
                    Label("Type a food name instead", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var manualFoodSuggestionSection: some View {
        Section("Food Name") {
            TextField("Enter food name", text: $manualFoodName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    requestManualFoodSuggestion()
                }

            Button {
                requestManualFoodSuggestion()
            } label: {
                Label(isSuggestingManualFood ? "Identifying Food..." : "Identify Food", systemImage: "sparkles")
            }
            .glassButton(.text)
            .disabled(trimmedManualFoodName.isEmpty || isSuggestingManualFood)

            if isSuggestingManualFood {
                ProgressView("Preparing food proposal…")
                    .font(.caption)
            } else if let manualFoodSuggestionError {
                Text(manualFoodSuggestionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let manualFoodSuggestionConfidence {
                Text("AI proposed this food for review. Confidence: \((manualFoodSuggestionConfidence * 100).rounded().cleanNumber)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if MealPhotoAIConfig.client() == nil {
                Text("OpenAI API key missing. Add it in Manage > Integrations > Meal Photo AI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var logContextSection: some View {
        Section("Details") {
            NavigationLink {
                QuickAddMealSlotPicker(
                    mealSlots: mealSlots,
                    isCategoryFirst: isCategoryFirst,
                    fallbackMealSlot: fallbackMealSlot,
                    selectedMealSlotID: $selectedMealSlotID
                )
            } label: {
                selectorRow(title: "Meal", value: mealSelectionSummary, isPlaceholder: selectedMealSlotID == nil)
            }

            if isCompositeFoodSelected {
                selectorRow(title: "Category", value: categorySelectionSummary, isPlaceholder: false)
                    .foregroundStyle(.secondary)
            } else {
                NavigationLink {
                    QuickAddCategoryPicker(
                        categories: categories,
                        selectedCategoryID: $selectedCategoryID
                    )
                } label: {
                    selectorRow(title: "Category", value: categorySelectionSummary, isPlaceholder: selectedCategoryID == nil)
                }
            }
        }
    }

    private var prominentFoodSelectorRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selectedFoodID == nil ? "fork.knife.circle" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(selectedFoodID == nil ? Color.accentColor : Color.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Food")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(foodSelectionSummary)
                    .font(.headline)
                    .foregroundStyle(selectedFoodID == nil ? .secondary : .primary)
                    .lineLimit(2)
                Text(selectedFoodID == nil ? "Choose a food from your library." : "Selected food details are ready to review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var unavailableFoodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Food", systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("No foods in library")
                .font(.headline)
            Text("You can still log manually, or add foods to the library for a faster flow.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func selectorRow(title: String, value: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var inputModeSection: some View {
        Section("Input Mode") {
            Picker("Input Mode", selection: $inputMode) {
                ForEach(EntryInputMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!amountInputEnabled)
            if !amountInputEnabled {
                Text(isDrinkCategory ? "Enable ml or L units to enter amounts." : "Select a food with a portion size to enter amounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var portionSection: some View {
        Section("Portion") {
            PortionWheelControl(portion: $portion, accentColor: selectedCategoryColor, increment: portionIncrement)
                .disabled(inputMode == .amount && amountInputEnabled)
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        Section("Amount") {
            HStack {
                TextField("0", text: $amountText)
                    .keyboardType(activeUnit?.allowsDecimal == false ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .disabled(inputMode == .portion || !amountInputEnabled)
                if isDrinkCategory {
                    Picker("Unit", selection: $drinkUnitID) {
                        ForEach(drinkUnits) { unit in
                            Text(unit.symbol).tag(Optional(unit.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(inputMode == .portion || !amountInputEnabled)
                } else if let unitSymbol = selectedUnit?.symbol {
                    Text(unitSymbol)
                        .foregroundStyle(.secondary)
                }
            }
            if !isDrinkCategory, let amountPerPortion, let unitSymbol = selectedUnit?.symbol {
                Text("1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            TextField("Add a note", text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        }
    }

    private func requestManualFoodSuggestion() {
        let enteredName = trimmedManualFoodName
        guard !enteredName.isEmpty else { return }
        guard let apiKey = MealPhotoAIConfig.apiKey() else {
            manualFoodSuggestionError = "OpenAI API key missing."
            return
        }

        manualFoodSuggestionError = nil
        manualFoodSuggestionConfidence = nil
        hasManualFoodProposal = false
        isSuggestingManualFood = true

        Task {
            do {
                let client = OpenAIFoodDetailClient(apiKey: apiKey, model: MealPhotoAIConfig.model())
                let suggestion = try await client.suggestFood(
                    request: FoodDetailSuggestionRequest(
                        enteredName: enteredName,
                        referenceImage: nil,
                        referenceNotes: nil
                    ),
                    categories: categories,
                    units: units
                )

                await MainActor.run {
                    applyManualFoodSuggestion(suggestion)
                    isSuggestingManualFood = false
                }
            } catch {
                await MainActor.run {
                    manualFoodSuggestionError = manualFoodSuggestionErrorMessage(for: error)
                    isSuggestingManualFood = false
                }
            }
        }
    }

    private func applyManualFoodSuggestion(_ suggestion: FoodDetailSuggestion) {
        pendingSuggestedManualFoodName = suggestion.name
        manualFoodName = suggestion.name
        if let categoryID = suggestion.categoryID {
            selectedCategoryID = categoryID
        }
        portion = PortionWheelControl.roundedToIncrement(
            suggestion.portionEquivalent,
            increment: DrinkRules.portionIncrement(for: categories.first(where: { $0.id == suggestion.categoryID }))
        )
        manualAmountPerPortion = suggestion.amountPerPortion
        manualUnitID = suggestion.unitID
        notes = suggestion.notes ?? ""
        manualFoodSuggestionConfidence = suggestion.confidence
        hasManualFoodProposal = true

        if let category = categories.first(where: { $0.id == suggestion.categoryID }),
           DrinkRules.isDrinkCategory(category) {
            ensureDrinkUnitSelection(preferredUnitID: suggestion.unitID)
        } else {
            drinkUnitID = nil
        }

        if suggestion.amountPerPortion != nil {
            inputMode = .amount
            syncAmountFromPortion()
        } else {
            inputMode = .portion
            amountText = ""
        }
    }

    private func manualFoodSuggestionErrorMessage(for error: Error) -> String {
        if let clientError = error as? OpenAIMealPhotoClient.ClientError {
            return clientError.errorDescription ?? "Food suggestion failed."
        }
        return error.localizedDescription
    }

    private func handleSaveAction() {
        if let matchingLibraryFood {
            completeSave(using: matchingLibraryFood)
            return
        }
        if shouldOfferFoodLibraryEntry {
            shouldCompleteSaveAfterLibraryEntry = true
            libraryOfferContext = QuickAddLibraryEntryContext(
                suggestionRequest: FoodDetailSuggestionRequest(
                    enteredName: trimmedManualFoodName,
                    referenceImage: nil,
                    referenceNotes: trimmedNotesForSuggestion
                )
            )
            return
        }
        completeSave()
    }

    private var trimmedNotesForSuggestion: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func completeSave(using foodOverride: FoodItem? = nil) {
        let resolvedFood = foodOverride ?? selectedFoodItem
        let resolvedFoodID = resolvedFood?.id ?? selectedFoodID
        let resolvedCategoryID = resolvedFood?.categoryID ?? selectedCategoryID
        guard let resolvedCategoryID,
              let category = categories.first(where: { $0.id == resolvedCategoryID }),
              let meal = resolvedMealSlot else {
            return
        }

        let resolvedUnit: Core.FoodUnit? = {
            guard let resolvedFood else { return activeUnit }
            if let category = categories.first(where: { $0.id == resolvedCategoryID }),
               DrinkRules.isDrinkCategory(category) {
                return selectedDrinkUnit ?? drinkUnits.first(where: { $0.id == resolvedFood.unitID })
            }
            return units.first(where: { $0.id == resolvedFood.unitID }) ?? activeUnit
        }()

        let storedAmount = inputMode == .amount && amountInputEnabled ? roundedAmount(parsedAmount) : nil
        let storedUnitID = storedAmount == nil ? nil : resolvedUnit?.id
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFoodName = resolvedFoodID == nil ? trimmedManualFoodName : ""
        let resolvedNotes = trimmedNotes.isEmpty ? fallbackFoodName : trimmedNotes

        onSave(
            meal,
            category,
            portion,
            storedAmount,
            storedUnitID,
            resolvedNotes.isEmpty ? nil : resolvedNotes,
            resolvedFoodID
        )
        dismiss()
    }

    private func saveQuickAddLibraryFood(_ item: FoodItem) async {
        let error = await store.saveFoodItemReturningError(item)
        await MainActor.run {
            if let error {
                libraryEntryErrorMessage = error
                showingLibraryEntryError = true
                return
            }

            pendingLibraryEntry = nil
            applySavedFoodToQuickAdd(item)

            if shouldCompleteSaveAfterLibraryEntry {
                shouldCompleteSaveAfterLibraryEntry = false
                completeSave(using: item)
            }
        }
    }

    private func applySavedFoodToQuickAdd(_ item: FoodItem) {
        manualFoodName = item.name
        selectedFoodID = item.id
        selectedCategoryID = item.categoryID
        hasManualFoodProposal = false
        manualFoodSuggestionConfidence = nil
        manualFoodSuggestionError = nil
        manualAmountPerPortion = nil
        manualUnitID = nil
        portion = PortionWheelControl.roundedToIncrement(
            item.portionEquivalent,
            increment: DrinkRules.portionIncrement(for: categories.first(where: { $0.id == item.categoryID }))
        )
        if let amountPerPortion = item.amountPerPortion {
            amountText = amountPerPortion.cleanNumber
            inputMode = .amount
        } else {
            amountText = ""
            inputMode = .portion
        }
        ensureDrinkUnitSelection(preferredUnitID: item.unitID)
        if inputMode == .portion {
            syncAmountFromPortion()
        }
    }

    private func roundedAmount(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return roundedAmountValue(value)
    }

    private func ensureDrinkUnitSelection(preferredUnitID: UUID?) {
        guard isDrinkCategory else { return }
        if let preferredUnitID,
           let symbol = units.first(where: { $0.id == preferredUnitID })?.symbol,
           DrinkRules.isDrinkUnitSymbol(symbol) {
            drinkUnitID = preferredUnitID
            return
        }
        if let currentSymbol = selectedDrinkUnit?.symbol, DrinkRules.isDrinkUnitSymbol(currentSymbol) {
            return
        }
        drinkUnitID = drinkUnits.first(where: { $0.symbol.lowercased() == "ml" })?.id ?? drinkUnits.first?.id
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if isDrinkCategory {
            let symbol = activeUnit?.symbol.lowercased()
            if symbol == "ml" {
                return value.rounded()
            }
            return Portion.roundToIncrement(value, increment: Portion.drinkIncrement)
        }
        if activeUnit?.allowsDecimal == false {
            return value.rounded()
        }
        return Portion.roundToIncrement(value)
    }

    private func syncAmountFromPortion() {
        guard amountInputEnabled else {
            amountText = ""
            return
        }
        guard !isSyncing else { return }
        if isDrinkCategory {
            guard let unitSymbol = activeUnit?.symbol else { return }
            isSyncing = true
            let liters = Portion.roundToIncrement(portion, increment: Portion.drinkIncrement)
            let amount: Double
            if unitSymbol.lowercased() == "ml" {
                amount = liters * DrinkRules.mlPerLiter
            } else {
                amount = liters
            }
            let rounded = roundedAmountValue(amount)
            amountText = rounded.cleanNumber
            isSyncing = false
            return
        }
        guard let amountPerPortion else { return }
        isSyncing = true
        let amount = roundedAmountValue(portion * amountPerPortion)
        amountText = amount.cleanNumber
        isSyncing = false
    }

    private func syncPortionFromAmount() {
        guard amountInputEnabled else { return }
        guard !isSyncing else { return }
        guard let amount = parsedAmount else { return }
        isSyncing = true
        if isDrinkCategory {
            let normalizedAmount = roundedAmountValue(amount)
            let unitSymbol = activeUnit?.symbol
            let liters = DrinkRules.liters(from: normalizedAmount, unitSymbol: unitSymbol) ?? normalizedAmount
            let computed = Portion.roundToIncrement(liters, increment: Portion.drinkIncrement)
            let clamped = min(max(computed, 0.0), 6.0)
            portion = clamped
            let correctedAmount: Double
            if (unitSymbol ?? "").lowercased() == "ml" {
                correctedAmount = clamped * DrinkRules.mlPerLiter
            } else {
                correctedAmount = clamped
            }
            amountText = roundedAmountValue(correctedAmount).cleanNumber
            isSyncing = false
            return
        }
        guard let amountPerPortion else { return }
        let normalizedAmount = roundedAmountValue(amount)
        let computed = Portion.roundToIncrement(normalizedAmount / amountPerPortion)
        let clamped = min(max(computed, 0.0), 6.0)
        portion = clamped
        let correctedAmount = roundedAmountValue(clamped * amountPerPortion)
        amountText = correctedAmount.cleanNumber
        isSyncing = false
    }

    private var quickAddDynamicTypeSize: DynamicTypeSize {
        switch store.settings.fontSize {
        case .small:
            return .xSmall
        case .standard:
            return .large
        case .large:
            return .xLarge
        }
    }
}

private struct QuickAddMealSlotPicker: View {
    let mealSlots: [MealSlot]
    let isCategoryFirst: Bool
    let fallbackMealSlot: MealSlot?
    @Binding var selectedMealSlotID: UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if isCategoryFirst {
                Button {
                    selectedMealSlotID = nil
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text("Auto")
                        Spacer()
                        if let fallbackMealSlot {
                            Text(fallbackMealSlot.name)
                                .foregroundStyle(.secondary)
                        }
                        if selectedMealSlotID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(mealSlots) { slot in
                Button {
                    selectedMealSlotID = slot.id
                    dismiss()
                } label: {
                    HStack {
                        Text(slot.name)
                        Spacer()
                        if selectedMealSlotID == slot.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Meal")
    }
}

private struct QuickAddCategoryPicker: View {
    let categories: [Core.Category]
    @Binding var selectedCategoryID: UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    selectedCategoryID = category.id
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(CategoryColorPalette.color(for: category))
                            .frame(width: 10, height: 10)
                        Text(category.name)
                        Spacer()
                        if selectedCategoryID == category.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Category")
    }
}

private struct FoodLibraryPicker: View {
    let items: [FoodItem]
    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let selectedCategoryID: UUID?
    @Binding var selectedFoodID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter: FoodLibraryFilter
    private let libraryRowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    private let libraryRowMinHeight: CGFloat = 36
    private let libraryThumbnailSize: CGFloat = 30
    private let libraryRowPadding: CGFloat = 2

    init(
        items: [FoodItem],
        categories: [Core.Category],
        units: [Core.FoodUnit],
        selectedCategoryID: UUID?,
        selectedFoodID: Binding<UUID?>
    ) {
        self.items = items
        self.categories = categories
        self.units = units
        self.selectedCategoryID = selectedCategoryID
        _selectedFoodID = selectedFoodID
        _filter = State(initialValue: .all)
    }

    var body: some View {
        List {
            Section("Filter") {
                Picker("Filter", selection: $filter) {
                    ForEach(FoodLibraryFilter.allCases) { option in
                        Text(option.label(selectedCategoryName: selectedCategoryName)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Library") {
                if items.isEmpty {
                    Text("No foods in your library yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowInsets(libraryRowInsets)
                } else {
                    Button {
                        selectedFoodID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("No saved food")
                            Spacer()
                            if selectedFoodID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(libraryRowInsets)

                    if filteredItems.isEmpty {
                        Text("No foods match your search or filters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowInsets(libraryRowInsets)
                    } else {
                        ForEach(filteredItems) { item in
                            Button {
                                selectedFoodID = item.id
                                dismiss()
                            } label: {
                                FoodItemRow(
                                    item: item,
                                    categoryName: categoryName(for: item.categoryID),
                                    unitSymbol: unitSymbol(for: item.unitID),
                                    showsFavorite: false,
                                    thumbnailSize: libraryThumbnailSize,
                                    verticalPadding: libraryRowPadding
                                )
                                .overlay(alignment: .trailing) {
                                    if selectedFoodID == item.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(libraryRowInsets)
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, libraryRowMinHeight)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search foods"
        )
        .navigationTitle("Choose Food")
    }

    private var selectedCategoryName: String? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id == selectedCategoryID })?.name
    }

    private var filteredItems: [FoodItem] {
        var results = items
        results = filter.apply(to: results, selectedCategoryID: selectedCategoryID)
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { return results }
        return results.filter { item in
            let category = categoryName(for: item.categoryID)
            let notes = item.notes ?? ""
            return item.name.localizedStandardContains(term)
                || category.localizedStandardContains(term)
                || notes.localizedStandardContains(term)
        }
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return units.first(where: { $0.id == id })?.symbol
    }
}

private enum FoodLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case selectedCategory

    var id: String { rawValue }

    func label(selectedCategoryName: String?) -> String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
        case .selectedCategory:
            return selectedCategoryName ?? "Category"
        }
    }

    func apply(to items: [FoodItem], selectedCategoryID: UUID?) -> [FoodItem] {
        switch self {
        case .all:
            return items
        case .favorites:
            return items.filter(\.isFavorite)
        case .selectedCategory:
            guard let selectedCategoryID else { return items }
            return items.filter { $0.categoryID == selectedCategoryID }
        }
    }
}

struct EntryEditSheet: View {
    let entry: DailyLogEntry
    let categories: [Core.Category]
    let mealSlots: [MealSlot]
    let foodItems: [FoodItem]
    let units: [Core.FoodUnit]
    let onSave: (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID: UUID?
    @State private var selectedMealSlotID: UUID?
    @State private var selectedFoodID: UUID?
    @State private var portion: Double
    @State private var inputMode: EntryInputMode
    @State private var amountText: String
    @State private var drinkUnitID: UUID?
    @State private var isSyncing = false
    @State private var notes: String
    private var selectedCategory: Core.Category? {
        guard let selectedCategoryID else { return nil }
        return categories.first(where: { $0.id == selectedCategoryID })
    }

    private var selectedCategoryColor: Color {
        guard let category = selectedCategory else {
            return CategoryColorPalette.fallback
        }
        return CategoryColorPalette.color(for: category)
    }
    private var availableFoodItems: [FoodItem] {
        let allowedCategoryIDs = Set(categories.map(\.id))
        return foodItems.filter { allowedCategoryIDs.contains($0.categoryID) && !$0.kind.isComposite }
    }
    private var selectedFoodItem: FoodItem? {
        let foodID = selectedFoodID ?? entry.foodItemID
        guard let foodID else { return nil }
        return foodItems.first(where: { $0.id == foodID })
    }

    private var isDrinkCategory: Bool {
        guard let selectedCategory else { return false }
        return DrinkRules.isDrinkCategory(selectedCategory)
    }

    private var drinkUnits: [Core.FoodUnit] {
        DrinkRules.drinkUnits(from: units)
    }

    private var selectedUnit: Core.FoodUnit? {
        guard let unitID = selectedFoodItem?.unitID else { return nil }
        return units.first(where: { $0.id == unitID })
    }

    private var selectedDrinkUnit: Core.FoodUnit? {
        guard let drinkUnitID else { return nil }
        return drinkUnits.first(where: { $0.id == drinkUnitID }) ?? units.first(where: { $0.id == drinkUnitID })
    }

    private var activeUnit: Core.FoodUnit? {
        isDrinkCategory ? selectedDrinkUnit : selectedUnit
    }

    private var amountPerPortion: Double? {
        selectedFoodItem?.amountPerPortion
    }

    private var amountInputEnabled: Bool {
        if isDrinkCategory {
            return selectedDrinkUnit != nil
        }
        return amountPerPortion != nil && selectedUnit != nil
    }

    private var portionIncrement: Double {
        DrinkRules.portionIncrement(for: selectedCategory)
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        guard selectedMealSlotID != nil, selectedCategoryID != nil else { return false }
        if inputMode == .amount && amountInputEnabled {
            return parsedAmount != nil
        }
        return true
    }

    private func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    init(entry: DailyLogEntry, categories: [Core.Category], mealSlots: [MealSlot], foodItems: [FoodItem], units: [Core.FoodUnit], onSave: @escaping (MealSlot, Core.Category, Double, Double?, UUID?, String?, UUID?) -> Void) {
        self.entry = entry
        self.categories = categories
        self.mealSlots = mealSlots
        self.foodItems = foodItems
        self.units = units
        self.onSave = onSave
        let category = categories.first(where: { $0.id == entry.categoryID })
        let increment = DrinkRules.portionIncrement(for: category)
        _portion = State(initialValue: PortionWheelControl.roundedToIncrement(entry.portion.value, increment: increment))
        _inputMode = State(initialValue: entry.amountValue == nil ? .portion : .amount)
        _amountText = State(initialValue: entry.amountValue.map { $0.cleanNumber } ?? "")
        _drinkUnitID = State(initialValue: entry.amountUnitID)
        _selectedCategoryID = State(initialValue: entry.categoryID)
        _selectedMealSlotID = State(initialValue: entry.mealSlotID)
        _selectedFoodID = State(initialValue: entry.foodItemID)
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Meal Slot", selection: $selectedMealSlotID) {
                        ForEach(mealSlots) { slot in
                            Text(slot.name).tag(Optional(slot.id))
                        }
                    }
                }

                Section("Food") {
                    if availableFoodItems.isEmpty && selectedFoodItem == nil {
                        Text("No foods in your library yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            FoodLibraryPicker(
                                items: availableFoodItems,
                                categories: categories,
                                units: units,
                                selectedCategoryID: selectedCategoryID,
                                selectedFoodID: $selectedFoodID
                            )
                        } label: {
                            if let item = selectedFoodItem {
                                FoodItemRow(
                                    item: item,
                                    categoryName: categoryName(for: item.categoryID),
                                    unitSymbol: selectedUnit?.symbol,
                                    thumbnailSize: 34
                                )
                            } else {
                                Text("Choose a food")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(categories) { category in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(CategoryColorPalette.color(for: category))
                                    .frame(width: 10, height: 10)
                                Text(category.name)
                            }
                            .tag(Optional(category.id))
                        }
                    }
                }

                Section("Input Mode") {
                    Picker("Input Mode", selection: $inputMode) {
                        ForEach(EntryInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!amountInputEnabled)
                    if !amountInputEnabled {
                        Text(isDrinkCategory ? "Enable ml or L units to enter amounts." : "Select a food with a portion size to enter amounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Portion") {
                    PortionWheelControl(portion: $portion, accentColor: selectedCategoryColor, increment: portionIncrement)
                        .disabled(inputMode == .amount && amountInputEnabled)
                }

                Section("Amount") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(activeUnit?.allowsDecimal == false ? .numberPad : .decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(inputMode == .portion || !amountInputEnabled)
                        if isDrinkCategory {
                            Picker("Unit", selection: $drinkUnitID) {
                                ForEach(drinkUnits) { unit in
                                    Text(unit.symbol).tag(Optional(unit.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(inputMode == .portion || !amountInputEnabled)
                        } else if let unitSymbol = selectedUnit?.symbol {
                            Text(unitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !isDrinkCategory, let amountPerPortion, let unitSymbol = selectedUnit?.symbol {
                        Text("1 portion = \(amountPerPortion.cleanNumber) \(unitSymbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let mealID = selectedMealSlotID,
                              let categoryID = selectedCategoryID,
                              let meal = mealSlots.first(where: { $0.id == mealID }),
                              let category = categories.first(where: { $0.id == categoryID }) else {
                            return
                        }
                        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let storedAmount = inputMode == .amount && amountInputEnabled ? roundedAmount(parsedAmount) : nil
                        let storedUnitID = storedAmount == nil ? nil : activeUnit?.id
                        onSave(
                            meal,
                            category,
                            portion,
                            storedAmount,
                            storedUnitID,
                            trimmedNotes.isEmpty ? nil : trimmedNotes,
                            selectedFoodID
                        )
                        dismiss()
                    }
                    .glassButton(.text)
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedFoodID) { _, newValue in
                guard let foodID = newValue,
                      let item = availableFoodItems.first(where: { $0.id == foodID }) else {
                    amountText = ""
                    ensureDrinkUnitSelection(preferredUnitID: nil)
                    return
                }
                if categories.contains(where: { $0.id == item.categoryID }) {
                    selectedCategoryID = item.categoryID
                }
                portion = PortionWheelControl.roundedToIncrement(item.portionEquivalent, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: item.unitID)
                syncAmountFromPortion()
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
            .onChange(of: portion) { _, _ in
                syncAmountFromPortion()
            }
            .onChange(of: selectedCategoryID) { _, _ in
                portion = PortionWheelControl.roundedToIncrement(portion, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: selectedFoodItem?.unitID)
                if !amountInputEnabled {
                    inputMode = .portion
                }
                syncAmountFromPortion()
            }
            .onChange(of: amountText) { _, _ in
                guard inputMode == .amount else { return }
                syncPortionFromAmount()
            }
            .onChange(of: inputMode) { _, newValue in
                if newValue == .amount {
                    syncAmountFromPortion()
                }
            }
            .onAppear {
                portion = PortionWheelControl.roundedToIncrement(portion, increment: portionIncrement)
                ensureDrinkUnitSelection(preferredUnitID: entry.amountUnitID ?? selectedFoodItem?.unitID)
                if amountInputEnabled && entry.amountValue == nil {
                    syncAmountFromPortion()
                }
                if !amountInputEnabled {
                    inputMode = .portion
                }
            }
        }
    }

    private func roundedAmount(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return roundedAmountValue(value)
    }

    private func ensureDrinkUnitSelection(preferredUnitID: UUID?) {
        guard isDrinkCategory else { return }
        if let preferredUnitID,
           let symbol = units.first(where: { $0.id == preferredUnitID })?.symbol,
           DrinkRules.isDrinkUnitSymbol(symbol) {
            drinkUnitID = preferredUnitID
            return
        }
        if let currentSymbol = selectedDrinkUnit?.symbol, DrinkRules.isDrinkUnitSymbol(currentSymbol) {
            return
        }
        drinkUnitID = drinkUnits.first(where: { $0.symbol.lowercased() == "ml" })?.id ?? drinkUnits.first?.id
    }

    private func roundedAmountValue(_ value: Double) -> Double {
        if isDrinkCategory {
            let symbol = activeUnit?.symbol.lowercased()
            if symbol == "ml" {
                return value.rounded()
            }
            return Portion.roundToIncrement(value, increment: Portion.drinkIncrement)
        }
        if activeUnit?.allowsDecimal == false {
            return value.rounded()
        }
        return Portion.roundToIncrement(value)
    }

    private func syncAmountFromPortion() {
        guard amountInputEnabled else {
            amountText = ""
            return
        }
        guard !isSyncing else { return }
        if isDrinkCategory {
            guard let unitSymbol = activeUnit?.symbol else { return }
            isSyncing = true
            let liters = Portion.roundToIncrement(portion, increment: Portion.drinkIncrement)
            let amount: Double
            if unitSymbol.lowercased() == "ml" {
                amount = liters * DrinkRules.mlPerLiter
            } else {
                amount = liters
            }
            let rounded = roundedAmountValue(amount)
            amountText = rounded.cleanNumber
            isSyncing = false
            return
        }
        guard let amountPerPortion else { return }
        isSyncing = true
        let amount = roundedAmountValue(portion * amountPerPortion)
        amountText = amount.cleanNumber
        isSyncing = false
    }

    private func syncPortionFromAmount() {
        guard amountInputEnabled else { return }
        guard !isSyncing else { return }
        guard let amount = parsedAmount else { return }
        isSyncing = true
        if isDrinkCategory {
            let normalizedAmount = roundedAmountValue(amount)
            let unitSymbol = activeUnit?.symbol
            let liters = DrinkRules.liters(from: normalizedAmount, unitSymbol: unitSymbol) ?? normalizedAmount
            let computed = Portion.roundToIncrement(liters, increment: Portion.drinkIncrement)
            let clamped = min(max(computed, 0.0), 6.0)
            portion = clamped
            let correctedAmount: Double
            if (unitSymbol ?? "").lowercased() == "ml" {
                correctedAmount = clamped * DrinkRules.mlPerLiter
            } else {
                correctedAmount = clamped
            }
            amountText = roundedAmountValue(correctedAmount).cleanNumber
            isSyncing = false
            return
        }
        guard let amountPerPortion else { return }
        let normalizedAmount = roundedAmountValue(amount)
        let computed = Portion.roundToIncrement(normalizedAmount / amountPerPortion)
        let clamped = min(max(computed, 0.0), 6.0)
        portion = clamped
        let correctedAmount = roundedAmountValue(clamped * amountPerPortion)
        amountText = correctedAmount.cleanNumber
        isSyncing = false
    }
}

private struct PortionWheelControl: View {
    @Binding var portion: Double
    let accentColor: Color
    let step: Double

    init(portion: Binding<Double>, accentColor: Color, increment: Double = Portion.defaultIncrement) {
        self._portion = portion
        self.accentColor = accentColor
        self.step = increment
    }

    private var values: [Double] {
        let safeIncrement = max(step, Portion.drinkIncrement)
        let steps = Int(6.0 / safeIncrement)
        return (0...steps).map { Portion.roundToIncrement(Double($0) * safeIncrement, increment: safeIncrement) }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .padding(6)
            }
            .glassButton(.icon)
            .accessibilityLabel("Decrease by \(step.cleanNumber) portion")

            Picker("Portions", selection: $portion) {
                ForEach(values, id: \.self) { value in
                    Text(valueLabel(value))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 120, height: 120)
            .clipped()
            .accessibilityLabel("Portion picker")

            Button(action: increase) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .padding(6)
            }
            .glassButton(.icon)
            .accessibilityLabel("Increase by \(step.cleanNumber) portion")
        }
    }

    private func decrement() {
        let next = max(0.0, portion - step)
        portion = Self.roundedToIncrement(next, increment: step)
    }

    private func increase() {
        let next = min(6.0, portion + step)
        portion = Self.roundedToIncrement(next, increment: step)
    }

    static func roundedToIncrement(_ value: Double, increment: Double = Portion.defaultIncrement) -> Double {
        Portion.roundToIncrement(value, increment: increment)
    }

    private func valueLabel(_ value: Double) -> String {
        value.cleanNumber
    }
}

enum CategoryColorPalette {
    static let fallback = Color(.systemGray5)

    static func color(for category: Core.Category) -> Color {
        color(forName: category.name)
    }

    static func color(forName name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("protein") {
            return Color(red: 0.81, green: 0.94, blue: 0.82)
        }
        if lower.contains("vegetable") {
            return Color(red: 0.60, green: 0.83, blue: 0.60)
        }
        if lower.contains("fruit") {
            return Color(red: 0.72, green: 0.89, blue: 0.90)
        }
        if lower.contains("starch") || lower.contains("grain") || lower.contains("side") || lower.contains("carb") {
            return Color(red: 0.91, green: 0.78, blue: 0.63)
        }
        if lower.contains("dairy") {
            return Color(red: 0.75, green: 0.84, blue: 0.96)
        }
        if lower.contains("oil") || lower.contains("fat") || lower.contains("nut") {
            return Color(red: 0.96, green: 0.77, blue: 0.60)
        }
        if lower.contains("treat") {
            return Color(red: 0.84, green: 0.76, blue: 0.96)
        }
        return fallback
    }
}

private enum CategoryIconPalette {
    static func iconName(for category: Core.Category) -> String {
        iconName(forName: category.name)
    }

    static func iconName(forName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("protein") {
            return "fish"
        }
        if lower.contains("vegetable") {
            return "leaf"
        }
        if lower.contains("fruit") {
            return "apple.logo"
        }
        if lower.contains("starch") || lower.contains("grain") || lower.contains("side") || lower.contains("carb") {
            return preferredSymbol(["bagel", "baguette", "fork.knife"], fallback: "fork.knife")
        }
        if lower.contains("dairy") {
            return preferredSymbol(["carton", "carton.fill", "cup.and.saucer"], fallback: "cup.and.saucer")
        }
        if lower.contains("oil") || lower.contains("fat") || lower.contains("nut") {
            return "drop.circle"
        }
        if lower.contains("treat") {
            return preferredSymbol(["candybar", "birthday.cake", "gift.fill"], fallback: "gift.fill")
        }
        return "circle"
    }

    private static func preferredSymbol(_ names: [String], fallback: String) -> String {
        #if canImport(UIKit)
        for name in names {
            if UIImage(systemName: name) != nil {
                return name
            }
        }
        #endif
        return fallback
    }
}

private enum MealIconPalette {
    static func iconName(for mealSlot: MealSlot) -> String {
        iconName(forName: mealSlot.name)
    }

    static func iconName(forName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("breakfast") {
            return "sunrise"
        }
        if lower.contains("lunch") {
            return "sun.max"
        }
        if lower.contains("dinner") {
            return "moon.stars"
        }
        if lower.contains("snack") {
            return "leaf"
        }
        if lower.contains("late") || lower.contains("evening") || lower.contains("midnight") {
            return "💀"
        }
        return "fork.knife"
    }
}
