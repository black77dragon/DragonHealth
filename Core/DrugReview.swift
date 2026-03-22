import Foundation

public enum DrugReviewCriterion: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appetiteControl
    case energyLevel
    case sideEffects
    case mood

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appetiteControl:
            return "Appetite Control"
        case .energyLevel:
            return "Energy"
        case .sideEffects:
            return "Side Effects"
        case .mood:
            return "Mood"
        }
    }

    public var shortTitle: String {
        switch self {
        case .appetiteControl:
            return "Appetite"
        case .energyLevel:
            return "Energy"
        case .sideEffects:
            return "Side Effects"
        case .mood:
            return "Mood"
        }
    }

    public var symbolName: String {
        switch self {
        case .appetiteControl:
            return "fork.knife"
        case .energyLevel:
            return "bolt.heart"
        case .sideEffects:
            return "bandage"
        case .mood:
            return "face.smiling"
        }
    }
}

public struct DrugReviewDailyEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let day: Date
    public let timestamp: Date
    public let appetiteControl: Int
    public let energyLevel: Int
    public let sideEffects: Int
    public let mood: Int
    public let observation: String?

    public init(
        id: UUID = UUID(),
        day: Date,
        timestamp: Date = Date(),
        appetiteControl: Int,
        energyLevel: Int,
        sideEffects: Int,
        mood: Int,
        observation: String? = nil
    ) {
        self.id = id
        self.day = day
        self.timestamp = timestamp
        self.appetiteControl = Self.clamp(appetiteControl)
        self.energyLevel = Self.clamp(energyLevel)
        self.sideEffects = Self.clamp(sideEffects)
        self.mood = Self.clamp(mood)
        self.observation = Self.normalizedText(observation)
    }

    public func value(for criterion: DrugReviewCriterion) -> Double {
        switch criterion {
        case .appetiteControl:
            return Double(appetiteControl)
        case .energyLevel:
            return Double(energyLevel)
        case .sideEffects:
            return Double(sideEffects)
        case .mood:
            return Double(mood)
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 1), 10)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct DrugReviewWeeklyReflection: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let weekStart: Date
    public let updatedAt: Date
    public let whatWentWell: String?
    public let whatDidNotWork: String?
    public let whatToAdjust: String?

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        updatedAt: Date = Date(),
        whatWentWell: String? = nil,
        whatDidNotWork: String? = nil,
        whatToAdjust: String? = nil
    ) {
        self.id = id
        self.weekStart = weekStart
        self.updatedAt = updatedAt
        self.whatWentWell = Self.normalizedText(whatWentWell)
        self.whatDidNotWork = Self.normalizedText(whatDidNotWork)
        self.whatToAdjust = Self.normalizedText(whatToAdjust)
    }

    public var notes: [DrugReviewFlaggedNote] {
        var notes: [DrugReviewFlaggedNote] = []
        if let whatWentWell {
            notes.append(DrugReviewFlaggedNote(title: "What Went Well", text: whatWentWell))
        }
        if let whatDidNotWork {
            notes.append(DrugReviewFlaggedNote(title: "What Didn't Work", text: whatDidNotWork))
        }
        if let whatToAdjust {
            notes.append(DrugReviewFlaggedNote(title: "What To Adjust", text: whatToAdjust))
        }
        return notes
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct DrugReviewFlaggedNote: Identifiable, Hashable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    public var id: String {
        "\(title)|\(text)"
    }
}

public struct DrugReviewWeeklyAverages: Hashable, Sendable {
    public let appetiteControl: Double?
    public let energyLevel: Double?
    public let sideEffects: Double?
    public let mood: Double?

    public init(
        appetiteControl: Double?,
        energyLevel: Double?,
        sideEffects: Double?,
        mood: Double?
    ) {
        self.appetiteControl = appetiteControl
        self.energyLevel = energyLevel
        self.sideEffects = sideEffects
        self.mood = mood
    }

    public func value(for criterion: DrugReviewCriterion) -> Double? {
        switch criterion {
        case .appetiteControl:
            return appetiteControl
        case .energyLevel:
            return energyLevel
        case .sideEffects:
            return sideEffects
        case .mood:
            return mood
        }
    }
}

public struct DrugReviewWeeklySummary: Hashable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let entryCount: Int
    public let averages: DrugReviewWeeklyAverages
    public let observationHighlights: [String]
    public let reflectionNotes: [DrugReviewFlaggedNote]

    public init(
        weekStart: Date,
        weekEnd: Date,
        entryCount: Int,
        averages: DrugReviewWeeklyAverages,
        observationHighlights: [String],
        reflectionNotes: [DrugReviewFlaggedNote]
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.entryCount = entryCount
        self.averages = averages
        self.observationHighlights = observationHighlights
        self.reflectionNotes = reflectionNotes
    }
}

public struct DrugReviewTrendPoint: Identifiable, Hashable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let entryCount: Int
    public let averages: DrugReviewWeeklyAverages
    public let reflectionNotes: [DrugReviewFlaggedNote]

    public init(
        weekStart: Date,
        weekEnd: Date,
        entryCount: Int,
        averages: DrugReviewWeeklyAverages,
        reflectionNotes: [DrugReviewFlaggedNote]
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.entryCount = entryCount
        self.averages = averages
        self.reflectionNotes = reflectionNotes
    }

    public var id: Date {
        weekStart
    }

    public func value(for criterion: DrugReviewCriterion) -> Double? {
        averages.value(for: criterion)
    }
}

public struct DrugReviewAnalytics: Sendable {
    public init() {}

    public func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        var reviewCalendar = calendar
        reviewCalendar.firstWeekday = 2
        reviewCalendar.minimumDaysInFirstWeek = 4

        guard let interval = reviewCalendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }

        let start = reviewCalendar.startOfDay(for: interval.start)
        guard let weekEnd = reviewCalendar.date(byAdding: .day, value: 6, to: start) else {
            return DateInterval(start: start, end: start)
        }
        return DateInterval(start: start, end: weekEnd)
    }

    public func weeklySummary(
        referenceDate: Date,
        entries: [DrugReviewDailyEntry],
        reflection: DrugReviewWeeklyReflection?,
        calendar: Calendar
    ) -> DrugReviewWeeklySummary? {
        guard let interval = weekInterval(containing: referenceDate, calendar: calendar) else {
            return nil
        }
        return summary(
            weekStart: interval.start,
            weekEnd: interval.end,
            entries: entries,
            reflection: reflection,
            calendar: calendar
        )
    }

    public func weeklyTrendPoints(
        referenceDate: Date,
        entries: [DrugReviewDailyEntry],
        reflections: [DrugReviewWeeklyReflection],
        weeks: Int = 8,
        calendar: Calendar
    ) -> [DrugReviewTrendPoint] {
        guard weeks > 0,
              let currentInterval = weekInterval(containing: referenceDate, calendar: calendar) else {
            return []
        }

        var points: [DrugReviewTrendPoint] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .day, value: -(offset * 7), to: currentInterval.start),
                  let interval = weekInterval(containing: weekStart, calendar: calendar) else {
                continue
            }

            let reflection = reflections.first {
                calendar.isDate($0.weekStart, inSameDayAs: interval.start)
            }
            let summary = summary(
                weekStart: interval.start,
                weekEnd: interval.end,
                entries: entries,
                reflection: reflection,
                calendar: calendar
            )

            if summary.entryCount > 0 || !summary.reflectionNotes.isEmpty {
                points.append(
                    DrugReviewTrendPoint(
                        weekStart: summary.weekStart,
                        weekEnd: summary.weekEnd,
                        entryCount: summary.entryCount,
                        averages: summary.averages,
                        reflectionNotes: summary.reflectionNotes
                    )
                )
            }
        }
        return points
    }

    private func summary(
        weekStart: Date,
        weekEnd: Date,
        entries: [DrugReviewDailyEntry],
        reflection: DrugReviewWeeklyReflection?,
        calendar: Calendar
    ) -> DrugReviewWeeklySummary {
        let weekEntries = entries
            .filter {
                let day = calendar.startOfDay(for: $0.day)
                return day >= weekStart && day <= weekEnd
            }
            .sorted(by: { $0.day < $1.day })

        let averages = DrugReviewWeeklyAverages(
            appetiteControl: average(for: .appetiteControl, entries: weekEntries),
            energyLevel: average(for: .energyLevel, entries: weekEntries),
            sideEffects: average(for: .sideEffects, entries: weekEntries),
            mood: average(for: .mood, entries: weekEntries)
        )

        let observationHighlights = weekEntries
            .sorted(by: { $0.timestamp > $1.timestamp })
            .compactMap(\.observation)
            .prefix(3)
            .map { $0 }

        return DrugReviewWeeklySummary(
            weekStart: weekStart,
            weekEnd: weekEnd,
            entryCount: weekEntries.count,
            averages: averages,
            observationHighlights: observationHighlights,
            reflectionNotes: reflection?.notes ?? []
        )
    }

    private func average(
        for criterion: DrugReviewCriterion,
        entries: [DrugReviewDailyEntry]
    ) -> Double? {
        guard !entries.isEmpty else { return nil }
        let total = entries.reduce(0.0) { partialResult, entry in
            partialResult + entry.value(for: criterion)
        }
        return total / Double(entries.count)
    }
}
