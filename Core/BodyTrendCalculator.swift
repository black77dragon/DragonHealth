import Foundation

public struct BodyMetricAverages: Hashable, Sendable {
    public let weightKg: Double?
    public let muscleMass: Double?
    public let bodyFatPercent: Double?
    public let waistCm: Double?
    public let steps: Double?

    public init(
        weightKg: Double?,
        muscleMass: Double?,
        bodyFatPercent: Double?,
        waistCm: Double?,
        steps: Double?
    ) {
        self.weightKg = weightKg
        self.muscleMass = muscleMass
        self.bodyFatPercent = bodyFatPercent
        self.waistCm = waistCm
        self.steps = steps
    }
}

public struct BodyTrendCalculator: Sendable {
    public init() {}

    public func sevenDayAverages(entries: [BodyMetricEntry], referenceDate: Date = Date(), calendar: Calendar = .current) -> BodyMetricAverages {
        let cutoffDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        let recent = entries.filter { $0.date >= cutoffDate }

        return BodyMetricAverages(
            weightKg: average(recent.compactMap(\.weightKg)),
            muscleMass: average(recent.compactMap(\.muscleMass)),
            bodyFatPercent: average(recent.compactMap(\.bodyFatPercent)),
            waistCm: average(recent.compactMap(\.waistCm)),
            steps: average(recent.compactMap(\.steps))
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Double(values.count)
    }
}
