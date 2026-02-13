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

    static let foodSeedVersion = 2

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
    ]
}
