import PhotosUI
import SwiftUI
import UIKit

struct EditMomentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore

    let postId: String

    @State private var text = ""
    @State private var occurredAt = Date()
    @State private var mediaItems: [MomentEditMediaItem] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showDraftChoice = false
    @State private var showDiscardConfirmation = false
    @State private var hasLoaded = false
    @State private var draggedItemID: String?
    @State private var isSaving = false
    @State private var editorResetToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    editFieldsSection
                    mediaSection

                    if EditDraftStore.hasDraft(postId: postId) {
                        discardDraftSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDisabled(draggedItemID != nil)
            .navigationTitle(L10n.t("Edit Moment", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L10n.t("Save", appLanguage))
                        }
                    }
                    .disabled(isSaving || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaItems.isEmpty))
                }
            }
            .task {
                loadInitialState()
            }
            .onChange(of: text) { _, _ in
                guard hasLoaded else { return }
                saveDraft()
            }
            .onChange(of: occurredAt) { _, _ in
                guard hasLoaded else { return }
                saveDraft()
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await appendPhotos(items)
                    selectedItems = []
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    appendNewImage(data)
                }
            }
            .confirmationDialog(L10n.t("Continue editing draft?", appLanguage), isPresented: $showDraftChoice, titleVisibility: .visible) {
                Button(L10n.t("Continue Editing Draft", appLanguage)) {
                    loadDraft()
                }
                Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
                    try? store.clearEditDraft(postId: postId, reason: "draft_edit_discard")
                    loadFromCurrentItem()
                }
            } message: {
                Text(L10n.t("There is an unsaved edit draft for this moment.", appLanguage))
            }
            .confirmationDialog(L10n.t("Discard edit draft?", appLanguage), isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
                    try? store.clearEditDraft(postId: postId, reason: "draft_edit_discard")
                    loadFromCurrentItem()
                }
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
            }
        }
    }

    private var editFieldsSection: some View {
        VStack(spacing: 0) {
            MarkdownTextEditor(text: $text, externalResetToken: editorResetToken)
                .frame(minHeight: 160, alignment: .topLeading)

            Divider()

            DatePicker(
                L10n.t("Date", appLanguage),
                selection: $occurredAt,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
                .environment(\.locale, MomentDateFormatter.twentyFourHourLocale(for: appLanguage))
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var mediaSection: some View {
        VStack(spacing: 0) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: max(0, 9 - mediaItems.count), matching: .images) {
                Label(L10n.t("Add from Library", appLanguage), systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(mediaItems.count >= 9 || hasNonImageMedia)

            Divider()
                .padding(.leading, 80)

            Button {
                showingCamera = true
            } label: {
                Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(!CameraPicker.isAvailable || mediaItems.count >= 9 || hasNonImageMedia)

            if hasNonImageMedia {
                Divider()
                    .padding(.leading, 80)

                ForEach(nonImageMediaItems) { item in
                    EditableFileMediaPreview(item: item) {
                        removeMedia(item)
                    }
                    .padding(.vertical, 12)
                }
            } else if !mediaItems.isEmpty {
                Divider()
                    .padding(.leading, 80)

                EditableMediaGrid(
                    items: $mediaItems,
                    draggedItemID: $draggedItemID,
                    onRemove: removeMedia,
                    onCommit: saveDraft
                )
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var hasNonImageMedia: Bool {
        mediaItems.contains { !$0.isEditableImage }
    }

    private var nonImageMediaItems: [MomentEditMediaItem] {
        mediaItems.filter { !$0.isEditableImage }
    }

    private var discardDraftSection: some View {
        Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
            showDiscardConfirmation = true
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadInitialState() {
        guard !hasLoaded else {
            return
        }

        loadFromCurrentItem()
        hasLoaded = true

        if EditDraftStore.hasDraft(postId: postId) {
            showDraftChoice = true
        }
    }

    private func loadFromCurrentItem() {
        guard let item = store.item(id: postId) else {
            return
        }

        text = item.post.text
        occurredAt = item.post.occurredAt
        mediaItems = item.media.map { MomentEditMediaItem(id: $0.id, source: .existing($0)) }
        editorResetToken += 1
    }

    private func loadDraft() {
        guard let item = store.item(id: postId),
              let draft = EditDraftStore.load(postId: postId, currentItem: item) else {
            loadFromCurrentItem()
            return
        }

        text = draft.text
        occurredAt = draft.occurredAt
        mediaItems = Array(draft.mediaItems.prefix(9))
        editorResetToken += 1
    }

    private func saveDraft() {
        try? store.saveEditDraft(
            postId: postId,
            text: text,
            occurredAt: occurredAt,
            mediaItems: mediaItems,
            reason: "draft_edit_save"
        )
    }

    private func appendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(max(0, 9 - mediaItems.count)) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                appendNewImage(data)
            }
        }
    }

    private func appendNewImage(_ data: Data) {
        guard mediaItems.count < 9 else {
            return
        }

        mediaItems.append(MomentEditMediaItem(id: UUID().uuidString, source: .new(data)))
        saveDraft()
    }

    private func removeMedia(_ item: MomentEditMediaItem) {
        mediaItems.removeAll { $0.id == item.id }
        saveDraft()
    }

    private func save() {
        guard !isSaving else {
            return
        }

        guard let item = store.item(id: postId) else {
            dismiss()
            return
        }

        let textSnapshot = text
        let occurredAtSnapshot = occurredAt
        let mediaSnapshot = mediaItems
        isSaving = true

        Task {
            let didSave = await store.updatePost(
                item: item,
                text: textSnapshot,
                occurredAt: occurredAtSnapshot,
                mediaItems: mediaSnapshot
            )

            await MainActor.run {
                if didSave {
                    try? store.clearEditDraft(postId: postId, reason: "draft_edit_publish")
                    dismiss()
                } else {
                    isSaving = false
                }
            }
        }
    }
}

private struct EditableMediaGrid: View {
    @Binding var items: [MomentEditMediaItem]
    @Binding var draggedItemID: String?

    let onRemove: (MomentEditMediaItem) -> Void
    let onCommit: () -> Void

    @State private var activeItemID: String?
    @State private var activeLocation: CGPoint?
    @State private var didReorder = false
    @State private var lastFeedbackIndex: Int?

    private let columns = 3
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let cellSize = (proxy.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)

            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isDragging = activeItemID == item.id
                    let offset = offset(for: index, cellSize: cellSize, isDragging: isDragging)

                    EditableMediaThumbnail(item: item, sideLength: cellSize, isDragging: isDragging) {
                        onRemove(item)
                    }
                    .contentShape(Rectangle())
                    .offset(x: offset.width, y: offset.height)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
                    .zIndex(isDragging ? 2 : 0)
                    .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.05), value: items.map(\.id))
                    .gesture(dragGesture(for: item, cellSize: cellSize))
                }
            }
            .coordinateSpace(name: "edit-media-grid")
        }
        .aspectRatio(gridAspectRatio, contentMode: .fit)
    }

    private var rowCount: Int {
        max(1, Int(ceil(Double(items.count) / Double(columns))))
    }

    private var gridAspectRatio: CGFloat {
        CGFloat(columns) / CGFloat(rowCount)
    }

    private func position(for index: Int, cellSize: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(index % columns) * (cellSize + spacing),
            height: CGFloat(index / columns) * (cellSize + spacing)
        )
    }

    private func center(for index: Int, cellSize: CGFloat) -> CGPoint {
        let position = position(for: index, cellSize: cellSize)
        return CGPoint(
            x: position.width + cellSize / 2,
            y: position.height + cellSize / 2
        )
    }

    private func offset(for index: Int, cellSize: CGFloat, isDragging: Bool) -> CGSize {
        if isDragging, let activeLocation {
            return CGSize(
                width: activeLocation.x - cellSize / 2,
                height: activeLocation.y - cellSize / 2
            )
        }

        return position(for: index, cellSize: cellSize)
    }

    private func dragGesture(for item: MomentEditMediaItem, cellSize: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.08)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("edit-media-grid")))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginDragging(item, cellSize: cellSize)

                case .second(true, let drag?):
                    beginDragging(item, cellSize: cellSize)
                    activeLocation = drag.location
                    moveActiveItemIfNeeded(item, location: drag.location, cellSize: cellSize)

                default:
                    break
                }
            }
            .onEnded { _ in
                finishDragging(item)
            }
    }

    private func beginDragging(_ item: MomentEditMediaItem, cellSize: CGFloat) {
        guard activeItemID == nil else {
            return
        }

        activeItemID = item.id
        draggedItemID = item.id
        didReorder = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            activeLocation = center(for: index, cellSize: cellSize)
            lastFeedbackIndex = index
        }
    }

    private func moveActiveItemIfNeeded(_ item: MomentEditMediaItem, location: CGPoint, cellSize: CGFloat) {
        guard let from = items.firstIndex(where: { $0.id == item.id }),
              let target = nearestIndex(at: location, cellSize: cellSize),
              target != from else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.14, dampingFraction: 0.92, blendDuration: 0.04)) {
            let moved = items.remove(at: from)
            items.insert(moved, at: target)
        }

        if lastFeedbackIndex != target {
            UISelectionFeedbackGenerator().selectionChanged()
            lastFeedbackIndex = target
        }

        didReorder = true
    }

    private func finishDragging(_ item: MomentEditMediaItem) {
        defer {
            activeItemID = nil
            draggedItemID = nil
            activeLocation = nil
            didReorder = false
            lastFeedbackIndex = nil
        }

        if didReorder {
            onCommit()
        }
    }

    private func nearestIndex(at location: CGPoint, cellSize: CGFloat) -> Int? {
        guard !items.isEmpty else {
            return nil
        }

        var nearest = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        for index in items.indices {
            let center = center(for: index, cellSize: cellSize)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = index
            }
        }

        return nearest
    }
}

private struct EditableMediaThumbnail: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: MomentEditMediaItem
    let sideLength: CGFloat
    let isDragging: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            image
                .allowsHitTesting(false)
                .frame(width: sideLength, height: sideLength)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isDragging ? 0.78 : 1)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(4)
                }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.62))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(L10n.t("Remove image", appLanguage))
        }
        .frame(width: sideLength, height: sideLength)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var image: some View {
        CachedEditMediaImage(item: item)
    }
}

private struct EditableFileMediaPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: MomentEditMediaItem
    let onRemove: () -> Void

    var body: some View {
        if let media = item.existingMedia {
            ZStack(alignment: .topTrailing) {
                filePreview(media)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.62))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(L10n.t(removeLabel(for: media), appLanguage))
            }
        }
    }

    @ViewBuilder
    private func filePreview(_ media: TimelineMedia) -> some View {
        if media.isAudio {
            TimelineAudioCard(media: media)
                .padding(.trailing, 34)
        } else if media.isVideo {
            TimelineVideoCard(media: media)
        } else if media.isDocument {
            TimelineDocumentCard(media: media)
                .padding(.trailing, 34)
        }
    }

    private func removeLabel(for media: TimelineMedia) -> String {
        if media.isAudio {
            return "Remove audio"
        }

        if media.isDocument {
            return "Remove document"
        }

        return "Remove video"
    }
}

private struct CachedEditMediaImage: View {
    let item: MomentEditMediaItem

    @State private var uiImage: UIImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderImage()
                    .background(Color(.secondarySystemBackground))
            }
        }
        .task(id: item.id) {
            guard !didLoad else {
                return
            }

            didLoad = true
            uiImage = await Task.detached(priority: .userInitiated) {
                Self.loadImage(item)
            }.value
        }
    }

    nonisolated private static func loadImage(_ item: MomentEditMediaItem) -> UIImage? {
        switch item.source {
        case .existing(let media):
            return UIImage(contentsOfFile: media.localCompressedPath)

        case .new(let data):
            return UIImage(data: data)
        }
    }
}

private extension MomentEditMediaItem {
    var existingMedia: TimelineMedia? {
        if case .existing(let media) = source {
            return media
        }

        return nil
    }

    var isEditableImage: Bool {
        switch source {
        case .new:
            return true
        case .existing(let media):
            return media.isImage
        }
    }
}
