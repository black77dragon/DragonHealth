import Foundation

public struct FeatureFlag: Hashable, Sendable {
    public let name: String
    public let productionEnabled: Bool

    public init(name: String, productionEnabled: Bool) {
        self.name = name
        self.productionEnabled = productionEnabled
    }
}

public protocol FeatureFlagService: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
    func allFlags() -> [FeatureFlag]
}

public struct InMemoryFeatureFlagService: FeatureFlagService, Sendable {
    private let flags: [FeatureFlag]
    private let enabledOverrides: Set<String>

    public init(flags: [FeatureFlag], enabledOverrides: Set<String> = []) {
        self.flags = flags
        self.enabledOverrides = enabledOverrides
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        if enabledOverrides.contains(flag.name) {
            return true
        }
        return flag.productionEnabled
    }

    public func allFlags() -> [FeatureFlag] {
        flags
    }
}
