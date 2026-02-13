import Core
import Foundation
import UIKit

struct MealPhotoDetection: Hashable {
    let foodName: String
    let portionEstimate: Double
    let amountValue: Double?
    let amountUnit: String?
    let confidence: Double
    let categoryHint: String?
    let notes: String?
}

struct MealPhotoDraftItem: Identifiable, Hashable {
    let id: UUID = UUID()
    var foodText: String
    var matchedFoodID: UUID?
    var categoryID: UUID?
    var amountValue: Double?
    var amountUnitID: UUID?
    var portion: Double?
    var confidence: Double
    var notes: String?
}

enum MealPhotoAIConfig {
    static let apiKeyInfoKey = "OPENAI_API_KEY"
    static let modelInfoKey = "OPENAI_VISION_MODEL"
    static let defaultModel = "gpt-4.1-mini"

    static func apiKey() -> String? {
        if let key = KeychainStore.read(.openAIApiKey),
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        let value = Bundle.main.object(forInfoDictionaryKey: apiKeyInfoKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func model() -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: modelInfoKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    static func client() -> OpenAIMealPhotoClient? {
        guard let apiKey = apiKey() else { return nil }
        return OpenAIMealPhotoClient(apiKey: apiKey, model: model())
    }
}

struct OpenAIMealPhotoClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidImageData
        case invalidResponse
        case emptyResponse
        case decodingError(String)
        case requestTimedOut
        case networkUnavailable
        case requestCancelled
        case httpError(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key is missing."
            case .invalidURL:
                return "Invalid OpenAI URL."
            case .invalidImageData:
                return "Unable to process selected image."
            case .invalidResponse:
                return "Unexpected response from OpenAI."
            case .emptyResponse:
                return "No meal items were returned."
            case .decodingError(let message):
                return "OpenAI response decode failed: \(message)"
            case .requestTimedOut:
                return "The request timed out. Please try again."
            case .networkUnavailable:
                return "No internet connection. Check network access and try again."
            case .requestCancelled:
                return "The request was cancelled."
            case .httpError(let statusCode, let message):
                if let message, !message.isEmpty {
                    return "OpenAI error \(statusCode): \(message)"
                }
                return "OpenAI error \(statusCode)."
            }
        }
    }

    let apiKey: String
    let model: String
    let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func analyzeMeal(
        image: UIImage,
        foodNames: [String],
        categoryNames: [String]
    ) async throws -> [MealPhotoDetection] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ClientError.missingAPIKey }
        guard let imageData = image.preparedForMealAnalysisJPEGData() else {
            throw ClientError.invalidImageData
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw ClientError.invalidURL
        }

        let payload = makePayload(
            imageData: imageData,
            model: model,
            foodNames: foodNames,
            categoryNames: categoryNames
        )
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let data = try await performRequestWithRetry(request)

        let completion: ChatCompletionResponse
        do {
            completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw ClientError.decodingError(error.localizedDescription)
        }

        guard let content = completion.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.emptyResponse
        }

        return try parseDetections(from: content)
    }

    private func makePayload(
        imageData: Data,
        model: String,
        foodNames: [String],
        categoryNames: [String]
    ) -> [String: Any] {
        let allowedFoods = Array(foodNames.prefix(140)).joined(separator: ", ")
        let allowedCategories = categoryNames.joined(separator: ", ")
        let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let prompt = """
        Analyze this meal image and return all visible and plausible food items with estimated portions.
        Output JSON only.
        Rules:
        - Return all distinct food items you can identify (not just a sample), between 1 and 20 items.
        - If a food is only a plausible guess, include it with a lower confidence instead of omitting it.
        - Do not duplicate the same food item multiple times.
        - Use `portionEstimate` in 0.1 steps between 0.1 and 6.0.
        - If known, set `amountValue` and `amountUnit` using one of: g, ml, pc, portion.
        - If unknown, set amount fields to null.
        - Set `confidence` between 0 and 1.
        - Prefer category hints from this list when possible: \(allowedCategories).
        - If a close match exists, prefer these local food names: \(allowedFoods).
        """

        return [
            "model": model,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a nutrition logging assistant for portion-based meal tracking."
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": ["url": imageURL]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "meal_photo_detection",
                    "strict": true,
                    "schema": mealPhotoSchema()
                ]
            ]
        ]
    }

    private func mealPhotoSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["items"],
            "properties": [
                "items": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 20,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["foodName", "portionEstimate", "amountValue", "amountUnit", "confidence", "categoryHint", "notes"],
                        "properties": [
                            "foodName": ["type": "string"],
                            "portionEstimate": ["type": "number"],
                            "amountValue": ["type": ["number", "null"]],
                            "amountUnit": ["type": ["string", "null"]],
                            "confidence": ["type": "number"],
                            "categoryHint": ["type": ["string", "null"]],
                            "notes": ["type": ["string", "null"]]
                        ]
                    ]
                ]
            ]
        ]
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
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

    private func parseDetections(from content: String) throws -> [MealPhotoDetection] {
        let candidateBlocks = [
            normalizeJSONContent(content),
            extractFirstJSONObject(from: content)
        ].compactMap { $0 }

        for block in candidateBlocks {
            do {
                let parsed = try JSONDecoder().decode(MealPhotoDetectionResponse.self, from: Data(block.utf8))
                return parsed.items.map {
                    MealPhotoDetection(
                        foodName: $0.foodName,
                        portionEstimate: $0.portionEstimate,
                        amountValue: $0.amountValue,
                        amountUnit: $0.amountUnit,
                        confidence: $0.confidence,
                        categoryHint: $0.categoryHint,
                        notes: $0.notes
                    )
                }
            } catch {
                continue
            }
        }

        throw ClientError.decodingError("Could not parse meal items from model output.")
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> Data {
        let maxRetries = 1
        let retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClientError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    return data
                }

                if retryableStatusCodes.contains(httpResponse.statusCode), attempt < maxRetries {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }

                let message = parseErrorMessage(from: data)
                throw ClientError.httpError(statusCode: httpResponse.statusCode, message: message)
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

        throw ClientError.invalidResponse
    }

    private func mapNetworkError(_ error: Error) -> (error: ClientError, isRetryable: Bool)? {
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

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let firstOpen = text.firstIndex(of: "{"),
              let lastClose = text.lastIndex(of: "}"),
              firstOpen < lastClose else {
            return nil
        }
        return String(text[firstOpen...lastClose]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MealPhotoDraftBuilder {
    let categories: [Core.Category]
    let foodItems: [FoodItem]
    let units: [FoodUnit]

    func makeDraftItems(from detections: [MealPhotoDetection]) -> [MealPhotoDraftItem] {
        let availableFoods = foodItems.filter { !$0.kind.isComposite }
        return detections.compactMap { detection in
            let normalizedFoodName = normalizeText(detection.foodName)
            guard !normalizedFoodName.isEmpty else { return nil }

            let matchedFood = matchFood(normalizedFoodName, in: availableFoods)
            let amountUnitID = resolveUnitID(for: detection.amountUnit)
            let amountValue = sanitizedAmountValue(detection.amountValue)
            let portion = resolvedPortion(
                for: detection,
                matchedFood: matchedFood,
                amountValue: amountValue,
                amountUnitID: amountUnitID
            )
            let categoryID = matchedFood?.categoryID ?? matchCategoryID(for: detection.categoryHint ?? detection.foodName)
            let trimmedNotes = detection.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = trimmedNotes?.isEmpty == true ? nil : trimmedNotes

            return MealPhotoDraftItem(
                foodText: matchedFood?.name ?? detection.foodName,
                matchedFoodID: matchedFood?.id,
                categoryID: categoryID,
                amountValue: amountValue,
                amountUnitID: amountUnitID,
                portion: portion,
                confidence: min(max(detection.confidence, 0), 1),
                notes: notes
            )
        }
    }

    private func resolvedPortion(
        for detection: MealPhotoDetection,
        matchedFood: FoodItem?,
        amountValue: Double?,
        amountUnitID: UUID?
    ) -> Double? {
        if let matchedFood,
           let amountValue,
           let amountPerPortion = matchedFood.amountPerPortion,
           amountPerPortion > 0,
           let unitID = matchedFood.unitID,
           let amountUnitID,
           unitID == amountUnitID {
            let value = (amountValue / amountPerPortion) * matchedFood.portionEquivalent
            let rounded = Portion.roundToIncrement(value)
            let clamped = clampPortion(rounded)
            if clamped > 0 { return clamped }
        }

        let estimated = clampPortion(Portion.roundToIncrement(detection.portionEstimate))
        if estimated > 0 { return estimated }

        if let matchedFood {
            let fallback = clampPortion(Portion.roundToIncrement(matchedFood.portionEquivalent))
            if fallback > 0 { return fallback }
        }
        return nil
    }

    private func clampPortion(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0.1), 6.0)
    }

    private func sanitizedAmountValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Portion.roundToIncrement(value)
    }

    private func resolveUnitID(for rawUnit: String?) -> UUID? {
        guard let rawUnit else { return nil }
        let normalized = normalizeText(rawUnit)
        let preferredSymbol: String?
        switch normalized {
        case "g", "gram", "grams", "gramm":
            preferredSymbol = "g"
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            preferredSymbol = "ml"
        case "pc", "piece", "pieces", "stuck", "stueck", "stk":
            preferredSymbol = "pc"
        default:
            preferredSymbol = normalized
        }
        guard let preferredSymbol else { return nil }
        return units.first(where: { normalizeText($0.symbol) == preferredSymbol })?.id
    }

    private func matchCategoryID(for hint: String) -> UUID? {
        let normalizedHint = normalizeText(hint)
        guard !normalizedHint.isEmpty else { return nil }

        if let direct = categories.first(where: { normalizeText($0.name) == normalizedHint }) {
            return direct.id
        }

        let hintTokens = Set(normalizedHint.split(separator: " ").map(String.init))
        let scored = categories.compactMap { category -> (UUID, Int)? in
            let categoryTokens = Set(normalizeText(category.name).split(separator: " ").map(String.init))
            let score = hintTokens.intersection(categoryTokens).count
            guard score > 0 else { return nil }
            return (category.id, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func matchFood(_ normalizedFoodName: String, in foods: [FoodItem]) -> FoodItem? {
        if let exact = foods.first(where: { normalizeText($0.name) == normalizedFoodName }) {
            return exact
        }

        let requestedTokens = Set(normalizedFoodName.split(separator: " ").map(String.init))
        guard !requestedTokens.isEmpty else { return nil }

        let scored = foods.compactMap { food -> (FoodItem, Int)? in
            let nameTokens = Set(normalizeText(food.name).split(separator: " ").map(String.init))
            let score = requestedTokens.intersection(nameTokens).count
            guard score > 0 else { return nil }
            return (food, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func normalizeText(_ text: String) -> String {
        let lowered = text.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9äöüß\\s]", with: " ", options: .regularExpression)
        return cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct MealPhotoDetectionResponse: Decodable {
    struct Item: Decodable {
        let foodName: String
        let portionEstimate: Double
        let amountValue: Double?
        let amountUnit: String?
        let confidence: Double
        let categoryHint: String?
        let notes: String?
    }

    let items: [Item]
}

private struct OpenAIErrorResponse: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}

private extension UIImage {
    func preparedForMealAnalysisJPEGData(maxDimension: CGFloat = 1024, compressionQuality: CGFloat = 0.75) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let sourceSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let longest = max(sourceSize.width, sourceSize.height)
        guard longest > 0 else { return nil }

        let ratio = min(1, maxDimension / longest)
        let targetSize = CGSize(width: floor(sourceSize.width * ratio), height: floor(sourceSize.height * ratio))

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: compressionQuality)
    }
}
