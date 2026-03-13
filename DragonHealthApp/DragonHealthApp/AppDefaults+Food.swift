import Foundation
import Core

extension AppDefaults {
    struct FoodSeed {
        let name: String
        let categoryName: String
        let portion: Double
        let amountPerPortion: Double?
        let unitSymbol: String?
        let notes: String

        init(
            name: String,
            categoryName: String,
            portion: Double,
            amountPerPortion: Double? = nil,
            unitSymbol: String? = nil,
            notes: String
        ) {
            self.name = name
            self.categoryName = categoryName
            self.portion = portion
            self.amountPerPortion = amountPerPortion
            self.unitSymbol = unitSymbol
            self.notes = notes
        }
    }

    static let foodSeedVersion = 3

    static func foodItems(categories: [Core.Category], units: [Core.FoodUnit]) -> [Core.FoodItem] {
        let idsByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.id) })
        let unitsBySymbol = Dictionary(uniqueKeysWithValues: units.map { ($0.symbol.lowercased(), $0.id) })
        return foodSeeds.compactMap { seed -> Core.FoodItem? in
            guard let categoryID = idsByName[seed.categoryName] else { return nil }
            let unitID = seed.unitSymbol.flatMap { unitsBySymbol[$0.lowercased()] }
            return Core.FoodItem(
                name: seed.name,
                categoryID: categoryID,
                portionEquivalent: seed.portion,
                amountPerPortion: seed.amountPerPortion,
                unitID: unitID,
                notes: seed.notes
            )
        }
    }

    static func missingFoodItems(existing: [Core.FoodItem], categories: [Core.Category], units: [Core.FoodUnit]) -> [Core.FoodItem] {
        let idsByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.id) })
        let unitsBySymbol = Dictionary(uniqueKeysWithValues: units.map { ($0.symbol.lowercased(), $0.id) })
        let existingKeys = Set(existing.map { foodKey(name: $0.name, categoryID: $0.categoryID) })
        return foodSeeds.compactMap { seed -> Core.FoodItem? in
            guard let categoryID = idsByName[seed.categoryName] else { return nil }
            let key = foodKey(name: seed.name, categoryID: categoryID)
            guard !existingKeys.contains(key) else { return nil }
            let unitID = seed.unitSymbol.flatMap { unitsBySymbol[$0.lowercased()] }
            return Core.FoodItem(
                name: seed.name,
                categoryID: categoryID,
                portionEquivalent: seed.portion,
                amountPerPortion: seed.amountPerPortion,
                unitID: unitID,
                notes: seed.notes
            )
        }
    }

    static func enrichFoodItems(existing: [Core.FoodItem], categories: [Core.Category], units: [Core.FoodUnit]) -> [Core.FoodItem] {
        let idsByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.id) })
        let unitsBySymbol = Dictionary(uniqueKeysWithValues: units.map { ($0.symbol.lowercased(), $0.id) })
        let seedsByKey: [String: FoodSeed] = Dictionary(
            uniqueKeysWithValues: foodSeeds.compactMap { seed in
                guard let categoryID = idsByName[seed.categoryName] else { return nil }
                let key = foodKey(name: seed.name, categoryID: categoryID)
                return (key, seed)
            }
        )

        return existing.compactMap { item in
            let key = foodKey(name: item.name, categoryID: item.categoryID)
            guard let seed = seedsByKey[key] else { return nil }
            var updated = item
            if updated.amountPerPortion == nil, let seedAmount = seed.amountPerPortion {
                updated.amountPerPortion = seedAmount
            }
            if updated.unitID == nil,
               let symbol = seed.unitSymbol,
               let unitID = unitsBySymbol[symbol.lowercased()] {
                updated.unitID = unitID
            }
            return updated == item ? nil : updated
        }
    }

    private static func foodKey(name: String, categoryID: UUID) -> String {
        let normalizedName = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        return "\(categoryID.uuidString.lowercased())|\(normalizedName)"
    }

    static let foodSeeds: [FoodSeed] = [
        FoodSeed(
            name: "Water",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Mineral water (sparkling)",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Herbal tea",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Green tea",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Black coffee",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Rooibos tea",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Unsweetened iced tea",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Unsweetened beverage. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Vegetable broth (low sodium)",
            categoryName: "Unsweetened Drinks",
            portion: 0.3,
            amountPerPortion: 300,
            unitSymbol: "ml",
            notes: "Light savory drink. 1 portion = 300 ml."
        ),
        FoodSeed(
            name: "Broccoli",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable, high in fiber. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Cauliflower",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable, high in fiber. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Spinach",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Leafy green, rich in iron. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Kale",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Leafy green, rich in vitamins. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Mixed salad greens",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Leafy greens mix. 1 portion = 2 cups raw."
        ),
        FoodSeed(
            name: "Carrots",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Crunchy root vegetable. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Zucchini",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Mild non-starchy vegetable. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Eggplant",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Bell pepper",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Vitamin C rich vegetable. 1 portion = 1 cup chopped."
        ),
        FoodSeed(
            name: "Tomatoes",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Juicy non-starchy vegetable. 1 portion = 1 cup chopped."
        ),
        FoodSeed(
            name: "Cucumber",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Hydrating vegetable. 1 portion = 1 cup sliced."
        ),
        FoodSeed(
            name: "Mushrooms",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Savory low-calorie vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Green beans",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Asparagus",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Brussels sprouts",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Cruciferous vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Cabbage",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Cruciferous vegetable. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Red beets",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Root vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Pumpkin (winter squash)",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Non-starchy vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Swiss chard",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Leafy green, rich in minerals. 1 portion = 1 cup cooked or 2 cups raw."
        ),
        FoodSeed(
            name: "Leeks",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Aromatic vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Onions",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Aromatic vegetable. 1 portion = 1 cup cooked."
        ),
        FoodSeed(
            name: "Green peas",
            categoryName: "Vegetables",
            portion: 1.0,
            notes: "Starchy vegetable. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Apple",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in fiber. 1 portion = 1 medium fruit or 1 cup chopped."
        ),
        FoodSeed(
            name: "Pear",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in fiber. 1 portion = 1 medium fruit or 1 cup chopped."
        ),
        FoodSeed(
            name: "Banana",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in fiber. 1 portion = 1 medium banana."
        ),
        FoodSeed(
            name: "Orange",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in vitamin C. 1 portion = 1 medium orange."
        ),
        FoodSeed(
            name: "Kiwi",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in vitamin C. 1 portion = 2 small kiwi."
        ),
        FoodSeed(
            name: "Grapes",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in fiber. 1 portion = 1 cup."
        ),
        FoodSeed(
            name: "Strawberries",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in vitamin C. 1 portion = 1 cup."
        ),
        FoodSeed(
            name: "Blueberries",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, rich in antioxidants. 1 portion = 1 cup."
        ),
        FoodSeed(
            name: "Raspberries",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit, high in fiber. 1 portion = 1 cup."
        ),
        FoodSeed(
            name: "Mango",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Tropical fruit. 1 portion = 1 cup chopped."
        ),
        FoodSeed(
            name: "Pineapple",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Tropical fruit. 1 portion = 1 cup chopped."
        ),
        FoodSeed(
            name: "Peach",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit. 1 portion = 1 medium peach."
        ),
        FoodSeed(
            name: "Plum",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Fresh fruit. 1 portion = 2 medium plums."
        ),
        FoodSeed(
            name: "Grapefruit",
            categoryName: "Fruit",
            portion: 1.0,
            notes: "Citrus fruit. 1 portion = 1/2 large grapefruit."
        ),
        FoodSeed(
            name: "Oats (rolled oats)",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup dry."
        ),
        FoodSeed(
            name: "Whole wheat bread",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain bread. 1 portion = 1 slice."
        ),
        FoodSeed(
            name: "Rye bread",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain bread. 1 portion = 1 slice."
        ),
        FoodSeed(
            name: "Brown rice",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Quinoa",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Whole wheat pasta",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain pasta. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Potatoes",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Starchy vegetable. 1 portion = 1 medium potato."
        ),
        FoodSeed(
            name: "Sweet potatoes",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Starchy vegetable. 1 portion = 1 medium sweet potato."
        ),
        FoodSeed(
            name: "Couscous (whole wheat)",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Bulgur",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Barley",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Buckwheat",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Polenta",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Whole grain. 1 portion = 1/2 cup cooked."
        ),
        FoodSeed(
            name: "Sweet corn",
            categoryName: "Carb",
            portion: 1.0,
            notes: "Starchy vegetable. 1 portion = 1/2 cup kernels."
        ),
        FoodSeed(
            name: "Chicken breast",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean protein. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Turkey breast",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean protein. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Lean beef",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean protein. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Pork tenderloin",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean protein. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Salmon",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Fatty fish with omega-3. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Tuna",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean fish. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Sardines",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Fatty fish with omega-3. 1 portion = 100 g drained."
        ),
        FoodSeed(
            name: "White fish (cod)",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean fish. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Shrimp",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Lean seafood. 1 portion = 100 g cooked."
        ),
        FoodSeed(
            name: "Eggs",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "High-quality protein. 1 portion = 2 eggs."
        ),
        FoodSeed(
            name: "Tofu",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 100 g."
        ),
        FoodSeed(
            name: "Tempeh",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 100 g."
        ),
        FoodSeed(
            name: "Lentils",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 3/4 cup cooked."
        ),
        FoodSeed(
            name: "Chickpeas",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 3/4 cup cooked."
        ),
        FoodSeed(
            name: "Black beans",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 3/4 cup cooked."
        ),
        FoodSeed(
            name: "Kidney beans",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 3/4 cup cooked."
        ),
        FoodSeed(
            name: "Edamame",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Plant protein. 1 portion = 1/2 cup shelled."
        ),
        FoodSeed(
            name: "Seitan",
            categoryName: "Protein Sources",
            portion: 1.0,
            notes: "Wheat-based protein. 1 portion = 100 g."
        ),
        FoodSeed(
            name: "Low fat milk",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Calcium rich dairy. 1 portion = 200 ml."
        ),
        FoodSeed(
            name: "Natural yogurt",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Calcium rich dairy. 1 portion = 150-200 g."
        ),
        FoodSeed(
            name: "Greek yogurt",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Higher protein dairy. 1 portion = 150-200 g."
        ),
        FoodSeed(
            name: "Kefir",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Fermented dairy drink. 1 portion = 200 ml."
        ),
        FoodSeed(
            name: "Cottage cheese",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "High protein dairy. 1 portion = 150 g."
        ),
        FoodSeed(
            name: "Quark",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "High protein dairy. 1 portion = 150 g."
        ),
        FoodSeed(
            name: "Skyr",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "High protein dairy. 1 portion = 150 g."
        ),
        FoodSeed(
            name: "Mozzarella",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Cheese. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Ricotta",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Soft cheese. 1 portion = 60 g."
        ),
        FoodSeed(
            name: "Swiss cheese (Emmental)",
            categoryName: "Dairy",
            portion: 1.0,
            notes: "Cheese. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Olive oil",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fat. 1 portion = 1 tbsp."
        ),
        FoodSeed(
            name: "Rapeseed oil",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fat. 1 portion = 1 tbsp."
        ),
        FoodSeed(
            name: "Avocado",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fat. 1 portion = 1/2 avocado."
        ),
        FoodSeed(
            name: "Almonds",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Walnuts",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Hazelnuts",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Chia seeds",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 1 tbsp."
        ),
        FoodSeed(
            name: "Ground flaxseed",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 1 tbsp."
        ),
        FoodSeed(
            name: "Pumpkin seeds",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 30 g."
        ),
        FoodSeed(
            name: "Peanut butter (unsweetened)",
            categoryName: "Oils / Fats / Nuts",
            portion: 1.0,
            notes: "Healthy fats. 1 portion = 1 tbsp."
        ),
        FoodSeed(
            name: "Dark chocolate (70%+)",
            categoryName: "Treats",
            portion: 1.0,
            notes: "Treat food. 1 portion = 20 g."
        ),
        FoodSeed(
            name: "Ice cream",
            categoryName: "Treats",
            portion: 1.0,
            notes: "Treat food. 1 portion = 1/2 cup."
        ),
        FoodSeed(
            name: "Croissant",
            categoryName: "Treats",
            portion: 1.0,
            notes: "Treat food. 1 portion = 1 small croissant."
        ),
        FoodSeed(
            name: "Potato chips",
            categoryName: "Treats",
            portion: 1.0,
            notes: "Treat food. 1 portion = 30 g."
        )
    ] + additionalFoodSeeds

    private static let additionalFoodSeeds: [FoodSeed] =
        additionalDrinkSeeds
        + additionalVegetableSeeds
        + additionalFruitSeeds
        + additionalCarbSeeds
        + additionalProteinSeeds
        + additionalDairySeeds
        + additionalFatSeeds
        + additionalTreatSeeds

    private static let additionalDrinkSeeds: [FoodSeed] = [
        ("Black tea", 300.0, "Classic unsweetened tea."),
        ("White tea", 300.0, "Delicate unsweetened tea."),
        ("Oolong tea", 300.0, "Toasted unsweetened tea."),
        ("Chamomile tea", 300.0, "Calming herbal tea."),
        ("Peppermint tea", 300.0, "Cooling herbal tea."),
        ("Ginger tea", 300.0, "Warming herbal tea."),
        ("Fennel tea", 300.0, "Digestive herbal tea."),
        ("Hibiscus tea", 300.0, "Tart herbal tea."),
        ("Jasmine tea", 300.0, "Fragrant unsweetened tea."),
        ("Earl Grey tea", 300.0, "Bergamot black tea."),
        ("English breakfast tea", 300.0, "Robust black tea."),
        ("Sencha tea", 300.0, "Japanese green tea."),
        ("Darjeeling tea", 300.0, "Light black tea."),
        ("Decaf coffee", 300.0, "Coffee without caffeine."),
        ("Americano", 300.0, "Unsweetened coffee drink."),
        ("Cold brew coffee", 300.0, "Chilled unsweetened coffee."),
        ("Dandelion coffee substitute", 300.0, "Roasted herbal coffee alternative."),
        ("Chicory coffee substitute", 300.0, "Roasted root coffee alternative."),
        ("Barley coffee", 300.0, "Roasted grain coffee alternative."),
        ("Yerba mate", 300.0, "Traditional unsweetened mate tea."),
        ("Matcha tea", 250.0, "Stone-ground green tea."),
        ("Lemon water", 300.0, "Infused water without added sugar."),
        ("Ginger lemon water", 300.0, "Infused water without added sugar."),
        ("Chicken broth (low sodium)", 300.0, "Savory broth with minimal calories."),
        ("Bone broth (low sodium)", 300.0, "Savory broth with minimal calories.")
    ].map {
        drinkSeed(name: $0.0, milliliters: $0.1, notes: $0.2)
    }

    private static let additionalVegetableSeeds: [FoodSeed] = [
        ("Romaine lettuce", 75.0, "Crisp leafy salad green."),
        ("Iceberg lettuce", 75.0, "Mild crunchy salad lettuce."),
        ("Arugula", 75.0, "Peppery salad green."),
        ("Celery", 150.0, "Crunchy low-calorie vegetable."),
        ("Radishes", 150.0, "Crisp root vegetable."),
        ("Bok choy", 150.0, "Tender Asian leafy vegetable."),
        ("Artichoke hearts", 150.0, "Prepared non-starchy vegetable."),
        ("Fennel bulb", 150.0, "Aromatic bulb vegetable."),
        ("Okra", 150.0, "Non-starchy pod vegetable."),
        ("Turnips", 150.0, "Mild root vegetable."),
        ("Snow peas", 150.0, "Tender edible-pod vegetable."),
        ("Sugar snap peas", 150.0, "Sweet crisp edible-pod vegetable."),
        ("Radicchio", 75.0, "Bitter leafy salad vegetable."),
        ("Endive", 75.0, "Slightly bitter leafy vegetable."),
        ("Watercress", 75.0, "Peppery aquatic leafy green."),
        ("Collard greens", 75.0, "Hearty leafy green."),
        ("Mustard greens", 75.0, "Sharp leafy green."),
        ("Beet greens", 75.0, "Tender leafy tops."),
        ("Napa cabbage", 150.0, "Crisp Asian cabbage."),
        ("Bean sprouts", 150.0, "Crunchy sprouted vegetable."),
        ("Bamboo shoots", 150.0, "Low-calorie stir-fry vegetable."),
        ("Hearts of palm", 150.0, "Tender, mild vegetable."),
        ("Kohlrabi", 150.0, "Crunchy brassica vegetable."),
        ("Daikon radish", 150.0, "Mild peppery root vegetable."),
        ("Spaghetti squash", 150.0, "Low-carb squash alternative.")
    ].map {
        gramSeed(name: $0.0, categoryName: "Vegetables", grams: $0.1, notes: $0.2)
    }

    private static let additionalFruitSeeds: [FoodSeed] =
        [
            ("Cherries", 150.0, "Juicy stone fruit."),
            ("Watermelon", 150.0, "Hydrating melon fruit."),
            ("Cantaloupe", 150.0, "Orange-fleshed melon."),
            ("Honeydew melon", 150.0, "Sweet green melon."),
            ("Blackberries", 150.0, "Berry fruit, high in fiber."),
            ("Pomegranate arils", 100.0, "Seeded fruit with tart sweetness."),
            ("Papaya", 150.0, "Tropical fruit rich in vitamin C."),
            ("Dragon fruit", 150.0, "Mild tropical fruit."),
            ("Raisins", 40.0, "Dried fruit with concentrated sweetness."),
            ("Dates", 40.0, "Dried fruit with concentrated sweetness."),
            ("Dried apricots", 40.0, "Dried fruit with concentrated sweetness."),
            ("Prunes", 40.0, "Dried fruit rich in fiber."),
            ("Unsweetened applesauce", 150.0, "Pureed fruit without added sugar."),
            ("Fruit salad (fresh)", 150.0, "Mixed fresh fruit."),
            ("Cranberries", 150.0, "Tart berry fruit.")
        ].map {
            gramSeed(name: $0.0, categoryName: "Fruit", grams: $0.1, notes: $0.2)
        }
        + [
            ("Mandarin", 2.0, "Easy-to-peel citrus fruit."),
            ("Clementine", 2.0, "Small sweet citrus fruit."),
            ("Tangerine", 1.0, "Sweet citrus fruit."),
            ("Apricots", 3.0, "Small stone fruit."),
            ("Nectarine", 1.0, "Smooth-skinned stone fruit."),
            ("Passion fruit", 2.0, "Tangy tropical fruit."),
            ("Figs", 2.0, "Soft fiber-rich fruit."),
            ("Guava", 1.0, "Tropical fruit rich in vitamin C."),
            ("Persimmon", 1.0, "Sweet autumn fruit."),
            ("Lychees", 10.0, "Juicy tropical fruit.")
        ].map {
            pieceSeed(name: $0.0, categoryName: "Fruit", pieces: $0.1, notes: $0.2)
        }

    private static let additionalCarbSeeds: [FoodSeed] =
        [
            ("White rice", 120.0, "Cooked carbohydrate staple."),
            ("Basmati rice", 120.0, "Cooked rice grain."),
            ("Jasmine rice", 120.0, "Cooked rice grain."),
            ("Wild rice", 120.0, "Cooked grain side."),
            ("Sourdough bread", 40.0, "Bread-based carbohydrate."),
            ("Multigrain bread", 40.0, "Bread-based carbohydrate."),
            ("Muesli", 45.0, "Dry cereal carbohydrate."),
            ("Granola", 45.0, "Dry cereal carbohydrate."),
            ("Millet", 120.0, "Cooked grain side."),
            ("Farro", 120.0, "Cooked grain side."),
            ("Spelt berries", 120.0, "Cooked whole grain."),
            ("Gnocchi", 120.0, "Potato-based carbohydrate."),
            ("White pasta", 120.0, "Cooked pasta carbohydrate."),
            ("Soba noodles", 120.0, "Cooked noodle carbohydrate."),
            ("Udon noodles", 120.0, "Cooked noodle carbohydrate."),
            ("Egg noodles", 120.0, "Cooked noodle carbohydrate."),
            ("Whole grain crackers", 30.0, "Dry cracker carbohydrate."),
            ("Plain popcorn", 20.0, "Popped whole grain carbohydrate."),
            ("Couscous", 120.0, "Cooked grain side.")
        ].map {
            gramSeed(name: $0.0, categoryName: "Carb", grams: $0.1, notes: $0.2)
        }
        + [
            ("Pita bread", 1.0, "Bread-based carbohydrate."),
            ("Corn tortilla", 2.0, "Flatbread carbohydrate."),
            ("Flour tortilla", 1.0, "Flatbread carbohydrate."),
            ("Rice cakes", 2.0, "Light crisp carbohydrate."),
            ("Bagel", 1.0, "Bread-based carbohydrate."),
            ("English muffin", 1.0, "Bread-based carbohydrate.")
        ].map {
            pieceSeed(name: $0.0, categoryName: "Carb", pieces: $0.1, notes: $0.2)
        }

    private static let additionalProteinSeeds: [FoodSeed] =
        [
            ("Chicken thigh", 120.0, "Cooked poultry protein."),
            ("Ground turkey", 120.0, "Lean poultry protein."),
            ("Ground chicken", 120.0, "Lean poultry protein."),
            ("Lean ground beef", 120.0, "Cooked meat protein."),
            ("Roast beef", 120.0, "Cooked meat protein."),
            ("Lean ham", 120.0, "Cooked meat protein."),
            ("Trout", 120.0, "Fatty fish protein."),
            ("Mackerel", 120.0, "Fatty fish protein."),
            ("Haddock", 120.0, "Lean fish protein."),
            ("Tilapia", 120.0, "Lean fish protein."),
            ("Halibut", 120.0, "Lean fish protein."),
            ("Scallops", 120.0, "Lean shellfish protein."),
            ("Mussels", 150.0, "Shellfish protein."),
            ("Clams", 150.0, "Shellfish protein."),
            ("Crab", 120.0, "Lean shellfish protein."),
            ("Lobster", 120.0, "Lean shellfish protein."),
            ("White beans", 150.0, "Cooked legume protein."),
            ("Cannellini beans", 150.0, "Cooked legume protein."),
            ("Pinto beans", 150.0, "Cooked legume protein."),
            ("Navy beans", 150.0, "Cooked legume protein."),
            ("Split peas", 150.0, "Cooked legume protein."),
            ("Soybeans", 150.0, "Cooked soy protein."),
            ("Smoked tofu", 120.0, "Soy-based protein."),
            ("Falafel", 90.0, "Legume-based protein.")
        ].map {
            gramSeed(name: $0.0, categoryName: "Protein Sources", grams: $0.1, notes: $0.2)
        }
        + [
            ("Egg whites", 4.0, "Lean egg protein.")
        ].map {
            pieceSeed(name: $0.0, categoryName: "Protein Sources", pieces: $0.1, notes: $0.2)
        }

    private static let additionalDairySeeds: [FoodSeed] =
        [
            ("Whole milk", 200.0, "Liquid dairy serving."),
            ("Reduced-fat milk", 200.0, "Liquid dairy serving."),
            ("Lactose-free milk", 200.0, "Liquid dairy serving."),
            ("Buttermilk", 200.0, "Cultured dairy drink."),
            ("Plain drinking yogurt", 200.0, "Cultured dairy drink."),
            ("Ayran", 250.0, "Salted yogurt drink."),
            ("Cheddar cheese", 30.0, "Firm dairy cheese."),
            ("Parmesan", 30.0, "Hard aged cheese."),
            ("Feta", 30.0, "Brined cheese."),
            ("Goat cheese", 30.0, "Soft tangy cheese."),
            ("Cream cheese", 30.0, "Spreadable fresh cheese."),
            ("Sour cream", 30.0, "Cultured dairy topping."),
            ("Labneh", 60.0, "Strained yogurt cheese."),
            ("Provolone", 30.0, "Semi-hard cheese."),
            ("Gouda", 30.0, "Semi-hard cheese."),
            ("Brie", 30.0, "Soft-ripened cheese."),
            ("Camembert", 30.0, "Soft-ripened cheese."),
            ("Monterey Jack", 30.0, "Semi-soft cheese."),
            ("Halloumi", 50.0, "Firm grilling cheese."),
            ("Mascarpone", 30.0, "Rich fresh cheese."),
            ("Fromage blanc", 150.0, "Fresh cultured dairy."),
            ("Sheep milk yogurt", 150.0, "Cultured dairy yogurt."),
            ("Blue cheese", 30.0, "Aged veined cheese."),
            ("Pecorino", 30.0, "Hard sheep's milk cheese.")
        ].map {
            gramOrLiquidDairySeed(name: $0.0, amount: $0.1, notes: $0.2)
        }
        + [
            ("String cheese", 1.0, "Portioned cheese snack.")
        ].map {
            pieceSeed(name: $0.0, categoryName: "Dairy", pieces: $0.1, notes: $0.2)
        }

    private static let additionalFatSeeds: [FoodSeed] = [
        ("Butter", 10.0, "Concentrated cooking fat."),
        ("Ghee", 10.0, "Clarified cooking fat."),
        ("Sunflower oil", 10.0, "Plant-based cooking oil."),
        ("Sesame oil", 10.0, "Flavorful plant oil."),
        ("Coconut oil", 10.0, "Saturated plant oil."),
        ("Mayonnaise", 15.0, "Emulsified fat-based spread."),
        ("Pesto", 15.0, "Oil-based herb spread."),
        ("Tahini", 15.0, "Sesame seed paste."),
        ("Almond butter", 15.0, "Nut-based spread."),
        ("Cashew butter", 15.0, "Nut-based spread."),
        ("Sunflower seed butter", 15.0, "Seed-based spread."),
        ("Cashews", 30.0, "Nut source of healthy fats."),
        ("Pistachios", 30.0, "Nut source of healthy fats."),
        ("Pecans", 30.0, "Nut source of healthy fats."),
        ("Macadamia nuts", 30.0, "Nut source of healthy fats."),
        ("Brazil nuts", 30.0, "Nut source of healthy fats."),
        ("Peanuts", 30.0, "Legume source of fats."),
        ("Pine nuts", 30.0, "Seed source of healthy fats."),
        ("Sunflower seeds", 30.0, "Seed source of healthy fats."),
        ("Sesame seeds", 15.0, "Seed source of healthy fats."),
        ("Hemp seeds", 15.0, "Seed source of healthy fats."),
        ("Mixed nuts", 30.0, "Mixed nut source of fats."),
        ("Olive tapenade", 15.0, "Olive-based savory spread."),
        ("Olives", 40.0, "Olive fruit source of fats."),
        ("Unsweetened coconut flakes", 15.0, "Coconut source of fats.")
    ].map {
        gramSeed(name: $0.0, categoryName: "Oils / Fats / Nuts", grams: $0.1, notes: $0.2)
    }

    private static let additionalTreatSeeds: [FoodSeed] =
        [
            ("Milk chocolate", 20.0, "Sweet chocolate treat."),
            ("White chocolate", 20.0, "Sweet chocolate treat."),
            ("Cheesecake", 80.0, "Sweet dessert."),
            ("Apple pie", 80.0, "Sweet dessert."),
            ("Gummy candy", 30.0, "Sugary candy treat."),
            ("Marshmallows", 30.0, "Sugary candy treat."),
            ("Pudding", 100.0, "Sweet dairy dessert."),
            ("Sweetened breakfast cereal", 30.0, "Sugary cereal treat."),
            ("Fruit sorbet", 100.0, "Frozen sweet dessert."),
            ("Caramel popcorn", 30.0, "Sugary snack treat."),
            ("French fries", 120.0, "Fried treat food.")
        ].map {
            gramSeed(name: $0.0, categoryName: "Treats", grams: $0.1, notes: $0.2)
        }
        + [
            ("Chocolate chip cookie", 1.0, "Sweet baked treat."),
            ("Brownie", 1.0, "Sweet baked treat."),
            ("Muffin", 1.0, "Sweet baked treat."),
            ("Doughnut", 1.0, "Sweet baked treat."),
            ("Cupcake", 1.0, "Sweet baked treat."),
            ("Cinnamon roll", 1.0, "Sweet baked treat."),
            ("Candy bar", 1.0, "Sugary packaged treat."),
            ("Sweet pastry", 1.0, "Sweet baked treat."),
            ("Sweet waffle", 1.0, "Sweet breakfast treat."),
            ("Sweet pancakes", 2.0, "Sweet breakfast treat.")
        ].map {
            pieceSeed(name: $0.0, categoryName: "Treats", pieces: $0.1, notes: $0.2)
        }
        + [
            ("Milkshake", 250.0, "Sweet drink treat."),
            ("Hot chocolate", 250.0, "Sweet drink treat."),
            ("Soda", 330.0, "Sugary soft drink."),
            ("Lemonade", 330.0, "Sugary soft drink.")
        ].map {
            liquidSeed(name: $0.0, categoryName: "Treats", milliliters: $0.1, notes: $0.2)
        }

    private static func drinkSeed(name: String, milliliters: Double, notes: String) -> FoodSeed {
        FoodSeed(
            name: name,
            categoryName: "Unsweetened Drinks",
            portion: milliliters / 1_000,
            amountPerPortion: milliliters,
            unitSymbol: "ml",
            notes: "\(notes) 1 portion = \(Int(milliliters)) ml."
        )
    }

    private static func gramSeed(name: String, categoryName: String, grams: Double, notes: String) -> FoodSeed {
        FoodSeed(
            name: name,
            categoryName: categoryName,
            portion: 1.0,
            amountPerPortion: grams,
            unitSymbol: "g",
            notes: "\(notes) 1 portion = \(Int(grams)) g."
        )
    }

    private static func liquidSeed(name: String, categoryName: String, milliliters: Double, notes: String) -> FoodSeed {
        FoodSeed(
            name: name,
            categoryName: categoryName,
            portion: 1.0,
            amountPerPortion: milliliters,
            unitSymbol: "ml",
            notes: "\(notes) 1 portion = \(Int(milliliters)) ml."
        )
    }

    private static func pieceSeed(name: String, categoryName: String, pieces: Double, notes: String) -> FoodSeed {
        FoodSeed(
            name: name,
            categoryName: categoryName,
            portion: 1.0,
            amountPerPortion: pieces,
            unitSymbol: "pc",
            notes: "\(notes) 1 portion = \(Int(pieces)) pc."
        )
    }

    private static func gramOrLiquidDairySeed(name: String, amount: Double, notes: String) -> FoodSeed {
        let liquidDairyNames: Set<String> = [
            "Whole milk",
            "Reduced-fat milk",
            "Lactose-free milk",
            "Buttermilk",
            "Plain drinking yogurt",
            "Ayran"
        ]

        if liquidDairyNames.contains(name) {
            return liquidSeed(name: name, categoryName: "Dairy", milliliters: amount, notes: notes)
        } else {
            return gramSeed(name: name, categoryName: "Dairy", grams: amount, notes: notes)
        }
    }
}
