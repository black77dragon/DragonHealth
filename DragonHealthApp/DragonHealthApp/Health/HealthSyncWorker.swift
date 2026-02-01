import Foundation
import HealthKit
import Core
import CoreDB
import InfraLogging

struct HealthSyncStatus: Sendable {
    let lastSyncDate: Date?
    let lastSyncError: String?
}

struct HealthSyncOutcome: Sendable {
    let success: Bool
    let performed: Bool
    let errorMessage: String?

    nonisolated static func skipped() -> HealthSyncOutcome {
        HealthSyncOutcome(success: true, performed: false, errorMessage: nil)
    }

    nonisolated static func succeeded() -> HealthSyncOutcome {
        HealthSyncOutcome(success: true, performed: true, errorMessage: nil)
    }

    nonisolated static func failed(_ message: String) -> HealthSyncOutcome {
        HealthSyncOutcome(success: false, performed: true, errorMessage: message)
    }
}

enum HealthSyncError: Error, LocalizedError {
    case unavailable
    case notAuthorized
    case missingDataTypes

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Health data is not available on this device."
        case .notAuthorized:
            return "Apple Health access has not been authorized."
        case .missingDataTypes:
            return "Apple Health data types are unavailable."
        }
    }
}

actor HealthSyncWorker {
    static let shared = HealthSyncWorker()

    private enum Keys {
        static let lastSyncDate = "dragonhealth.health.last_sync"
        static let lastSyncError = "dragonhealth.health.last_error"
    }

    private struct HealthDayValues {
        var weightKg: Double?
        var bodyFatPercent: Double?
        var leanMassKg: Double?
        var waistCm: Double?
        var steps: Double?
    }

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let isoFormatter: ISO8601DateFormatter
    private let logger = AppLogger(category: .health)

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    func loadStatus() -> HealthSyncStatus {
        let lastDate = defaults.string(forKey: Keys.lastSyncDate).flatMap { isoFormatter.date(from: $0) }
        let lastError = defaults.string(forKey: Keys.lastSyncError)
        return HealthSyncStatus(lastSyncDate: lastDate, lastSyncError: lastError)
    }

    func sync(allowAuthorization: Bool) async -> HealthSyncOutcome {
        guard HKHealthStore.isHealthDataAvailable() else {
            return recordFailure(HealthSyncError.unavailable)
        }

        guard !Self.readTypes.isEmpty else {
            return recordFailure(HealthSyncError.missingDataTypes)
        }

        let authorized = await requestAuthorizationIfNeeded(allowRequest: allowAuthorization)
        guard authorized else {
            return allowAuthorization ? recordFailure(HealthSyncError.notAuthorized) : .skipped()
        }

        let range = syncRange()
        do {
            let values = try await fetchHealthValues(start: range.start, end: range.end)
            try await storeHealthValues(values)
            recordSuccess(date: Date())
            logger.info("health_sync_completed", metadata: ["days": "\(range.lookbackDays)", "entries": "\(values.count)"])
            return .succeeded()
        } catch {
            return recordFailure(error)
        }
    }

    private func recordSuccess(date: Date) {
        defaults.set(isoFormatter.string(from: date), forKey: Keys.lastSyncDate)
        defaults.removeObject(forKey: Keys.lastSyncError)
    }

    @discardableResult
    private func recordFailure(_ error: Error) -> HealthSyncOutcome {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        defaults.set(message, forKey: Keys.lastSyncError)
        logger.error("health_sync_failed", metadata: ["error": message])
        return .failed(message)
    }

    private func syncRange() -> (start: Date, end: Date, lookbackDays: Int) {
        let today = calendar.startOfDay(for: Date())
        let hasSyncedBefore = defaults.string(forKey: Keys.lastSyncDate) != nil
        let lookbackDays = hasSyncedBefore ? 14 : 365
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return (start, end, lookbackDays)
    }

    private func requestAuthorizationIfNeeded(allowRequest: Bool) async -> Bool {
        let readTypes = Self.readTypes
        if allowRequest {
            do {
                return try await requestAuthorization(readTypes: readTypes)
            } catch {
                logger.error("health_auth_request_failed", metadata: ["error": error.localizedDescription])
                return false
            }
        }

        do {
            let status = try await requestStatus(readTypes: readTypes)
            return status == .unnecessary
        } catch {
            logger.error("health_auth_status_failed", metadata: ["error": error.localizedDescription])
            return false
        }
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let shareTypes = Set<HKSampleType>()
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: success)
            }
        }
    }

    private func requestStatus(readTypes: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            let shareTypes = Set<HKSampleType>()
            healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    private func fetchHealthValues(start: Date, end: Date) async throws -> [Date: HealthDayValues] {
        async let weightByDay = fetchLatestSamplesByDay(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            transform: { $0 },
            start: start,
            end: end
        )
        async let leanMassByDay = fetchLatestSamplesByDay(
            identifier: .leanBodyMass,
            unit: .gramUnit(with: .kilo),
            transform: { $0 },
            start: start,
            end: end
        )
        async let bodyFatByDay = fetchLatestSamplesByDay(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            transform: { $0 * 100 },
            start: start,
            end: end
        )
        async let waistByDay = fetchLatestSamplesByDay(
            identifier: .waistCircumference,
            unit: .meterUnit(with: .centi),
            transform: { $0 },
            start: start,
            end: end
        )
        async let stepsByDay = fetchDailyStepCounts(start: start, end: end)

        let (weights, leanMass, bodyFat, waist, steps) = try await (
            weightByDay,
            leanMassByDay,
            bodyFatByDay,
            waistByDay,
            stepsByDay
        )

        var combined: [Date: HealthDayValues] = [:]

        func merge(_ map: [Date: Double], update: (inout HealthDayValues, Double) -> Void) {
            for (day, value) in map {
                var current = combined[day] ?? HealthDayValues()
                update(&current, value)
                combined[day] = current
            }
        }

        merge(weights) { $0.weightKg = $1 }
        merge(leanMass) { $0.leanMassKg = $1 }
        merge(bodyFat) { $0.bodyFatPercent = $1 }
        merge(waist) { $0.waistCm = $1 }
        merge(steps) { $0.steps = $1 }

        return combined
    }

    private func storeHealthValues(_ values: [Date: HealthDayValues]) async throws {
        guard !values.isEmpty else { return }
        let db = try SQLiteDatabase(path: AppStore.databaseURL().path, calendar: calendar)
        let existingEntries = try await db.fetchBodyMetrics()
        let dayBoundary = DayBoundary(cutoffMinutes: 0)
        var existingByDay: [String: BodyMetricEntry] = [:]
        for entry in existingEntries {
            let key = dayBoundary.dayKey(for: entry.date, calendar: calendar)
            existingByDay[key] = entry
        }

        for (date, health) in values {
            let day = calendar.startOfDay(for: date)
            let key = dayBoundary.dayKey(for: day, calendar: calendar)
            let existing = existingByDay[key]
            let merged = BodyMetricEntry(
                date: day,
                weightKg: existing?.weightKg ?? health.weightKg,
                muscleMass: existing?.muscleMass ?? health.leanMassKg,
                bodyFatPercent: existing?.bodyFatPercent ?? health.bodyFatPercent,
                waistCm: existing?.waistCm ?? health.waistCm,
                steps: existing?.steps ?? health.steps
            )

            if merged.weightKg == nil,
               merged.muscleMass == nil,
               merged.bodyFatPercent == nil,
               merged.waistCm == nil,
               merged.steps == nil {
                continue
            }

            try await db.upsertBodyMetric(merged)
        }
    }

    private func fetchLatestSamplesByDay(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        transform: @escaping (Double) -> Double,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        let samples = try await fetchSamples(for: type, start: start, end: end)
        var byDay: [Date: (date: Date, value: Double)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.endDate)
            let value = transform(sample.quantity.doubleValue(for: unit))
            if let existing = byDay[day] {
                if sample.endDate > existing.date {
                    byDay[day] = (sample.endDate, value)
                }
            } else {
                byDay[day] = (sample.endDate, value)
            }
        }
        return byDay.mapValues { $0.value }
    }

    private func fetchSamples(for type: HKQuantityType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func fetchDailyStepCounts(start: Date, end: Date) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let calendar = calendar
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let anchorDate = calendar.startOfDay(for: start)
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }
                var byDay: [Date: Double] = [:]
                results.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let day = calendar.startOfDay(for: statistics.startDate)
                        byDay[day] = sum.doubleValue(for: .count())
                    }
                }
                continuation.resume(returning: byDay)
            }
            healthStore.execute(query)
        }
    }

    private static let readTypes: Set<HKObjectType> = {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .waistCircumference,
            .stepCount
        ]
        let types = identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        return Set(types)
    }()
}
