import Foundation

public struct Portion: Hashable, Comparable, Sendable {
    public static let defaultIncrement: Double = 0.1
    public static let drinkIncrement: Double = 0.01
    public static let minimumIncrement: Double = defaultIncrement
    public let value: Double

    public init(_ value: Double, increment: Double = Portion.defaultIncrement) {
        self.value = Portion.roundToIncrement(value, increment: increment)
    }

    public init(raw value: Double) {
        self.value = value
    }

    public static func < (lhs: Portion, rhs: Portion) -> Bool {
        lhs.value < rhs.value
    }

    public static func roundToIncrement(_ value: Double, increment: Double = Portion.defaultIncrement) -> Double {
        guard increment > 0 else { return value }
        let scaled = (value / increment).rounded()
        return scaled * increment
    }

    public static func isValidIncrement(_ value: Double, increment: Double = Portion.defaultIncrement) -> Bool {
        guard increment > 0 else { return true }
        let remainder = (value / increment).rounded() - (value / increment)
        return abs(remainder) < 0.000001
    }
}
