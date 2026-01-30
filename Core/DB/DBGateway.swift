import Foundation
import Core

public protocol DBGateway: Sendable {
    func fetchCategories() async throws -> [Category]
    func saveDailyLog(_ log: DailyLog) async throws
    func fetchDailyLog(for date: Date) async throws -> DailyLog?
}
