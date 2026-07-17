import PhotosUI
import SwiftUI

struct CheckInEntryDetailRoute: Identifiable, Hashable {
    let entryId: String

    var id: String {
        entryId
    }
}

struct CheckInEntryDetailView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.scenePhase) private var scenePhase

    let entryId: String

    @State private var draft: CheckInEntry?
    @State private var isSaving = false
    @State private var isDeleteConfirmationPresented = false
    @State private var capturedImageData: Data?
    @State private var audioDraft: PreparedMomentMedia?
    @State private var removesExistingMedia = false
    @State private var isCameraPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var mediaError: String?
    @StateObject private var audioRecorder = AudioRecorderController()

    var body: some View {
        NavigationStack {
            Group {
                if let entry = draft,
                   let item = store.checkInItem(id: entry.itemId) {
                    Form {
                        Section {
                            LabeledContent(L10n.t("Check-in", appLanguage), value: item.name)
                            DatePicker(
                                L10n.t("Time", appLanguage),
                                selection: Binding(
                                    get: { entry.occurredAt },
                                    set: { draft?.occurredAt = $0 }
                                ),
                                in: ...Date()
                            )
                            .environment(\.locale, MomentDateFormatter.twentyFourHourLocale(for: appLanguage))
                            Toggle(
                                L10n.t("Show in Timeline", appLanguage),
                                isOn: Binding(
                                    get: { entry.showInTimeline },
                                    set: { draft?.showInTimeline = $0 }
                                )
                            )
                        }

                        Section(L10n.t("Note", appLanguage)) {
                            PlainTextListEditor(
                                text: Binding(
                                    get: { entry.note },
                                    set: { draft?.note = $0 }
                                )
                            )
                            .frame(minHeight: 120)
                        }

                        Section(L10n.t("Media", appLanguage)) {
                            if let capturedImageData, let image = UIImage(data: capturedImageData) {
                                CheckInCapturedImagePreview(image: image) {
                                    self.capturedImageData = nil
                                    self.removesExistingMedia = false
                                }
                            } else if let audioDraft {
                                CheckInDraftAudioPreview(media: audioDraft) {
                                    audioRecorder.discard()
                                    self.audioDraft = nil
                                    self.removesExistingMedia = false
                                }
                            } else if let existingMedia, !removesExistingMedia, existingMedia.isImage {
                                ZStack(alignment: .topTrailing) {
                                    CheckInImageThumbnail(media: existingMedia)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 180)

                                    Button {
                                        removesExistingMedia = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.t("Remove photo", appLanguage))
                                }
                                .padding(.vertical, 4)
                            } else if let existingMedia, !removesExistingMedia, existingMedia.isAudio {
                                ZStack(alignment: .topTrailing) {
                                    CheckInAudioAttachmentView(media: existingMedia)

                                    Button {
                                        removesExistingMedia = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.secondary, .quaternary)
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.t("Remove audio", appLanguage))
                                }
                                .padding(.vertical, 4)

                                if let summary = existingSummary {
                                    CheckInSummaryCard(summary: summary, transcriptText: existingMedia.transcriptionText)
                                        .padding(.bottom, 4)
                                }
                            }

                            if audioRecorder.isRecording {
                                CheckInRecordingStatusView(audioRecorder: audioRecorder)
                            }

                            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images) {
                                Label(L10n.t("Add Photos", appLanguage), systemImage: "photo.on.rectangle.angled")
                            }
                            .disabled(audioDraft != nil || audioRecorder.isRecording)

                            Button {
                                isCameraPresented = true
                            } label: {
                                Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
                            }
                            .disabled(!CameraPicker.isAvailable || audioDraft != nil || audioRecorder.isRecording)

                            Button {
                                toggleRecording()
                            } label: {
                                Label(
                                    L10n.t(audioRecorder.isRecording ? "Stop Recording" : "Record Audio", appLanguage),
                                    systemImage: audioRecorder.isRecording ? "stop.circle" : "mic"
                                )
                            }
                            .disabled(capturedImageData != nil && !audioRecorder.isRecording)
                        }

                        Section {
                            Button(L10n.t("Cancel check-in", appLanguage), role: .destructive) {
                                isDeleteConfirmationPresented = true
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(L10n.t("Check-in unavailable", appLanguage), systemImage: "checkmark.circle")
                }
            }
            .navigationTitle(L10n.t("Check-in", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Close", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving || draft == nil || audioRecorder.isRecording)
                }
            }
            .onAppear {
                draft = store.checkInEntry(id: entryId)
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker { data in
                    capturedImageData = data
                    audioRecorder.discard()
                    audioDraft = nil
                    removesExistingMedia = false
                }
            }
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else {
                    return
                }

                Task {
                    capturedImageData = await loadSelectedPhoto(from: items)
                    audioRecorder.discard()
                    audioDraft = nil
                    removesExistingMedia = false
                    selectedPhotoItems = []
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    audioRecorder.pauseIfRecording()
                }
            }
            .onDisappear {
                audioRecorder.pauseIfRecording()
            }
            .alert(L10n.t("Media unavailable", appLanguage), isPresented: mediaErrorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(mediaError ?? "")
            }
            .alert(L10n.t("Cancel check-in?", appLanguage), isPresented: $isDeleteConfirmationPresented) {
                Button(L10n.t("Keep", appLanguage), role: .cancel) {}
                Button(L10n.t("Cancel check-in", appLanguage), role: .destructive) {
                    if let draft {
                        Task {
                            await store.deleteCheckInEntry(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var existingMedia: CheckInMedia? {
        store.checkInMedia
            .filter { $0.entryId == entryId && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
            }
            .first
    }

    private var existingSummary: CheckInAISummary? {
        guard store.showCheckInSummaries,
              let media = existingMedia,
              media.isAudio,
              let summary = store.checkInAISummary(mediaId: media.id),
              summary.isReady,
              summary.hasDisplayContent else {
            return nil
        }

        return summary
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

    private func loadSelectedPhoto(from items: [PhotosPickerItem]) async -> Data? {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                return data
            }
        }

        return nil
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stop()
            guard let url = audioRecorder.recordedURL else {
                return
            }

            Task {
                do {
                    audioDraft = try await AudioMediaInspector.preparedAudio(from: url)
                    capturedImageData = nil
                    removesExistingMedia = false
                } catch {
                    mediaError = error.localizedDescription
                }
            }
            return
        }

        capturedImageData = nil
        audioDraft = nil
        removesExistingMedia = false
        audioRecorder.start()
    }

    private func save() {
        guard let draft else {
            return
        }

        isSaving = true
        Task {
            guard await store.updateCheckInEntry(draft) else {
                isSaving = false
                return
            }

            if capturedImageData != nil || audioDraft != nil || removesExistingMedia {
                guard await store.replaceCheckInEntryMedia(
                    entry: draft,
                    imageData: capturedImageData,
                    audioDraft: audioDraft
                ) else {
                    isSaving = false
                    return
                }
            }

            dismiss()
            isSaving = false
        }
    }
}
