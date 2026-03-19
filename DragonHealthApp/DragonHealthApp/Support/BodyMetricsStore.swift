import Foundation
import Core
import CoreDB

struct BodyMetricsStore {
    private let db: any DBGateway
    private let calendar: Calendar
    private let dayBoundary = DayBoundary(cutoffMinutes: 0)

    nonisolated init(db: any DBGateway, calendar: Calendar) {
        self.db = db
        self.calendar = calendar
    }

    func fetchAll() async throws -> [BodyMetricEntry] {
        let entries = try await db.fetchBodyMetrics()
        return entries.sorted(by: { $0.date > $1.date })
    }

    func save(_ entry: BodyMetricEntry) async throws -> [BodyMetricEntry] {
        try await db.upsertBodyMetric(normalized(entry))
        return try await fetchAll()
    }

    func importHealthMetrics(_ importedEntries: [BodyMetricEntry]) async throws {
        guard !importedEntries.isEmpty else { return }

        let existingEntries = try await db.fetchBodyMetrics()
        var existingByDay: [String: BodyMetricEntry] = [:]
        for entry in existingEntries {
            existingByDay[dayKey(for: entry.date)] = normalized(entry)
        }

        for importedEntry in importedEntries {
            let normalizedImportedEntry = normalized(importedEntry)
            let key = dayKey(for: normalizedImportedEntry.date)
            let merged = mergedEntry(existing: existingByDay[key], imported: normalizedImportedEntry)
            guard !isEmpty(merged) else { continue }
            try await db.upsertBodyMetric(merged)
            existingByDay[key] = merged
        }
    }

    private func normalized(_ entry: BodyMetricEntry) -> BodyMetricEntry {
        BodyMetricEntry(
            date: calendar.startOfDay(for: entry.date),
            weightKg: entry.weightKg,
            muscleMass: entry.muscleMass,
            bodyFatPercent: entry.bodyFatPercent,
            waistCm: entry.waistCm,
            steps: entry.steps,
            activeEnergyKcal: entry.activeEnergyKcal
        )
    }

    private func dayKey(for date: Date) -> String {
        dayBoundary.dayKey(for: calendar.startOfDay(for: date), calendar: calendar)
    }

    private func mergedEntry(existing: BodyMetricEntry?, imported: BodyMetricEntry) -> BodyMetricEntry {
        BodyMetricEntry(
            date: imported.date,
            weightKg: existing?.weightKg ?? imported.weightKg,
            muscleMass: existing?.muscleMass ?? imported.muscleMass,
            bodyFatPercent: existing?.bodyFatPercent ?? imported.bodyFatPercent,
            waistCm: existing?.waistCm ?? imported.waistCm,
            steps: existing?.steps ?? imported.steps,
            activeEnergyKcal: existing?.activeEnergyKcal ?? imported.activeEnergyKcal
        )
    }

    private func isEmpty(_ entry: BodyMetricEntry) -> Bool {
        entry.weightKg == nil
            && entry.muscleMass == nil
            && entry.bodyFatPercent == nil
            && entry.waistCm == nil
            && entry.steps == nil
            && entry.activeEnergyKcal == nil
    }
}

nonisolated func openBodyMetricsStore(path: String, calendar: Calendar) throws -> BodyMetricsStore {
    BodyMetricsStore(
        db: try SQLiteDatabase(path: path, calendar: calendar),
        calendar: calendar
    )
}
