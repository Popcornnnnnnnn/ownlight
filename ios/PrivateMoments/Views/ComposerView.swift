import Foundation
import PhotosUI
import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import VisionKit

struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: TimelineStore

    @State private var text = ComposerDraftStore.loadText()
    @State private var occurredAt = ComposerDraftStore.loadOccurredAt()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var imageData: [Data] = []
    @State private var videoDraft: PreparedMomentMedia?
    @State private var audioDrafts: [PreparedMomentMedia] = []
    @State private var documentDraft: PreparedMomentMedia?
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var showingFileImporter = false
    @State private var isPublishing = false
    @State private var isProcessingVideo = false
    @State private var isImportingShare = false
    @State private var mediaError: String?
    @State private var nextTextChangeWasUserDriven = false
    @State private var suppressNextOccurredAtDraftSave = false
    @ObservedObject private var audioRecorder: AudioRecorderController

    init(audioRecorder: AudioRecorderController) {
        self.audioRecorder = audioRecorder
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MarkdownTextEditor(
                        text: $text,
                        onPasteImages: handlePastedImages,
                        onUserTextChange: handleUserTextChange,
                        autoFocus: true
                    )
                        .frame(minHeight: 210, alignment: .topLeading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                        )

                    mediaControls

                    mediaPreview

                    ComposerContextStrip(
                        occurredAt: $occurredAt,
                        language: appLanguage
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.t("New Moment", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                    .disabled(isPublishing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        publish()
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text(L10n.t("Publish", appLanguage))
                        }
                    }
                    .disabled(!canPublish || isPublishing)
                    .accessibilityLabel(L10n.t(isPublishing ? "Publishing" : "Publish", appLanguage))
                }
            }
            .onChange(of: text) { _, value in
                persistDraftText(value)
            }
            .onChange(of: occurredAt) { _, value in
                if suppressNextOccurredAtDraftSave {
                    suppressNextOccurredAtDraftSave = false
                    return
                }

                try? store.saveComposerDraft(
                    text: text,
                    occurredAt: value,
                    reason: "draft_composer_date"
                )
            }
            .onChange(of: selectedItems) { _, items in
                Task {
                    imageData = await loadImageData(from: items)
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
            .onChange(of: selectedVideoItem) { _, item in
                guard let item else { return }
                Task {
                    await processVideo(item)
                    selectedVideoItem = nil
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    imageData = Array((imageData + [data]).prefix(ComposerImageDraft.maxImageCount))
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { scannedImages in
                    appendImageDrafts(scannedImages)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image, .movie, .video, .audio, .pdf],
                allowsMultipleSelection: true
            ) { result in
                Task {
                    await handleImportedFiles(result)
                }
            }
            .onAppear {
                refreshEmptyDraftSessionIfNeeded()
            }
            .task {
                await loadPendingShareImportIfNeeded()
                await loadRecoverableMediaDrafts()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    audioRecorder.pauseIfRecording()
                    return
                }

                recoverTransientEmptyDraftIfNeeded()
                Task { @MainActor in
                    await Task.yield()
                    recoverTransientEmptyDraftIfNeeded()
                }
                audioRecorder.refreshElapsedTime()
            }
            .onDisappear {
                audioRecorder.pauseIfRecording()
            }
            .alert(L10n.t("Media unavailable", appLanguage), isPresented: mediaErrorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(mediaError ?? "")
            }
        }
    }

    private var canPublish: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !imageData.isEmpty ||
            videoDraft != nil ||
            !audioDrafts.isEmpty ||
            documentDraft != nil) &&
            !isProcessingVideo &&
            !isImportingShare &&
            !audioRecorder.isRecording
    }

    private var hasNonImageMedia: Bool {
        videoDraft != nil || !audioDrafts.isEmpty || documentDraft != nil || audioRecorder.isRecording
    }

    private var hasAnyMedia: Bool {
        !imageData.isEmpty || videoDraft != nil || !audioDrafts.isEmpty || documentDraft != nil || audioRecorder.isRecording
    }

    private var canStartAudioRecording: Bool {
        imageData.isEmpty &&
            videoDraft == nil &&
            documentDraft == nil &&
            audioDrafts.count < 9 &&
            !audioRecorder.isRecording &&
            !isImportingShare &&
            !isProcessingVideo
    }

    private var mediaErrorBinding: Binding<Bool> {
        Binding(
            get: { mediaError != nil || audioRecorder.errorMessage != nil },
            set: { _ in
                mediaError = nil
                audioRecorder.errorMessage = nil
            }
        )
    }

    @ViewBuilder
    private var mediaControls: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: ComposerImageDraft.maxImageCount, matching: .images) {
                ComposerMediaActionLabel(title: L10n.t("Photos", appLanguage), systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(ComposerMediaActionButtonStyle())
            .disabled(hasNonImageMedia)

            Button {
                showingCamera = true
            } label: {
                ComposerMediaActionLabel(title: L10n.t("Camera", appLanguage), systemImage: "camera")
            }
            .buttonStyle(ComposerMediaActionButtonStyle())
            .disabled(!CameraPicker.isAvailable || hasNonImageMedia)

            Button {
                ComposerMediaActionPolicy.startAudioRecordingIfPossible(
                    canStart: canStartAudioRecording,
                    dismissKeyboard: dismissKeyboard,
                    startRecording: startRecording
                )
            } label: {
                ComposerMediaActionLabel(title: L10n.t("Audio", appLanguage), systemImage: "mic")
            }
            .buttonStyle(ComposerMediaActionButtonStyle())
            .disabled(!canStartAudioRecording)

            Menu {
                PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                    Label(L10n.t("Video", appLanguage), systemImage: "video")
                }
                .disabled(hasAnyMedia || isProcessingVideo)

                Button {
                    if DocumentScannerView.isAvailable {
                        showingScanner = true
                    } else {
                        mediaError = L10n.t("Document scanner is not available on this device.", appLanguage)
                    }
                } label: {
                    Label(L10n.t("Scan", appLanguage), systemImage: "doc.viewfinder")
                }
                .disabled(hasNonImageMedia || imageData.count >= ComposerImageDraft.maxImageCount)

                Button {
                    showingFileImporter = true
                } label: {
                    Label(L10n.t("Files", appLanguage), systemImage: "folder")
                }
                .disabled(isImportingShare || isProcessingVideo || audioRecorder.isRecording)
            } label: {
                ComposerMediaActionLabel(title: L10n.t("More", appLanguage), systemImage: "ellipsis.circle")
            }
            .buttonStyle(ComposerMediaActionButtonStyle())
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if isProcessingVideo || isImportingShare || audioRecorder.isRecording || hasAnyMedia {
            VStack(alignment: .leading, spacing: 12) {
                if isProcessingVideo {
                    ComposerProgressRow(title: L10n.t("Processing video", appLanguage))
                }

                if isImportingShare {
                    ComposerProgressRow(title: L10n.t("Importing shared item", appLanguage))
                }

                if audioRecorder.isRecording {
                    HStack {
                        Label(
                            L10n.t(audioRecorder.isPaused ? "Recording paused" : "Recording", appLanguage),
                            systemImage: audioRecorder.isPaused ? "pause.circle.fill" : "waveform"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(mediaDurationLabel(audioRecorder.elapsedSeconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button(L10n.t(audioRecorder.isPaused ? "Resume" : "Pause", appLanguage)) {
                            audioRecorder.pauseOrResume()
                        }
                        .buttonStyle(.borderless)
                        Button(L10n.t("Done", appLanguage)) {
                            finishRecording()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let videoDraft {
                    DraftVideoPreview(media: videoDraft) {
                        self.videoDraft = nil
                    }
                }

                if let documentDraft {
                    DraftDocumentPreview(media: documentDraft) {
                        removeDocumentDraft()
                    }
                }

                ForEach(audioDrafts) { audioDraft in
                    DraftAudioPreview(media: audioDraft) {
                        removeAudioDraft(audioDraft)
                    }
                }

                if !imageData.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(minHeight: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    if imageData.count > 1 {
                                        HStack(spacing: 2) {
                                            Button {
                                                moveImage(from: index, to: index - 1)
                                            } label: {
                                                Image(systemName: "chevron.left.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.62))
                                            }
                                            .disabled(index == 0)
                                            .accessibilityLabel(L10n.t("Move image left", appLanguage))

                                            Button {
                                                moveImage(from: index, to: index + 1)
                                            } label: {
                                                Image(systemName: "chevron.right.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.62))
                                            }
                                            .disabled(index == imageData.count - 1)
                                            .accessibilityLabel(L10n.t("Move image right", appLanguage))
                                        }
                                        .font(.title3)
                                        .buttonStyle(.plain)
                                        .padding(4)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    }

                                    Button {
                                        removeImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.62))
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .accessibilityLabel(L10n.t("Remove image", appLanguage))
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func publish() {
        guard canPublish, !isPublishing else {
            return
        }

        isPublishing = true
        Task {
            let didCreate = await store.createPost(
                text: text,
                imageData: imageData,
                video: videoDraft,
                audio: audioDrafts,
                document: documentDraft,
                occurredAt: occurredAt,
                primaryTagId: nil
            )
            isPublishing = false

            if didCreate {
                try? store.clearComposerDraft(reason: "draft_composer_publish")
                dismiss()
            }
        }
    }

    private func loadImageData(from items: [PhotosPickerItem]) async -> [Data] {
        var result: [Data] = []

        for item in items.prefix(ComposerImageDraft.maxImageCount) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                result.append(data)
            }
        }

        return result
    }

    private func handlePastedImages(_ pastedImages: [Data]) {
        guard !pastedImages.isEmpty else {
            return
        }

        appendImageDrafts(pastedImages)
    }

    private func appendImageDrafts(_ newImages: [Data]) {
        guard !newImages.isEmpty else {
            return
        }

        guard !hasNonImageMedia else {
            mediaError = L10n.t("Remove audio or video before adding photos.", appLanguage)
            return
        }

        let result = ComposerImageDraft.appending(newImages, to: imageData)
        guard result.didAppend else {
            mediaError = L10n.t("You can add up to 9 photos.", appLanguage)
            return
        }

        imageData = result.images
        try? ComposerDraftStore.saveImages(imageData)

        if result.didDiscard {
            mediaError = L10n.t("Only the available photo slots were added.", appLanguage)
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                return
            }

            try await importFiles(urls)
        } catch {
            mediaError = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) async throws {
        var imageURLs: [URL] = []
        var videoURLs: [URL] = []
        var audioURLs: [URL] = []
        var documentURLs: [URL] = []

        for url in urls {
            let type = Self.contentType(for: url)
            if type?.conforms(to: .image) == true {
                imageURLs.append(url)
            } else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
                videoURLs.append(url)
            } else if type?.conforms(to: .audio) == true {
                audioURLs.append(url)
            } else if type?.conforms(to: .pdf) == true {
                documentURLs.append(url)
            }
        }

        let selectedKindCount = [!imageURLs.isEmpty, !videoURLs.isEmpty, !audioURLs.isEmpty, !documentURLs.isEmpty].filter { $0 }.count
        guard selectedKindCount > 0 else {
            mediaError = L10n.t("Unsupported file type.", appLanguage)
            return
        }

        guard selectedKindCount == 1 else {
            mediaError = L10n.t("Choose one media type at a time.", appLanguage)
            return
        }

        if !imageURLs.isEmpty {
            guard !hasNonImageMedia else {
                mediaError = L10n.t("Remove audio or video before adding photos.", appLanguage)
                return
            }

            let imported = imageURLs
                .prefix(max(0, ComposerImageDraft.maxImageCount - imageData.count))
                .compactMap { Self.readSecurityScopedData(from: $0) }
            appendImageDrafts(imported)
            return
        }

        if let videoURL = videoURLs.first {
            guard !hasAnyMedia else {
                mediaError = L10n.t("Remove existing media before adding a video.", appLanguage)
                return
            }

            isProcessingVideo = true
            defer {
                isProcessingVideo = false
            }
            let preparedVideo = try await Self.withSecurityScopedAccess(to: videoURL) {
                try await VideoMediaProcessor.prepareVideo(from: videoURL)
            }
            videoDraft = preparedVideo
            imageData = []
            audioDrafts = []
            documentDraft = nil
            audioRecorder.discard()
            try? ComposerDraftStore.saveImages([])
            return
        }

        if let documentURL = documentURLs.first {
            guard !hasAnyMedia else {
                mediaError = L10n.t("Remove existing media before adding a document.", appLanguage)
                return
            }

            let preparedDocument = try await Self.withSecurityScopedAccess(to: documentURL) {
                try DocumentMediaImporter.preparePDF(from: documentURL)
            }
            documentDraft = preparedDocument
            imageData = []
            videoDraft = nil
            audioDrafts = []
            audioRecorder.discard()
            try? ComposerDraftStore.saveImages([])
            if documentURLs.count > 1 {
                mediaError = L10n.t("Only one document can be added.", appLanguage)
            }
            return
        }

        guard !audioURLs.isEmpty else {
            mediaError = L10n.t("Unsupported file type.", appLanguage)
            return
        }

        guard imageData.isEmpty, videoDraft == nil, documentDraft == nil else {
            mediaError = L10n.t("Remove photos, video, or document before adding audio.", appLanguage)
            return
        }

        let availableSlots = max(0, 9 - audioDrafts.count)
        guard availableSlots > 0 else {
            mediaError = L10n.t("You can add up to 9 audio clips.", appLanguage)
            return
        }

        var importedAudio: [PreparedMomentMedia] = []
        for url in audioURLs.prefix(availableSlots) {
            let preparedAudio = try await Self.withSecurityScopedAccess(to: url) {
                try await AudioMediaInspector.prepareImportedAudio(from: url)
            }
            importedAudio.append(preparedAudio)
        }

        audioDrafts.append(contentsOf: importedAudio)
        if audioURLs.count > availableSlots {
            mediaError = L10n.t("Only the available audio slots were added.", appLanguage)
        }
    }

    private static func contentType(for url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        return type
    }

    private static func readSecurityScopedData(from url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? Data(contentsOf: url)
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
    }

    private func handleUserTextChange(_ value: String) {
        nextTextChangeWasUserDriven = true
    }

    private func persistDraftText(_ value: String) {
        let wasUserDriven = nextTextChangeWasUserDriven
        nextTextChangeWasUserDriven = false

        if wasUserDriven,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !hasAnyMedia {
            try? store.clearComposerDraftTextAndDate(reason: "draft_composer_empty")
            resetOccurredAtWithoutPersisting()
            return
        }

        try? store.saveComposerDraft(
            text: value,
            occurredAt: occurredAt,
            reason: "draft_composer_text"
        )
    }

    private func refreshEmptyDraftSessionIfNeeded() {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hasAnyMedia,
              !ComposerDraftStore.hasMediaDrafts() else {
            return
        }

        try? store.clearComposerDraftTextAndDate(reason: "draft_composer_empty")
        resetOccurredAtWithoutPersisting()
    }

    private func resetOccurredAtWithoutPersisting() {
        suppressNextOccurredAtDraftSave = true
        occurredAt = Date()
    }

    private func recoverTransientEmptyDraftIfNeeded() {
        let recoveredText = ComposerDraftStore.textAfterRecoveringTransientEmpty(currentText: text)
        if recoveredText != text {
            text = recoveredText
            occurredAt = ComposerDraftStore.loadOccurredAt()
        }
    }

    private func removeImage(at index: Int) {
        guard imageData.indices.contains(index) else {
            return
        }

        imageData.remove(at: index)
        try? ComposerDraftStore.saveImages(imageData)
    }

    private func moveImage(from sourceIndex: Int, to destinationIndex: Int) {
        guard imageData.indices.contains(sourceIndex),
              imageData.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let item = imageData.remove(at: sourceIndex)
        imageData.insert(item, at: destinationIndex)
        try? ComposerDraftStore.saveImages(imageData)
    }

    private func processVideo(_ item: PhotosPickerItem) async {
        isProcessingVideo = true
        defer {
            isProcessingVideo = false
        }

        do {
            guard let picked = try await item.loadTransferable(type: PickedVideoFile.self) else {
                throw MediaPreparationError.videoExportUnavailable
            }

            videoDraft = try await VideoMediaProcessor.prepareVideo(from: picked.url)
            imageData = []
            audioDrafts = []
            documentDraft = nil
            audioRecorder.discard()
            try? ComposerDraftStore.saveImages([])
        } catch {
            mediaError = error.localizedDescription
        }
    }

    private func loadPendingShareImportIfNeeded() async {
        let envelope: PendingShareImportEnvelope?
        do {
            envelope = try ShareImportInbox.nextPendingImport()
        } catch ShareImportInboxError.appGroupUnavailable {
            return
        } catch {
            mediaError = error.localizedDescription
            return
        }

        guard let envelope else {
            return
        }

        isImportingShare = true
        defer {
            isImportingShare = false
        }

        do {
            applySharedText(envelope.importRecord.text, createdAt: envelope.importRecord.createdAt)
            try await applySharedAttachments(envelope)
            try? store.saveComposerDraft(
                text: text,
                occurredAt: occurredAt,
                reason: "draft_composer_share_import"
            )
            try ShareImportInbox.delete(envelope)
        } catch {
            mediaError = "Could not import shared item: \(error.localizedDescription)"
        }
    }

    private func applySharedText(_ sharedText: String, createdAt: Date) {
        let trimmedSharedText = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        occurredAt = createdAt
        guard !trimmedSharedText.isEmpty else {
            return
        }

        let normalizedSharedText = Self.normalizedSharedText(trimmedSharedText)
        let trimmedCurrentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmedCurrentText.isEmpty
            ? normalizedSharedText
            : "\(trimmedCurrentText)\n\n\(normalizedSharedText)"
    }

    private static func normalizedSharedText(_ value: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return value
        }

        let nsValue = value as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        let matches = detector.matches(in: value, options: [], range: fullRange)
        guard !matches.isEmpty else {
            return value
        }

        var result = value
        for match in matches.reversed() {
            guard let url = match.url,
                  let range = Range(match.range, in: result) else {
                continue
            }

            result.replaceSubrange(range, with: "\n\(url.absoluteString)\n")
        }

        return result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func applySharedAttachments(_ envelope: PendingShareImportEnvelope) async throws {
        let attachments = envelope.importRecord.attachments.sorted { $0.sortOrder < $1.sortOrder }
        guard !attachments.isEmpty else {
            return
        }

        if let video = attachments.first(where: { $0.kind == .video }) {
            isProcessingVideo = true
            defer {
                isProcessingVideo = false
            }
            videoDraft = try await VideoMediaProcessor.prepareVideo(from: envelope.fileURL(for: video))
            audioDrafts = []
            imageData = []
            documentDraft = nil
            selectedItems = []
            selectedVideoItem = nil
            audioRecorder.discard()
            try? ComposerDraftStore.saveImages([])
            return
        }

        if let audio = attachments.first(where: { $0.kind == .audio }) {
            audioDrafts = [try await AudioMediaInspector.prepareImportedAudio(from: envelope.fileURL(for: audio))]
            videoDraft = nil
            imageData = []
            documentDraft = nil
            selectedItems = []
            selectedVideoItem = nil
            try? ComposerDraftStore.saveImages([])
            return
        }

        let importedImages = attachments
            .filter { $0.kind == .image }
            .prefix(ComposerImageDraft.maxImageCount)
            .compactMap { try? Data(contentsOf: envelope.fileURL(for: $0)) }

        guard !importedImages.isEmpty else {
            return
        }

        imageData = importedImages
        videoDraft = nil
        audioDrafts = []
        documentDraft = nil
        selectedItems = []
        selectedVideoItem = nil
        audioRecorder.discard()
        try ComposerDraftStore.saveImages(imageData)
    }

    private func startRecording() {
        guard canStartAudioRecording else {
            return
        }

        videoDraft = nil
        documentDraft = nil
        imageData = []
        try? ComposerDraftStore.saveImages([])
        audioRecorder.start()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func finishRecording() {
        guard let url = audioRecorder.finishCurrentRecording() else {
            return
        }

        Task {
            do {
                let draft = try await AudioMediaInspector.preparedAudio(from: url)
                audioDrafts.append(draft)
                if audioDrafts.count > 9 {
                    audioDrafts = Array(audioDrafts.prefix(9))
                }
                imageData = []
                videoDraft = nil
                documentDraft = nil
                try? ComposerDraftStore.saveImages([])
            } catch {
                mediaError = error.localizedDescription
            }
        }
    }

    private func removeAudioDraft(_ draft: PreparedMomentMedia) {
        audioDrafts.removeAll { $0.id == draft.id }
        try? FileManager.default.removeItem(at: draft.fileURL)
        if let thumbnailURL = draft.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    private func removeDocumentDraft() {
        guard let documentDraft else {
            return
        }

        try? FileManager.default.removeItem(at: documentDraft.fileURL)
        self.documentDraft = nil
    }

    private func loadRecoverableAudioDrafts() async {
        guard imageData.isEmpty, videoDraft == nil, documentDraft == nil, audioDrafts.isEmpty else {
            return
        }

        var recovered: [PreparedMomentMedia] = []
        let activeRecordingPath = audioRecorder.recordedURL?.standardizedFileURL.path
        for url in ComposerDraftStore.loadAudioDraftURLs() where url.standardizedFileURL.path != activeRecordingPath {
            if let draft = try? await AudioMediaInspector.preparedAudio(from: url) {
                recovered.append(draft)
            }
        }

        if !recovered.isEmpty {
            audioDrafts = recovered
        }
    }

    private func loadRecoverableMediaDrafts() async {
        guard imageData.isEmpty, videoDraft == nil, documentDraft == nil, audioDrafts.isEmpty else {
            return
        }

        let recoveredImages = await Task.detached(priority: .utility) {
            ComposerDraftStore.loadImages()
        }.value

        if !recoveredImages.isEmpty {
            imageData = recoveredImages
            return
        }

        await loadRecoverableAudioDrafts()
    }
}

private struct ComposerMediaActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(height: 20)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.62))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ComposerMediaActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.965 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.secondary.opacity(0.045)
        }

        return isPressed ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.065)
    }

    private func borderColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color.clear
        }

        return isPressed ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08)
    }
}

private struct ComposerProgressRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ComposerContextStrip: View {
    @Binding var occurredAt: Date

    let language: AppResolvedLanguage
    @State private var isShowingDatePicker = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isShowingDatePicker = true
            } label: {
                contextPill(
                    title: Self.dateLabel(for: occurredAt, language: language),
                    systemImage: "calendar",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Date", language))
        }
        .sheet(isPresented: $isShowingDatePicker) {
            ComposerDatePickerSheet(occurredAt: $occurredAt, language: language)
                .presentationDetents([.height(470)])
                .presentationDragIndicator(.visible)
        }
    }

    private func contextPill(title: String, systemImage: String, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private static func dateLabel(for date: Date, language: AppResolvedLanguage) -> String {
        let calendar = Calendar.current
        let now = Date()
        let dayLabel: String
        if calendar.isDate(date, inSameDayAs: now) {
            dayLabel = L10n.t("Today", language)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            dayLabel = L10n.t("Yesterday", language)
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: language == .simplifiedChinese ? "zh_Hans" : "en_US")
            formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "yMMMd")
            dayLabel = formatter.string(from: date)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = MomentDateFormatter.twentyFourHourLocale(for: language)
        timeFormatter.dateFormat = "HH:mm"
        return "\(dayLabel) · \(timeFormatter.string(from: date))"
    }
}

private struct ComposerDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var occurredAt: Date

    let language: AppResolvedLanguage

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                DatePicker(
                    L10n.t("Date", language),
                    selection: $occurredAt,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack(spacing: 12) {
                    Label(L10n.t("Time", language), systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    DatePicker(
                        L10n.t("Time", language),
                        selection: $occurredAt,
                        in: ...Date(),
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, MomentDateFormatter.twentyFourHourLocale(for: language))
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle(L10n.t("Date", language))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: clampFutureSelection)
            .onChange(of: occurredAt) { _, _ in
                clampFutureSelection()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func clampFutureSelection() {
        let now = Date()
        if occurredAt > now {
            occurredAt = now
        }
    }
}

private struct DraftVideoPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let thumbnailURL = media.thumbnailURL,
                   let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                    Image(systemName: "video")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                if let duration = media.durationSeconds {
                    Text(mediaDurationLabel(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.48), in: Capsule())
                        .padding(8)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.62))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(L10n.t("Remove video", appLanguage))
        }
    }
}

private struct DraftAudioPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(isPlaying ? "Pause audio" : "Play audio", appLanguage))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Audio", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(mediaDurationLabel(media.durationSeconds ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, .quaternary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Remove audio", appLanguage))
        }
        .padding(.vertical, 8)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        if player == nil {
            player = AVPlayer(url: media.fileURL)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
    }
}

private struct DraftDocumentPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("PDF document", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(Self.fileSizeLabel(for: media.fileURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, .quaternary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Remove document", appLanguage))
        }
        .padding(.vertical, 8)
    }

    private static func fileSizeLabel(for url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            return "PDF"
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

func mediaDurationLabel(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    return String(format: "%d:%02d", minutes, remainingSeconds)
}

struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void

        init(onCapture: @escaping (Data) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }

            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onScan: ([Data]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, dismiss: dismiss)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([Data]) -> Void
        private let dismiss: DismissAction

        init(onScan: @escaping ([Data]) -> Void, dismiss: DismissAction) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).compactMap { index in
                scan.imageOfPage(at: index).jpegData(compressionQuality: 0.86)
            }
            onScan(images)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            dismiss()
        }
    }
}
