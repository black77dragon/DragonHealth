import Foundation

public struct Category: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var unitName: String
    public var isEnabled: Bool
    public var targetRule: TargetRule

    public init(id: UUID = UUID(), name: String, unitName: String, isEnabled: Bool, targetRule: TargetRule) {
        self.id = id
        self.name = name
        self.unitName = unitName
        self.isEnabled = isEnabled
        self.targetRule = targetRule
    }
}

public struct MealSlot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

public struct DailyLogEntry: Hashable, Sendable {
    public let date: Date
    public let mealSlotID: UUID
    public let categoryID: UUID
    public let portion: Portion

    public init(date: Date, mealSlotID: UUID, categoryID: UUID, portion: Portion) {
        self.date = date
        self.mealSlotID = mealSlotID
        self.categoryID = categoryID
        self.portion = portion
    }
}

public struct DailyLog: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public var entries: [DailyLogEntry]

    public init(id: UUID = UUID(), date: Date, entries: [DailyLogEntry]) {
        self.id = id
        self.date = date
        self.entries = entries
    }
}

public struct BodyMetricEntry: Hashable, Sendable {
    public let date: Date
    public let weightKg: Double?
    public let muscleMass: Double?
    public let bodyFatPercent: Double?
    public let waistCm: Double?

    public init(date: Date, weightKg: Double?, muscleMass: Double?, bodyFatPercent: Double?, waistCm: Double?) {
        self.date = date
        self.weightKg = weightKg
        self.muscleMass = muscleMass
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
    }
}
