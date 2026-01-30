import Foundation

public struct CategoryAdherence: Hashable, Sendable {
    public let categoryID: UUID
    public let targetMet: Bool
    public let total: Double

    public init(categoryID: UUID, targetMet: Bool, total: Double) {
        self.categoryID = categoryID
        self.targetMet = targetMet
        self.total = total
    }
}

public struct DailyAdherenceSummary: Hashable, Sendable {
    public let categoryResults: [CategoryAdherence]
    public let allTargetsMet: Bool

    public init(categoryResults: [CategoryAdherence], allTargetsMet: Bool) {
        self.categoryResults = categoryResults
        self.allTargetsMet = allTargetsMet
    }
}

public struct DailyTotalEvaluator {
    public init() {}

    public func evaluate(categories: [Category], totalsByCategoryID: [UUID: Double]) -> DailyAdherenceSummary {
        let enabledCategories = categories.filter { $0.isEnabled }
        let results = enabledCategories.map { category in
            let total = totalsByCategoryID[category.id] ?? 0
            let targetMet = category.targetRule.isSatisfied(by: total)
            return CategoryAdherence(categoryID: category.id, targetMet: targetMet, total: total)
        }
        let allTargetsMet = results.allSatisfy { $0.targetMet }
        return DailyAdherenceSummary(categoryResults: results, allTargetsMet: allTargetsMet)
    }
}
