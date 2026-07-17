import SwiftUI
import UIKit

struct MomentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter

    let postId: String

    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var gallery: DetailMediaGallery?
    @State private var videoPlayer: VideoPlayerRoute?
    @State private var documentPreview: DocumentPreviewRoute?
    @State private var isTagEditorPresented = false
    @State private var didCopyText = false

    var body: some View {
        Group {
            if let item = store.item(id: postId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(item)
                        tagsSection(item)

                        if !item.post.text.isEmpty {
                            if item.post.isAIReviewMoment {
                                AIReviewMomentDetailView(
                                    document: AIReviewMomentDocument.parse(item.post.text),
                                    sourceLabel: aiReviewSourceLabel(for: item)
                                )
                            } else {
                                MomentTextView(
                                    text: item.post.text,
                                    style: .detail,
                                    onToggleTaskItem: store.canEdit(item) ? { taskItem in
                                        toggleTaskListItem(taskItem, in: item)
                                    } : nil
                                )
                            }
                        }

                        if !item.media.isEmpty {
                            mediaGrid(item.media)
                        }
                    }
                    .padding()
                }
                .navigationTitle(L10n.t("Moment", appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    copyMomentText(item.post.text)
                                } label: {
                                    Label(L10n.t(didCopyText ? "Copied" : "Copy text", appLanguage), systemImage: didCopyText ? "checkmark" : "doc.on.doc")
                                }
                            }

                            Button {
                                Task {
                                    await store.togglePinned(item)
                                }
                            } label: {
                                Label(
                                    L10n.t(item.post.isPinned ? "Unpin moment" : "Pin moment", appLanguage),
                                    systemImage: item.post.isPinned ? "pin.slash" : "pin"
                                )
                            }

                            Button {
                                Task {
                                    await store.toggleFavorite(item)
                                }
                            } label: {
                                Label(
                                    L10n.t(item.post.isFavorite ? "Remove favorite" : "Favorite moment", appLanguage),
                                    systemImage: item.post.isFavorite ? "star.slash" : "star"
                                )
                            }

                            Button {
                                playbackCenter.pause()
                                isEditing = true
                            } label: {
                                Label(L10n.t("Edit moment", appLanguage), systemImage: "square.and.pencil")
                            }
                            .disabled(!store.canEdit(item))

                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label(L10n.t("Delete moment", appLanguage), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(L10n.t("More", appLanguage))
                    }
                }
                .sheet(isPresented: $isEditing) {
                    EditMomentView(postId: postId)
                }
                .sheet(isPresented: $isTagEditorPresented) {
                    if store.showTagsInTimeline {
                        EditTagsView(postId: postId)
                    }
                }
                .fullScreenCover(item: $gallery) { gallery in
                    MediaGalleryView(media: gallery.media, initialIndex: gallery.startIndex)
                }
                .fullScreenCover(item: $videoPlayer) { route in
                    VideoMomentPlayerView(media: route.media)
                }
                .sheet(item: $documentPreview) { route in
                    DocumentPreviewSheet(route: route)
                }
                .alert(deleteConfirmationTitle(for: item), isPresented: $confirmDelete) {
                    Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                    Button(L10n.t("Delete", appLanguage), role: .destructive) {
                        Task {
                            await store.deletePost(item)
                            dismiss()
                        }
                    }
                } message: {
                    Text(deleteConfirmationMessage(for: item))
                }
                .onDisappear {
                    playbackCenter.pauseForInterfaceChange()
                }
                .onChange(of: item.post.text) { _, _ in
                    didCopyText = false
                }
                .task(id: item.post.id) {
                    if item.post.isAIReviewMoment {
                        await store.refreshReviews()
                    }
                }
            } else {
                ContentUnavailableView(L10n.t("Moment unavailable", appLanguage), systemImage: "rectangle.stack.badge.minus")
            }
        }
    }

    private func copyMomentText(_ text: String) {
        UIPasteboard.general.string = text
        didCopyText = true

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopyText = false
            }
        }
    }

    private func toggleTaskListItem(_ taskItem: MomentTextMarkdown.ListItem, in item: TimelineItem) {
        guard let sourceLineIndex = taskItem.sourceLineIndex else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            guard let currentItem = await MainActor.run(body: { store.item(id: item.post.id) }),
                  let nextText = MomentTextMarkdown.togglingTaskListItem(
                    in: currentItem.post.text,
                    sourceLineIndex: sourceLineIndex
                  ) else {
                return
            }

            let mediaItems = currentItem.media.map { media in
                MomentEditMediaItem(id: media.id, source: .existing(media))
            }

            _ = await store.updatePost(
                item: currentItem,
                text: nextText,
                occurredAt: currentItem.post.occurredAt,
                mediaItems: mediaItems
            )
        }
    }

    private func deleteConfirmationTitle(for item: TimelineItem) -> String {
        guard WelcomeSampleContent.isSample(item) else {
            return L10n.t("Delete this moment?", appLanguage)
        }

        return appLanguage == .simplifiedChinese ? "删除 welcome sample？" : "Delete welcome sample?"
    }

    private func deleteConfirmationMessage(for item: TimelineItem) -> String {
        guard WelcomeSampleContent.isSample(item) else {
            return L10n.t("This removes the moment from your timeline and syncs the deletion to your Mac.", appLanguage)
        }

        return appLanguage == .simplifiedChinese
            ? "这只会删除本机教学样例，不会同步；本次安装内也不会再次自动创建。"
            : "This only removes the local teaching sample. It will not sync and will not be created again in this installation."
    }

    private func aiReviewSourceLabel(for item: TimelineItem) -> String? {
        guard let review = aiReviewPayload(for: item) else {
            return nil
        }

        return AIProviderSourceFormatter.label(
            provider: review.provider,
            model: review.model,
            language: appLanguage
        )
    }

    private func aiReviewPayload(for item: TimelineItem) -> ReviewPayload? {
        guard let reviewId = item.post.aiReviewId else {
            return nil
        }

        return store.weeklyReviews.first { review in
            review.id == reviewId || review.publishedPostId == item.post.id
        }
    }

    private func header(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MomentDateFormatter.detailDateTitle(for: item.post.occurredAt, language: appLanguage))
                        .font(.headline.weight(.semibold))
                    Text(MomentDateFormatter.clockTimeTitle(for: item.post.occurredAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }

            if let editedAt = item.post.localEditedAt {
                MomentDetailMetaPill(
                    title: "\(L10n.t("Edited", appLanguage)) \(MomentDateFormatter.mediumDateTimeTitle(for: editedAt, language: appLanguage))",
                    systemImage: "pencil"
                )
            }

            if !store.canEdit(item) {
                Text(L10n.t("Editing is available after this moment finishes syncing.", appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func tagsSection(_ item: TimelineItem) -> some View {
        let displayTags = item.topicTags
        if store.showTagsInTimeline && (!displayTags.isEmpty || !store.activeTopicTags.isEmpty) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if displayTags.isEmpty {
                        Text(L10n.t("No tags", appLanguage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        DetailFlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(displayTags) { assignedTag in
                                DetailTagBadge(tag: assignedTag.tag)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !store.activeTopicTags.isEmpty {
                    Button {
                        playbackCenter.pause()
                        isTagEditorPresented = true
                    } label: {
                        Image(systemName: "tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Edit tags", appLanguage))
                }
            }
        }
    }

    @ViewBuilder
    private func mediaGrid(_ media: [TimelineMedia]) -> some View {
        let audioMedia = media
            .filter(\.isAudio)
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortOrder < $1.sortOrder
            }
        let documentMedia = media
            .filter(\.isDocument)
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortOrder < $1.sortOrder
            }
        let imageMedia = media.filter(\.isImage)

        if !audioMedia.isEmpty {
            VStack(spacing: 10) {
                ForEach(audioMedia) { audio in
                    TimelineAudioCard(media: audio, style: .detail)
                }
            }
        } else if !documentMedia.isEmpty {
            VStack(spacing: 10) {
                ForEach(documentMedia) { document in
                    Button {
                        openDocument(document)
                    } label: {
                        TimelineDocumentCard(media: document)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let video = media.first, video.isVideo {
            Button {
                playbackCenter.pause()
                videoPlayer = VideoPlayerRoute(media: video)
            } label: {
                TimelineVideoCard(media: video)
            }
            .buttonStyle(.plain)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: imageMedia.count == 1 ? 1 : 3), spacing: 6) {
                ForEach(Array(imageMedia.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playbackCenter.pause()
                        gallery = DetailMediaGallery(media: imageMedia, startIndex: index)
                    } label: {
                        TimelineImage(media: item, style: imageMedia.count == 1 ? .single : .grid)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openDocument(_ media: TimelineMedia) {
        playbackCenter.pause()

        Task {
            do {
                let url = try await store.localPlayableURL(for: media)
                await MainActor.run {
                    documentPreview = DocumentPreviewRoute(mediaId: media.id, url: url)
                }
            } catch {
                await MainActor.run {
                    store.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct MomentDetailMetaPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct DetailMediaGallery: Identifiable {
    let media: [TimelineMedia]
    let startIndex: Int

    var id: String {
        "\(media.map(\.id).joined(separator: "-"))-\(startIndex)"
    }
}
