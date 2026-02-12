import SwiftUI
import Core
import UIKit
import UniformTypeIdentifiers

struct FoodLibraryTransferView: View {
    @EnvironmentObject private var store: AppStore

    @State private var exportFile: TransferFile?
    @State private var showingImportPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingReport = false
    @State private var reportMessage = ""
    @State private var pendingPlan: FoodImportPlan?
    @State private var lastImportedFileName: String?
    @State private var showingConflictModeDialog = false
    @State private var showingNoConflictConfirm = false
    @State private var showingBulkReplaceConfirm = false
    @State private var showingReviewDecisionDialog = false
    @State private var reviewSession: FoodImportReviewSession?
    @State private var isApplyingImport = false
    @State private var lastReport: TransferOperationReport?
    @State private var pendingExportReport: TransferOperationReport?

    var body: some View {
        Form {
            Section("Export") {
                Button {
                    exportFoodLibrary()
                } label: {
                    Label("Export Food Library", systemImage: "square.and.arrow.up")
                }
                .glassButton(.text)

                Text("Exports all food items with full details as JSON.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Import") {
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Food Library", systemImage: "square.and.arrow.down")
                }
                .glassButton(.text)
                .disabled(isApplyingImport)

                if let plan = pendingPlan {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to import")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(importPlanSummary(plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isApplyingImport {
                    ProgressView("Applying import…")
                        .font(.caption)
                }
            }

            Section("Conflict Handling") {
                Text("If existing foods are found by ID, you can review each conflict one by one or replace all existing items in bulk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let report = lastReport {
                Section("Last Report") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(report.status.color)
                            .frame(width: 10, height: 10)
                        Text("RAG Status: \(report.status.label)")
                            .font(.subheadline)
                    }
                    Text(report.operationLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Processed: \(report.processedCount) • Added: \(report.addedCount) • Changed: \(report.changedCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let fileName = report.fileName {
                        Text("File: \(fileName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Food Library Transfer")
        .sheet(item: $exportFile, onDismiss: clearExportFile) { file in
            ActivityShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showingImportPicker) {
            FoodLibraryImportPicker { url in
                Task {
                    await prepareImport(from: url)
                }
            } onDismiss: {
                showingImportPicker = false
            }
        }
        .confirmationDialog("Existing Foods Found", isPresented: $showingConflictModeDialog, titleVisibility: .visible) {
            Button("Review One by One") {
                startReviewImport()
            }
            Button("Replace All Existing") {
                showingBulkReplaceConfirm = true
            }
            Button("Cancel", role: .cancel) {
                pendingPlan = nil
            }
        } message: {
            if let plan = pendingPlan {
                Text("\(plan.conflicts.count) existing items detected. Choose how to handle conflicts.")
            }
        }
        .confirmationDialog(reviewDialogTitle, isPresented: $showingReviewDecisionDialog, titleVisibility: .visible, presenting: reviewSession?.currentConflict) { _ in
            Button("Replace Existing") {
                applyReviewDecision(.replace)
            }
            Button("Keep Existing") {
                applyReviewDecision(.keep)
            }
            Button("Import as New Copy") {
                applyReviewDecision(.importAsCopy)
            }
            Button("Cancel Review", role: .cancel) {
                cancelReviewImport()
            }
        } message: { conflict in
            Text(reviewMessage(for: conflict))
        }
        .alert("Import Food Library", isPresented: $showingNoConflictConfirm) {
            Button("Import") {
                Task {
                    await executeNoConflictImport()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPlan = nil
            }
        } message: {
            if let plan = pendingPlan {
                Text(importPlanSummary(plan))
            }
        }
        .alert("Replace Existing Foods", isPresented: $showingBulkReplaceConfirm) {
            Button("Replace") {
                Task {
                    await executeBulkReplaceImport()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPlan = nil
            }
        } message: {
            if let plan = pendingPlan {
                Text("This will replace \(plan.conflicts.count) existing items and add \(plan.newItems.count) new items.")
            }
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Operation Report", isPresented: $showingReport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportMessage)
        }
    }

    private var reviewDialogTitle: String {
        guard let session = reviewSession else { return "Resolve Conflict" }
        return "Resolve Conflict (\(session.index + 1)/\(session.plan.conflicts.count))"
    }

    private func exportFoodLibrary() {
        do {
            let payload = FoodLibraryTransferPayload(
                formatVersion: 1,
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                itemCount: store.foodItems.count,
                items: store.foodItems.map { item in
                    FoodLibraryTransferItem(
                        id: item.id.uuidString,
                        name: item.name,
                        categoryID: item.categoryID.uuidString,
                        categoryName: categoryName(for: item.categoryID),
                        portionEquivalent: item.portionEquivalent,
                        amountPerPortion: item.amountPerPortion,
                        unitID: item.unitID?.uuidString,
                        unitName: unitName(for: item.unitID),
                        unitSymbol: unitSymbol(for: item.unitID),
                        notes: item.notes,
                        isFavorite: item.isFavorite,
                        imagePath: item.imagePath,
                        imageRemoteURL: item.imageRemoteURL,
                        imageSource: item.imageSource?.rawValue,
                        imageSourceID: item.imageSourceID,
                        imageAttributionName: item.imageAttributionName,
                        imageAttributionURL: item.imageAttributionURL,
                        imageSourceURL: item.imageSourceURL,
                        kind: item.kind.rawValue,
                        compositeComponents: item.compositeComponents.map {
                            FoodLibraryTransferComponent(
                                foodItemID: $0.foodItemID.uuidString,
                                portionMultiplier: $0.portionMultiplier
                            )
                        }
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let data = try encoder.encode(payload)
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName())
            try data.write(to: fileURL, options: .atomic)
            pendingExportReport = TransferOperationReport(
                operation: .export,
                status: .green,
                processedCount: payload.itemCount,
                addedCount: 0,
                changedCount: 0,
                fileName: fileURL.lastPathComponent
            )
            exportFile = TransferFile(url: fileURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "dragonhealth-food-library-\(formatter.string(from: Date())).json"
    }

    private func clearExportFile() {
        if let pendingExportReport {
            presentReport(pendingExportReport)
            self.pendingExportReport = nil
        }
        guard let url = exportFile?.url else { return }
        try? FileManager.default.removeItem(at: url)
        exportFile = nil
    }

    private func prepareImport(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let payload = try decoder.decode(FoodLibraryImportPayload.self, from: data)
            let plan = makeImportPlan(from: payload)
            guard plan.validCount > 0 else {
                errorMessage = "No valid food items found in this file."
                showingError = true
                return
            }

            pendingPlan = plan
            lastImportedFileName = url.lastPathComponent

            if plan.conflicts.isEmpty {
                showingNoConflictConfirm = true
            } else {
                showingConflictModeDialog = true
            }
        } catch {
            errorMessage = "Unable to read import file: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func makeImportPlan(from payload: FoodLibraryImportPayload) -> FoodImportPlan {
        var parsed: [Core.FoodItem] = []
        var invalidCount = 0

        for item in payload.items {
            guard let food = normalizeImportedItem(item) else {
                invalidCount += 1
                continue
            }
            parsed.append(food)
        }

        var dedupedByID: [UUID: Core.FoodItem] = [:]
        var insertionOrder: [UUID] = []
        var duplicateInFileCount = 0

        for item in parsed {
            if dedupedByID[item.id] == nil {
                insertionOrder.append(item.id)
            } else {
                duplicateInFileCount += 1
            }
            dedupedByID[item.id] = item
        }

        let uniqueItems = insertionOrder.compactMap { dedupedByID[$0] }
        let existingByID = Dictionary(uniqueKeysWithValues: store.foodItems.map { ($0.id, $0) })

        var newItems: [Core.FoodItem] = []
        var conflicts: [FoodImportConflict] = []

        for item in uniqueItems {
            if let existing = existingByID[item.id] {
                conflicts.append(FoodImportConflict(existing: existing, incoming: item))
            } else {
                newItems.append(item)
            }
        }

        return FoodImportPlan(
            totalInFile: payload.items.count,
            invalidCount: invalidCount,
            duplicateInFileCount: duplicateInFileCount,
            newItems: newItems,
            conflicts: conflicts
        )
    }

    private func normalizeImportedItem(_ raw: FoodLibraryImportItem) -> Core.FoodItem? {
        guard let id = raw.id.flatMap(UUID.init(uuidString:)) else { return nil }
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }

        let fallbackCategoryID = store.categories.first?.id ?? UUID()
        let categoryID = raw.categoryID.flatMap(UUID.init(uuidString:)) ?? fallbackCategoryID

        let portionEquivalent: Double = {
            guard let value = raw.portionEquivalent, value.isFinite, value > 0 else { return 1.0 }
            return Portion.roundToIncrement(value)
        }()

        let amountPerPortion: Double? = {
            guard let value = raw.amountPerPortion, value.isFinite, value > 0 else { return nil }
            return Portion.roundToIncrement(value)
        }()

        let unitID = raw.unitID.flatMap(UUID.init(uuidString:))
        let notes = normalizedText(raw.notes)
        let kind = Core.FoodItemKind(rawValue: raw.kind ?? "") ?? .single
        var components: [Core.FoodComponent] = []
        if kind.isComposite {
            components = raw.compositeComponents.compactMap { component in
                guard let componentID = component.foodItemID.flatMap(UUID.init(uuidString:)), componentID != id else {
                    return nil
                }
                guard let multiplier = component.portionMultiplier,
                      multiplier.isFinite,
                      multiplier > 0 else {
                    return nil
                }
                return Core.FoodComponent(foodItemID: componentID, portionMultiplier: max(0.1, multiplier))
            }
        }

        return Core.FoodItem(
            id: id,
            name: name,
            categoryID: categoryID,
            portionEquivalent: portionEquivalent,
            amountPerPortion: amountPerPortion,
            unitID: amountPerPortion == nil ? nil : unitID,
            notes: notes,
            isFavorite: raw.isFavorite ?? false,
            imagePath: normalizedText(raw.imagePath),
            imageRemoteURL: normalizedText(raw.imageRemoteURL),
            imageSource: raw.imageSource.flatMap(Core.FoodImageSource.init(rawValue:)),
            imageSourceID: normalizedText(raw.imageSourceID),
            imageAttributionName: normalizedText(raw.imageAttributionName),
            imageAttributionURL: normalizedText(raw.imageAttributionURL),
            imageSourceURL: normalizedText(raw.imageSourceURL),
            kind: kind,
            compositeComponents: components
        )
    }

    private func executeNoConflictImport() async {
        guard let plan = pendingPlan else { return }
        let outcome = FoodImportOutcome(
            addedCount: plan.newItems.count,
            replacedCount: 0,
            copiedCount: 0,
            keptExistingCount: 0,
            skippedCount: plan.skippedBeforeApplyCount
        )
        await applyImport(items: plan.newItems, outcome: outcome)
    }

    private func executeBulkReplaceImport() async {
        guard let plan = pendingPlan else { return }
        let items = plan.newItems + plan.conflicts.map(\.incoming)
        let outcome = FoodImportOutcome(
            addedCount: plan.newItems.count,
            replacedCount: plan.conflicts.count,
            copiedCount: 0,
            keptExistingCount: 0,
            skippedCount: plan.skippedBeforeApplyCount
        )
        await applyImport(items: items, outcome: outcome)
    }

    private func startReviewImport() {
        guard let plan = pendingPlan else { return }
        reviewSession = FoodImportReviewSession(plan: plan)
        showingReviewDecisionDialog = true
    }

    private func applyReviewDecision(_ decision: FoodImportConflictDecision) {
        guard var session = reviewSession,
              let conflict = session.currentConflict else {
            cancelReviewImport()
            return
        }

        switch decision {
        case .replace:
            session.replacements.append(conflict.incoming)
        case .keep:
            session.keptExistingCount += 1
        case .importAsCopy:
            session.copies.append(copyFoodItem(withNewID: conflict.incoming))
        }

        session.index += 1

        if session.index >= session.plan.conflicts.count {
            reviewSession = nil
            showingReviewDecisionDialog = false

            let items = session.plan.newItems + session.replacements + session.copies
            let outcome = FoodImportOutcome(
                addedCount: session.plan.newItems.count,
                replacedCount: session.replacements.count,
                copiedCount: session.copies.count,
                keptExistingCount: session.keptExistingCount,
                skippedCount: session.plan.skippedBeforeApplyCount
            )

            Task {
                await applyImport(items: items, outcome: outcome)
            }
            return
        }

        reviewSession = session
        DispatchQueue.main.async {
            showingReviewDecisionDialog = true
        }
    }

    private func cancelReviewImport() {
        reviewSession = nil
        pendingPlan = nil
        showingReviewDecisionDialog = false
    }

    private func applyImport(items: [Core.FoodItem], outcome: FoodImportOutcome) async {
        guard !items.isEmpty || outcome.skippedCount > 0 else {
            pendingPlan = nil
            return
        }

        isApplyingImport = true
        let error = await store.upsertFoodItems(items)
        isApplyingImport = false

        guard error == nil else {
            errorMessage = error ?? "Unknown import error."
            showingError = true
            return
        }

        pendingPlan = nil
        reviewSession = nil
        let importedCount = outcome.addedCount + outcome.replacedCount + outcome.copiedCount
        let addedCount = outcome.addedCount + outcome.copiedCount
        let changedCount = outcome.replacedCount
        let report = TransferOperationReport(
            operation: .importOperation,
            status: .green,
            processedCount: importedCount,
            addedCount: addedCount,
            changedCount: changedCount,
            fileName: lastImportedFileName
        )
        presentReport(report)
    }

    private func copyFoodItem(withNewID item: Core.FoodItem) -> Core.FoodItem {
        Core.FoodItem(
            id: UUID(),
            name: item.name,
            categoryID: item.categoryID,
            portionEquivalent: item.portionEquivalent,
            amountPerPortion: item.amountPerPortion,
            unitID: item.unitID,
            notes: item.notes,
            isFavorite: item.isFavorite,
            imagePath: item.imagePath,
            imageRemoteURL: item.imageRemoteURL,
            imageSource: item.imageSource,
            imageSourceID: item.imageSourceID,
            imageAttributionName: item.imageAttributionName,
            imageAttributionURL: item.imageAttributionURL,
            imageSourceURL: item.imageSourceURL,
            kind: item.kind,
            compositeComponents: item.compositeComponents
        )
    }

    private func importPlanSummary(_ plan: FoodImportPlan) -> String {
        """
        File items: \(plan.totalInFile)
        Valid items: \(plan.validCount)
        New items: \(plan.newItems.count)
        Existing items: \(plan.conflicts.count)
        Skipped (invalid/duplicate): \(plan.skippedBeforeApplyCount)
        """
    }

    private func presentReport(_ report: TransferOperationReport) {
        lastReport = report
        reportMessage = """
        Status (RAG): \(report.status.label)
        Operation: \(report.operationLine)
        Processed: \(report.processedCount)
        Added: \(report.addedCount)
        Changed: \(report.changedCount)
        \(report.fileLine)
        """
        showingReport = true
    }

    private func reviewMessage(for conflict: FoodImportConflict) -> String {
        let existingCategory = categoryName(for: conflict.existing.categoryID)
        let incomingCategory = categoryName(for: conflict.incoming.categoryID)
        return """
        Existing: \(conflict.existing.name) [\(existingCategory)]
        Incoming: \(conflict.incoming.name) [\(incomingCategory)]
        """
    }

    private func categoryName(for id: UUID) -> String {
        store.categories.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private func unitSymbol(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.units.first(where: { $0.id == id })?.symbol
    }

    private func unitName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.units.first(where: { $0.id == id })?.name
    }

    private func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FoodImportPlan {
    let totalInFile: Int
    let invalidCount: Int
    let duplicateInFileCount: Int
    let newItems: [Core.FoodItem]
    let conflicts: [FoodImportConflict]

    var validCount: Int {
        newItems.count + conflicts.count
    }

    var skippedBeforeApplyCount: Int {
        invalidCount + duplicateInFileCount
    }
}

private struct FoodImportConflict {
    let existing: Core.FoodItem
    let incoming: Core.FoodItem
}

private struct FoodImportReviewSession {
    let plan: FoodImportPlan
    var index: Int = 0
    var replacements: [Core.FoodItem] = []
    var copies: [Core.FoodItem] = []
    var keptExistingCount = 0

    var currentConflict: FoodImportConflict? {
        guard index < plan.conflicts.count else { return nil }
        return plan.conflicts[index]
    }
}

private enum FoodImportConflictDecision {
    case replace
    case keep
    case importAsCopy
}

private struct FoodImportOutcome {
    let addedCount: Int
    let replacedCount: Int
    let copiedCount: Int
    let keptExistingCount: Int
    let skippedCount: Int
}

private enum TransferOperationType {
    case export
    case importOperation

    var title: String {
        switch self {
        case .export: return "Export"
        case .importOperation: return "Import"
        }
    }
}

private enum TransferRAGStatus {
    case green
    case amber
    case red

    var label: String {
        switch self {
        case .green: return "GREEN"
        case .amber: return "AMBER"
        case .red: return "RED"
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }
}

private struct TransferOperationReport {
    let operation: TransferOperationType
    let status: TransferRAGStatus
    let processedCount: Int
    let addedCount: Int
    let changedCount: Int
    let fileName: String?

    var operationLine: String {
        operation.title
    }

    var fileLine: String {
        guard let fileName else { return "" }
        return "File: \(fileName)"
    }
}

private struct FoodLibraryTransferPayload: Encodable {
    let formatVersion: Int
    let exportedAt: String
    let itemCount: Int
    let items: [FoodLibraryTransferItem]
}

private struct FoodLibraryTransferItem: Encodable {
    let id: String
    let name: String
    let categoryID: String
    let categoryName: String
    let portionEquivalent: Double
    let amountPerPortion: Double?
    let unitID: String?
    let unitName: String?
    let unitSymbol: String?
    let notes: String?
    let isFavorite: Bool
    let imagePath: String?
    let imageRemoteURL: String?
    let imageSource: String?
    let imageSourceID: String?
    let imageAttributionName: String?
    let imageAttributionURL: String?
    let imageSourceURL: String?
    let kind: String
    let compositeComponents: [FoodLibraryTransferComponent]
}

private struct FoodLibraryTransferComponent: Encodable {
    let foodItemID: String
    let portionMultiplier: Double
}

private struct FoodLibraryImportPayload: Decodable {
    let items: [FoodLibraryImportItem]

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([FoodLibraryImportItem].self, forKey: .items) ?? []
    }
}

private struct FoodLibraryImportItem: Decodable {
    let id: String?
    let name: String?
    let categoryID: String?
    let portionEquivalent: Double?
    let amountPerPortion: Double?
    let unitID: String?
    let notes: String?
    let isFavorite: Bool?
    let imagePath: String?
    let imageRemoteURL: String?
    let imageSource: String?
    let imageSourceID: String?
    let imageAttributionName: String?
    let imageAttributionURL: String?
    let imageSourceURL: String?
    let kind: String?
    let compositeComponents: [FoodLibraryImportComponent]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case categoryID
        case portionEquivalent
        case amountPerPortion
        case unitID
        case notes
        case isFavorite
        case imagePath
        case imageRemoteURL
        case imageSource
        case imageSourceID
        case imageAttributionName
        case imageAttributionURL
        case imageSourceURL
        case kind
        case compositeComponents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        portionEquivalent = try container.decodeIfPresent(Double.self, forKey: .portionEquivalent)
        amountPerPortion = try container.decodeIfPresent(Double.self, forKey: .amountPerPortion)
        unitID = try container.decodeIfPresent(String.self, forKey: .unitID)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        imageRemoteURL = try container.decodeIfPresent(String.self, forKey: .imageRemoteURL)
        imageSource = try container.decodeIfPresent(String.self, forKey: .imageSource)
        imageSourceID = try container.decodeIfPresent(String.self, forKey: .imageSourceID)
        imageAttributionName = try container.decodeIfPresent(String.self, forKey: .imageAttributionName)
        imageAttributionURL = try container.decodeIfPresent(String.self, forKey: .imageAttributionURL)
        imageSourceURL = try container.decodeIfPresent(String.self, forKey: .imageSourceURL)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        compositeComponents = try container.decodeIfPresent([FoodLibraryImportComponent].self, forKey: .compositeComponents) ?? []
    }
}

private struct FoodLibraryImportComponent: Decodable {
    let foodItemID: String?
    let portionMultiplier: Double?
}

private struct TransferFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

private struct FoodLibraryImportPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onDismiss: () -> Void

        init(onPick: @escaping (URL) -> Void, onDismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.onDismiss = onDismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onDismiss()
                return
            }
            onPick(url)
            onDismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }
}
