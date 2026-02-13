import Foundation
import SQLite3
import Core

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteDatabaseError: Error, CustomStringConvertible, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case executionFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message),
             .prepareFailed(let message),
             .stepFailed(let message),
             .executionFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}

public actor SQLiteDatabase: DBGateway {
    nonisolated(unsafe) private let db: OpaquePointer
    private let calendar: Calendar

    public init(path: String, calendar: Calendar = .autoupdatingCurrent) throws {
        self.calendar = calendar
        var handle: OpaquePointer?
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw SQLiteDatabaseError.openFailed("Unable to open database at \(path)")
        }
        guard let opened = handle else {
            throw SQLiteDatabaseError.openFailed("Database handle missing for \(path)")
        }
        self.db = opened
        try Self.migrate(db: opened)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    public func fetchCategories() async throws -> [Core.Category] {
        let sql = """
        SELECT id, name, unit_name, is_enabled, target_type, target_min, target_max, sort_order
        FROM categories
        ORDER BY sort_order ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var categories: [Core.Category] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let name = readText(statement, index: 1)
            let unitName = readText(statement, index: 2)
            let isEnabled = readBool(statement, index: 3)
            let targetType = readText(statement, index: 4)
            let targetMin = readOptionalDouble(statement, index: 5)
            let targetMax = readOptionalDouble(statement, index: 6)
            let targetRule = decodeTargetRule(type: targetType, min: targetMin, max: targetMax)
            let sortOrder = Int(sqlite3_column_int(statement, 7))
            categories.append(
                Core.Category(
                    id: id,
                    name: name,
                    unitName: unitName,
                    isEnabled: isEnabled,
                    targetRule: targetRule,
                    sortOrder: sortOrder
                )
            )
        }
        return categories
    }

    public func upsertCategory(_ category: Core.Category) async throws {
        let sql = """
        INSERT INTO categories (id, name, unit_name, is_enabled, target_type, target_min, target_max, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            unit_name = excluded.unit_name,
            is_enabled = excluded.is_enabled,
            target_type = excluded.target_type,
            target_min = excluded.target_min,
            target_max = excluded.target_max,
            sort_order = excluded.sort_order;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let target = encodeTargetRule(category.targetRule)
        bindUUID(statement, index: 1, value: category.id)
        bindText(statement, index: 2, value: category.name)
        bindText(statement, index: 3, value: category.unitName)
        bindBool(statement, index: 4, value: category.isEnabled)
        bindText(statement, index: 5, value: target.type)
        bindOptionalDouble(statement, index: 6, value: target.min)
        bindOptionalDouble(statement, index: 7, value: target.max)
        bindInt(statement, index: 8, value: category.sortOrder)
        try step(statement)
    }

    public func deleteCategory(id: UUID) async throws {
        try execute("BEGIN TRANSACTION;")
        do {
            let dailyEntryCount = try scalarCount(
                "SELECT COUNT(*) FROM daily_entries WHERE category_id = ?;"
            ) { statement in
                self.bindUUID(statement, index: 1, value: id)
            }
            guard dailyEntryCount == 0 else {
                throw SQLiteDatabaseError.executionFailed(
                    "Category can't be deleted because it has logged entries. Disable it instead."
                )
            }

            let foodItemCount = try scalarCount(
                "SELECT COUNT(*) FROM food_items WHERE category_id = ?;"
            ) { statement in
                self.bindUUID(statement, index: 1, value: id)
            }
            guard foodItemCount == 0 else {
                throw SQLiteDatabaseError.executionFailed(
                    "Category can't be deleted because food library items still use it."
                )
            }

            let deleteProfileSQL = "DELETE FROM score_profiles WHERE category_id = ?;"
            let deleteProfileStatement = try prepare(deleteProfileSQL)
            defer { sqlite3_finalize(deleteProfileStatement) }
            bindUUID(deleteProfileStatement, index: 1, value: id)
            try step(deleteProfileStatement)

            let deleteCompensationSQL = """
            DELETE FROM compensation_rules
            WHERE from_category_id = ? OR to_category_id = ?;
            """
            let deleteCompensationStatement = try prepare(deleteCompensationSQL)
            defer { sqlite3_finalize(deleteCompensationStatement) }
            bindUUID(deleteCompensationStatement, index: 1, value: id)
            bindUUID(deleteCompensationStatement, index: 2, value: id)
            try step(deleteCompensationStatement)

            let deleteCategorySQL = "DELETE FROM categories WHERE id = ?;"
            let deleteCategoryStatement = try prepare(deleteCategorySQL)
            defer { sqlite3_finalize(deleteCategoryStatement) }
            bindUUID(deleteCategoryStatement, index: 1, value: id)
            try step(deleteCategoryStatement)

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func fetchScoreProfiles() async throws -> [UUID: Core.ScoreProfile] {
        let sql = """
        SELECT category_id, weight, under_penalty, over_penalty, under_soft_limit, over_soft_limit, curve, cap_over
        FROM score_profiles;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var profiles: [UUID: Core.ScoreProfile] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let categoryID = readUUID(statement, index: 0)
            let weight = sqlite3_column_double(statement, 1)
            let underPenalty = sqlite3_column_double(statement, 2)
            let overPenalty = sqlite3_column_double(statement, 3)
            let underSoftLimit = sqlite3_column_double(statement, 4)
            let overSoftLimit = sqlite3_column_double(statement, 5)
            let curveRaw = readText(statement, index: 6)
            let capOver = readBool(statement, index: 7)
            let curve = Core.ScoreCurve(rawValue: curveRaw) ?? .linear
            profiles[categoryID] = Core.ScoreProfile(
                weight: weight,
                underPenaltyPerUnit: underPenalty,
                overPenaltyPerUnit: overPenalty,
                underSoftLimit: underSoftLimit,
                overSoftLimit: overSoftLimit,
                curve: curve,
                capOverAtTarget: capOver
            )
        }
        return profiles
    }

    public func upsertScoreProfile(categoryID: UUID, profile: Core.ScoreProfile) async throws {
        let sql = """
        INSERT INTO score_profiles (
            category_id, weight, under_penalty, over_penalty, under_soft_limit, over_soft_limit, curve, cap_over
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(category_id) DO UPDATE SET
            weight = excluded.weight,
            under_penalty = excluded.under_penalty,
            over_penalty = excluded.over_penalty,
            under_soft_limit = excluded.under_soft_limit,
            over_soft_limit = excluded.over_soft_limit,
            curve = excluded.curve,
            cap_over = excluded.cap_over;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: categoryID)
        bindDouble(statement, index: 2, value: profile.weight)
        bindDouble(statement, index: 3, value: profile.underPenaltyPerUnit)
        bindDouble(statement, index: 4, value: profile.overPenaltyPerUnit)
        bindDouble(statement, index: 5, value: profile.underSoftLimit)
        bindDouble(statement, index: 6, value: profile.overSoftLimit)
        bindText(statement, index: 7, value: profile.curve.rawValue)
        bindBool(statement, index: 8, value: profile.capOverAtTarget)
        try step(statement)
    }

    public func deleteScoreProfile(categoryID: UUID) async throws {
        let sql = "DELETE FROM score_profiles WHERE category_id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: categoryID)
        try step(statement)
    }

    public func fetchCompensationRules() async throws -> [Core.CompensationRule] {
        let sql = """
        SELECT from_category_id, to_category_id, ratio, max_offset
        FROM compensation_rules;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var rules: [Core.CompensationRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let fromID = readUUID(statement, index: 0)
            let toID = readUUID(statement, index: 1)
            let ratio = sqlite3_column_double(statement, 2)
            let maxOffset = sqlite3_column_double(statement, 3)
            rules.append(
                Core.CompensationRule(
                    fromCategoryID: fromID,
                    toCategoryID: toID,
                    ratio: ratio,
                    maxOffset: maxOffset
                )
            )
        }
        return rules
    }

    public func upsertCompensationRule(_ rule: Core.CompensationRule) async throws {
        let sql = """
        INSERT INTO compensation_rules (from_category_id, to_category_id, ratio, max_offset)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(from_category_id, to_category_id) DO UPDATE SET
            ratio = excluded.ratio,
            max_offset = excluded.max_offset;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: rule.fromCategoryID)
        bindUUID(statement, index: 2, value: rule.toCategoryID)
        bindDouble(statement, index: 3, value: rule.ratio)
        bindDouble(statement, index: 4, value: rule.maxOffset)
        try step(statement)
    }

    public func deleteCompensationRule(_ rule: Core.CompensationRule) async throws {
        let sql = """
        DELETE FROM compensation_rules
        WHERE from_category_id = ? AND to_category_id = ?;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: rule.fromCategoryID)
        bindUUID(statement, index: 2, value: rule.toCategoryID)
        try step(statement)
    }

    public func fetchUnits() async throws -> [Core.FoodUnit] {
        let sql = """
        SELECT id, name, symbol, allows_decimal, is_enabled, sort_order
        FROM units
        ORDER BY sort_order ASC, name ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var units: [Core.FoodUnit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let name = readText(statement, index: 1)
            let symbol = readText(statement, index: 2)
            let allowsDecimal = readBool(statement, index: 3)
            let isEnabled = readBool(statement, index: 4)
            let sortOrder = Int(sqlite3_column_int(statement, 5))
            units.append(
                Core.FoodUnit(
                    id: id,
                    name: name,
                    symbol: symbol,
                    allowsDecimal: allowsDecimal,
                    isEnabled: isEnabled,
                    sortOrder: sortOrder
                )
            )
        }
        return units
    }

    public func upsertUnit(_ unit: Core.FoodUnit) async throws {
        let sql = """
        INSERT INTO units (id, name, symbol, allows_decimal, is_enabled, sort_order)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            symbol = excluded.symbol,
            allows_decimal = excluded.allows_decimal,
            is_enabled = excluded.is_enabled,
            sort_order = excluded.sort_order;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: unit.id)
        bindText(statement, index: 2, value: unit.name)
        bindText(statement, index: 3, value: unit.symbol)
        bindBool(statement, index: 4, value: unit.allowsDecimal)
        bindBool(statement, index: 5, value: unit.isEnabled)
        bindInt(statement, index: 6, value: unit.sortOrder)
        try step(statement)
    }

    public func fetchMealSlots() async throws -> [Core.MealSlot] {
        let sql = """
        SELECT id, name, sort_order
        FROM meal_slots
        ORDER BY sort_order ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var slots: [Core.MealSlot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let name = readText(statement, index: 1)
            let sortOrder = Int(sqlite3_column_int(statement, 2))
            slots.append(Core.MealSlot(id: id, name: name, sortOrder: sortOrder))
        }
        return slots
    }

    public func upsertMealSlot(_ mealSlot: Core.MealSlot) async throws {
        let sql = """
        INSERT INTO meal_slots (id, name, sort_order)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            sort_order = excluded.sort_order;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: mealSlot.id)
        bindText(statement, index: 2, value: mealSlot.name)
        bindInt(statement, index: 3, value: mealSlot.sortOrder)
        try step(statement)
    }

    public func deleteMealSlot(id: UUID) async throws {
        let slotCount = try scalarCount("SELECT COUNT(*) FROM meal_slots;")
        guard slotCount > 1 else {
            throw SQLiteDatabaseError.executionFailed("At least one meal slot is required.")
        }

        let dailyEntryCount = try scalarCount(
            "SELECT COUNT(*) FROM daily_entries WHERE meal_slot_id = ?;"
        ) { statement in
            self.bindUUID(statement, index: 1, value: id)
        }
        guard dailyEntryCount == 0 else {
            throw SQLiteDatabaseError.executionFailed(
                "Meal slot can't be deleted because it has logged entries."
            )
        }

        let sql = "DELETE FROM meal_slots WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: id)
        try step(statement)
    }

    public func fetchSettings() async throws -> Core.AppSettings {
        let sql = """
        SELECT day_cutoff_minutes,
               profile_image_path,
               height_cm,
               target_weight_kg,
               target_weight_date,
               motivation,
               doctor_name,
               nutritionist_name,
               food_seed_version,
               show_launch_splash,
               appearance_mode,
               meal_timing_json
        FROM app_settings
        WHERE id = 1;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW {
            let minutes = Int(sqlite3_column_int(statement, 0))
            let appearanceRaw = readOptionalText(statement, index: 10)
            let appearance = Core.AppAppearance(rawValue: appearanceRaw ?? "") ?? .system
            let targetWeightDate = readOptionalDouble(statement, index: 4).map {
                Date(timeIntervalSince1970: $0)
            }
            let mealTimingJSON = readOptionalText(statement, index: 11)
            let mealSlotTimings = decodeMealSlotTimings(from: mealTimingJSON)
            return Core.AppSettings(
                dayCutoffMinutes: minutes,
                profileImagePath: readOptionalText(statement, index: 1),
                heightCm: readOptionalDouble(statement, index: 2),
                targetWeightKg: readOptionalDouble(statement, index: 3),
                targetWeightDate: targetWeightDate,
                motivation: readOptionalText(statement, index: 5),
                doctorName: readOptionalText(statement, index: 6),
                nutritionistName: readOptionalText(statement, index: 7),
                foodSeedVersion: Int(sqlite3_column_int(statement, 8)),
                showLaunchSplash: sqlite3_column_int(statement, 9) != 0,
                appearance: appearance,
                mealSlotTimings: mealSlotTimings
            )
        }
        return Core.AppSettings.defaultValue
    }

    public func updateSettings(_ settings: Core.AppSettings) async throws {
        let sql = """
        INSERT INTO app_settings (
            id,
            day_cutoff_minutes,
            profile_image_path,
            height_cm,
            target_weight_kg,
            target_weight_date,
            motivation,
            doctor_name,
            nutritionist_name,
            food_seed_version,
            show_launch_splash,
            appearance_mode,
            meal_timing_json
        )
        VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            day_cutoff_minutes = excluded.day_cutoff_minutes,
            profile_image_path = excluded.profile_image_path,
            height_cm = excluded.height_cm,
            target_weight_kg = excluded.target_weight_kg,
            target_weight_date = excluded.target_weight_date,
            motivation = excluded.motivation,
            doctor_name = excluded.doctor_name,
            nutritionist_name = excluded.nutritionist_name,
            food_seed_version = excluded.food_seed_version,
            show_launch_splash = excluded.show_launch_splash,
            appearance_mode = excluded.appearance_mode,
            meal_timing_json = excluded.meal_timing_json;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindInt(statement, index: 1, value: settings.dayCutoffMinutes)
        bindOptionalText(statement, index: 2, value: settings.profileImagePath)
        bindOptionalDouble(statement, index: 3, value: settings.heightCm)
        bindOptionalDouble(statement, index: 4, value: settings.targetWeightKg)
        bindOptionalDouble(statement, index: 5, value: settings.targetWeightDate?.timeIntervalSince1970)
        bindOptionalText(statement, index: 6, value: settings.motivation)
        bindOptionalText(statement, index: 7, value: settings.doctorName)
        bindOptionalText(statement, index: 8, value: settings.nutritionistName)
        bindInt(statement, index: 9, value: settings.foodSeedVersion)
        bindInt(statement, index: 10, value: settings.showLaunchSplash ? 1 : 0)
        bindText(statement, index: 11, value: settings.appearance.rawValue)
        bindText(statement, index: 12, value: encodeMealSlotTimings(settings.mealSlotTimings))
        try step(statement)
    }

    public func fetchFoodItems() async throws -> [Core.FoodItem] {
        let sql = """
        SELECT id, name, category_id, portion, amount_per_portion, unit_id, notes, is_favorite, image_path,
               image_remote_url, image_source, image_source_id, image_attribution_name, image_attribution_url, image_source_url,
               kind, composite_components_json
        FROM food_items
        ORDER BY is_favorite DESC, name ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var items: [Core.FoodItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let name = readText(statement, index: 1)
            let categoryID = readUUID(statement, index: 2)
            let portion = readDouble(statement, index: 3)
            let amountPerPortion = readOptionalDouble(statement, index: 4)
            let unitID = readOptionalText(statement, index: 5).flatMap(UUID.init(uuidString:))
            let notes = readOptionalText(statement, index: 6)
            let isFavorite = readBool(statement, index: 7)
            let imagePath = readOptionalText(statement, index: 8)
            let imageRemoteURL = readOptionalText(statement, index: 9)
            let imageSource = readOptionalText(statement, index: 10).flatMap(Core.FoodImageSource.init(rawValue:))
            let imageSourceID = readOptionalText(statement, index: 11)
            let imageAttributionName = readOptionalText(statement, index: 12)
            let imageAttributionURL = readOptionalText(statement, index: 13)
            let imageSourceURL = readOptionalText(statement, index: 14)
            let kindRaw = readOptionalText(statement, index: 15) ?? Core.FoodItemKind.single.rawValue
            let kind = Core.FoodItemKind(rawValue: kindRaw) ?? .single
            let components = decodeCompositeComponents(from: readOptionalText(statement, index: 16))
            items.append(
                Core.FoodItem(
                    id: id,
                    name: name,
                    categoryID: categoryID,
                    portionEquivalent: portion,
                    amountPerPortion: amountPerPortion,
                    unitID: unitID,
                    notes: notes,
                    isFavorite: isFavorite,
                    imagePath: imagePath,
                    imageRemoteURL: imageRemoteURL,
                    imageSource: imageSource,
                    imageSourceID: imageSourceID,
                    imageAttributionName: imageAttributionName,
                    imageAttributionURL: imageAttributionURL,
                    imageSourceURL: imageSourceURL,
                    kind: kind,
                    compositeComponents: components
                )
            )
        }
        return items
    }

    public func upsertFoodItem(_ item: Core.FoodItem) async throws {
        let sql = """
        INSERT INTO food_items (id, name, category_id, portion, amount_per_portion, unit_id, notes, is_favorite, image_path,
                                image_remote_url, image_source, image_source_id, image_attribution_name, image_attribution_url, image_source_url,
                                kind, composite_components_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            category_id = excluded.category_id,
            portion = excluded.portion,
            amount_per_portion = excluded.amount_per_portion,
            unit_id = excluded.unit_id,
            notes = excluded.notes,
            is_favorite = excluded.is_favorite,
            image_path = excluded.image_path,
            image_remote_url = excluded.image_remote_url,
            image_source = excluded.image_source,
            image_source_id = excluded.image_source_id,
            image_attribution_name = excluded.image_attribution_name,
            image_attribution_url = excluded.image_attribution_url,
            image_source_url = excluded.image_source_url,
            kind = excluded.kind,
            composite_components_json = excluded.composite_components_json;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: item.id)
        bindText(statement, index: 2, value: item.name)
        bindUUID(statement, index: 3, value: item.categoryID)
        bindDouble(statement, index: 4, value: item.portionEquivalent)
        bindOptionalDouble(statement, index: 5, value: item.amountPerPortion)
        bindOptionalText(statement, index: 6, value: item.unitID?.uuidString)
        bindOptionalText(statement, index: 7, value: item.notes)
        bindBool(statement, index: 8, value: item.isFavorite)
        bindOptionalText(statement, index: 9, value: item.imagePath)
        bindOptionalText(statement, index: 10, value: item.imageRemoteURL)
        bindOptionalText(statement, index: 11, value: item.imageSource?.rawValue)
        bindOptionalText(statement, index: 12, value: item.imageSourceID)
        bindOptionalText(statement, index: 13, value: item.imageAttributionName)
        bindOptionalText(statement, index: 14, value: item.imageAttributionURL)
        bindOptionalText(statement, index: 15, value: item.imageSourceURL)
        bindText(statement, index: 16, value: item.kind.rawValue)
        bindOptionalText(statement, index: 17, value: encodeCompositeComponents(item.compositeComponents))
        try step(statement)
    }

    public func deleteFoodItem(id: UUID) async throws {
        let sql = "DELETE FROM food_items WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: id)
        try step(statement)
    }

    public func saveDailyLog(_ log: Core.DailyLog) async throws {
        let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: log.date, calendar: calendar)
        var seenEntryIDs = Set<UUID>()
        let uniqueEntries = log.entries.filter { entry in
            if seenEntryIDs.contains(entry.id) { return false }
            seenEntryIDs.insert(entry.id)
            return true
        }
        try execute("BEGIN TRANSACTION;")
        do {
            let deleteSQL = "DELETE FROM daily_entries WHERE day = ?;"
            let deleteStatement = try prepare(deleteSQL)
            bindText(deleteStatement, index: 1, value: dayKey)
            try step(deleteStatement)
            sqlite3_finalize(deleteStatement)

            if !uniqueEntries.isEmpty {
                let placeholders = Array(repeating: "?", count: uniqueEntries.count).joined(separator: ", ")
                let deleteByIDSQL = "DELETE FROM daily_entries WHERE id IN (\(placeholders));"
                let deleteByIDStatement = try prepare(deleteByIDSQL)
                for (index, entry) in uniqueEntries.enumerated() {
                    bindUUID(deleteByIDStatement, index: Int32(index + 1), value: entry.id)
                }
                try step(deleteByIDStatement)
                sqlite3_finalize(deleteByIDStatement)
            }

            let insertSQL = """
            INSERT INTO daily_entries (
                id, day, meal_slot_id, category_id, portion, amount_value, amount_unit_id, food_item_id, notes,
                composite_group_id, composite_food_id, composite_food_name
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            for entry in uniqueEntries {
                let statement = try prepare(insertSQL)
                bindUUID(statement, index: 1, value: entry.id)
                bindText(statement, index: 2, value: dayKey)
                bindUUID(statement, index: 3, value: entry.mealSlotID)
                bindUUID(statement, index: 4, value: entry.categoryID)
                bindDouble(statement, index: 5, value: entry.portion.value)
                bindOptionalDouble(statement, index: 6, value: entry.amountValue)
                bindOptionalText(statement, index: 7, value: entry.amountUnitID?.uuidString)
                bindOptionalText(statement, index: 8, value: entry.foodItemID?.uuidString)
                bindOptionalText(statement, index: 9, value: entry.notes)
                bindOptionalText(statement, index: 10, value: entry.compositeGroupID?.uuidString)
                bindOptionalText(statement, index: 11, value: entry.compositeFoodID?.uuidString)
                bindOptionalText(statement, index: 12, value: entry.compositeFoodName)
                try step(statement)
                sqlite3_finalize(statement)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func fetchDailyLog(for date: Date) async throws -> Core.DailyLog? {
        let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: date, calendar: calendar)
        let sql = """
        SELECT id, meal_slot_id, category_id, portion, amount_value, amount_unit_id, food_item_id, notes,
               composite_group_id, composite_food_id, composite_food_name
        FROM daily_entries
        WHERE day = ?
        ORDER BY rowid ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: dayKey)
        var entries: [Core.DailyLogEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let mealSlotID = readUUID(statement, index: 1)
            let categoryID = readUUID(statement, index: 2)
            let portion = readDouble(statement, index: 3)
            let amountValue = readOptionalDouble(statement, index: 4)
            let amountUnitID = readOptionalText(statement, index: 5).flatMap(UUID.init(uuidString:))
            let foodItemID = readOptionalText(statement, index: 6).flatMap(UUID.init(uuidString:))
            let notes = readOptionalText(statement, index: 7)
            let compositeGroupID = readOptionalText(statement, index: 8).flatMap(UUID.init(uuidString:))
            let compositeFoodID = readOptionalText(statement, index: 9).flatMap(UUID.init(uuidString:))
            let compositeFoodName = readOptionalText(statement, index: 10)
            entries.append(
                Core.DailyLogEntry(
                    id: id,
                    date: date,
                    mealSlotID: mealSlotID,
                    categoryID: categoryID,
                    portion: Portion(portion),
                    amountValue: amountValue,
                    amountUnitID: amountUnitID,
                    notes: notes,
                    foodItemID: foodItemID,
                    compositeGroupID: compositeGroupID,
                    compositeFoodID: compositeFoodID,
                    compositeFoodName: compositeFoodName
                )
            )
        }
        guard !entries.isEmpty else { return nil }
        return Core.DailyLog(date: date, entries: entries)
    }

    public func fetchDailyTotalsByDay(start: Date, end: Date) async throws -> [String: [UUID: Double]] {
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        let dayBoundary = DayBoundary(cutoffMinutes: 0)
        let startKey = dayBoundary.dayKey(for: rangeStart, calendar: calendar)
        let endKey = dayBoundary.dayKey(for: rangeEnd, calendar: calendar)
        let sql = """
        SELECT day, category_id, SUM(portion) as total
        FROM daily_entries
        WHERE day >= ? AND day <= ?
        GROUP BY day, category_id
        ORDER BY day ASC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: startKey)
        bindText(statement, index: 2, value: endKey)
        var totalsByDay: [String: [UUID: Double]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let dayString = readText(statement, index: 0)
            let categoryID = readUUID(statement, index: 1)
            let total = readDouble(statement, index: 2)
            var totals = totalsByDay[dayString] ?? [:]
            totals[categoryID] = total
            totalsByDay[dayString] = totals
        }
        return totalsByDay
    }

    public func fetchBodyMetrics() async throws -> [Core.BodyMetricEntry] {
        let sql = """
        SELECT day, weight_kg, muscle_mass, body_fat_percent, waist_cm, steps, active_energy_kcal
        FROM body_metrics
        ORDER BY day DESC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var entries: [Core.BodyMetricEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let dayString = readText(statement, index: 0)
            guard let day = DayKeyParser.date(from: dayString, timeZone: calendar.timeZone) else { continue }
            entries.append(
                Core.BodyMetricEntry(
                    date: day,
                    weightKg: readOptionalDouble(statement, index: 1),
                    muscleMass: readOptionalDouble(statement, index: 2),
                    bodyFatPercent: readOptionalDouble(statement, index: 3),
                    waistCm: readOptionalDouble(statement, index: 4),
                    steps: readOptionalDouble(statement, index: 5),
                    activeEnergyKcal: readOptionalDouble(statement, index: 6)
                )
            )
        }
        return entries
    }

    public func upsertBodyMetric(_ entry: Core.BodyMetricEntry) async throws {
        let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: entry.date, calendar: calendar)
        let sql = """
        INSERT INTO body_metrics (day, weight_kg, muscle_mass, body_fat_percent, waist_cm, steps, active_energy_kcal)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
            weight_kg = excluded.weight_kg,
            muscle_mass = excluded.muscle_mass,
            body_fat_percent = excluded.body_fat_percent,
            waist_cm = excluded.waist_cm,
            steps = excluded.steps,
            active_energy_kcal = excluded.active_energy_kcal;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: dayKey)
        bindOptionalDouble(statement, index: 2, value: entry.weightKg)
        bindOptionalDouble(statement, index: 3, value: entry.muscleMass)
        bindOptionalDouble(statement, index: 4, value: entry.bodyFatPercent)
        bindOptionalDouble(statement, index: 5, value: entry.waistCm)
        bindOptionalDouble(statement, index: 6, value: entry.steps)
        bindOptionalDouble(statement, index: 7, value: entry.activeEnergyKcal)
        try step(statement)
    }

    public func fetchCareMeetings() async throws -> [Core.CareMeeting] {
        let sql = """
        SELECT id, day, provider_type, notes
        FROM care_meetings
        ORDER BY day DESC, rowid DESC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var meetings: [Core.CareMeeting] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let dayString = readText(statement, index: 1)
            let providerRaw = readText(statement, index: 2)
            let notes = readText(statement, index: 3)
            guard let date = DayKeyParser.date(from: dayString, timeZone: calendar.timeZone) else { continue }
            let providerType = Core.CareProviderType(rawValue: providerRaw) ?? .doctor
            meetings.append(
                Core.CareMeeting(
                    id: id,
                    date: date,
                    providerType: providerType,
                    notes: notes
                )
            )
        }
        return meetings
    }

    public func upsertCareMeeting(_ meeting: Core.CareMeeting) async throws {
        let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: meeting.date, calendar: calendar)
        let sql = """
        INSERT INTO care_meetings (id, day, provider_type, notes)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            day = excluded.day,
            provider_type = excluded.provider_type,
            notes = excluded.notes;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: meeting.id)
        bindText(statement, index: 2, value: dayKey)
        bindText(statement, index: 3, value: meeting.providerType.rawValue)
        bindText(statement, index: 4, value: meeting.notes)
        try step(statement)
    }

    public func deleteCareMeeting(id: UUID) async throws {
        let sql = "DELETE FROM care_meetings WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: id)
        try step(statement)
    }

    public func fetchDocuments() async throws -> [Core.HealthDocument] {
        let sql = """
        SELECT id, title, filename, file_type, created_at
        FROM documents
        ORDER BY created_at DESC;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var documents: [Core.HealthDocument] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = readUUID(statement, index: 0)
            let title = readText(statement, index: 1)
            let fileName = readText(statement, index: 2)
            let typeRaw = readText(statement, index: 3)
            let createdAt = readDouble(statement, index: 4)
            let fileType = Core.DocumentType(rawValue: typeRaw) ?? .image
            documents.append(
                Core.HealthDocument(
                    id: id,
                    title: title,
                    fileName: fileName,
                    fileType: fileType,
                    createdAt: Date(timeIntervalSince1970: createdAt)
                )
            )
        }
        return documents
    }

    public func upsertDocument(_ document: Core.HealthDocument) async throws {
        let sql = """
        INSERT INTO documents (id, title, filename, file_type, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            filename = excluded.filename,
            file_type = excluded.file_type,
            created_at = excluded.created_at;
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: document.id)
        bindText(statement, index: 2, value: document.title)
        bindText(statement, index: 3, value: document.fileName)
        bindText(statement, index: 4, value: document.fileType.rawValue)
        bindDouble(statement, index: 5, value: document.createdAt.timeIntervalSince1970)
        try step(statement)
    }

    public func deleteDocument(id: UUID) async throws {
        let sql = "DELETE FROM documents WHERE id = ?;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindUUID(statement, index: 1, value: id)
        try step(statement)
    }

    // MARK: - Migration

    private static func migrate(db: OpaquePointer) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            unit_name TEXT NOT NULL,
            is_enabled INTEGER NOT NULL,
            target_type TEXT NOT NULL,
            target_min REAL,
            target_max REAL,
            sort_order INTEGER NOT NULL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS units (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            allows_decimal INTEGER NOT NULL,
            is_enabled INTEGER NOT NULL,
            sort_order INTEGER NOT NULL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS meal_slots (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS daily_entries (
            id TEXT PRIMARY KEY,
            day TEXT NOT NULL,
            meal_slot_id TEXT NOT NULL,
            category_id TEXT NOT NULL,
            portion REAL NOT NULL,
            amount_value REAL,
            amount_unit_id TEXT,
            notes TEXT,
            food_item_id TEXT,
            composite_group_id TEXT,
            composite_food_id TEXT,
            composite_food_name TEXT
        );
        """, db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN food_item_id TEXT;", db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN amount_value REAL;", db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN amount_unit_id TEXT;", db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN composite_group_id TEXT;", db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN composite_food_id TEXT;", db: db)
        try? execute("ALTER TABLE daily_entries ADD COLUMN composite_food_name TEXT;", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_daily_entries_day ON daily_entries(day);", db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS food_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category_id TEXT NOT NULL,
            portion REAL NOT NULL,
            amount_per_portion REAL,
            unit_id TEXT,
            notes TEXT,
            is_favorite INTEGER NOT NULL,
            image_path TEXT,
            image_remote_url TEXT,
            image_source TEXT,
            image_source_id TEXT,
            image_attribution_name TEXT,
            image_attribution_url TEXT,
            image_source_url TEXT,
            kind TEXT NOT NULL DEFAULT 'single',
            composite_components_json TEXT
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS body_metrics (
            day TEXT PRIMARY KEY,
            weight_kg REAL,
            muscle_mass REAL,
            body_fat_percent REAL,
            waist_cm REAL,
            steps REAL,
            active_energy_kcal REAL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS care_meetings (
            id TEXT PRIMARY KEY,
            day TEXT NOT NULL,
            provider_type TEXT NOT NULL,
            notes TEXT NOT NULL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS app_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            day_cutoff_minutes INTEGER NOT NULL,
            profile_image_path TEXT,
            height_cm REAL,
            target_weight_kg REAL,
            target_weight_date REAL,
            motivation TEXT,
            doctor_name TEXT,
            nutritionist_name TEXT,
            food_seed_version INTEGER NOT NULL DEFAULT 0,
            show_launch_splash INTEGER NOT NULL DEFAULT 1,
            appearance_mode TEXT NOT NULL DEFAULT 'system',
            meal_timing_json TEXT NOT NULL DEFAULT '[]'
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            filename TEXT NOT NULL,
            file_type TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """, db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at);", db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS score_profiles (
            category_id TEXT PRIMARY KEY,
            weight REAL NOT NULL,
            under_penalty REAL NOT NULL,
            over_penalty REAL NOT NULL,
            under_soft_limit REAL NOT NULL,
            over_soft_limit REAL NOT NULL,
            curve TEXT NOT NULL,
            cap_over INTEGER NOT NULL
        );
        """, db: db)

        try execute("""
        CREATE TABLE IF NOT EXISTS compensation_rules (
            from_category_id TEXT NOT NULL,
            to_category_id TEXT NOT NULL,
            ratio REAL NOT NULL,
            max_offset REAL NOT NULL,
            PRIMARY KEY (from_category_id, to_category_id)
        );
        """, db: db)

        try ensureColumns(
            table: "categories",
            definitions: [
                "name": "TEXT NOT NULL DEFAULT ''",
                "unit_name": "TEXT NOT NULL DEFAULT ''",
                "is_enabled": "INTEGER NOT NULL DEFAULT 1",
                "target_type": "TEXT NOT NULL DEFAULT 'exact'",
                "target_min": "REAL",
                "target_max": "REAL",
                "sort_order": "INTEGER NOT NULL DEFAULT 0"
            ],
            db: db
        )

        try ensureColumns(
            table: "meal_slots",
            definitions: [
                "name": "TEXT NOT NULL DEFAULT ''",
                "sort_order": "INTEGER NOT NULL DEFAULT 0"
            ],
            db: db
        )

        try ensureColumns(
            table: "units",
            definitions: [
                "name": "TEXT NOT NULL DEFAULT ''",
                "symbol": "TEXT NOT NULL DEFAULT ''",
                "allows_decimal": "INTEGER NOT NULL DEFAULT 1",
                "is_enabled": "INTEGER NOT NULL DEFAULT 1",
                "sort_order": "INTEGER NOT NULL DEFAULT 0"
            ],
            db: db
        )

        try ensureColumns(
            table: "daily_entries",
            definitions: [
                "day": "TEXT NOT NULL DEFAULT ''",
                "meal_slot_id": "TEXT NOT NULL DEFAULT ''",
                "category_id": "TEXT NOT NULL DEFAULT ''",
                "portion": "REAL NOT NULL DEFAULT 0",
                "amount_value": "REAL",
                "amount_unit_id": "TEXT",
                "notes": "TEXT",
                "food_item_id": "TEXT",
                "composite_group_id": "TEXT",
                "composite_food_id": "TEXT",
                "composite_food_name": "TEXT"
            ],
            db: db
        )

        try ensureColumns(
            table: "food_items",
            definitions: [
                "name": "TEXT NOT NULL DEFAULT ''",
                "category_id": "TEXT NOT NULL DEFAULT ''",
                "portion": "REAL NOT NULL DEFAULT 1",
                "amount_per_portion": "REAL",
                "unit_id": "TEXT",
                "notes": "TEXT",
                "is_favorite": "INTEGER NOT NULL DEFAULT 0",
                "image_path": "TEXT",
                "image_remote_url": "TEXT",
                "image_source": "TEXT",
                "image_source_id": "TEXT",
                "image_attribution_name": "TEXT",
                "image_attribution_url": "TEXT",
                "image_source_url": "TEXT",
                "kind": "TEXT NOT NULL DEFAULT 'single'",
                "composite_components_json": "TEXT"
            ],
            db: db
        )

        try ensureColumns(
            table: "body_metrics",
            definitions: [
                "weight_kg": "REAL",
                "muscle_mass": "REAL",
                "body_fat_percent": "REAL",
                "waist_cm": "REAL",
                "steps": "REAL",
                "active_energy_kcal": "REAL"
            ],
            db: db
        )

        try ensureColumns(
            table: "app_settings",
            definitions: [
                "day_cutoff_minutes": "INTEGER NOT NULL DEFAULT 240",
                "profile_image_path": "TEXT",
                "height_cm": "REAL",
                "target_weight_kg": "REAL",
                "target_weight_date": "REAL",
                "motivation": "TEXT",
                "doctor_name": "TEXT",
                "nutritionist_name": "TEXT",
                "food_seed_version": "INTEGER NOT NULL DEFAULT 0",
                "show_launch_splash": "INTEGER NOT NULL DEFAULT 1",
                "appearance_mode": "TEXT NOT NULL DEFAULT 'system'",
                "meal_timing_json": "TEXT NOT NULL DEFAULT '[]'"
            ],
            db: db
        )

        try ensureColumns(
            table: "care_meetings",
            definitions: [
                "day": "TEXT NOT NULL DEFAULT ''",
                "provider_type": "TEXT NOT NULL DEFAULT 'doctor'",
                "notes": "TEXT NOT NULL DEFAULT ''"
            ],
            db: db
        )

        try ensureColumns(
            table: "documents",
            definitions: [
                "title": "TEXT NOT NULL DEFAULT ''",
                "filename": "TEXT NOT NULL DEFAULT ''",
                "file_type": "TEXT NOT NULL DEFAULT 'image'",
                "created_at": "REAL NOT NULL DEFAULT 0"
            ],
            db: db
        )

        try ensureColumns(
            table: "score_profiles",
            definitions: [
                "category_id": "TEXT NOT NULL DEFAULT ''",
                "weight": "REAL NOT NULL DEFAULT 1",
                "under_penalty": "REAL NOT NULL DEFAULT 1",
                "over_penalty": "REAL NOT NULL DEFAULT 1",
                "under_soft_limit": "REAL NOT NULL DEFAULT 1",
                "over_soft_limit": "REAL NOT NULL DEFAULT 1",
                "curve": "TEXT NOT NULL DEFAULT 'linear'",
                "cap_over": "INTEGER NOT NULL DEFAULT 0"
            ],
            db: db
        )

        try ensureColumns(
            table: "compensation_rules",
            definitions: [
                "from_category_id": "TEXT NOT NULL DEFAULT ''",
                "to_category_id": "TEXT NOT NULL DEFAULT ''",
                "ratio": "REAL NOT NULL DEFAULT 1",
                "max_offset": "REAL NOT NULL DEFAULT 0"
            ],
            db: db
        )
    }

    // MARK: - Helpers

    private static func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.flatMap { String(cString: $0) } ?? "SQLite execution failed"
            sqlite3_free(errorMessage)
            throw SQLiteDatabaseError.executionFailed(message)
        }
    }

    private static func existingColumns(in table: String, db: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteDatabaseError.prepareFailed(message)
        }
        guard let prepared = statement else {
            throw SQLiteDatabaseError.prepareFailed("Unable to prepare table_info for \(table)")
        }
        defer { sqlite3_finalize(prepared) }
        var columns = Set<String>()
        while sqlite3_step(prepared) == SQLITE_ROW {
            if let cString = sqlite3_column_text(prepared, 1) {
                columns.insert(String(cString: cString))
            }
        }
        return columns
    }

    private static func ensureColumns(
        table: String,
        definitions: [String: String],
        db: OpaquePointer
    ) throws {
        let existing = try existingColumns(in: table, db: db)
        for (name, definition) in definitions where !existing.contains(name) {
            try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition);", db: db)
        }
    }

    private func execute(_ sql: String) throws {
        try Self.execute(sql, db: db)
    }

    private func scalarCount(
        _ sql: String,
        bind: ((OpaquePointer) -> Void)? = nil
    ) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind?(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteDatabaseError.stepFailed(message)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteDatabaseError.prepareFailed(message)
        }
        guard let prepared = statement else {
            throw SQLiteDatabaseError.prepareFailed("Unable to prepare statement")
        }
        return prepared
    }

    private func step(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteDatabaseError.stepFailed(message)
        }
    }

    private func bindText(_ statement: OpaquePointer, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bindOptionalText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindDouble(_ statement: OpaquePointer, index: Int32, value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    private func bindOptionalDouble(_ statement: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindInt(_ statement: OpaquePointer, index: Int32, value: Int) {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func bindBool(_ statement: OpaquePointer, index: Int32, value: Bool) {
        sqlite3_bind_int(statement, index, value ? 1 : 0)
    }

    private func bindUUID(_ statement: OpaquePointer, index: Int32, value: UUID) {
        bindText(statement, index: index, value: value.uuidString)
    }

    private func readText(_ statement: OpaquePointer, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func readOptionalText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func readDouble(_ statement: OpaquePointer, index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func readOptionalDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private func readBool(_ statement: OpaquePointer, index: Int32) -> Bool {
        sqlite3_column_int(statement, index) == 1
    }

    private func readUUID(_ statement: OpaquePointer, index: Int32) -> UUID {
        UUID(uuidString: readText(statement, index: index)) ?? UUID()
    }

    private func encodeTargetRule(_ rule: Core.TargetRule) -> (type: String, min: Double?, max: Double?) {
        switch rule {
        case .exact(let value):
            return ("exact", value, value)
        case .atLeast(let value):
            return ("atLeast", value, nil)
        case .atMost(let value):
            return ("atMost", nil, value)
        case .range(let minValue, let maxValue):
            return ("range", minValue, maxValue)
        }
    }

    private func decodeTargetRule(type: String, min: Double?, max: Double?) -> Core.TargetRule {
        switch type {
        case "atLeast":
            return .atLeast(min ?? 0)
        case "atMost":
            return .atMost(max ?? 0)
        case "range":
            return .range(min: min ?? 0, max: max ?? 0)
        default:
            return .exact(min ?? max ?? 0)
        }
    }

    private func encodeCompositeComponents(_ components: [Core.FoodComponent]) -> String? {
        guard !components.isEmpty else { return nil }
        do {
            let data = try JSONEncoder().encode(components)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func decodeCompositeComponents(from json: String?) -> [Core.FoodComponent] {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Core.FoodComponent].self, from: data)) ?? []
    }

    private func encodeMealSlotTimings(_ timings: [Core.MealSlotTiming]) -> String {
        guard !timings.isEmpty else { return "[]" }
        do {
            let data = try JSONEncoder().encode(timings)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }

    private func decodeMealSlotTimings(from json: String?) -> [Core.MealSlotTiming] {
        guard let json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Core.MealSlotTiming].self, from: data)) ?? []
    }

}
