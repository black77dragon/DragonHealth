import Foundation
import OSLog

public enum LogCategory: String {
    case appUI = "app.ui"
    case coreDomain = "core.domain"
    case dbSQL = "db.sql"
    case infraConfig = "infra.config"
    case security = "sec"
}

public struct AppLogger: Sendable {
    private let logger: Logger

    public init(category: LogCategory) {
        self.logger = Logger(subsystem: "DragonHealth", category: category.rawValue)
    }

    public func info(_ message: String, metadata: [String: String] = [:]) {
        logger.info("\(message, privacy: .private) \(formatted(metadata), privacy: .private)")
    }

    public func error(_ message: String, metadata: [String: String] = [:]) {
        logger.error("\(message, privacy: .private) \(formatted(metadata), privacy: .private)")
    }

    private func formatted(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else {
            return ""
        }
        return metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}
