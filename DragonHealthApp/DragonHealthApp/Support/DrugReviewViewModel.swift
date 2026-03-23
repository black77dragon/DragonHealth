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
    @Published private(set) var medicationEntries: [GLP1MedicationEntry] = []
    @Published private(set) var preferredMedicationWeekday = 1
    @Published private(set) var isSavingDaily = false
    @Published private(set) var isSavingReflection = false
    @Published private(set) var isSavingMedication = false
    @Published private(set) var dailySaveConfirmationMessage: String?
    @Published private(set) var weeklySaveConfirmationMessage: String?
    @Published private(set) var medicationSaveConfirmationMessage: String?

    private let analytics = DrugReviewAnalytics()
    private var dailySaveConfirmationTask: Task<Void, Never>?
    private var weeklySaveConfirmationTask: Task<Void, Never>?
    private var medicationSaveConfirmationTask: Task<Void, Never>?

    deinit {
        dailySaveConfirmationTask?.cancel()
        weeklySaveConfirmationTask?.cancel()
        medicationSaveConfirmationTask?.cancel()
    }

    func load(store: AppStore, dailyDate: Date, weeklyReferenceDate: Date) async {
        preferredMedicationWeekday = store.settings.glp1MedicationWeekday
        medicationEntries = await store.fetchGLP1MedicationEntries()

        let currentEntry = await store.fetchDrugReviewEntry(for: dailyDate)
        applyDailyEntry(currentEntry)

        let currentReflection = await store.fetchDrugReviewWeeklyReflection(for: weeklyReferenceDate)
        applyWeeklyReflection(currentReflection)

        guard let selectedWeek = analytics.weekInterval(containing: weeklyReferenceDate, calendar: store.appCalendar),
              let trendRangeStart = store.appCalendar.date(byAdding: .day, value: -84, to: selectedWeek.start) else {
            weeklySummary = analytics.weeklySummary(
                referenceDate: weeklyReferenceDate,
                entries: currentEntry.map { [$0] } ?? [],
                reflection: currentReflection,
                calendar: store.appCalendar
            )
            trendPoints = []
            return
        }

        let entries = await store.fetchDrugReviewEntries(start: trendRangeStart, end: selectedWeek.end)
        let reflections = await store.fetchDrugReviewWeeklyReflections(start: trendRangeStart, end: selectedWeek.end)

        weeklySummary = analytics.weeklySummary(
            referenceDate: weeklyReferenceDate,
            entries: entries,
            reflection: currentReflection,
            calendar: store.appCalendar
        )
        trendPoints = analytics.weeklyTrendPoints(
            referenceDate: weeklyReferenceDate,
            entries: entries,
            reflections: reflections,
            weeks: 8,
            calendar: store.appCalendar
        )
    }

    func saveDaily(store: AppStore, day: Date, weeklyReferenceDate: Date) async {
        isSavingDaily = true
        defer { isSavingDaily = false }

        let entry = DrugReviewDailyEntry(
            id: existingEntryID(for: day, calendar: store.appCalendar) ?? UUID(),
            day: day,
            timestamp: Date(),
            appetiteControl: appetiteControl,
            energyLevel: energyLevel,
            sideEffects: sideEffects,
            mood: mood,
            observation: observation
        )
        let didSave = await store.saveDrugReviewEntry(entry)
        guard didSave else { return }
        await load(store: store, dailyDate: day, weeklyReferenceDate: weeklyReferenceDate)
        showDailySaveConfirmation("Daily check-in saved")
    }

    func saveWeeklyReflection(store: AppStore, dailyDate: Date, referenceDate: Date) async {
        isSavingReflection = true
        defer { isSavingReflection = false }

        guard let interval = analytics.weekInterval(containing: referenceDate, calendar: store.appCalendar) else {
            return
        }

        let reflection = DrugReviewWeeklyReflection(
            id: existingReflectionID(for: interval.start, calendar: store.appCalendar) ?? UUID(),
            weekStart: interval.start,
            updatedAt: Date(),
            whatWentWell: whatWentWell,
            whatDidNotWork: whatDidNotWork,
            whatToAdjust: whatToAdjust
        )
        let didSave = await store.saveDrugReviewWeeklyReflection(reflection)
        guard didSave else { return }
        await load(store: store, dailyDate: dailyDate, weeklyReferenceDate: referenceDate)
        showWeeklySaveConfirmation("Weekly reflection saved")
    }

    func saveMedicationEntry(
        store: AppStore,
        entryID: UUID? = nil,
        day: Date,
        medication: GLP1Medication,
        dose: GLP1Dose,
        isTaken: Bool,
        comment: String,
        dailyDate: Date,
        weeklyReferenceDate: Date
    ) async {
        isSavingMedication = true
        defer { isSavingMedication = false }

        let entry = GLP1MedicationEntry(
            id: entryID ?? UUID(),
            day: day,
            medication: medication,
            dose: dose,
            isTaken: isTaken,
            comment: comment
        )
        let didSave = await store.saveGLP1MedicationEntry(entry)
        guard didSave else { return }
        await load(store: store, dailyDate: dailyDate, weeklyReferenceDate: weeklyReferenceDate)
        let confirmation = isTaken ? "Medication entry saved" : "Medication plan saved"
        showMedicationSaveConfirmation(confirmation)
    }

    func deleteMedicationEntry(
        store: AppStore,
        entry: GLP1MedicationEntry,
        dailyDate: Date,
        weeklyReferenceDate: Date
    ) async {
        let didDelete = await store.deleteGLP1MedicationEntry(entry)
        guard didDelete else { return }
        await load(store: store, dailyDate: dailyDate, weeklyReferenceDate: weeklyReferenceDate)
    }

    func updatePreferredMedicationWeekday(store: AppStore, weekday: Int) async {
        let normalizedWeekday = min(max(weekday, 1), 7)
        preferredMedicationWeekday = normalizedWeekday

        var settings = store.settings
        settings.glp1MedicationWeekday = normalizedWeekday
        await store.updateSettings(settings)
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

    private func existingEntryID(for day: Date, calendar: Calendar) -> UUID? {
        guard let savedEntry,
              calendar.isDate(savedEntry.day, inSameDayAs: day) else {
            return nil
        }
        return savedEntry.id
    }

    private func existingReflectionID(for weekStart: Date, calendar: Calendar) -> UUID? {
        guard let savedReflection,
              calendar.isDate(savedReflection.weekStart, inSameDayAs: weekStart) else {
            return nil
        }
        return savedReflection.id
    }

    private func showDailySaveConfirmation(_ message: String) {
        dailySaveConfirmationMessage = message
        dailySaveConfirmationTask?.cancel()
        dailySaveConfirmationTask = makeConfirmationTask {
            self.dailySaveConfirmationMessage = nil
        }
    }

    private func showWeeklySaveConfirmation(_ message: String) {
        weeklySaveConfirmationMessage = message
        weeklySaveConfirmationTask?.cancel()
        weeklySaveConfirmationTask = makeConfirmationTask {
            self.weeklySaveConfirmationMessage = nil
        }
    }

    private func showMedicationSaveConfirmation(_ message: String) {
        medicationSaveConfirmationMessage = message
        medicationSaveConfirmationTask?.cancel()
        medicationSaveConfirmationTask = makeConfirmationTask {
            self.medicationSaveConfirmationMessage = nil
        }
    }

    private func makeConfirmationTask(onComplete: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            onComplete()
        }
    }
}
