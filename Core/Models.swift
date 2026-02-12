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

public struct FoodUnit: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var symbol: String
    public var allowsDecimal: Bool
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        allowsDecimal: Bool = true,
        isEnabled: Bool = true,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.allowsDecimal = allowsDecimal
        self.isEnabled = isEnabled
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

public struct MealSlotTiming: Codable, Hashable, Sendable {
    public let slotID: UUID
    public var startMinutes: Int
    public var includeInAuto: Bool

    public init(slotID: UUID, startMinutes: Int, includeInAuto: Bool = true) {
        self.slotID = slotID
        self.startMinutes = startMinutes
        self.includeInAuto = includeInAuto
    }

    private enum CodingKeys: String, CodingKey {
        case slotID
        case startMinutes
        case includeInAuto
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slotID = try container.decode(UUID.self, forKey: .slotID)
        startMinutes = try container.decode(Int.self, forKey: .startMinutes)
        includeInAuto = try container.decodeIfPresent(Bool.self, forKey: .includeInAuto) ?? true
    }
}

public struct DailyLogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let mealSlotID: UUID
    public let categoryID: UUID
    public let portion: Portion
    public let amountValue: Double?
    public let amountUnitID: UUID?
    public let notes: String?
    public let foodItemID: UUID?
    public let compositeGroupID: UUID?
    public let compositeFoodID: UUID?
    public let compositeFoodName: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        mealSlotID: UUID,
        categoryID: UUID,
        portion: Portion,
        amountValue: Double? = nil,
        amountUnitID: UUID? = nil,
        notes: String? = nil,
        foodItemID: UUID? = nil,
        compositeGroupID: UUID? = nil,
        compositeFoodID: UUID? = nil,
        compositeFoodName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mealSlotID = mealSlotID
        self.categoryID = categoryID
        self.portion = portion
        self.amountValue = amountValue
        self.amountUnitID = amountUnitID
        self.notes = notes
        self.foodItemID = foodItemID
        self.compositeGroupID = compositeGroupID
        self.compositeFoodID = compositeFoodID
        self.compositeFoodName = compositeFoodName
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
    public let activeEnergyKcal: Double?

    public init(
        date: Date,
        weightKg: Double?,
        muscleMass: Double?,
        bodyFatPercent: Double?,
        waistCm: Double?,
        steps: Double? = nil,
        activeEnergyKcal: Double? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.muscleMass = muscleMass
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
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

public enum FoodImageSource: String, Hashable, Sendable {
    case unsplash
}

public enum FoodItemKind: String, Hashable, Sendable {
    case single
    case composite

    public var isComposite: Bool {
        self == .composite
    }
}

public struct FoodComponent: Codable, Hashable, Sendable {
    public var foodItemID: UUID
    public var portionMultiplier: Double

    public init(foodItemID: UUID, portionMultiplier: Double) {
        self.foodItemID = foodItemID
        self.portionMultiplier = Portion.roundToIncrement(max(0, portionMultiplier))
    }
}

public struct FoodItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var categoryID: UUID
    public var portionEquivalent: Double
    public var amountPerPortion: Double?
    public var unitID: UUID?
    public var notes: String?
    public var isFavorite: Bool
    public var imagePath: String?
    public var imageRemoteURL: String?
    public var imageSource: FoodImageSource?
    public var imageSourceID: String?
    public var imageAttributionName: String?
    public var imageAttributionURL: String?
    public var imageSourceURL: String?
    public var kind: FoodItemKind
    public var compositeComponents: [FoodComponent]

    public init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        portionEquivalent: Double,
        amountPerPortion: Double? = nil,
        unitID: UUID? = nil,
        notes: String? = nil,
        isFavorite: Bool = false,
        imagePath: String? = nil,
        imageRemoteURL: String? = nil,
        imageSource: FoodImageSource? = nil,
        imageSourceID: String? = nil,
        imageAttributionName: String? = nil,
        imageAttributionURL: String? = nil,
        imageSourceURL: String? = nil,
        kind: FoodItemKind = .single,
        compositeComponents: [FoodComponent] = []
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.portionEquivalent = portionEquivalent
        self.amountPerPortion = amountPerPortion
        self.unitID = unitID
        self.notes = notes
        self.isFavorite = isFavorite
        self.imagePath = imagePath
        self.imageRemoteURL = imageRemoteURL
        self.imageSource = imageSource
        self.imageSourceID = imageSourceID
        self.imageAttributionName = imageAttributionName
        self.imageAttributionURL = imageAttributionURL
        self.imageSourceURL = imageSourceURL
        self.kind = kind
        self.compositeComponents = compositeComponents
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
    public var targetWeightDate: Date?
    public var motivation: String?
    public var doctorName: String?
    public var nutritionistName: String?
    public var foodSeedVersion: Int
    public var showLaunchSplash: Bool
    public var appearance: AppAppearance
    public var mealSlotTimings: [MealSlotTiming]

    public init(
        dayCutoffMinutes: Int,
        profileImagePath: String? = nil,
        heightCm: Double? = nil,
        targetWeightKg: Double? = nil,
        targetWeightDate: Date? = nil,
        motivation: String? = nil,
        doctorName: String? = nil,
        nutritionistName: String? = nil,
        foodSeedVersion: Int = 0,
        showLaunchSplash: Bool = true,
        appearance: AppAppearance = .system,
        mealSlotTimings: [MealSlotTiming] = []
    ) {
        self.dayCutoffMinutes = dayCutoffMinutes
        self.profileImagePath = profileImagePath
        self.heightCm = heightCm
        self.targetWeightKg = targetWeightKg
        self.targetWeightDate = targetWeightDate
        self.motivation = motivation
        self.doctorName = doctorName
        self.nutritionistName = nutritionistName
        self.foodSeedVersion = foodSeedVersion
        self.showLaunchSplash = showLaunchSplash
        self.appearance = appearance
        self.mealSlotTimings = mealSlotTimings
    }

    public static let defaultValue = AppSettings(dayCutoffMinutes: 4 * 60, showLaunchSplash: true)
}
