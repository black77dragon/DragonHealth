import Foundation

public struct Portion: Hashable, Comparable, Sendable {
    public static let minimumIncrement: Double = 0.25
    public let value: Double

    public init(_ value: Double) {
        self.value = Portion.roundToQuarter(value)
    }

    public static func < (lhs: Portion, rhs: Portion) -> Bool {
        lhs.value < rhs.value
    }

    public static func roundToQuarter(_ value: Double) -> Double {
        let scaled = (value / minimumIncrement).rounded()
        return scaled * minimumIncrement
    }

    public static func isValidIncrement(_ value: Double) -> Bool {
        let remainder = (value / minimumIncrement).rounded() - (value / minimumIncrement)
        return abs(remainder) < 0.000001
    }
}
