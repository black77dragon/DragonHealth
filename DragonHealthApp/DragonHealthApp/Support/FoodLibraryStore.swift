import Foundation
import Core
import CoreDB

struct FoodLibraryStore {
    private let db: any DBGateway

    nonisolated init(db: any DBGateway) {
        self.db = db
    }

    func fetchAll() async throws -> [FoodItem] {
        try await db.fetchFoodItems()
    }

    func save(_ item: FoodItem) async throws -> [FoodItem] {
        try await db.upsertFoodItem(item)
        return try await fetchAll()
    }

    func saveAll(_ items: [FoodItem]) async throws -> [FoodItem] {
        guard !items.isEmpty else { return try await fetchAll() }
        for item in items {
            try await db.upsertFoodItem(item)
        }
        return try await fetchAll()
    }

    func delete(_ item: FoodItem) async throws -> [FoodItem] {
        try await db.deleteFoodItem(id: item.id)
        if let imagePath = item.imagePath {
            try? FoodImageStorage.deleteImage(fileName: imagePath)
        }
        return try await fetchAll()
    }
}
