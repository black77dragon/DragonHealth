import Foundation
import UIKit
import Combine
import Core

@MainActor
final class FoodImageSearchModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [UnsplashPhoto] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: UnsplashClient?

    init(client: UnsplashClient? = nil) {
        self.client = client ?? UnsplashConfig.client()
    }

    var isConfigured: Bool {
        client != nil
    }

    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            errorMessage = nil
            return
        }
        guard let client else {
            results = []
            errorMessage = "Unsplash Access Key is missing. Add it in Manage > Unsplash or set UNSPLASH_ACCESS_KEY in Info.plist."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let photos = try await client.searchPhotos(query: trimmedQuery)
            results = photos
            errorMessage = photos.isEmpty ? "No photos found. Try another search." : nil
        } catch {
            results = []
            errorMessage = "Unsplash search failed: \(error.localizedDescription)"
        }
    }

    func selectPhoto(_ photo: UnsplashPhoto) async throws -> UIImage {
        guard let client else { throw UnsplashClient.ClientError.missingAccessKey }
        Task { await client.trackDownload(for: photo) }
        let image = try await client.downloadImage(from: photo.urls.small)
        return image
    }

    func attribution(for photo: UnsplashPhoto) -> FoodImageAttribution {
        FoodImageAttribution(
            source: .unsplash,
            sourceID: photo.id,
            sourceURL: UnsplashConfig.withUtm(photo.links.html),
            remoteURL: photo.urls.small,
            attributionName: photo.user.name,
            attributionURL: UnsplashConfig.withUtm(photo.user.links.html)
        )
    }
}

struct FoodImageAttribution: Hashable, Sendable {
    let source: Core.FoodImageSource
    let sourceID: String
    let sourceURL: String
    let remoteURL: String
    let attributionName: String
    let attributionURL: String
}

extension FoodItem {
    var foodImageAttribution: FoodImageAttribution? {
        guard let source = imageSource,
              let sourceID = imageSourceID,
              let sourceURL = imageSourceURL,
              let remoteURL = imageRemoteURL,
              let attributionName = imageAttributionName,
              let attributionURL = imageAttributionURL else {
            return nil
        }
        return FoodImageAttribution(
            source: source,
            sourceID: sourceID,
            sourceURL: sourceURL,
            remoteURL: remoteURL,
            attributionName: attributionName,
            attributionURL: attributionURL
        )
    }
}
