import SwiftUI
import Combine
import Core
import UniformTypeIdentifiers
import QuickLook
import QuickLookThumbnailing
import UIKit

struct DocumentsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingPicker = false
    @State private var previewDocument: Core.HealthDocument?
    @State private var documentPendingDelete: Core.HealthDocument?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @AppStorage("documents.sort") private var sortOrderRaw: String = DocumentsSortOrder.newest.rawValue

    private var sortOrder: DocumentsSortOrder {
        DocumentsSortOrder(rawValue: sortOrderRaw) ?? .newest
    }

    private var filteredDocuments: [Core.HealthDocument] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = store.documents.filter { document in
            guard !trimmedSearch.isEmpty else { return true }
            return document.title.localizedStandardContains(trimmedSearch)
                || document.fileType.searchLabel.localizedStandardContains(trimmedSearch)
        }

        switch sortOrder {
        case .newest:
            return matching.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return matching.sorted { $0.createdAt < $1.createdAt }
        case .title:
            return matching.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            Section {
                DocumentsHeroCard(
                    documentCount: store.documents.count,
                    pdfCount: store.documents.filter { $0.fileType == .pdf }.count,
                    imageCount: store.documents.filter { $0.fileType != .pdf }.count,
                    sortOrder: Binding(
                        get: { sortOrder },
                        set: { sortOrderRaw = $0.rawValue }
                    )
                )
                .listRowBackground(Color.clear)
            }

            if filteredDocuments.isEmpty {
                Section {
                    DocumentsEmptyStateCard(
                        title: store.documents.isEmpty ? "No documents yet" : "No documents match your search",
                        message: store.documents.isEmpty
                            ? "Add PDFs or images to keep medical records, scans, and letters close at hand."
                            : "Try a different search term or switch the sort order."
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Library") {
                    ForEach(filteredDocuments) { document in
                        DocumentRow(document: document) {
                            previewDocument = document
                        } onDelete: {
                            documentPendingDelete = document
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Documents")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Document", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .glassLabel(.icon)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(allowedTypes: [.pdf, .image]) { url in
                importDocument(from: url)
            } onDismiss: {
                showingPicker = false
            }
        }
        .sheet(item: $previewDocument) { document in
            DocumentPreviewSheet(url: DocumentStorage.url(for: document.fileName))
        }
        .confirmationDialog(
            "Delete Document?",
            isPresented: Binding(
                get: { documentPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        documentPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: documentPendingDelete
        ) { document in
            Button("Delete \(document.title)", role: .destructive) {
                delete(document)
                documentPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                documentPendingDelete = nil
            }
        } message: { document in
            Text("This removes \(document.title) from DragonHealth.")
        }
        .alert("Unable to Add Document", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func importDocument(from url: URL) {
        do {
            let result = try DocumentStorage.importDocument(from: url)
            let document = Core.HealthDocument(
                title: result.title,
                fileName: result.fileName,
                fileType: result.fileType,
                createdAt: Date()
            )
            Task { await store.saveDocument(document) }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func delete(_ document: Core.HealthDocument) {
        do {
            try DocumentStorage.deleteDocument(fileName: document.fileName)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        Task { await store.deleteDocument(document) }
    }
}

private struct DocumentRow: View {
    let document: Core.HealthDocument
    let onView: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DocumentThumbnailView(document: document, size: CGSize(width: 56, height: 72))
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.subheadline)
                Text(document.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(document.fileType == .pdf ? "PDF" : "Image")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onView()
        }
        .contextMenu {
            Button("View Document") {
                onView()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private enum DocumentsSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .title: return "Title"
        }
    }
}

private struct DocumentsHeroCard: View {
    let documentCount: Int
    let pdfCount: Int
    let imageCount: Int
    @Binding var sortOrder: DocumentsSortOrder

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.section) {
            VStack(alignment: .leading, spacing: ZenSpacing.text) {
                Text("Records library")
                    .zenEyebrow()
                Text("Keep the important paperwork easy to find, preview, and sort.")
                    .zenHeroTitle()
                HStack(spacing: 12) {
                    DocumentsHeroMetric(label: "Total", value: "\(documentCount)")
                    DocumentsHeroMetric(label: "PDFs", value: "\(pdfCount)")
                    DocumentsHeroMetric(label: "Images", value: "\(imageCount)")
                }
            }

            Picker("Sort", selection: $sortOrder) {
                ForEach(DocumentsSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 22)
    }
}

private struct DocumentsHeroMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .zenMetricLabel()
            Text(value)
                .zenMetricValue()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct DocumentsEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .zenSectionTitle()
            Text(message)
                .zenSupportText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .zenCard()
    }
}

private extension Core.DocumentType {
    var searchLabel: String {
        switch self {
        case .pdf:
            return "PDF"
        case .image:
            return "Image"
        }
    }
}

private struct DocumentThumbnailView: View {
    let document: Core.HealthDocument
    let size: CGSize
    @StateObject private var loader: DocumentThumbnailLoader
    @Environment(\.displayScale) private var displayScale

    init(document: Core.HealthDocument, size: CGSize) {
        self.document = document
        self.size = size
        let url = DocumentStorage.url(for: document.fileName)
        _loader = StateObject(wrappedValue: DocumentThumbnailLoader(url: url, size: size))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: document.fileType == .pdf ? "doc.richtext" : "photo")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .onAppear {
            loader.load(scale: displayScale)
        }
    }
}

private final class DocumentThumbnailLoader: ObservableObject {
    @Published var image: UIImage?

    private let url: URL
    private let size: CGSize
    private var isLoading = false

    init(url: URL, size: CGSize) {
        self.url = url
        self.size = size
    }

    func load(scale: CGFloat) {
        guard !isLoading, image == nil else { return }
        isLoading = true
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            DispatchQueue.main.async {
                self?.image = representation?.uiImage
                self?.isLoading = false
            }
        }
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let onPick: (URL) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: false)
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

private struct DocumentPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            uiViewController.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
