import Foundation

enum NightGuardStatus: String, Codable, CaseIterable {
    case pending
    case compliant
    case violation
    case proteinException

    var isCompliant: Bool {
        switch self {
        case .compliant, .proteinException:
            return true
        case .pending, .violation:
            return false
        }
    }
}

struct NightGuardRecord: Codable, Hashable {
    let dayKey: String
    var status: NightGuardStatus
    var updatedAt: Date
    var note: String?
}

enum NightGuardTracking {
    static let recordsStorageKey = "nightguard.dailyRecordsJSON"

    static func decodeRecords(from rawValue: String) -> [NightGuardRecord] {
        guard let data = rawValue.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([NightGuardRecord].self, from: data)) ?? []
    }

    static func encodeRecords(_ records: [NightGuardRecord]) -> String? {
        guard let data = try? JSONEncoder().encode(records) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func statusByDayKey(from rawValue: String) -> [String: NightGuardStatus] {
        let records = decodeRecords(from: rawValue)
        return Dictionary(uniqueKeysWithValues: records.map { ($0.dayKey, $0.status) })
    }
}
