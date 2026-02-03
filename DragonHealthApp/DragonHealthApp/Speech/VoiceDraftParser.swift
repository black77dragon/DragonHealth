import Foundation
import Core

struct VoiceDraftParser {
    func parse(
        transcript: String,
        categories _: [Core.Category],
        foodItems: [FoodItem],
        units: [FoodUnit],
        mealSlots: [MealSlot]
    ) -> VoiceDraft {
        let normalizedTranscript = normalizeText(transcript)
        let mealSlotID = detectMealSlot(in: normalizedTranscript, mealSlots: mealSlots)
        let unitMap = unitSymbolMap(units: units)
        let foodIndex = foodIndexMap(foodItems: foodItems)
        let mealSlotKeywords = mealSlotKeywordSequences(mealSlots: mealSlots)
        let segments = splitSegments(from: normalizedTranscript)

        let items = segments.compactMap { segment -> VoiceDraftItem? in
            guard let parsed = parseSegment(segment, mealSlotKeywords: mealSlotKeywords) else { return nil }
            guard !parsed.foodText.isEmpty else { return nil }
            let normalizedFood = normalizeText(parsed.foodText)
            let matchedFood = matchFood(normalizedFood, foodIndex: foodIndex)

            var portion: Double? = nil
            let isPortionUnit = isPortionToken(parsed.unitToken)
            let unitResolution = isPortionUnit ? nil : resolveUnit(parsed.unitToken)
            var convertedAmount: Double?
            var amountUnitID: UUID?
            if let value = parsed.amount, let unitResolution {
                convertedAmount = value * unitResolution.multiplier
                amountUnitID = unitMap[unitResolution.symbol]
            } else {
                convertedAmount = isPortionUnit ? nil : parsed.amount
                amountUnitID = nil
            }
            let shouldDefaultToPortion = parsed.unitToken == nil && parsed.amount != nil
            var didDefaultToPortion = false

            if isPortionUnit, let amount = parsed.amount {
                portion = Portion.roundToIncrement(amount)
            } else {
                if let matchedFood {
                    portion = calculatePortion(
                        for: matchedFood,
                        amountValue: convertedAmount,
                        amountUnitID: amountUnitID
                    )
                }

                if portion == nil, let countPortion = countBasedPortion(for: normalizedFood, amount: parsed.amount) {
                    portion = countPortion
                    if amountUnitID == nil {
                        amountUnitID = unitMap["pc"]
                    }
                }

                if portion == nil, shouldDefaultToPortion, let amount = parsed.amount {
                    portion = Portion.roundToIncrement(amount)
                    didDefaultToPortion = true
                }
            }

            if didDefaultToPortion {
                convertedAmount = nil
                amountUnitID = nil
            }

            let categoryID = matchedFood?.categoryID

            return VoiceDraftItem(
                foodText: parsed.foodText,
                matchedFoodID: matchedFood?.id,
                categoryID: categoryID,
                amountValue: convertedAmount,
                amountUnitID: amountUnitID,
                portion: portion,
                notes: nil
            )
        }

        return VoiceDraft(
            transcript: transcript,
            mealSlotID: mealSlotID,
            items: items
        )
    }

    private func splitSegments(from transcript: String) -> [String] {
        let separators = [",", ";", " and ", " und "]
        var segments: [String] = [transcript]
        for separator in separators {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseSegment(_ segment: String, mealSlotKeywords: [[String]]) -> (amount: Double?, unitToken: String?, foodText: String)? {
        let withNumberWords = replaceNumberWords(in: segment)
        let cleaned = withNumberWords
            .replacingOccurrences(of: "(\\d)([a-zA-ZäöüÄÖÜß])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fillerPrefixes = ["i had ", "i ate ", "i drank ", "for ", "ich hatte ", "ich habe "]
        let trimmed = fillerPrefixes.reduce(cleaned) { current, prefix in
            current.hasPrefix(prefix) ? String(current.dropFirst(prefix.count)) : current
        }

        let numberFinderPattern = "(\\d+(?:[\\.,]\\d+)?)"
        guard let numberFinder = try? NSRegularExpression(pattern: numberFinderPattern) else { return nil }
        let searchRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let firstNumberMatch = numberFinder.firstMatch(in: trimmed, options: [], range: searchRange),
              let numberStartRange = Range(firstNumberMatch.range(at: 1), in: trimmed) else {
            return nil
        }

        let candidate = String(trimmed[numberStartRange.lowerBound...])
        let numberPattern = "^(\\d+(?:[\\.,]\\d+)?)\\s*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: numberPattern) else { return nil }
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        guard let match = regex.firstMatch(in: candidate, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: candidate),
              let restRange = Range(match.range(at: 2), in: candidate) else {
            return nil
        }

        let numberText = candidate[numberRange].replacingOccurrences(of: ",", with: ".")
        let amount = Double(numberText)
        let rest = candidate[restRange].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rest.isEmpty else { return (amount, nil, "") }

        var tokens = rest
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        var unitToken: String?

        if let first = tokens.first, isUnitToken(first) {
            unitToken = first
            tokens.removeFirst()
        }

        if let first = tokens.first, first == "of" || first == "von" {
            tokens.removeFirst()
        }

        let cleanedTokens = stripMealSlotSuffix(tokens, mealSlotKeywords: mealSlotKeywords)
        let foodText = cleanedTokens.joined(separator: " ")
        return (amount, unitToken, foodText.isEmpty ? rest : foodText)
    }

    private func detectMealSlot(in transcript: String, mealSlots: [MealSlot]) -> UUID? {
        let normalized = normalizeText(transcript)
        if let directMatch = mealSlots.first(where: { normalized.contains(normalizeText($0.name)) }) {
            return directMatch.id
        }

        let fallback: [(keywords: [String], slotName: String)] = [
            (["breakfast", "frühstück", "fruhstuck"], "Breakfast"),
            (["morning snack", "snack"], "Morning Snack"),
            (["lunch", "mittagessen"], "Lunch"),
            (["afternoon snack"], "Afternoon Snack"),
            (["dinner", "abendessen", "supper"], "Dinner"),
            (["late night"], "Late Night"),
            (["midnight"], "Midnight")
        ]

        for entry in fallback {
            if entry.keywords.contains(where: { normalized.contains($0) }) {
                if let slot = mealSlots.first(where: { normalizeText($0.name).contains(normalizeText(entry.slotName)) }) {
                    return slot.id
                }
            }
        }

        return nil
    }

    private func normalizeText(_ text: String) -> String {
        let lowered = text.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9äöüß\\s]", with: " ", options: .regularExpression)
        return cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func replaceNumberWords(in text: String) -> String {
        let replacements: [String: String] = [
            "zero": "0",
            "one": "1",
            "two": "2",
            "three": "3",
            "four": "4",
            "five": "5",
            "six": "6",
            "seven": "7",
            "eight": "8",
            "nine": "9",
            "ten": "10",
            "eleven": "11",
            "twelve": "12",
            "null": "0",
            "eins": "1",
            "ein": "1",
            "eine": "1",
            "einen": "1",
            "zwei": "2",
            "drei": "3",
            "vier": "4",
            "fuenf": "5",
            "fünf": "5",
            "sechs": "6",
            "sieben": "7",
            "acht": "8",
            "neun": "9",
            "zehn": "10",
            "elf": "11",
            "zwoelf": "12",
            "zwölf": "12"
        ]

        var output = text
        for (word, value) in replacements {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: value)
            }
        }
        return output
    }

    private func mealSlotKeywordSequences(mealSlots: [MealSlot]) -> [[String]] {
        var sequences: [[String]] = []
        var seen = Set<String>()

        let slotNames = mealSlots.map { normalizeText($0.name) }
        let fallback = [
            "breakfast",
            "morning snack",
            "lunch",
            "afternoon snack",
            "dinner",
            "supper",
            "late night",
            "midnight",
            "snack",
            "frühstück",
            "fruhstuck",
            "mittagessen",
            "abendessen"
        ]

        for name in slotNames + fallback {
            let tokens = name.split(separator: " ").map { String($0) }
            guard !tokens.isEmpty else { continue }
            let key = tokens.joined(separator: " ")
            if seen.insert(key).inserted {
                sequences.append(tokens)
            }
        }

        return sequences
    }

    private func stripMealSlotSuffix(_ tokens: [String], mealSlotKeywords: [[String]]) -> [String] {
        guard !tokens.isEmpty else { return tokens }
        let normalizedTokens = tokens.map { normalizeText($0) }
        let markers: Set<String> = ["for", "at", "zum", "zu", "für", "fuer"]

        for index in normalizedTokens.indices {
            guard markers.contains(normalizedTokens[index]) else { continue }
            let remaining = Array(normalizedTokens[(index + 1)...])
            for sequence in mealSlotKeywords {
                if remaining.starts(with: sequence) {
                    return Array(tokens[..<index])
                }
            }
        }

        return tokens
    }

    private func unitSymbolMap(units: [FoodUnit]) -> [String: UUID] {
        Dictionary(uniqueKeysWithValues: units.map { ($0.symbol.lowercased(), $0.id) })
    }

    private func foodIndexMap(foodItems: [FoodItem]) -> [String: FoodItem] {
        Dictionary(uniqueKeysWithValues: foodItems.map { (normalizeText($0.name), $0) })
    }

    private func matchFood(_ normalizedFood: String, foodIndex: [String: FoodItem]) -> FoodItem? {
        if let exact = foodIndex[normalizedFood] {
            return exact
        }

        let synonyms: [String: String] = [
            "egg": "eggs",
            "eggs": "eggs",
            "ei": "eggs",
            "eier": "eggs",
            "water": "water",
            "wasser": "water",
            "cheese": "swiss cheese emmental",
            "käse": "swiss cheese emmental",
            "kaese": "swiss cheese emmental"
        ]

        if let mapped = synonyms[normalizedFood], let match = foodIndex[mapped] {
            return match
        }

        let tokens = Set(normalizedFood.split(separator: " "))
        let best = foodIndex.max { lhs, rhs in
            let lhsScore = tokens.intersection(Set(lhs.key.split(separator: " "))).count
            let rhsScore = tokens.intersection(Set(rhs.key.split(separator: " "))).count
            return lhsScore < rhsScore
        }

        if let best, !tokens.isEmpty {
            let score = tokens.intersection(Set(best.key.split(separator: " "))).count
            if score > 0 {
                return best.value
            }
        }

        return nil
    }

    private func isUnitToken(_ token: String) -> Bool {
        isPortionToken(token) || resolveUnit(token) != nil
    }

    private func isPortionToken(_ token: String?) -> Bool {
        guard let token else { return false }
        let normalized = normalizeText(token)
        switch normalized {
        case "portion", "portions", "portionen":
            return true
        default:
            return false
        }
    }

    private func resolveUnit(_ token: String?) -> (symbol: String, multiplier: Double)? {
        guard let token else { return nil }
        let normalized = token.lowercased()
        switch normalized {
        case "g", "gram", "grams", "gramm":
            return ("g", 1.0)
        case "kg", "kilogram", "kilograms", "kilogramm":
            return ("g", 1000.0)
        case "ml", "milliliter", "millilitre":
            return ("ml", 1.0)
        case "l", "liter", "litre":
            return ("ml", 1000.0)
        case "pc", "piece", "pieces", "stück", "stk", "stueck", "stuck":
            return ("pc", 1.0)
        default:
            return nil
        }
    }

    private func calculatePortion(for food: FoodItem, amountValue: Double?, amountUnitID: UUID?) -> Double? {
        guard let amountValue else { return nil }
        guard let amountPerPortion = food.amountPerPortion else { return nil }
        guard let unitID = food.unitID, unitID == amountUnitID else { return nil }
        let portionValue = (amountValue / amountPerPortion) * food.portionEquivalent
        return Portion.roundToIncrement(portionValue)
    }

    private func countBasedPortion(for normalizedFood: String, amount: Double?) -> Double? {
        guard let amount else { return nil }
        let countPerPortion: [String: Double] = [
            "eggs": 2.0,
            "egg": 2.0,
            "ei": 2.0,
            "eier": 2.0
        ]
        guard let perPortion = countPerPortion[normalizedFood] else { return nil }
        return Portion.roundToIncrement(amount / perPortion)
    }
}
