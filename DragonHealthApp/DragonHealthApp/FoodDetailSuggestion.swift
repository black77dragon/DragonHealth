import Core
import Foundation
import UIKit

struct FoodDetailSuggestionRequest {
    let enteredName: String
    let referenceImage: UIImage?
    let referenceNotes: String?
}

struct FoodDetailSuggestion {
    let name: String
    let categoryID: UUID?
    let portionEquivalent: Double
    let amountPerPortion: Double?
    let unitID: UUID?
    let notes: String?
    let confidence: Double
}

struct OpenAIFoodDetailClient {
    let apiKey: String
    let model: String
    let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func suggestFood(
        request: FoodDetailSuggestionRequest,
        categories: [Core.Category],
        units: [Core.FoodUnit]
    ) async throws -> FoodDetailSuggestion {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenAIMealPhotoClient.ClientError.missingAPIKey }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIMealPhotoClient.ClientError.invalidURL
        }

        let payload = try makePayload(
            request: request,
            model: model,
            categories: categories,
            units: units
        )
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var requestURL = URLRequest(url: url)
        requestURL.httpMethod = "POST"
        requestURL.httpBody = bodyData
        requestURL.timeoutInterval = 35
        requestURL.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestURL.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let data = try await performRequestWithRetry(requestURL)

        let completion: FoodSuggestionChatCompletionResponse
        do {
            completion = try JSONDecoder().decode(FoodSuggestionChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAIMealPhotoClient.ClientError.decodingError(error.localizedDescription)
        }

        guard let content = completion.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIMealPhotoClient.ClientError.emptyResponse
        }

        let parsed = try parseSuggestion(from: content)
        return FoodDetailSuggestionBuilder(categories: categories, units: units).build(from: parsed, fallbackName: request.enteredName)
    }

    private func makePayload(
        request: FoodDetailSuggestionRequest,
        model: String,
        categories: [Core.Category],
        units: [Core.FoodUnit]
    ) throws -> [String: Any] {
        let allowedCategories = categories.map(\.name).joined(separator: ", ")
        let allowedUnits = units.map(\.symbol).joined(separator: ", ")
        var prompt = """
        Prepare a food library proposal for this food.
        Output JSON only.
        Rules:
        - Use one of these categories when possible: \(allowedCategories).
        - Use one of these unit symbols when possible: \(allowedUnits).
        - Return the canonical food name.
        - `portionEquivalent` is the default logged portion value. Use 1.0 for most foods. For drinks, use the liters equivalent (for example 250 ml -> 0.25).
        - `amountPerPortion` is the numeric amount for one portion, or null if unknown.
        - `amountUnit` must be one of the allowed unit symbols or null.
        - `notes` should be short and useful for a final manual review.
        - `confidence` must be between 0 and 1.
        - If uncertain, still make the best proposal and lower the confidence.
        Food name: \(request.enteredName)
        """

        if let referenceNotes = request.referenceNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !referenceNotes.isEmpty {
            prompt += "\nContext notes: \(referenceNotes)"
        }

        var content: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt
            ]
        ]

        if let image = request.referenceImage {
            guard let imageData = FoodImageStorage.thumbnailData(from: image) else {
                throw OpenAIMealPhotoClient.ClientError.invalidImageData
            }
            let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
            content.append(
                [
                    "type": "image_url",
                    "image_url": ["url": imageURL]
                ]
            )
        }

        return [
            "model": model,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "You prepare structured food library entries for a nutrition tracking app."
                ],
                [
                    "role": "user",
                    "content": content
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "food_library_suggestion",
                    "strict": true,
                    "schema": suggestionSchema()
                ]
            ]
        ]
    }

    private func suggestionSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["name", "categoryName", "portionEquivalent", "amountPerPortion", "amountUnit", "notes", "confidence"],
            "properties": [
                "name": ["type": "string"],
                "categoryName": ["type": ["string", "null"]],
                "portionEquivalent": ["type": ["number", "null"]],
                "amountPerPortion": ["type": ["number", "null"]],
                "amountUnit": ["type": ["string", "null"]],
                "notes": ["type": ["string", "null"]],
                "confidence": ["type": "number"]
            ]
        ]
    }

    private func parseSuggestion(from content: String) throws -> FoodSuggestionResponse {
        let candidateBlocks = [
            normalizeJSONContent(content),
            extractFirstJSONObject(from: content)
        ].compactMap { $0 }

        for block in candidateBlocks {
            do {
                return try JSONDecoder().decode(FoodSuggestionResponse.self, from: Data(block.utf8))
            } catch {
                continue
            }
        }

        throw OpenAIMealPhotoClient.ClientError.decodingError("Could not parse food suggestion from model output.")
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(FoodSuggestionOpenAIErrorResponse.self, from: data) {
            return decoded.error.message
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == true ? nil : raw
    }

    private func normalizeJSONContent(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            return trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let firstOpen = text.firstIndex(of: "{"),
              let lastClose = text.lastIndex(of: "}"),
              firstOpen < lastClose else {
            return nil
        }
        return String(text[firstOpen...lastClose]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> Data {
        let maxRetries = 1
        let retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIMealPhotoClient.ClientError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    return data
                }

                if retryableStatusCodes.contains(httpResponse.statusCode), attempt < maxRetries {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }

                let message = parseErrorMessage(from: data)
                throw OpenAIMealPhotoClient.ClientError.httpError(statusCode: httpResponse.statusCode, message: message)
            } catch {
                if let mapped = mapNetworkError(error) {
                    if mapped.isRetryable, attempt < maxRetries {
                        try await Task.sleep(nanoseconds: 700_000_000)
                        continue
                    }
                    throw mapped.error
                }
                throw error
            }
        }

        throw OpenAIMealPhotoClient.ClientError.invalidResponse
    }

    private func mapNetworkError(_ error: Error) -> (error: OpenAIMealPhotoClient.ClientError, isRetryable: Bool)? {
        if error is CancellationError {
            return (.requestCancelled, false)
        }
        guard let urlError = error as? URLError else { return nil }

        switch urlError.code {
        case .timedOut:
            return (.requestTimedOut, true)
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return (.networkUnavailable, true)
        case .notConnectedToInternet:
            return (.networkUnavailable, false)
        case .cancelled:
            return (.requestCancelled, false)
        default:
            return (.networkUnavailable, false)
        }
    }
}

private struct FoodDetailSuggestionBuilder {
    let categories: [Core.Category]
    let units: [Core.FoodUnit]

    func build(from response: FoodSuggestionResponse, fallbackName: String) -> FoodDetailSuggestion {
        let resolvedName = trimmed(response.name) ?? trimmed(fallbackName) ?? fallbackName
        let categoryID = resolveCategoryID(for: response.categoryName)
        let amountValue = sanitizeAmountValue(response.amountPerPortion, unit: response.amountUnit)
        let unitID = amountValue == nil ? nil : resolveUnitID(for: response.amountUnit)
        let portionEquivalent = resolvePortionEquivalent(
            categoryID: categoryID,
            proposedPortion: response.portionEquivalent,
            amountPerPortion: amountValue,
            unitID: unitID
        )
        let notes = trimmed(response.notes)
        let confidence = min(max(response.confidence, 0), 1)

        return FoodDetailSuggestion(
            name: resolvedName,
            categoryID: categoryID,
            portionEquivalent: portionEquivalent,
            amountPerPortion: amountValue,
            unitID: unitID,
            notes: notes,
            confidence: confidence
        )
    }

    private func resolvePortionEquivalent(
        categoryID: UUID?,
        proposedPortion: Double?,
        amountPerPortion: Double?,
        unitID: UUID?
    ) -> Double {
        let category = categoryID.flatMap { id in
            categories.first(where: { $0.id == id })
        }
        if let amountPerPortion,
           let liters = DrinkRules.liters(from: amountPerPortion, unitID: unitID, units: units),
           category.map(DrinkRules.isDrinkCategory) == true {
            return max(Portion.drinkIncrement, DrinkRules.roundedLiters(liters))
        }

        let increment = DrinkRules.portionIncrement(for: category)
        let rawValue = (proposedPortion ?? 1.0).isFinite ? (proposedPortion ?? 1.0) : 1.0
        return max(increment, Portion.roundToIncrement(rawValue, increment: increment))
    }

    private func sanitizeAmountValue(_ value: Double?, unit: String?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        switch normalize(unit ?? "") {
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            return value.rounded()
        case "l", "liter", "liters", "litre", "litres":
            return Portion.roundToIncrement(value, increment: Portion.drinkIncrement)
        default:
            return Portion.roundToIncrement(value)
        }
    }

    private func resolveCategoryID(for rawValue: String?) -> UUID? {
        let normalized = normalize(rawValue ?? "")
        guard !normalized.isEmpty else { return nil }

        if let exact = categories.first(where: { normalize($0.name) == normalized }) {
            return exact.id
        }

        let requestedTokens = Set(normalized.split(separator: " ").map(String.init))
        let scored = categories.compactMap { category -> (UUID, Int)? in
            let categoryTokens = Set(normalize(category.name).split(separator: " ").map(String.init))
            let score = requestedTokens.intersection(categoryTokens).count
            guard score > 0 else { return nil }
            return (category.id, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func resolveUnitID(for rawValue: String?) -> UUID? {
        let normalized = normalize(rawValue ?? "")
        guard !normalized.isEmpty else { return nil }

        let preferredSymbol: String
        switch normalized {
        case "g", "gram", "grams", "gramm":
            preferredSymbol = "g"
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            preferredSymbol = "ml"
        case "l", "liter", "liters", "litre", "litres":
            preferredSymbol = "l"
        case "pc", "piece", "pieces", "stuck", "stueck", "stk":
            preferredSymbol = "pc"
        default:
            preferredSymbol = normalized
        }

        return units.first(where: { normalize($0.symbol) == preferredSymbol })?.id
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue?.isEmpty == true ? nil : trimmedValue
    }

    private func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9äöüß\\s]", with: " ", options: .regularExpression)
        return cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private struct FoodSuggestionChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct FoodSuggestionResponse: Decodable {
    let name: String
    let categoryName: String?
    let portionEquivalent: Double?
    let amountPerPortion: Double?
    let amountUnit: String?
    let notes: String?
    let confidence: Double
}

private struct FoodSuggestionOpenAIErrorResponse: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}
