import Foundation
import UIKit

struct UnsplashPhoto: Identifiable, Hashable, Decodable {
    struct Urls: Hashable, Decodable {
        let small: String
        let regular: String
        let thumb: String
    }

    struct Links: Hashable, Decodable {
        let html: String
        let downloadLocation: String?

        private enum CodingKeys: String, CodingKey {
            case html
            case downloadLocation = "download_location"
        }
    }

    struct User: Hashable, Decodable {
        struct Links: Hashable, Decodable {
            let html: String
        }

        let name: String
        let username: String
        let links: Links
    }

    let id: String
    let urls: Urls
    let links: Links
    let user: User
}

struct UnsplashSearchResponse: Decodable {
    let results: [UnsplashPhoto]
}

struct UnsplashClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case invalidImage
        case missingAccessKey
        case httpError(statusCode: Int, message: String?)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Unsplash URL."
            case .invalidResponse:
                return "Unexpected response from Unsplash."
            case .invalidImage:
                return "Unable to decode the image."
            case .missingAccessKey:
                return "Unsplash API key is missing."
            case let .httpError(statusCode, message):
                if let message, !message.isEmpty {
                    return "Unsplash error \(statusCode): \(message)"
                }
                return "Unsplash error \(statusCode)."
            case let .decodingError(message):
                return "Unsplash response decode failed: \(message)"
            }
        }
    }

    let accessKey: String
    let utmSource: String
    let session: URLSession

    init(accessKey: String, utmSource: String, session: URLSession = .shared) {
        self.accessKey = accessKey
        self.utmSource = utmSource
        self.session = session
    }

    func searchPhotos(query: String, perPage: Int = 24) async throws -> [UnsplashPhoto] {
        guard !accessKey.isEmpty else { throw ClientError.missingAccessKey }
        var components = URLComponents(string: "https://api.unsplash.com/search/photos")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "orientation", value: "squarish"),
            URLQueryItem(name: "content_filter", value: "high")
        ]
        guard let url = components?.url else { throw ClientError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            throw ClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
            return decoded.results
        } catch {
            throw ClientError.decodingError(error.localizedDescription)
        }
    }

    func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else { throw ClientError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            throw ClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        guard let image = UIImage(data: data) else { throw ClientError.invalidImage }
        return image
    }

    func trackDownload(for photo: UnsplashPhoto) async {
        guard let downloadLocation = photo.links.downloadLocation,
              let url = URL(string: downloadLocation) else { return }
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        _ = try? await session.data(for: request)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(UnsplashErrorResponse.self, from: data) {
            if let errors = decoded.errors, !errors.isEmpty {
                return errors.joined(separator: " ")
            }
            if let errorDescription = decoded.errorDescription {
                return errorDescription
            }
            if let error = decoded.error {
                return error
            }
        }
        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

private struct UnsplashErrorResponse: Decodable {
    let errors: [String]?
    let error: String?
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case errors
        case error
        case errorDescription = "error_description"
    }
}

enum UnsplashConfig {
    static let accessKeyInfoKey = "UNSPLASH_ACCESS_KEY"
    static let applicationIDInfoKey = "UNSPLASH_APPLICATION_ID"
    static let defaultUtmSource = "dragonhealth"

    static func accessKey() -> String? {
        if let key = KeychainStore.read(.unsplashAccessKey), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        let value = Bundle.main.object(forInfoDictionaryKey: accessKeyInfoKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func applicationID() -> String? {
        if let key = KeychainStore.read(.unsplashApplicationID), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        let value = Bundle.main.object(forInfoDictionaryKey: applicationIDInfoKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func client() -> UnsplashClient? {
        guard let key = accessKey() else { return nil }
        return UnsplashClient(accessKey: key, utmSource: defaultUtmSource)
    }

    static func withUtm(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        var items = components.queryItems ?? []
        items.removeAll(where: { $0.name.lowercased() == "utm_source" || $0.name.lowercased() == "utm_medium" })
        items.append(URLQueryItem(name: "utm_source", value: defaultUtmSource))
        items.append(URLQueryItem(name: "utm_medium", value: "referral"))
        components.queryItems = items
        return components.url?.absoluteString ?? urlString
    }
}
