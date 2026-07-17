import SwiftUI
import UniformTypeIdentifiers

struct StorageExportSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var localStats: LocalStorageStats?
    @State private var exportTask: Task<Void, Never>?
    @State private var exportState: ExportState = .idle
    @State private var exportResult: LocalArchiveExportResult?
    @State private var shareURL: URL?
    @State private var showsExportWarning = false
    @State private var importTask: Task<Void, Never>?
    @State private var importState: ImportState = .idle
    @State private var importResult: LocalArchiveImportResult?
    @State private var importConfirmation: ImportConfirmation?
    @State private var showsImportConfirmation = false
    @State private var showsImportPicker = false

    var body: some View {
        Form {
            Section(L10n.t("Storage", appLanguage)) {
                if let localStats {
                    LabeledContent(
                        L10n.t("This iPhone", appLanguage),
                        value: StorageByteFormatter.string(from: localStats.totalBytes)
                    )
                    LabeledContent(
                        L10n.t("Database", appLanguage),
                        value: StorageByteFormatter.string(from: localStats.databaseBytes)
                    )
                    LabeledContent(
                        L10n.t("Media", appLanguage),
                        value: StorageByteFormatter.string(from: localStats.mediaBytes)
                    )
                } else {
                    LabeledContent(L10n.t("This iPhone", appLanguage), value: L10n.t("Checking storage", appLanguage))
                }
            }

            Section {
                if case .exporting = exportState {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.t("Preparing archive", appLanguage))
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.t("Cancel Export", appLanguage), role: .destructive) {
                        exportTask?.cancel()
                    }
                } else {
                    archiveActionRow(
                        title: L10n.t("Export Data", appLanguage),
                        systemImage: "square.and.arrow.up",
                        isDisabled: false
                    ) {
                        showsExportWarning = true
                    }
                }

                if case .working(let label) = importState {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.t(label, appLanguage))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    archiveActionRow(
                        title: L10n.t("Import Archive", appLanguage),
                        systemImage: "tray.and.arrow.down",
                        isDisabled: isBusy
                    ) {
                        showsImportPicker = true
                    }
                }
            } header: {
                Text(L10n.t("Archive", appLanguage))
            } footer: {
                archiveFooter
            }
        }
        .navigationTitle(L10n.t("Storage & Export", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshStats()
        }
        .alert(L10n.t("Export Private Archive?", appLanguage), isPresented: $showsExportWarning) {
            Button(L10n.t("Export", appLanguage)) {
                startExport()
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        } message: {
            Text(L10n.t("This archive can include private text, comments, AI summaries, reviews, check-ins, and media. It is not encrypted.", appLanguage))
        }
        .alert(L10n.t("Import Archive?", appLanguage), isPresented: $showsImportConfirmation) {
            Button(L10n.t("Import", appLanguage)) {
                if let importConfirmation {
                    startImport(importConfirmation)
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        } message: {
            if let importConfirmation {
                Text(importConfirmationMessage(for: importConfirmation.preview))
            } else {
                Text("")
            }
        }
        .fileImporter(
            isPresented: $showsImportPicker,
            allowedContentTypes: [Self.archiveContentType],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .sheet(item: shareBinding) { url in
            ShareSheet(activityItems: [url])
        }
    }

    private var shareBinding: Binding<ShareURL?> {
        Binding(
            get: { shareURL.map(ShareURL.init(url:)) },
            set: { shareURL = $0?.url }
        )
    }

    private var isBusy: Bool {
        if case .exporting = exportState {
            return true
        }
        if case .working = importState {
            return true
        }
        return false
    }

    @ViewBuilder
    private var archiveFooter: some View {
        if hasArchiveFooter {
            VStack(alignment: .leading, spacing: 4) {
                if let exportResult {
                    Text("\(L10n.t("Last export", appLanguage)): \(exportResult.filename) · \(exportResult.mediaFilesIncluded) \(L10n.t("media files", appLanguage)) · \(exportResult.missingMediaCount) \(L10n.t("missing", appLanguage))")
                }

                if let importResult {
                    Text("\(L10n.t("Last import", appLanguage)): \(importResult.imported.posts) \(L10n.t("moments", appLanguage)) · \(importResult.imported.comments) \(L10n.t("comments", appLanguage)) · \(importResult.imported.mediaFilesIncluded) \(L10n.t("media files", appLanguage))")
                }

                if case .failed(let message) = importState {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var hasArchiveFooter: Bool {
        if exportResult != nil || importResult != nil {
            return true
        }
        if case .failed = importState {
            return true
        }
        return false
    }

    private func archiveActionRow(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 22)

                Text(title)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 28)
    }

    private func refreshStats() {
        do {
            localStats = try LocalStorageStatsLoader.load(database: store.database)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func startExport() {
        exportState = .exporting
        exportResult = nil
        exportTask = Task {
            do {
                let result = try await LocalArchiveExporter.export(from: store)
                guard !Task.isCancelled else {
                    exportState = .idle
                    return
                }
                exportResult = result
                shareURL = result.url
                exportState = .idle
            } catch is CancellationError {
                exportState = .idle
            } catch {
                exportState = .failed(error.localizedDescription)
                store.errorMessage = error.localizedDescription
            }
            exportTask = nil
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            previewImport(url)
        case .failure(let error):
            importState = .failed(error.localizedDescription)
            store.errorMessage = error.localizedDescription
        }
    }

    private func previewImport(_ url: URL) {
        importResult = nil
        importState = .working("Checking archive")
        importTask = Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try LocalArchiveImporter.preview(archiveURL: url)
                }.value
                guard !Task.isCancelled else {
                    importState = .idle
                    return
                }
                importConfirmation = ImportConfirmation(url: url, preview: preview)
                showsImportConfirmation = true
                importState = .idle
            } catch {
                importState = .failed(error.localizedDescription)
                store.errorMessage = error.localizedDescription
            }
            importTask = nil
        }
    }

    private func startImport(_ confirmation: ImportConfirmation) {
        guard let database = store.database else {
            let message = L10n.t("Local database is not ready.", appLanguage)
            importState = .failed(message)
            store.errorMessage = message
            return
        }

        importState = .working("Importing archive")
        importTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LocalArchiveImporter.importArchive(from: confirmation.url, into: database)
                }.value
                guard !Task.isCancelled else {
                    importState = .idle
                    return
                }
                importResult = result
                try await store.reload()
                try store.refreshPendingCounts()
                refreshStats()
                importState = .idle
            } catch {
                importState = .failed(error.localizedDescription)
                store.errorMessage = error.localizedDescription
            }
            importTask = nil
        }
    }

    private func importConfirmationMessage(for preview: LocalArchiveImportPreview) -> String {
        [
            "\(L10n.t("Archive contents", appLanguage)): \(preview.counts.posts) \(L10n.t("moments", appLanguage)), \(preview.counts.comments) \(L10n.t("comments", appLanguage)), \(preview.counts.mediaFilesIncluded) \(L10n.t("media files", appLanguage)).",
            L10n.t("Import is only available when this iPhone has no existing local records. It does not merge or overwrite data.", appLanguage)
        ].joined(separator: "\n\n")
    }

    private static var archiveContentType: UTType {
        UTType(filenameExtension: "zip") ?? .data
    }
}

private enum ExportState: Equatable {
    case idle
    case exporting
    case failed(String)
}

private enum ImportState: Equatable {
    case idle
    case working(String)
    case failed(String)
}

private struct ImportConfirmation: Identifiable {
    let url: URL
    let preview: LocalArchiveImportPreview

    var id: String {
        url.absoluteString
    }
}

private struct ShareURL: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}
