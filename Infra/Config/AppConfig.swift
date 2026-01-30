import Foundation

public struct AppConfig: Sendable {
    public let environmentName: String
    public let minSupportedSchema: Int
    public let targetSchema: Int

    public init(environmentName: String, minSupportedSchema: Int, targetSchema: Int) {
        self.environmentName = environmentName
        self.minSupportedSchema = minSupportedSchema
        self.targetSchema = targetSchema
    }

    public static let defaultValue = AppConfig(
        environmentName: "development",
        minSupportedSchema: 0,
        targetSchema: 0
    )
}
