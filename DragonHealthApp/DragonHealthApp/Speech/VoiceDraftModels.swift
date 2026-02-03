import Foundation

struct VoiceDraft: Identifiable, Hashable {
    let id: UUID = UUID()
    var transcript: String
    var mealSlotID: UUID?
    var items: [VoiceDraftItem]
}

struct VoiceDraftItem: Identifiable, Hashable {
    let id: UUID = UUID()
    var foodText: String
    var matchedFoodID: UUID?
    var categoryID: UUID?
    var amountValue: Double?
    var amountUnitID: UUID?
    var portion: Double?
    var notes: String?
}
