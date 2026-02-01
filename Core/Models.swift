import Foundation

public struct Category: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var unitName: String
    public var isEnabled: Bool
    public var targetRule: TargetRule
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        unitName: String,
        isEnabled: Bool,
        targetRule: TargetRule,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.unitName = unitName
        self.isEnabled = isEnabled
        self.targetRule = targetRule
        self.sortOrder = sortOrder
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

public struct DailyLogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let mealSlotID: UUID
    public let categoryID: UUID
    public let portion: Portion
    public let notes: String?
    public let foodItemID: UUID?

    public init(
        id: UUID = UUID(),
        date: Date,
        mealSlotID: UUID,
        categoryID: UUID,
        portion: Portion,
        notes: String? = nil,
        foodItemID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.mealSlotID = mealSlotID
        self.categoryID = categoryID
        self.portion = portion
        self.notes = notes
        self.foodItemID = foodItemID
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
    public let steps: Double?

    public init(
        date: Date,
        weightKg: Double?,
        muscleMass: Double?,
        bodyFatPercent: Double?,
        waistCm: Double?,
        steps: Double? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.muscleMass = muscleMass
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
        self.steps = steps
    }
}

public enum CareProviderType: String, CaseIterable, Hashable, Sendable {
    case doctor
    case nutritionist

    public var label: String {
        switch self {
        case .doctor:
            return "Doctor"
        case .nutritionist:
            return "Nutrition Specialist"
        }
    }
}

public struct CareMeeting: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var providerType: CareProviderType
    public var notes: String

    public init(
        id: UUID = UUID(),
        date: Date,
        providerType: CareProviderType,
        notes: String
    ) {
        self.id = id
        self.date = date
        self.providerType = providerType
        self.notes = notes
    }
}

public struct FoodItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var categoryID: UUID
    public var portionEquivalent: Double
    public var notes: String?
    public var isFavorite: Bool
    public var imagePath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        portionEquivalent: Double,
        notes: String? = nil,
        isFavorite: Bool = false,
        imagePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.portionEquivalent = portionEquivalent
        self.notes = notes
        self.isFavorite = isFavorite
        self.imagePath = imagePath
    }
}

public enum DocumentType: String, CaseIterable, Hashable, Sendable {
    case pdf
    case image
}

public enum AppAppearance: String, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system:
            return "Automatic"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

public struct HealthDocument: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var fileName: String
    public var fileType: DocumentType
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        fileType: DocumentType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileType = fileType
        self.createdAt = createdAt
    }
}

public struct AppSettings: Hashable, Sendable {
    public var dayCutoffMinutes: Int
    public var profileImagePath: String?
    public var heightCm: Double?
    public var targetWeightKg: Double?
    public var motivation: String?
    public var doctorName: String?
    public var nutritionistName: String?
    public var foodSeedVersion: Int
    public var showLaunchSplash: Bool
    public var appearance: AppAppearance

    public init(
        dayCutoffMinutes: Int,
        profileImagePath: String? = nil,
        heightCm: Double? = nil,
        targetWeightKg: Double? = nil,
        motivation: String? = nil,
        doctorName: String? = nil,
        nutritionistName: String? = nil,
        foodSeedVersion: Int = 0,
        showLaunchSplash: Bool = true,
        appearance: AppAppearance = .system
    ) {
        self.dayCutoffMinutes = dayCutoffMinutes
        self.profileImagePath = profileImagePath
        self.heightCm = heightCm
        self.targetWeightKg = targetWeightKg
        self.motivation = motivation
        self.doctorName = doctorName
        self.nutritionistName = nutritionistName
        self.foodSeedVersion = foodSeedVersion
        self.showLaunchSplash = showLaunchSplash
        self.appearance = appearance
    }

    public static let defaultValue = AppSettings(dayCutoffMinutes: 4 * 60, showLaunchSplash: true)
}
