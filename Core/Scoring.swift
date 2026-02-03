import Foundation

public enum ScoreCurve: String, Hashable, Sendable {
    case linear
    case quadratic
}

public struct ScoreProfile: Hashable, Sendable {
    public var weight: Double
    public var underPenaltyPerUnit: Double
    public var overPenaltyPerUnit: Double
    public var underSoftLimit: Double
    public var overSoftLimit: Double
    public var curve: ScoreCurve
    public var capOverAtTarget: Bool

    public init(
        weight: Double,
        underPenaltyPerUnit: Double,
        overPenaltyPerUnit: Double,
        underSoftLimit: Double,
        overSoftLimit: Double,
        curve: ScoreCurve,
        capOverAtTarget: Bool
    ) {
        self.weight = weight
        self.underPenaltyPerUnit = underPenaltyPerUnit
        self.overPenaltyPerUnit = overPenaltyPerUnit
        self.underSoftLimit = underSoftLimit
        self.overSoftLimit = overSoftLimit
        self.curve = curve
        self.capOverAtTarget = capOverAtTarget
    }

    public static func defaultProfile(for category: Category) -> ScoreProfile {
        let template = ScoreProfileTemplate.templates[normalizedKey(category.name)] ?? ScoreProfileTemplate.defaultTemplate
        let range = category.targetRule.preferredRange()
        let underReference = range.min.isInfinite ? (range.max.isInfinite ? 1.0 : abs(range.max)) : abs(range.min)
        let overReference = range.max.isInfinite ? (range.min.isInfinite ? 1.0 : abs(range.min)) : abs(range.max)
        let underSoftLimit = max(template.minSoftLimit, underReference * template.underSoftLimitMultiplier)
        let overSoftLimit = max(template.minSoftLimit, overReference * template.overSoftLimitMultiplier)

        return ScoreProfile(
            weight: template.weight,
            underPenaltyPerUnit: template.underPenaltyPerUnit,
            overPenaltyPerUnit: template.overPenaltyPerUnit,
            underSoftLimit: underSoftLimit,
            overSoftLimit: overSoftLimit,
            curve: template.curve,
            capOverAtTarget: template.capOverAtTarget
        )
    }
}

public struct CompensationRule: Hashable, Sendable {
    public let fromCategoryID: UUID
    public let toCategoryID: UUID
    public let ratio: Double
    public let maxOffset: Double

    public init(fromCategoryID: UUID, toCategoryID: UUID, ratio: Double, maxOffset: Double) {
        self.fromCategoryID = fromCategoryID
        self.toCategoryID = toCategoryID
        self.ratio = ratio
        self.maxOffset = maxOffset
    }

    public static func defaultRules(for categories: [Category]) -> [CompensationRule] {
        let normalized = Dictionary(
            uniqueKeysWithValues: categories.map { (normalizedKey($0.name), $0) }
        )
        guard let treats = normalized["treats"],
              let sports = normalized["sports"] else { return [] }
        return [
            CompensationRule(
                fromCategoryID: treats.id,
                toCategoryID: sports.id,
                ratio: 15.0,
                maxOffset: 2.0
            )
        ]
    }
}

public struct CategoryScore: Hashable, Sendable {
    public let categoryID: UUID
    public let score: Double
    public let total: Double
    public let adjustedTotal: Double

    public init(categoryID: UUID, score: Double, total: Double, adjustedTotal: Double) {
        self.categoryID = categoryID
        self.score = score
        self.total = total
        self.adjustedTotal = adjustedTotal
    }
}

public struct DailyScoreSummary: Hashable, Sendable {
    public let categoryScores: [CategoryScore]
    public let overallScore: Double

    public init(categoryScores: [CategoryScore], overallScore: Double) {
        self.categoryScores = categoryScores
        self.overallScore = overallScore
    }
}

public struct DailyScoreEvaluator {
    public init() {}

    public func evaluate(
        categories: [Category],
        totalsByCategoryID: [UUID: Double],
        profilesByCategoryID: [UUID: ScoreProfile] = [:],
        compensationRules: [CompensationRule]? = nil
    ) -> DailyScoreSummary {
        let enabledCategories = categories.filter { $0.isEnabled }
        guard !enabledCategories.isEmpty else {
            return DailyScoreSummary(categoryScores: [], overallScore: 0)
        }

        var profiles: [UUID: ScoreProfile] = [:]
        for category in enabledCategories {
            profiles[category.id] = profilesByCategoryID[category.id] ?? ScoreProfile.defaultProfile(for: category)
        }

        let rules = compensationRules ?? CompensationRule.defaultRules(for: enabledCategories)
        let adjustedTotals = applyCompensationRules(
            categories: enabledCategories,
            totalsByCategoryID: totalsByCategoryID,
            rules: rules
        )

        var categoryScores: [CategoryScore] = []
        var weightedTotal: Double = 0
        var weightSum: Double = 0

        for category in enabledCategories {
            let total = totalsByCategoryID[category.id] ?? 0
            let adjustedTotal = adjustedTotals[category.id] ?? total
            let profile = profiles[category.id] ?? ScoreProfile.defaultProfile(for: category)
            let score = score(for: category, total: adjustedTotal, profile: profile)
            categoryScores.append(
                CategoryScore(categoryID: category.id, score: score, total: total, adjustedTotal: adjustedTotal)
            )
            weightedTotal += score * profile.weight
            weightSum += profile.weight
        }

        let overallScore: Double
        if weightSum > 0 {
            overallScore = weightedTotal / weightSum
        } else {
            let sum = categoryScores.reduce(0) { $0 + $1.score }
            overallScore = categoryScores.isEmpty ? 0 : sum / Double(categoryScores.count)
        }

        return DailyScoreSummary(categoryScores: categoryScores, overallScore: clampScore(overallScore))
    }

    private func applyCompensationRules(
        categories: [Category],
        totalsByCategoryID: [UUID: Double],
        rules: [CompensationRule]
    ) -> [UUID: Double] {
        guard !rules.isEmpty else { return totalsByCategoryID }
        var adjusted = totalsByCategoryID
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        for rule in rules {
            guard let fromCategory = categoryMap[rule.fromCategoryID],
                  let toCategory = categoryMap[rule.toCategoryID],
                  rule.ratio > 0 else { continue }
            let fromTotal = adjusted[rule.fromCategoryID] ?? 0
            let toTotal = adjusted[rule.toCategoryID] ?? 0
            let overage = fromCategory.targetRule.overageAmount(for: fromTotal)
            guard overage > 0 else { continue }
            let surplus = toCategory.targetRule.surplusAmount(for: toTotal)
            guard surplus > 0 else { continue }
            let offset = min(overage, surplus / rule.ratio, rule.maxOffset)
            guard offset > 0 else { continue }
            adjusted[rule.fromCategoryID] = fromTotal - offset
        }

        return adjusted
    }

    private func score(for category: Category, total: Double, profile: ScoreProfile) -> Double {
        let range = category.targetRule.preferredRange()
        if range.contains(total) {
            return 100
        }
        if total > range.max, profile.capOverAtTarget {
            return 100
        }

        if total < range.min {
            let deviation = range.min - total
            let penalty = penaltyAmount(
                deviation: deviation,
                softLimit: profile.underSoftLimit,
                multiplier: profile.underPenaltyPerUnit,
                curve: profile.curve
            )
            return clampScore(100 - penalty)
        }

        let deviation = total - range.max
        let penalty = penaltyAmount(
            deviation: deviation,
            softLimit: profile.overSoftLimit,
            multiplier: profile.overPenaltyPerUnit,
            curve: profile.curve
        )
        return clampScore(100 - penalty)
    }

    private func penaltyAmount(deviation: Double, softLimit: Double, multiplier: Double, curve: ScoreCurve) -> Double {
        guard deviation > 0, multiplier > 0 else { return 0 }
        let safeLimit = max(softLimit, 0.0001)
        let ratio = deviation / safeLimit
        let scaled = curve == .linear ? ratio : ratio * ratio
        return 50.0 * scaled * multiplier
    }
}

private struct ScoreProfileTemplate {
    let weight: Double
    let underPenaltyPerUnit: Double
    let overPenaltyPerUnit: Double
    let underSoftLimitMultiplier: Double
    let overSoftLimitMultiplier: Double
    let minSoftLimit: Double
    let curve: ScoreCurve
    let capOverAtTarget: Bool

    static let defaultTemplate = ScoreProfileTemplate(
        weight: 1.0,
        underPenaltyPerUnit: 1.0,
        overPenaltyPerUnit: 1.0,
        underSoftLimitMultiplier: 0.5,
        overSoftLimitMultiplier: 0.5,
        minSoftLimit: 0.5,
        curve: .linear,
        capOverAtTarget: false
    )

    static let templates: [String: ScoreProfileTemplate] = [
        "unsweeteneddrinks": ScoreProfileTemplate(
            weight: 0.10,
            underPenaltyPerUnit: 1.0,
            overPenaltyPerUnit: 0.0,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.25,
            curve: .linear,
            capOverAtTarget: true
        ),
        "vegetables": ScoreProfileTemplate(
            weight: 0.12,
            underPenaltyPerUnit: 1.0,
            overPenaltyPerUnit: 0.4,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .linear,
            capOverAtTarget: false
        ),
        "fruit": ScoreProfileTemplate(
            weight: 0.08,
            underPenaltyPerUnit: 0.8,
            overPenaltyPerUnit: 0.3,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .linear,
            capOverAtTarget: false
        ),
        "starchysides": ScoreProfileTemplate(
            weight: 0.12,
            underPenaltyPerUnit: 0.6,
            overPenaltyPerUnit: 1.2,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .quadratic,
            capOverAtTarget: false
        ),
        "proteinsources": ScoreProfileTemplate(
            weight: 0.12,
            underPenaltyPerUnit: 1.2,
            overPenaltyPerUnit: 0.4,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .linear,
            capOverAtTarget: false
        ),
        "dairy": ScoreProfileTemplate(
            weight: 0.08,
            underPenaltyPerUnit: 0.8,
            overPenaltyPerUnit: 0.8,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .linear,
            capOverAtTarget: false
        ),
        "oilsfatsnuts": ScoreProfileTemplate(
            weight: 0.06,
            underPenaltyPerUnit: 0.5,
            overPenaltyPerUnit: 0.5,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 0.5,
            curve: .linear,
            capOverAtTarget: false
        ),
        "treats": ScoreProfileTemplate(
            weight: 0.12,
            underPenaltyPerUnit: 0.0,
            overPenaltyPerUnit: 1.5,
            underSoftLimitMultiplier: 1.0,
            overSoftLimitMultiplier: 1.0,
            minSoftLimit: 0.5,
            curve: .quadratic,
            capOverAtTarget: false
        ),
        "sports": ScoreProfileTemplate(
            weight: 0.20,
            underPenaltyPerUnit: 1.2,
            overPenaltyPerUnit: 0.0,
            underSoftLimitMultiplier: 0.5,
            overSoftLimitMultiplier: 0.5,
            minSoftLimit: 10.0,
            curve: .linear,
            capOverAtTarget: true
        )
    ]
}

private extension TargetRule {
    func preferredRange() -> ScoreRange {
        switch self {
        case .exact(let target):
            return ScoreRange(min: target - TargetRule.exactTolerance, max: target + TargetRule.exactTolerance)
        case .atLeast(let target):
            return ScoreRange(min: target, max: Double.infinity)
        case .atMost(let target):
            return ScoreRange(min: -Double.infinity, max: target)
        case .range(let minValue, let maxValue):
            return ScoreRange(min: minValue, max: maxValue)
        }
    }

    func overageAmount(for total: Double) -> Double {
        let range = preferredRange()
        guard !range.max.isInfinite else { return 0 }
        return max(0, total - range.max)
    }

    func surplusAmount(for total: Double) -> Double {
        switch self {
        case .atLeast(let target):
            return max(0, total - target)
        default:
            let range = preferredRange()
            guard !range.max.isInfinite else { return 0 }
            return max(0, total - range.max)
        }
    }
}

private struct ScoreRange {
    let min: Double
    let max: Double

    func contains(_ value: Double) -> Bool {
        let aboveMin = min.isInfinite ? true : value >= min
        let belowMax = max.isInfinite ? true : value <= max
        return aboveMin && belowMax
    }
}

private func normalizedKey(_ name: String) -> String {
    let scalars = name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    return String(String.UnicodeScalarView(scalars))
}

private func clampScore(_ score: Double) -> Double {
    min(max(score, 0), 100)
}
