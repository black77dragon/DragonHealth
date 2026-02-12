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
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            if store.documents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No documents yet.")
                        .font(.headline)
                    Text("Add PDFs or images to keep important records handy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                ForEach(store.documents) { document in
                    DocumentRow(document: document) {
                        previewDocument = document
                    }
                }
                .onDelete(perform: deleteDocuments)
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Document", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .glassButton(.icon)
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

    private func deleteDocuments(_ indices: IndexSet) {
        for index in indices {
            guard index < store.documents.count else { continue }
            let document = store.documents[index]
            do {
                try DocumentStorage.deleteDocument(fileName: document.fileName)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            Task { await store.deleteDocument(document) }
        }
    }
}

private struct DocumentRow: View {
    let document: Core.HealthDocument
    let onView: () -> Void

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
