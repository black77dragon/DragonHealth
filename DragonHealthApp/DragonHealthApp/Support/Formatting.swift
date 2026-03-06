import Foundation
import Core

extension TargetRule {
    func displayText(unit: String) -> String {
        switch self {
        case .exact(let value):
            return "\(value.cleanNumber) \(unit)"
        case .atLeast(let value):
            return ">= \(value.cleanNumber) \(unit)"
        case .atMost(let value):
            return "<= \(value.cleanNumber) \(unit)"
        case .range(let min, let max):
            return "\(min.cleanNumber)-\(max.cleanNumber) \(unit)"
        }
    }
}

extension Double {
    var cleanNumber: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

enum DrinkRules {
    nonisolated static let mlPerLiter: Double = 1000.0

    nonisolated static func isDrinkCategory(_ category: Core.Category) -> Bool {
        let lowerName = category.name.lowercased()
        let lowerUnit = category.unitName.lowercased()
        return lowerName.contains("drink") || lowerUnit == "l" || lowerUnit == "ml"
    }

    nonisolated static func portionIncrement(for category: Core.Category?) -> Double {
        guard let category, isDrinkCategory(category) else { return Portion.defaultIncrement }
        return Portion.drinkIncrement
    }

    nonisolated static func isDrinkUnitSymbol(_ symbol: String?) -> Bool {
        guard let symbol else { return false }
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ml" || normalized == "l"
    }

    nonisolated static func drinkUnits(from units: [Core.FoodUnit]) -> [Core.FoodUnit] {
        units.filter { isDrinkUnitSymbol($0.symbol) }
    }

    nonisolated static func liters(from amount: Double, unitSymbol: String?) -> Double? {
        guard amount.isFinite else { return nil }
        guard let unitSymbol else { return nil }
        switch unitSymbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ml":
            return amount / mlPerLiter
        case "l":
            return amount
        default:
            return nil
        }
    }

    nonisolated static func liters(from amount: Double, unitID: UUID?, units: [Core.FoodUnit]) -> Double? {
        guard let unitID else { return nil }
        let symbol = units.first(where: { $0.id == unitID })?.symbol
        return liters(from: amount, unitSymbol: symbol)
    }

    nonisolated static func roundedLiters(_ liters: Double) -> Double {
        Portion.roundToIncrement(liters, increment: Portion.drinkIncrement)
    }
}
