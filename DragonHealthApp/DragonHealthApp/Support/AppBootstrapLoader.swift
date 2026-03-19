import Foundation
import Core
import CoreDB

struct AppBootstrapSnapshot {
    let categories: [Core.Category]
    let units: [Core.FoodUnit]
    let mealSlots: [Core.MealSlot]
    let settings: Core.AppSettings
    let foodItems: [Core.FoodItem]
    let bodyMetrics: [Core.BodyMetricEntry]
    let careMeetings: [Core.CareMeeting]
    let documents: [Core.HealthDocument]
    let scoreProfiles: [UUID: Core.ScoreProfile]
    let compensationRules: [Core.CompensationRule]
    let foodImagePaths: [String]
}

struct AppBootstrapLoader {
    let db: SQLiteDatabase
    let resolveMealSlotTimings: ([Core.MealSlot], Core.AppSettings) -> [Core.MealSlotTiming]
    let normalizedCategoryName: (String) -> String
    let isLegacyCarbCategoryName: (String) -> Bool

    func load() async throws -> AppBootstrapSnapshot {
        var loadedCategories = try await db.fetchCategories()
        if loadedCategories.isEmpty {
            loadedCategories = AppDefaults.categories
            for category in loadedCategories {
                try await db.upsertCategory(category)
            }
        }
        if !loadedCategories.contains(where: { normalizedCategoryName($0.name) == "carb" }) {
            var renamedCategories = loadedCategories
            var didRename = false
            for index in renamedCategories.indices {
                if isLegacyCarbCategoryName(renamedCategories[index].name) {
                    renamedCategories[index].name = "Carb"
                    didRename = true
                }
            }
            if didRename {
                for category in renamedCategories {
                    try await db.upsertCategory(category)
                }
                loadedCategories = try await db.fetchCategories()
            }
        }

        var loadedMealSlots = try await db.fetchMealSlots()
        if loadedMealSlots.isEmpty {
            loadedMealSlots = AppDefaults.mealSlots
            for slot in loadedMealSlots {
                try await db.upsertMealSlot(slot)
            }
        }

        var loadedUnits = try await db.fetchUnits()
        if loadedUnits.isEmpty {
            loadedUnits = AppDefaults.units
            for unit in loadedUnits {
                try await db.upsertUnit(unit)
            }
            loadedUnits = try await db.fetchUnits()
        } else {
            let existingSymbols = Set(loadedUnits.map { $0.symbol.lowercased() })
            let missingUnits = AppDefaults.units.filter { !existingSymbols.contains($0.symbol.lowercased()) }
            if !missingUnits.isEmpty {
                for unit in missingUnits {
                    try await db.upsertUnit(unit)
                }
                loadedUnits = try await db.fetchUnits()
            }
        }

        var loadedSettings = try await db.fetchSettings()
        let resolvedTimings = resolveMealSlotTimings(loadedMealSlots, loadedSettings)
        if resolvedTimings != loadedSettings.mealSlotTimings {
            loadedSettings.mealSlotTimings = resolvedTimings
        }
        try await db.updateSettings(loadedSettings)

        var loadedFoodItems = try await db.fetchFoodItems()
        var didSeedFoodItems = false
        if loadedFoodItems.isEmpty {
            let defaults = AppDefaults.foodItems(categories: loadedCategories, units: loadedUnits)
            if !defaults.isEmpty {
                for item in defaults {
                    try await db.upsertFoodItem(item)
                }
                loadedFoodItems = try await db.fetchFoodItems()
                didSeedFoodItems = true
            }
        } else if loadedSettings.foodSeedVersion < AppDefaults.foodSeedVersion {
            let missing = AppDefaults.missingFoodItems(existing: loadedFoodItems, categories: loadedCategories, units: loadedUnits)
            if !missing.isEmpty {
                for item in missing {
                    try await db.upsertFoodItem(item)
                }
                loadedFoodItems = try await db.fetchFoodItems()
            }
            let enriched = AppDefaults.enrichFoodItems(existing: loadedFoodItems, categories: loadedCategories, units: loadedUnits)
            if !enriched.isEmpty {
                for item in enriched {
                    try await db.upsertFoodItem(item)
                }
                loadedFoodItems = try await db.fetchFoodItems()
            }
            didSeedFoodItems = true
        }
        if didSeedFoodItems, loadedSettings.foodSeedVersion < AppDefaults.foodSeedVersion {
            loadedSettings.foodSeedVersion = AppDefaults.foodSeedVersion
            try await db.updateSettings(loadedSettings)
        }

        let loadedMetrics = try await db.fetchBodyMetrics()
        let loadedMeetings = try await db.fetchCareMeetings()
        let loadedDocuments = try await db.fetchDocuments()
        let loadedScoreProfiles = try await db.fetchScoreProfiles()
        var loadedCompensationRules = try await db.fetchCompensationRules()
        if loadedCompensationRules.isEmpty {
            let defaults = Core.CompensationRule.defaultRules(for: loadedCategories)
            if !defaults.isEmpty {
                for rule in defaults {
                    try await db.upsertCompensationRule(rule)
                }
                loadedCompensationRules = try await db.fetchCompensationRules()
            }
        }

        let categories = loadedCategories.sorted(by: { $0.sortOrder < $1.sortOrder })
        let units = loadedUnits.sorted(by: { $0.sortOrder < $1.sortOrder })
        let mealSlots = loadedMealSlots.sorted(by: { $0.sortOrder < $1.sortOrder })
        let bodyMetrics = loadedMetrics.sorted(by: { $0.date > $1.date })
        let careMeetings = loadedMeetings.sorted(by: { $0.date > $1.date })
        let documents = loadedDocuments.sorted(by: { $0.createdAt > $1.createdAt })
        let categoryIDs = Set(categories.map(\.id))

        return AppBootstrapSnapshot(
            categories: categories,
            units: units,
            mealSlots: mealSlots,
            settings: loadedSettings,
            foodItems: loadedFoodItems,
            bodyMetrics: bodyMetrics,
            careMeetings: careMeetings,
            documents: documents,
            scoreProfiles: loadedScoreProfiles.filter { categoryIDs.contains($0.key) },
            compensationRules: loadedCompensationRules.filter {
                categoryIDs.contains($0.fromCategoryID) && categoryIDs.contains($0.toCategoryID)
            },
            foodImagePaths: loadedFoodItems.compactMap(\.imagePath)
        )
    }
}
