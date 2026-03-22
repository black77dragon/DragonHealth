import Foundation
import Combine
import Core

@MainActor
final class DrugReviewViewModel: ObservableObject {
    @Published var appetiteControl = 5
    @Published var energyLevel = 5
    @Published var sideEffects = 5
    @Published var mood = 5
    @Published var observation = ""
    @Published var whatWentWell = ""
    @Published var whatDidNotWork = ""
    @Published var whatToAdjust = ""
    @Published var selectedTrendCriterion: DrugReviewCriterion = .appetiteControl
    @Published private(set) var savedEntry: DrugReviewDailyEntry?
    @Published private(set) var weeklySummary: DrugReviewWeeklySummary?
    @Published private(set) var trendPoints: [DrugReviewTrendPoint] = []
    @Published private(set) var savedReflection: DrugReviewWeeklyReflection?
    @Published private(set) var isSavingDaily = false
    @Published private(set) var isSavingReflection = false

    private let analytics = DrugReviewAnalytics()

    func load(store: AppStore) async {
        let currentDay = store.currentDay
        let currentEntry = await store.fetchDrugReviewEntry(for: currentDay)
        applyDailyEntry(currentEntry)

        let currentReflection = await store.fetchDrugReviewWeeklyReflection(for: currentDay)
        applyWeeklyReflection(currentReflection)

        guard let trendRangeStart = store.appCalendar.date(byAdding: .day, value: -84, to: currentDay) else {
            weeklySummary = analytics.weeklySummary(
                referenceDate: currentDay,
                entries: currentEntry.map { [$0] } ?? [],
                reflection: currentReflection,
                calendar: store.appCalendar
            )
            trendPoints = []
            return
        }

        let entries = await store.fetchDrugReviewEntries(start: trendRangeStart, end: currentDay)
        let reflections = await store.fetchDrugReviewWeeklyReflections(start: trendRangeStart, end: currentDay)

        weeklySummary = analytics.weeklySummary(
            referenceDate: currentDay,
            entries: entries,
            reflection: currentReflection,
            calendar: store.appCalendar
        )
        trendPoints = analytics.weeklyTrendPoints(
            referenceDate: currentDay,
            entries: entries,
            reflections: reflections,
            weeks: 8,
            calendar: store.appCalendar
        )
    }

    func saveDaily(store: AppStore) async {
        isSavingDaily = true
        defer { isSavingDaily = false }

        let entry = DrugReviewDailyEntry(
            id: savedEntry?.id ?? UUID(),
            day: store.currentDay,
            timestamp: Date(),
            appetiteControl: appetiteControl,
            energyLevel: energyLevel,
            sideEffects: sideEffects,
            mood: mood,
            observation: observation
        )
        await store.saveDrugReviewEntry(entry)
        await load(store: store)
    }

    func saveWeeklyReflection(store: AppStore) async {
        isSavingReflection = true
        defer { isSavingReflection = false }

        guard let interval = analytics.weekInterval(containing: store.currentDay, calendar: store.appCalendar) else {
            return
        }

        let reflection = DrugReviewWeeklyReflection(
            id: savedReflection?.id ?? UUID(),
            weekStart: interval.start,
            updatedAt: Date(),
            whatWentWell: whatWentWell,
            whatDidNotWork: whatDidNotWork,
            whatToAdjust: whatToAdjust
        )
        await store.saveDrugReviewWeeklyReflection(reflection)
        await load(store: store)
    }

    private func applyDailyEntry(_ entry: DrugReviewDailyEntry?) {
        savedEntry = entry
        appetiteControl = entry?.appetiteControl ?? 5
        energyLevel = entry?.energyLevel ?? 5
        sideEffects = entry?.sideEffects ?? 5
        mood = entry?.mood ?? 5
        observation = entry?.observation ?? ""
    }

    private func applyWeeklyReflection(_ reflection: DrugReviewWeeklyReflection?) {
        savedReflection = reflection
        whatWentWell = reflection?.whatWentWell ?? ""
        whatDidNotWork = reflection?.whatDidNotWork ?? ""
        whatToAdjust = reflection?.whatToAdjust ?? ""
    }
}
