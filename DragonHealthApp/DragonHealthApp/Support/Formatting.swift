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
