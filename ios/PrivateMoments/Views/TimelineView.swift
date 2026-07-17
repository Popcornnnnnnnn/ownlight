import AVKit
import QuickLook
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter
    @Environment(\.appLanguage) private var appLanguage
    @Binding private var calendarRoute: CalendarTimelineRoute?
    private let onOpenSettings: () -> Void
    @State private var isComposerPresented = false
    @State private var composerPresentationID = UUID()
    @State private var gallery: MediaGallery?
    @State private var videoPlayer: VideoPlayerRoute?
    @State private var documentPreview: DocumentPreviewRoute?
    @State private var detailRoute: DetailRoute?
    @State private var checkInDetailRoute: CheckInEntryDetailRoute?
    @State private var summaryRoute: AISummaryRoute?
    @State private var pendingDelete: TimelineItem?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isFilterSheetPresented = false
    @State private var selectedContentFilter: TimelineContentFilter = .all
    @State private var isFavoritesOnly = false
    @State private var isCommentedOnly = false
    @State private var selectedMonthFilter: TimelineMonthFilter?
    @State private var selectedDayFilter: TimelineDayFilter?
    @State private var selectedMatchSourceFilter: TimelineMatchSourceFilter = .all
    @State private var selectedTopicArea: TopicTagArea?
    @State private var selectedTopicTagIds = Set<String>()
    @State private var topicMatchMode: TimelineTopicMatchMode = .any
    @State private var dateJumpRequest: TimelineDateJumpRequest?
    @State private var floatingMonthTitle: String?
    @State private var isFloatingMonthVisible = false
    @State private var lastFloatingMonthAnchor: MonthAnchorValue?
    @State private var hideFloatingMonthTask: Task<Void, Never>?
    @State private var showDeleteDialogTask: Task<Void, Never>?
    @State private var isDeleteConfirmationPresented = false
    @State private var expandedCommentPostIDs = Set<String>()
    @State private var commentTargetPostId: String?
    @State private var pendingCommentTarget: TimelineItem?
    @State private var commentDraft = ""
    @State private var commentInputFocusRequest = 0
    @State private var commentInputDismissRequest = 0
    @StateObject private var composerAudioRecorder = AudioRecorderController()
    @State private var isDiscardDraftConfirmationPresented = false
    @State private var pendingDeleteComment: TimelineComment?
    @State private var isCommentDeleteConfirmationPresented = false
    @State private var relativeTimeNow = Date()
    @State private var commentFeedbackScrollTask: Task<Void, Never>?
    @State private var calendarRouteScrollTask: Task<Void, Never>?
    @State private var videoAutoplayCandidateMediaId: String?
    @State private var videoAutoplayTask: Task<Void, Never>?
    @State private var isPinnedSheetPresented = false
    @AppStorage("timelinePinnedSectionExpanded") private var isPinnedSectionExpanded = false
    @FocusState private var isSearchFocused: Bool

    init(
        calendarRoute: Binding<CalendarTimelineRoute?> = .constant(nil),
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._calendarRoute = calendarRoute
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady {
                    ProgressView()
                } else if store.timelineFeedItems.isEmpty {
                    ContentUnavailableView(L10n.t("No moments", appLanguage), systemImage: "rectangle.stack")
                } else {
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            TimelineActiveFilterBar(chips: activeFilterChips, onClearAll: clearAllFilters)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                        }

                        if !pinnedItems.isEmpty {
                            VStack(spacing: 6) {
                                PinnedMomentsSection(
                                    items: pinnedItems,
                                    isExpanded: $isPinnedSectionExpanded,
                                    onOpenSheet: {
                                        playbackCenter.pause()
                                        stopVideoAutoplay()
                                        isPinnedSheetPresented = true
                                    }
                                )

                                if isPinnedSectionExpanded && pinnedItems.count <= 3 {
                                    PinnedMomentsExpandedCard(
                                        items: pinnedItems,
                                        onOpenDetail: { item in
                                            playbackCenter.pause()
                                            stopVideoAutoplay()
                                            detailRoute = DetailRoute(postId: item.id)
                                        },
                                        onTogglePinned: { item in
                                            Task {
                                                await store.togglePinned(item)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, isPinnedSectionExpanded && pinnedItems.count <= 3 ? 10 : 0)
                            .background(Color(.systemBackground))
                        }

                        if filteredItems.isEmpty {
                            ContentUnavailableView(emptyStateTitle, systemImage: emptyStateSystemImage)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollViewReader { proxy in
                                ZStack(alignment: .top) {
                                    GeometryReader { listProxy in
                                        List {
                                            if shouldInsertTimelineMemoryLinkAtTop,
                                               let memoryLink = store.currentMemoryLink {
                                                TimelineMemoryPromptLink(link: memoryLink) {
                                                    openMemoryLink(memoryLink)
                                                }
                                                .id("timeline-memory-link-top")
                                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                                                .listRowSeparator(.hidden)
                                                .listRowBackground(Color.clear)
                                            }

                                            ForEach(groupedItems) { group in
                                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, feedItem in
                                                    Group {
                                                        switch feedItem {
                                                        case .moment(let item):
                                                            TimelineRow(
                                                                item: item,
                                                                isCommentsExpanded: expandedCommentPostIDs.contains(item.id),
                                                                searchQuery: searchText,
                                                                relativeTimeNow: relativeTimeNow,
                                                                aiSummaryRequestMediaIDs: store.aiSummaryRequestsInFlight,
                                                                searchResult: searchResult(for: feedItem),
                                                                showTagsInTimeline: store.showTagsInTimeline
                                                            ) { media, index in
                                                                openMedia(media, index: index)
                                                            } onOpenDetail: {
                                                                playbackCenter.pause()
                                                                stopVideoAutoplay()
                                                                detailRoute = DetailRoute(postId: item.id)
                                                            } onComment: {
                                                                beginComment(on: item, proxy: proxy)
                                                            } onToggleComments: {
                                                                toggleComments(for: item.id)
                                                            } onDeleteComment: { comment in
                                                                requestCommentDelete(comment)
                                                            } onOpenSummary: { media in
                                                                playbackCenter.pause()
                                                                summaryRoute = AISummaryRoute(mediaId: media.id)
                                                            } onOpenDocument: { media in
                                                                openDocument(media)
                                                            }
                                                            .id(item.id)
                                                            .background {
                                                                if index == 0 {
                                                                    monthAnchor(for: group)
                                                                }
                                                            }
                                                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                                            .listRowSeparatorTint(Color.secondary.opacity(0.14))
                                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                                Button {
                                                                    Task {
                                                                        await store.toggleFavorite(item)
                                                                    }
                                                                } label: {
                                                                    Label(
                                                                        L10n.t(item.post.isFavorite ? "Unfavorite" : "Favorite", appLanguage),
                                                                        systemImage: item.post.isFavorite ? "star.slash" : "star"
                                                                    )
                                                                }
                                                                .tint(.yellow)
                                                            }
                                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                                Button {
                                                                    requestDelete(item)
                                                                } label: {
                                                                    Label(L10n.t("Delete", appLanguage), systemImage: "trash")
                                                                }
                                                                .tint(.red)
                                                            }
                                                            .contextMenu {
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
                                                            }

                                                        case .checkIn(let checkIn):
                                                            CheckInTimelineRow(
                                                                checkIn: checkIn,
                                                                showTagsInTimeline: store.showTagsInTimeline
                                                            ) {
                                                                playbackCenter.pause()
                                                                stopVideoAutoplay()
                                                                checkInDetailRoute = CheckInEntryDetailRoute(entryId: checkIn.id)
                                                            }
                                                            .id(checkIn.id)
                                                            .background {
                                                                if index == 0 {
                                                                    monthAnchor(for: group)
                                                                }
                                                            }
                                                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                                            .listRowSeparatorTint(Color.secondary.opacity(0.14))
                                                        }

                                                        if shouldInsertTimelineMemoryLink(after: index, in: group.items),
                                                           let memoryLink = store.currentMemoryLink {
                                                            TimelineMemoryPromptLink(link: memoryLink) {
                                                                openMemoryLink(memoryLink)
                                                            }
                                                                .id("timeline-memory-prompt")
                                                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                                                                .listRowSeparator(.hidden)
                                                                .listRowBackground(Color.clear)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .listStyle(.plain)
                                        .listSectionSpacing(0)
                                        .coordinateSpace(name: "timelineList")
                                        .onPreferenceChange(MonthAnchorPreferenceKey.self) { anchors in
                                            updateFloatingMonth(from: anchors)
                                        }
                                        .onPreferenceChange(TimelineVideoVisibilityPreferenceKey.self) { videos in
                                            updateVideoAutoplay(from: videos, viewportHeight: listProxy.size.height)
                                        }
                                        .refreshable {
                                            if store.isAuthenticated {
                                                await store.syncNow()
                                            } else {
                                                try? await store.reload()
                                            }
                                        }
                                        .scrollDismissesKeyboard(.interactively)
                                        .simultaneousGesture(TapGesture().onEnded {
                                            if activeCommentTarget != nil {
                                                dismissCommentKeyboard()
                                            }
                                        })
                                    }

                                    if let floatingMonthTitle {
                                        FloatingMonthIndicator(title: floatingMonthTitle)
                                            .opacity(isFloatingMonthVisible ? 1 : 0)
                                            .offset(y: isFloatingMonthVisible ? 0 : -8)
                                            .animation(.easeOut(duration: 0.18), value: isFloatingMonthVisible)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .onChange(of: dateJumpRequest) { _, request in
                                    guard let request else {
                                        return
                                    }

                                    withAnimation(.easeInOut(duration: 0.24)) {
                                        proxy.scrollTo(request.targetID, anchor: request.anchor.unitPoint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ownlight")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TopActionButton(
                        title: L10n.t("Search", appLanguage),
                        systemImage: "magnifyingglass",
                        accessibilityIdentifier: "timeline.searchButton"
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            isSearchPresented = true
                        }
                        DispatchQueue.main.async {
                            isSearchFocused = true
                        }
                    }

                    TopActionButton(
                        title: L10n.t("Filter moments", appLanguage),
                        systemImage: "line.3.horizontal.decrease.circle",
                        accessibilityIdentifier: "timeline.filterButton"
                    ) {
                        isFilterSheetPresented = true
                    }

                    TopActionButton(
                        title: L10n.t("Settings", appLanguage),
                        systemImage: "gearshape",
                        accessibilityIdentifier: "timeline.settingsButton",
                        action: onOpenSettings
                    )

                    TopActionButton(
                        title: L10n.t("New moment", appLanguage),
                        systemImage: "square.and.pencil",
                        accessibilityIdentifier: "timeline.newMomentButton"
                    ) {
                        playbackCenter.pause()
                        composerPresentationID = UUID()
                        isComposerPresented = true
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isSearchPresented || hasSearchQuery {
                    timelineSearchChrome
                }
            }
            .sheet(isPresented: $isPinnedSheetPresented) {
                PinnedMomentsSheet(
                    items: pinnedItems,
                    onTogglePinned: { item in
                        Task {
                            await store.togglePinned(item)
                        }
                    }
                )
            }
            .sheet(isPresented: $isFilterSheetPresented) {
                TimelineFilterSheet(
                    language: appLanguage,
                    contentFilter: $selectedContentFilter,
                    isFavoritesOnly: $isFavoritesOnly,
                    isCommentedOnly: $isCommentedOnly,
                    topicTags: store.activeTopicTags,
                    selectedTopicArea: $selectedTopicArea,
                    selectedTopicTagIds: $selectedTopicTagIds,
                    topicMatchMode: $topicMatchMode,
                    showsMatchSource: hasSearchQuery,
                    matchSourceFilter: $selectedMatchSourceFilter,
                    hasActiveFilters: hasActiveFilters,
                    onClear: clearAllFilters
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isComposerPresented) {
                ComposerView(audioRecorder: composerAudioRecorder)
                    .id(composerPresentationID)
            }
            #if DEBUG
            .onAppear {
                presentComposerForUITestingIfRequested()
            }
            #endif
            .navigationDestination(item: $detailRoute) { route in
                MomentDetailView(postId: route.postId)
            }
            .sheet(item: $checkInDetailRoute) { route in
                CheckInEntryDetailView(entryId: route.entryId)
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
            .sheet(item: $summaryRoute) { route in
                if let media = mediaForSummaryRoute(route) {
                    AISummarySheet(
                        media: media,
                        summary: aiSummary(for: media),
                        onRegenerate: {
                            await requestAISummary(media: media, forceRegenerate: true)
                        },
                        onDelete: {
                            if let summary = aiSummary(for: media) {
                                deleteAISummary(summary)
                            }
                        }
                    )
                } else {
                    ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
                }
            }
            .alert(deleteConfirmationTitle, isPresented: deleteConfirmationBinding) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                    isDeleteConfirmationPresented = false
                    pendingDelete = nil
                }
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    if let pendingDelete {
                        Task {
                            await store.deletePost(pendingDelete)
                        }
                    }
                    isDeleteConfirmationPresented = false
                    pendingDelete = nil
                }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .alert(L10n.t("Delete comment?", appLanguage), isPresented: commentDeleteConfirmationBinding) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                    isCommentDeleteConfirmationPresented = false
                    pendingDeleteComment = nil
                }
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    confirmCommentDelete()
                }
            }
            .alert(L10n.t("Discard draft?", appLanguage), isPresented: discardDraftConfirmationBinding) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                    pendingCommentTarget = nil
                }
                Button(L10n.t("Discard", appLanguage), role: .destructive) {
                    discardCommentDraft()
                }
            }
            .alert(L10n.t("Error", appLanguage), isPresented: errorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let target = activeCommentTarget {
                    TimelineCommentInputBar(
                        targetSummary: commentTargetSummary(for: target),
                        text: $commentDraft,
                        focusRequest: commentInputFocusRequest,
                        dismissRequest: commentInputDismissRequest,
                        onCancel: requestCloseCommentInput,
                        onSend: sendComment
                    )
                } else {
                    Color.clear
                        .frame(height: 86)
                        .allowsHitTesting(false)
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                relativeTimeNow = now
            }
            .onChange(of: searchText) { _, value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedMatchSourceFilter = .all
                }
            }
            .onChange(of: isComposerPresented) { _, isPresented in
                if isPresented {
                    playbackCenter.pause()
                    stopVideoAutoplay()
                }
            }
            .onChange(of: gallery?.id) { _, id in
                if id != nil {
                    playbackCenter.pause()
                    stopVideoAutoplay()
                }
            }
            .onChange(of: videoPlayer?.id) { _, id in
                if id != nil {
                    playbackCenter.pause()
                    stopVideoAutoplay()
                } else {
                    videoAutoplayCandidateMediaId = nil
                }
            }
            .onChange(of: documentPreview?.id) { _, id in
                if id != nil {
                    playbackCenter.pause()
                    stopVideoAutoplay()
                }
            }
            .onChange(of: calendarRoute) { _, route in
                guard let route else {
                    return
                }

                applyCalendarRoute(route)
            }
            .onDisappear {
                hideFloatingMonthTask?.cancel()
                showDeleteDialogTask?.cancel()
                commentFeedbackScrollTask?.cancel()
                calendarRouteScrollTask?.cancel()
                playbackCenter.pauseForInterfaceChange()
                stopVideoAutoplay()
            }
        }
    }

    private var timelineSearchChrome: some View {
        timelineSearchField
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        .background(Color(.systemBackground))
        .animation(.snappy(duration: 0.22), value: isSearchPresented || hasSearchQuery)
    }

    private var timelineSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(L10n.t("Search", appLanguage), text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    isSearchPresented = hasSearchQuery
                    isSearchFocused = false
                }

            Button {
                searchText = ""
                selectedMatchSourceFilter = .all
                withAnimation(.snappy(duration: 0.22)) {
                    isSearchPresented = false
                }
                isSearchFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel(L10n.t("Clear Search", appLanguage))
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var groupedItems: [TimelineDateJumpMonthGroup] {
        TimelineDateJumpBuilder.groupsFromPresortedItems(from: timelineListItems, language: appLanguage)
    }

    private var monthMenuGroups: [TimelineDateJumpMonthGroup] {
        TimelineDateJumpBuilder.groupsFromPresortedItems(from: store.timelineFeedItems, language: appLanguage)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchQuery: Bool {
        !trimmedSearchText.isEmpty
    }

    private var filteredItems: [MomentFeedItem] {
        guard hasActiveFilters || hasSearchQuery else {
            return store.timelineFeedItems
        }

        return store.timelineFeedItems.filter { item in
            guard selectedContentFilter.includes(item) else {
                return false
            }

            if isFavoritesOnly && item.moment?.post.isFavorite != true {
                return false
            }

            if isCommentedOnly && item.comments.isEmpty {
                return false
            }

            if let selectedMonthFilter,
               !Calendar.current.isDate(item.occurredAt, equalTo: selectedMonthFilter.monthStart, toGranularity: .month) {
                return false
            }

            if let selectedDayFilter,
               !Calendar.current.isDate(item.occurredAt, inSameDayAs: selectedDayFilter.dayStart) {
                return false
            }

            if !TimelineTagFilter.matches(
                item,
                selectedArea: selectedTopicArea,
                selectedTopicTagIds: selectedTopicTagIds,
                topicMatchMode: topicMatchMode
            ) {
                return false
            }

            guard hasSearchQuery else {
                return true
            }

            let result = TimelineSearch.result(
                for: item,
                query: trimmedSearchText,
                aliasesByTagId: store.aliasesByTagId
            )
            return result.isMatch && selectedMatchSourceFilter.includes(result)
        }
    }

    private var timelineListItems: [MomentFeedItem] {
        filteredItems
    }

    private var shouldShowTimelineMemoryLink: Bool {
        store.currentMemoryLink != nil
            && !hasSearchQuery
            && !hasActiveFilters
            && !timelineListItems.isEmpty
    }

    private var shouldInsertTimelineMemoryLinkAtTop: Bool {
        guard shouldShowTimelineMemoryLink else {
            return false
        }

        return !timelineListItems.contains { Calendar.current.isDateInToday($0.occurredAt) }
    }

    private func shouldInsertTimelineMemoryLink(after index: Int, in items: [MomentFeedItem]) -> Bool {
        guard shouldShowTimelineMemoryLink,
              items.indices.contains(index),
              Calendar.current.isDateInToday(items[index].occurredAt) else {
            return false
        }

        let nextIndex = index + 1
        guard items.indices.contains(nextIndex) else {
            return true
        }

        return !Calendar.current.isDate(items[nextIndex].occurredAt, inSameDayAs: items[index].occurredAt)
    }

    private var pinnedItems: [TimelineItem] {
        guard !hasPinnedSuppressionState else {
            return []
        }

        return store.items
            .filter { $0.post.isPinned && $0.post.deletedAt == nil }
            .sorted { lhs, rhs in
                switch (lhs.post.pinnedAt, rhs.post.pinnedAt) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    if lhs.post.occurredAt != rhs.post.occurredAt {
                        return lhs.post.occurredAt > rhs.post.occurredAt
                    }

                    return lhs.id > rhs.id
                }
            }
    }

    private var hasPinnedSuppressionState: Bool {
        hasActiveFilters || hasSearchQuery
    }

    #if DEBUG
    private func presentComposerForUITestingIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--private-moments-open-composer"),
              !isComposerPresented else {
            return
        }

        DispatchQueue.main.async {
            playbackCenter.pause()
            composerPresentationID = UUID()
            isComposerPresented = true
        }
    }
    #endif

    private var hasActiveFilters: Bool {
        selectedContentFilter != .all
            || isFavoritesOnly
            || isCommentedOnly
            || selectedMonthFilter != nil
            || selectedDayFilter != nil
            || selectedTopicArea != nil
            || !selectedTopicTagIds.isEmpty
            || (selectedTopicTagIds.count > 1 && topicMatchMode == .all)
            || (hasSearchQuery && selectedMatchSourceFilter != .all)
    }

    private var activeFilterChips: [TimelineFilterChip] {
        var chips = [TimelineFilterChip]()

        if selectedContentFilter != .all {
            chips.append(
                TimelineFilterChip(
                    id: "content-\(selectedContentFilter.rawValue)",
                    title: selectedContentFilter.title(language: appLanguage),
                    systemImage: selectedContentFilter.systemImage
                ) {
                    selectedContentFilter = .all
                }
            )
        }

        if isFavoritesOnly {
            chips.append(
                TimelineFilterChip(id: "favorites", title: L10n.t("Favorites", appLanguage), systemImage: "star") {
                    isFavoritesOnly = false
                }
            )
        }

        if isCommentedOnly {
            chips.append(
                TimelineFilterChip(id: "commented", title: L10n.t("Commented", appLanguage), systemImage: "text.bubble") {
                    isCommentedOnly = false
                }
            )
        }

        if let selectedMonthFilter {
            chips.append(
                TimelineFilterChip(id: "month-\(selectedMonthFilter.id)", title: selectedMonthFilter.title, systemImage: "calendar") {
                    self.selectedMonthFilter = nil
                }
            )
        }

        if let selectedDayFilter {
            chips.append(
                TimelineFilterChip(id: "day-\(selectedDayFilter.id)", title: selectedDayFilter.title, systemImage: "calendar") {
                    self.selectedDayFilter = nil
                }
            )
        }

        if let selectedTopicArea {
            chips.append(
                TimelineFilterChip(
                    id: "area-\(selectedTopicArea.rawValue)",
                    title: selectedTopicArea.localizedTitle(language: appLanguage),
                    systemImage: selectedTopicArea.symbolName
                ) {
                    self.selectedTopicArea = nil
                }
            )
        }

        for tagId in selectedTopicTagIds.sorted() {
            guard let tag = store.tags.first(where: { $0.id == tagId }) else {
                continue
            }

            chips.append(
                TimelineFilterChip(id: "topic-\(tag.id)", title: tag.name, systemImage: "tag") {
                    selectedTopicTagIds.remove(tag.id)
                }
            )
        }

        if selectedTopicTagIds.count > 1 && topicMatchMode == .all {
            chips.append(
                TimelineFilterChip(id: "topic-match-all", title: L10n.t("Match all topics", appLanguage), systemImage: "checklist") {
                    topicMatchMode = .any
                }
            )
        }

        if hasSearchQuery && selectedMatchSourceFilter != .all {
            chips.append(
                TimelineFilterChip(
                    id: "match-\(selectedMatchSourceFilter.rawValue)",
                    title: selectedMatchSourceFilter.title(language: appLanguage),
                    systemImage: selectedMatchSourceFilter.systemImage
                ) {
                    selectedMatchSourceFilter = .all
                }
            )
        }

        return chips
    }

    private func clearAllFilters() {
        selectedContentFilter = .all
        isFavoritesOnly = false
        isCommentedOnly = false
        selectedMonthFilter = nil
        selectedDayFilter = nil
        selectedMatchSourceFilter = .all
        selectedTopicArea = nil
        selectedTopicTagIds.removeAll()
        topicMatchMode = .any
    }

    private func applyCalendarRoute(_ route: CalendarTimelineRoute) {
        searchText = ""
        clearAllFilters()
        selectedDayFilter = TimelineDayFilter(
            dayStart: route.dayStart,
            title: MomentDateFormatter.dayJumpTitle(
                for: route.dayStart,
                now: Date(),
                calendar: .current,
                language: appLanguage
            )
        )

        let targetID = route.targetItemID ?? store.timelineFeedItems
            .filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: route.dayStart) }
            .sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.sortKey > rhs.sortKey
                }

                return lhs.occurredAt > rhs.occurredAt
            }
            .first?
            .rawItemID

        if let targetID {
            scheduleCalendarRouteScroll(targetID: targetID)
        }

        calendarRoute = nil
    }

    private func scheduleCalendarRouteScroll(targetID: String) {
        calendarRouteScrollTask?.cancel()
        dateJumpRequest = TimelineDateJumpRequest(targetID: targetID)

        calendarRouteScrollTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                dateJumpRequest = TimelineDateJumpRequest(targetID: targetID)
            }
        }
    }

    private func toggleTopicFilter(_ tagId: String) {
        if selectedTopicTagIds.contains(tagId) {
            selectedTopicTagIds.remove(tagId)
        } else {
            selectedTopicTagIds.insert(tagId)
        }
    }

    private func searchResult(for item: MomentFeedItem) -> TimelineSearchResult? {
        guard hasSearchQuery else {
            return nil
        }

        return TimelineSearch.result(
            for: item,
            query: trimmedSearchText,
            aliasesByTagId: store.aliasesByTagId
        )
    }

    private var activeCommentTarget: TimelineItem? {
        guard let commentTargetPostId else {
            return nil
        }

        return store.item(id: commentTargetPostId)
    }

    private var emptyStateTitle: String {
        if hasSearchQuery {
            return L10n.t("No results", appLanguage)
        }

        if hasActiveFilters {
            return L10n.t("No matching moments", appLanguage)
        }

        return L10n.t("No moments", appLanguage)
    }

    private var emptyStateSystemImage: String {
        if hasSearchQuery {
            return "magnifyingglass"
        }

        if hasActiveFilters {
            return "line.3.horizontal.decrease.circle"
        }

        return "rectangle.stack"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.clearError() }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isDeleteConfirmationPresented },
            set: { isPresented in
                isDeleteConfirmationPresented = isPresented
                if !isPresented {
                    pendingDelete = nil
                    showDeleteDialogTask?.cancel()
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        guard let pendingDelete,
              WelcomeSampleContent.isSample(pendingDelete) else {
            return L10n.t("Delete this moment?", appLanguage)
        }

        return appLanguage == .simplifiedChinese ? "删除 welcome sample？" : "Delete welcome sample?"
    }

    private var deleteConfirmationMessage: String {
        guard let pendingDelete,
              WelcomeSampleContent.isSample(pendingDelete) else {
            return L10n.t("This removes the moment from your timeline and syncs the deletion to your Mac.", appLanguage)
        }

        return appLanguage == .simplifiedChinese
            ? "这只会删除本机教学样例，不会同步；本次安装内也不会再次自动创建。"
            : "This only removes the local teaching sample. It will not sync and will not be created again in this installation."
    }

    private var commentDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isCommentDeleteConfirmationPresented },
            set: { isPresented in
                isCommentDeleteConfirmationPresented = isPresented
                if !isPresented {
                    pendingDeleteComment = nil
                }
            }
        )
    }

    private var discardDraftConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isDiscardDraftConfirmationPresented },
            set: { isPresented in
                isDiscardDraftConfirmationPresented = isPresented
                if !isPresented {
                    pendingCommentTarget = nil
                }
            }
        )
    }

    private func requestDelete(_ item: TimelineItem) {
        showDeleteDialogTask?.cancel()
        pendingDelete = item

        showDeleteDialogTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard pendingDelete?.id == item.id else {
                    return
                }
                isDeleteConfirmationPresented = true
            }
        }
    }

    private func openMedia(_ media: [TimelineMedia], index: Int) {
        guard media.indices.contains(index) else {
            return
        }

        playbackCenter.pause()
        let selected = media[index]
        if selected.isVideo {
            stopVideoAutoplay()
            videoPlayer = VideoPlayerRoute(media: selected)
            return
        }

        let imageMedia = media.filter(\.isImage)
        let imageIndex = imageMedia.firstIndex { $0.id == selected.id } ?? 0
        gallery = MediaGallery(media: imageMedia, startIndex: imageIndex)
    }

    private func openDocument(_ media: TimelineMedia) {
        playbackCenter.pause()
        stopVideoAutoplay()

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

    private func openMemoryLink(_ link: MemoryLink) {
        playbackCenter.pause()
        stopVideoAutoplay()
        store.markMemoryLinkOpened(link)
        detailRoute = DetailRoute(postId: link.postId)
    }

    private func beginComment(on item: TimelineItem, proxy: ScrollViewProxy) {
        if commentTargetPostId != item.id && !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingCommentTarget = item
            isDiscardDraftConfirmationPresented = true
            return
        }

        commentTargetPostId = item.id
        pendingCommentTarget = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(item.id, anchor: .center)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            commentInputFocusRequest += 1
        }
    }

    private func requestCloseCommentInput() {
        if commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            closeCommentInput()
            return
        }

        pendingCommentTarget = nil
        isDiscardDraftConfirmationPresented = true
    }

    private func discardCommentDraft() {
        dismissCommentKeyboard()
        commentDraft = ""
        isDiscardDraftConfirmationPresented = false

        if let pendingCommentTarget {
            commentTargetPostId = pendingCommentTarget.id
            dateJumpRequest = TimelineDateJumpRequest(targetID: pendingCommentTarget.id)
            self.pendingCommentTarget = nil
            commentInputFocusRequest += 1
        } else {
            closeCommentInput()
        }
    }

    private func closeCommentInput() {
        dismissCommentKeyboard()
        commentTargetPostId = nil
        commentDraft = ""
    }

    private func sendComment() {
        let text = commentDraft
        guard let postId = commentTargetPostId else {
            return
        }

        Task {
            if await store.createComment(postId: postId, text: text) != nil {
                dismissCommentKeyboard()
                commentDraft = ""
                relativeTimeNow = Date()
                expandedCommentPostIDs.insert(postId)
                commentTargetPostId = nil
                scheduleCommentFeedbackScroll(postId: postId)
            }
        }
    }

    private func dismissCommentKeyboard() {
        commentInputDismissRequest += 1
    }

    private func scheduleCommentFeedbackScroll(postId: TimelineItem.ID) {
        commentFeedbackScrollTask?.cancel()
        commentFeedbackScrollTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                dateJumpRequest = TimelineDateJumpRequest(
                    targetID: postId,
                    anchor: .bottom
                )
            }

            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                dateJumpRequest = TimelineDateJumpRequest(
                    targetID: postId,
                    anchor: .bottom
                )
            }
        }
    }

    private func toggleComments(for postId: String) {
        if expandedCommentPostIDs.contains(postId) {
            expandedCommentPostIDs.remove(postId)
        } else {
            expandedCommentPostIDs.insert(postId)
        }
    }

    private func requestCommentDelete(_ comment: TimelineComment) {
        pendingDeleteComment = comment
        isCommentDeleteConfirmationPresented = true
    }

    private func confirmCommentDelete() {
        guard let comment = pendingDeleteComment else {
            return
        }

        pendingDeleteComment = nil
        isCommentDeleteConfirmationPresented = false

        Task {
            await store.deleteComment(comment)
            relativeTimeNow = Date()
        }
    }

    private func requestAISummary(media: TimelineMedia, forceRegenerate: Bool) async {
        await store.requestAISummary(for: media, forceRegenerate: forceRegenerate)
    }

    private func deleteAISummary(_ summary: TimelineAISummary) {
        Task {
            await store.deleteAISummary(summary)
        }
    }

    private func mediaForSummaryRoute(_ route: AISummaryRoute) -> TimelineMedia? {
        store.items
            .flatMap(\.media)
            .first { $0.id == route.mediaId }
    }

    private func aiSummary(for media: TimelineMedia) -> TimelineAISummary? {
        store.items
            .flatMap(\.aiSummaries)
            .first { $0.mediaId == media.id && $0.deletedAt == nil }
    }

    private func commentTargetSummary(for item: TimelineItem) -> String {
        let trimmedText = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            if trimmedText.count > 36 {
                return "\(trimmedText.prefix(36))..."
            }

            return trimmedText
        }

        if item.media.count == 1 {
            if item.media.first?.isAudio == true {
                return L10n.t("Audio moment", appLanguage)
            }
            if item.media.first?.isVideo == true {
                return L10n.t("Video moment", appLanguage)
            }
            if item.media.first?.isDocument == true {
                return L10n.t("Document moment", appLanguage)
            }
            return L10n.t("Photo moment", appLanguage)
        }

        if item.media.count > 1 {
            return "\(L10n.t("Photo moment", appLanguage)) · \(item.media.count) \(L10n.t("photos", appLanguage))"
        }

        return L10n.t("this moment", appLanguage)
    }

    private func monthAnchor(for group: TimelineDateJumpMonthGroup) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MonthAnchorPreferenceKey.self,
                value: [
                    MonthAnchorValue(
                        id: group.id,
                        title: group.title,
                        minY: proxy.frame(in: .named("timelineList")).minY
                    ),
                ]
            )
        }
        .allowsHitTesting(false)
    }

    private func updateFloatingMonth(from anchors: [MonthAnchorValue]) {
        guard let active = activeMonthAnchor(from: anchors) else {
            return
        }

        guard let previous = lastFloatingMonthAnchor else {
            floatingMonthTitle = active.title
            lastFloatingMonthAnchor = active
            return
        }

        let didMoveVertically = abs(previous.minY - active.minY) >= 4
        let didChangeMonth = previous.id != active.id
        guard didMoveVertically || didChangeMonth else {
            return
        }

        floatingMonthTitle = active.title
        lastFloatingMonthAnchor = active

        withAnimation(.easeOut(duration: 0.16)) {
            isFloatingMonthVisible = true
        }
        scheduleFloatingMonthHide()
    }

    private func activeMonthAnchor(from anchors: [MonthAnchorValue]) -> MonthAnchorValue? {
        let sortedAnchors = anchors.sorted { $0.minY < $1.minY }
        return sortedAnchors.last { $0.minY <= 72 } ?? sortedAnchors.first
    }

    private func scheduleFloatingMonthHide() {
        hideFloatingMonthTask?.cancel()
        hideFloatingMonthTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    isFloatingMonthVisible = false
                }
            }
        }
    }

    private func updateVideoAutoplay(
        from videos: [TimelineVideoVisibilityValue],
        viewportHeight: CGFloat
    ) {
        guard videoPlayer == nil else {
            stopVideoAutoplay()
            return
        }

        guard let target = videoAutoplayTarget(from: videos, viewportHeight: viewportHeight),
              let media = videoMedia(withId: target.mediaId) else {
            stopVideoAutoplay()
            return
        }

        guard videoAutoplayCandidateMediaId != media.id else {
            return
        }

        videoAutoplayCandidateMediaId = media.id
        videoAutoplayTask?.cancel()
        videoAutoplayTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            do {
                let url = try await store.localPlayableURL(for: media)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard videoAutoplayCandidateMediaId == media.id, videoPlayer == nil else {
                        return
                    }

                    playbackCenter.stop()
                    videoAutoplayCenter.play(media: media, url: url)
                }
            } catch {
                await MainActor.run {
                    if videoAutoplayCandidateMediaId == media.id {
                        videoAutoplayCandidateMediaId = nil
                    }
                }
            }
        }
    }

    private func videoAutoplayTarget(
        from videos: [TimelineVideoVisibilityValue],
        viewportHeight: CGFloat
    ) -> TimelineVideoVisibilityValue? {
        let viewportCenter = viewportHeight / 2

        return videos
            .compactMap { video -> (video: TimelineVideoVisibilityValue, score: CGFloat)? in
                let visibleHeight = max(0, min(video.minY + video.height, viewportHeight) - max(video.minY, 0))
                let visibleRatio = visibleHeight / max(video.height, 1)
                let centerIsVisible = video.midY >= 0 && video.midY <= viewportHeight

                guard visibleRatio >= 0.55 || (centerIsVisible && visibleHeight >= 160) else {
                    return nil
                }

                return (video, abs(video.midY - viewportCenter))
            }
            .min { lhs, rhs in
                lhs.score < rhs.score
            }?
            .video
    }

    private func videoMedia(withId mediaId: String) -> TimelineMedia? {
        for item in filteredItems {
            if let media = item.media.first(where: { $0.id == mediaId && $0.isVideo }) {
                return media
            }
        }

        return nil
    }

    private func stopVideoAutoplay() {
        videoAutoplayTask?.cancel()
        videoAutoplayTask = nil
        videoAutoplayCandidateMediaId = nil
        videoAutoplayCenter.stop()
    }
}

private struct TimelineFilterSheet: View {
    let language: AppResolvedLanguage
    @Binding var contentFilter: TimelineContentFilter
    @Binding var isFavoritesOnly: Bool
    @Binding var isCommentedOnly: Bool
    let topicTags: [TimelineTag]
    @Binding var selectedTopicArea: TopicTagArea?
    @Binding var selectedTopicTagIds: Set<String>
    @Binding var topicMatchMode: TimelineTopicMatchMode
    let showsMatchSource: Bool
    @Binding var matchSourceFilter: TimelineMatchSourceFilter
    let hasActiveFilters: Bool
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var topicSearchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.t("Content", language)) {
                    ForEach(TimelineContentFilter.allCases) { filter in
                        filterRow(
                            title: filter.title(language: language),
                            systemImage: filter.systemImage,
                            isSelected: contentFilter == filter
                        ) {
                            contentFilter = filter
                        }
                    }
                }

                Section(L10n.t("Attributes", language)) {
                    filterRow(
                        title: L10n.t("Favorites", language),
                        systemImage: "star",
                        isSelected: isFavoritesOnly
                    ) {
                        isFavoritesOnly.toggle()
                    }

                    filterRow(
                        title: L10n.t("Commented", language),
                        systemImage: "text.bubble",
                        isSelected: isCommentedOnly
                    ) {
                        isCommentedOnly.toggle()
                    }

                }

                if !topicTags.isEmpty {
                    Section(L10n.t("Areas", language)) {
                        filterRow(
                            title: L10n.t("Any Area", language),
                            systemImage: "square.grid.2x2",
                            isSelected: selectedTopicArea == nil
                        ) {
                            selectedTopicArea = nil
                        }

                        ForEach(availableAreas) { area in
                            filterRow(
                                title: area.localizedTitle(language: language),
                                systemImage: area.symbolName,
                                isSelected: selectedTopicArea == area
                            ) {
                                selectedTopicArea = area
                            }
                        }
                    }

                    Section(L10n.t("Topics", language)) {
                        TextField(L10n.t("Search Topics", language), text: $topicSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if filteredTopicTags.isEmpty {
                            Text(L10n.t("No matching topics", language))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(filteredTopicTags) { tag in
                            filterRow(
                                title: topicRowTitle(tag),
                                systemImage: "tag",
                                isSelected: selectedTopicTagIds.contains(tag.id)
                            ) {
                                if selectedTopicTagIds.contains(tag.id) {
                                    selectedTopicTagIds.remove(tag.id)
                                } else {
                                    selectedTopicTagIds.insert(tag.id)
                                }
                            }
                        }

                        if selectedTopicTagIds.count > 1 {
                            Toggle(
                                L10n.t("Match all topics", language),
                                isOn: Binding(
                                    get: { topicMatchMode == .all },
                                    set: { topicMatchMode = $0 ? .all : .any }
                                )
                            )
                        }
                    }
                }

                if showsMatchSource {
                    Section(L10n.t("Match Source", language)) {
                        ForEach(TimelineMatchSourceFilter.allCases) { filter in
                            filterRow(
                                title: filter.title(language: language),
                                systemImage: filter.systemImage,
                                isSelected: matchSourceFilter == filter
                            ) {
                                matchSourceFilter = filter
                            }
                        }
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button(role: .destructive) {
                            onClear()
                        } label: {
                            Label(L10n.t("Clear Filters", language), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("Filter moments", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var availableAreas: [TopicTagArea] {
        TopicTagArea.displayAreas
    }

    private var filteredTopicTags: [TimelineTag] {
        let query = topicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return topicTags
            .filter { tag in
                selectedTopicArea == nil || tag.resolvedArea == selectedTopicArea
            }
            .filter { tag in
                query.isEmpty || tag.name.lowercased().contains(query)
            }
            .sorted { lhs, rhs in
                if lhs.resolvedArea != rhs.resolvedArea {
                    return lhs.resolvedArea.title.localizedStandardCompare(rhs.resolvedArea.title) == .orderedAscending
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func topicRowTitle(_ tag: TimelineTag) -> String {
        guard selectedTopicArea == nil else {
            return tag.name
        }

        return "\(tag.name) · \(tag.resolvedArea.localizedTitle(language: language))"
    }

    private func filterRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private enum TimelineContentFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case photos
    case audio
    case video

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .all:
            return L10n.t("All Moments", language)
        case .text:
            return L10n.t("Text", language)
        case .photos:
            return L10n.t("With Photos", language)
        case .audio:
            return L10n.t("Audio", language)
        case .video:
            return L10n.t("Video", language)
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "rectangle.stack"
        case .text:
            return "text.alignleft"
        case .photos:
            return "photo.on.rectangle"
        case .audio:
            return "waveform"
        case .video:
            return "video"
        }
    }

    func includes(_ item: MomentFeedItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            switch item {
            case .moment(let moment):
                return !moment.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .checkIn(let checkIn):
                return checkIn.entry.hasNote
            }
        case .photos:
            switch item {
            case .moment(let moment):
                return moment.media.contains { $0.isImage }
            case .checkIn(let checkIn):
                return checkIn.media.contains { $0.isImage }
            }
        case .audio:
            return item.media.contains { $0.isAudio }
        case .video:
            return item.media.contains { $0.isVideo }
        }
    }
}

private enum TimelineMatchSourceFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case comments
    case summary
    case transcript
    case tags

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .all:
            return L10n.t("Any Match", language)
        case .text:
            return L10n.t("Post Text", language)
        case .comments:
            return L10n.t("Comments", language)
        case .summary:
            return L10n.t("Summary", language)
        case .transcript:
            return L10n.t("Transcript", language)
        case .tags:
            return L10n.t("Tags", language)
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "magnifyingglass"
        case .text:
            return TimelineSearchMatchSource.text.systemImage
        case .comments:
            return TimelineSearchMatchSource.comments.systemImage
        case .summary:
            return TimelineSearchMatchSource.summary.systemImage
        case .transcript:
            return TimelineSearchMatchSource.transcript.systemImage
        case .tags:
            return TimelineSearchMatchSource.tags.systemImage
        }
    }

    func includes(_ result: TimelineSearchResult) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return result.includes(.text)
        case .comments:
            return result.includes(.comments)
        case .summary:
            return result.includes(.summary)
        case .transcript:
            return result.includes(.transcript)
        case .tags:
            return result.includes(.tags)
        }
    }
}

private struct TimelineMonthFilter: Equatable {
    let monthStart: Date
    let title: String

    var id: String {
        String(Int(monthStart.timeIntervalSince1970))
    }
}

private struct TimelineDayFilter: Equatable {
    let dayStart: Date
    let title: String

    var id: String {
        String(Int(dayStart.timeIntervalSince1970))
    }
}

private struct TimelineMemoryPromptLink: View {
    let link: MemoryLink
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.blue.opacity(0.78))
                    .frame(width: 14, height: 14)

                Text(link.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue.opacity(0.86))
                    .fixedSize(horizontal: true, vertical: false)

                Text(link.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open memory from \(link.title)")
    }
}

private struct TimelineFilterChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let onRemove: () -> Void
}

private struct TimelineActiveFilterBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let chips: [TimelineFilterChip]
    let onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        chip.onRemove()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.systemImage)
                            Text(chip.title)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(L10n.t("Remove", appLanguage)) \(chip.title) \(L10n.t("filter", appLanguage))")
                }

                if !chips.isEmpty {
                    Button(L10n.t("Clear", appLanguage)) {
                        onClearAll()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Clear filters", appLanguage))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

private struct MonthAnchorValue: Equatable {
    let id: String
    let title: String
    let minY: CGFloat
}

private struct MonthAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [MonthAnchorValue] = []

    static func reduce(value: inout [MonthAnchorValue], nextValue: () -> [MonthAnchorValue]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FloatingMonthIndicator: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .padding(.top, 8)
    }
}

private struct TimelineDateJumpRequest: Equatable {
    let requestID = UUID()
    let targetID: String
    var anchor: TimelineScrollAnchor = .top
}

private enum TimelineScrollAnchor: Equatable {
    case top
    case bottom

    var unitPoint: UnitPoint {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

private struct DetailRoute: Identifiable, Hashable {
    let postId: String

    var id: String {
        postId
    }
}

private struct AISummaryRoute: Identifiable, Hashable {
    let mediaId: String

    var id: String {
        mediaId
    }
}

private struct MediaGallery: Identifiable {
    let media: [TimelineMedia]
    let startIndex: Int

    var id: String {
        "\(media.map(\.id).joined(separator: "-"))-\(startIndex)"
    }
}

struct VideoPlayerRoute: Identifiable {
    let media: TimelineMedia

    var id: String {
        media.id
    }
}

struct VideoMomentPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter

    let media: TimelineMedia

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        videoAutoplayCenter.stop()
                        playbackCenter.stop()
                        player.play()
                    }
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                ContentUnavailableView(
                    L10n.t("Video unavailable", appLanguage),
                    systemImage: "video.slash",
                    description: Text(errorMessage ?? L10n.t("Try again after sync finishes.", appLanguage))
                )
                .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(18)
            }
            .accessibilityLabel(L10n.t("Close video", appLanguage))
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadVideo() async {
        do {
            let url = try await store.localPlayableURL(for: media)
            await MainActor.run {
                player = AVPlayer(url: url)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct DocumentPreviewRoute: Identifiable, Hashable {
    let mediaId: String
    let url: URL

    var id: String {
        "\(mediaId)-\(url.path)"
    }
}

struct DocumentPreviewSheet: View {
    let route: DocumentPreviewRoute

    var body: some View {
        DocumentPreviewController(url: route.url)
            .presentationDragIndicator(.visible)
    }
}

struct DocumentPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
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
