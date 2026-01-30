import Foundation

public enum TargetRule: Hashable, Sendable {
    case exact(Double)
    case atLeast(Double)
    case atMost(Double)
    case range(min: Double, max: Double)

    public static let exactTolerance: Double = 0.25

    public func isSatisfied(by total: Double) -> Bool {
        switch self {
        case .exact(let target):
            return abs(total - target) <= Self.exactTolerance
        case .atLeast(let target):
            return total >= target
        case .atMost(let target):
            return total <= target
        case .range(let minValue, let maxValue):
            return total >= minValue && total <= maxValue
        }
    }
}
