import Foundation
import UniformTypeIdentifiers
import Core
import UIKit

struct DocumentStorage {
    struct ImportResult {
        let title: String
        let fileName: String
        let fileType: Core.DocumentType
    }

    private static let directoryName = "HealthDocuments"

    static func url(for fileName: String) -> URL {
        let directory = (try? storageDirectory()) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent(fileName)
    }

    static func importDocument(from url: URL) throws -> ImportResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileType = resolveType(for: url) else {
            throw DocumentStorageError(message: "Only PDF and image files are supported.")
        }

        let title = defaultTitle(for: url)
        let fileExtension = resolvedExtension(for: url, fileType: fileType)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = try storageDirectory().appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
        } catch {
            throw DocumentStorageError(message: "Unable to save the document. Please try again.")
        }

        return ImportResult(title: title, fileName: fileName, fileType: fileType)
    }

    static func deleteDocument(fileName: String) throws {
        let destinationURL = url(for: fileName)
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: destinationURL)
        } catch {
            throw DocumentStorageError(message: "Unable to remove the document file.")
        }
    }

    private static func storageDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DocumentStorageError(message: "Unable to access the app documents folder.")
        }
        let directory = documentsDirectory.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    private static func resolveType(for url: URL) -> Core.DocumentType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
        }
        return nil
    }

    private static func resolvedExtension(for url: URL, fileType: Core.DocumentType) -> String {
        let currentExtension = url.pathExtension.lowercased()
        if !currentExtension.isEmpty { return currentExtension }
        switch fileType {
        case .pdf:
            return "pdf"
        case .image:
            return "jpg"
        }
    }

    private static func defaultTitle(for url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Document" : trimmed
    }
}

private struct DocumentStorageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum FoodImageStorage {
    private static let directoryName = "FoodImages"
    // Largest UI thumbnail is 44pt; store at 3x for crispness while keeping files small.
    private static let thumbnailPixelSize: CGFloat = 132
    private static let thumbnailCompressionQuality: CGFloat = 0.82
    private static let thumbnailMigrationMarker = ".food_thumbnails_v1"

    static func url(for fileName: String) -> URL {
        let directory = (try? storageDirectory()) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent(fileName)
    }

    static func saveImageData(_ data: Data, fileName: String) throws {
        let destinationURL = try storageDirectory().appendingPathComponent(fileName)
        try data.write(to: destinationURL, options: .atomic)
    }

    static func thumbnailData(from image: UIImage) -> Data? {
        let thumbnail = thumbnailImage(from: image)
        return thumbnail.jpegData(compressionQuality: thumbnailCompressionQuality)
    }

    static func resizeExistingImagesIfNeeded(imagePaths: [String]) {
        guard !imagePaths.isEmpty else { return }
        guard !hasCompletedThumbnailMigration() else { return }
        let uniquePaths = Set(imagePaths)
        for path in uniquePaths {
            let fileURL = url(for: path)
            guard let image = UIImage(contentsOfFile: fileURL.path) else { continue }
            guard needsResize(image) else { continue }
            guard let data = thumbnailData(from: image) else { continue }
            try? data.write(to: fileURL, options: .atomic)
        }
        markThumbnailMigrationComplete()
    }

    static func deleteImage(fileName: String) throws {
        let destinationURL = url(for: fileName)
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        try FileManager.default.removeItem(at: destinationURL)
    }

    private static func needsResize(_ image: UIImage) -> Bool {
        let maxDimension = max(image.size.width * image.scale, image.size.height * image.scale)
        return maxDimension > thumbnailPixelSize
    }

    static func thumbnailImage(from image: UIImage) -> UIImage {
        guard needsResize(image) else { return image }
        let targetSize = CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize)
        let imageWidth = image.size.width * image.scale
        let imageHeight = image.size.height * image.scale
        let scale = max(targetSize.width / imageWidth, targetSize.height / imageHeight)
        let scaledSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    private static func storageDirectory() throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DocumentStorageError(message: "Unable to access the app documents folder.")
        }
        let directory = documentsDirectory.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    private static func hasCompletedThumbnailMigration() -> Bool {
        guard let markerURL = try? storageDirectory().appendingPathComponent(thumbnailMigrationMarker) else {
            return false
        }
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    private static func markThumbnailMigrationComplete() {
        guard let markerURL = try? storageDirectory().appendingPathComponent(thumbnailMigrationMarker) else {
            return
        }
        try? Data("done".utf8).write(to: markerURL, options: .atomic)
    }
}
