import Foundation

public struct DailyTotalsCalculator: Sendable {
    public init() {}

    public func totalsByCategory(entries: [DailyLogEntry]) -> [UUID: Double] {
        entries.reduce(into: [:]) { totals, entry in
            totals[entry.categoryID, default: 0] += entry.portion.value
        }
    }
}
