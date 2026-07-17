import Combine
import Foundation

struct AIExternalProcessingConsentRequest: Identifiable, Equatable {
    let id = "ai-external-processing-consent"
}

struct WelcomeOnboardingRequest: Identifiable, Equatable {
    let id = "welcome-onboarding"
}

@MainActor
final class TimelineStore: ObservableObject {
    @Published var items: [TimelineItem] = []
    @Published private(set) var checkInFeedEntries: [CheckInFeedEntry] = []
    @Published private(set) var timelineFeedItems: [MomentFeedItem] = []
    @Published var checkInItems: [CheckInItem] = []
    @Published var checkInEntries: [CheckInEntry] = []
    @Published var checkInMedia: [CheckInMedia] = []
    @Published var checkInAISummaries: [CheckInAISummary] = []
    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var syncMessage: String?
    @Published var isSyncing = false
    @Published var isAuthenticated = false
    @Published var serverURLString = AppSettings.serverURLString
    @Published var deviceId: String?
    @Published var lastSyncCursor = 0
    @Published var pendingOperationCount = 0
    @Published var pendingUploadCount = 0
    @Published var aiSummaryRequestsInFlight = Set<String>()
    @Published var tags: [TimelineTag] = []
    @Published var tagAliases: [TimelineTagAlias] = []
    @Published var tagUsageCounts: [String: Int] = [:]
    @Published var showTagsInTimeline = AppSettings.showTagsInTimeline
    @Published var showCheckInSummaries = AppSettings.showCheckInSummaries
    @Published var memoryLinksEnabled = AppSettings.memoryLinksEnabled
    @Published var currentMemoryLink: MemoryLink?
    @Published var aiTitleAutoInsertEnabled = AppSettings.aiTitleAutoInsertEnabled
    @Published var appAppearanceMode = AppSettings.appAppearanceMode
    @Published var markdownMathRenderingEnabled = AppSettings.markdownMathRenderingEnabled
    @Published var markdownRemoteImagesEnabled = AppSettings.markdownRemoteImagesEnabled
    @Published var markdownRawHTMLRenderingEnabled = AppSettings.markdownRawHTMLRenderingEnabled
    @Published var appLanguageMode = AppSettings.appLanguageMode
    @Published var aiLanguageMode = AppSettings.aiLanguageMode
    @Published var aiAnalysisEnabled = AppSettings.aiAnalysisEnabled
    @Published var aiExternalProcessingConsentAccepted = AppSettings.aiExternalProcessingConsentAccepted
    @Published var aiExternalProcessingConsentRequest: AIExternalProcessingConsentRequest?
    @Published var welcomeOnboardingRequest: WelcomeOnboardingRequest?
    @Published var aiProviderProfiles = AppSettings.aiProviderProfiles
    @Published var aiProviderFallbackState = AppSettings.aiProviderFallbackState
    @Published var useTextProviderForTranscription = AppSettings.useTextProviderForTranscription
    @Published var transcriptionProviderMode = AppSettings.transcriptionProviderMode
    @Published var localTranscriptionGatewaySettings = AppSettings.localTranscriptionGatewaySettings
    @Published var automaticSyncEnabled = AppSettings.automaticSyncEnabled
    @Published var weeklyReviews: [ReviewPayload] = []
    @Published var isLoadingReviews = false
    @Published var reviewGenerationInFlightId: String?
    @Published var reviewMutationIds = Set<String>()
    @Published var autoWeeklyReviewEnabled = AppSettings.autoWeeklyReviewEnabled
    @Published var publishWeeklyReviewToMoments = AppSettings.publishWeeklyReviewToMoments

    var database: LocalDatabase?
    var needsFollowUpSync = false
    var isDownloadingMedia = false
    var mediaDownloadsInFlight = Set<String>()
    var aiSummaryFollowUpSyncTask: Task<Void, Never>?
    var syncRetryTask: Task<Void, Never>?
    var syncRetryAttempt = 0
    var cloudKitAutoSyncTask: Task<Void, Never>?
    var cloudKitAutoSyncRetryTask: Task<Void, Never>?
    var cloudKitForegroundSyncTask: Task<Void, Never>?
    var cloudKitAutoSyncRetryAttempt = 0
    var isCloudKitAutoSyncing = false
    var needsCloudKitFollowUpSync = false
    var cloudKitAutoSyncDelayNanoseconds: UInt64 = 5_000_000_000
    var cloudKitPreferenceSyncDelayNanoseconds: UInt64 = 1_000_000_000
    var cloudKitForegroundSyncIntervalNanoseconds: UInt64 = 15_000_000_000
    var cloudKitAutoSyncRetryDelayNanoseconds: [UInt64] = [
        5_000_000_000,
        20_000_000_000,
        60_000_000_000,
        120_000_000_000,
        300_000_000_000
    ]
    var cloudKitSyncNowOverride: (@MainActor () async throws -> CloudKitManualSyncResult)?
    var aiTextAnalysisOverride: ((AIArtifactGenerationRequest, AIProviderProfile, String) async throws -> AIArtifactGenerationResult)?
    var speechTranscriptionOverride: ((URL, TimelineMedia) async throws -> String)?
    var localTranscriptionGatewayClient = LocalTranscriptionGatewayClient()
    var localTranscriptionGatewayOverride: ((LocalTranscriptionGatewayTranscriptionRequest) async throws -> String)?

    func bootstrap() async {
        do {
            let launchArguments = ProcessInfo.processInfo.arguments
            let shouldSeedDemoData = launchArguments.contains("--private-moments-demo-data")
            let shouldResetDemoData = launchArguments.contains("--private-moments-demo-data-reset")
            let shouldUseChineseDemoData = launchArguments.contains("--private-moments-demo-language-zh")
            #if DEBUG
            let shouldSeedMemoryLinkMockData = launchArguments.contains("--private-moments-memory-link-mock")
            #endif

            if shouldSeedDemoData {
                AppSettings.showTagsInTimeline = true
                AppSettings.showCheckInSummaries = true
                AppSettings.automaticSyncEnabled = false
                AppSettings.appAppearanceMode = .light
                AppSettings.markdownMathRenderingEnabled = true
                AppSettings.markdownRemoteImagesEnabled = false
                AppSettings.markdownRawHTMLRenderingEnabled = false
                AppSettings.appLanguageMode = shouldUseChineseDemoData ? .simplifiedChinese : .english
                showTagsInTimeline = AppSettings.showTagsInTimeline
                showCheckInSummaries = AppSettings.showCheckInSummaries
                automaticSyncEnabled = AppSettings.automaticSyncEnabled
                appAppearanceMode = AppSettings.appAppearanceMode
                markdownMathRenderingEnabled = AppSettings.markdownMathRenderingEnabled
                markdownRemoteImagesEnabled = AppSettings.markdownRemoteImagesEnabled
                markdownRawHTMLRenderingEnabled = AppSettings.markdownRawHTMLRenderingEnabled
                appLanguageMode = AppSettings.appLanguageMode
            }
            #if DEBUG
            if shouldSeedMemoryLinkMockData {
                AppSettings.memoryLinksEnabled = true
                memoryLinksEnabled = true
            }
            #endif

            AppSettings.ensureAITitleAutoInsertCutoff()
            database = try LocalDatabase.open()
            try restoreICloudSyncOptInFromHistoryIfNeeded()
            loadSessionState()
            var shouldPrepareWelcomeSample = !shouldSeedDemoData
                && !launchArguments.contains("--private-moments-checkins-mock")
            #if DEBUG
            shouldPrepareWelcomeSample = shouldPrepareWelcomeSample && !shouldSeedMemoryLinkMockData
            #endif
            if shouldSeedDemoData {
                try database?.seedDemoDataIfNeeded(
                    reset: shouldResetDemoData,
                    language: shouldUseChineseDemoData ? .simplifiedChinese : .english
                )
            } else if launchArguments.contains("--private-moments-checkins-mock") {
                try database?.seedCheckInMockDataIfNeeded()
            } else if shouldPrepareWelcomeSample,
                      !AppSettings.welcomeSampleDeleted,
                      let database {
                let didSeedWelcomeSample = try database.seedWelcomeSampleIfNeeded(
                    language: resolvedAppLanguage,
                    now: Date()
                )
                let hasWelcomeSample = try database.fetchTimelineItem(postId: WelcomeSampleContent.postId) != nil
                if !AppSettings.welcomeOnboardingShown,
                   didSeedWelcomeSample || hasWelcomeSample {
                    welcomeOnboardingRequest = WelcomeOnboardingRequest()
                }
            }
            #if DEBUG
            if shouldSeedMemoryLinkMockData {
                try database?.seedMemoryLinkMockData(now: Date())
            }
            #endif
            try await reload()
            try refreshPendingCounts()
            isReady = true

            if isAuthenticated && automaticSyncEnabled {
                Task {
                    await syncAfterBootstrap()
                }
            }

            syncCloudKitAfterBootstrapIfNeeded()

            Task {
                await refreshReviews()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async throws {
        guard let database else {
            return
        }

        items = try database.fetchTimelineItems()
        checkInItems = try database.fetchCheckInItems(includeArchived: true)
        checkInEntries = try database.fetchCheckInEntries()
        checkInMedia = try database.fetchCheckInMedia()
        checkInAISummaries = try database.fetchCheckInAISummaries()
        tags = try database.fetchTags(includeArchived: true)
            .filter { !WelcomeSampleContent.isSampleTagId($0.id) }
        tagAliases = try database.fetchTagAliases()
            .filter { alias in
                !WelcomeSampleContent.isSampleTagId(alias.tagId)
                    && !alias.id.hasPrefix("welcome-sample-")
            }
        tagUsageCounts = try database.fetchTagUsageCounts()
            .filter { !WelcomeSampleContent.isSampleTagId($0.key) }
        rebuildTimelineFeedCaches()
        refreshMemoryLink()
        await refreshReviews()
    }

    func clearError() {
        errorMessage = nil
    }

    func item(id: String) -> TimelineItem? {
        items.first { $0.id == id }
    }

    func checkInItem(id: String) -> CheckInItem? {
        checkInItems.first { $0.id == id }
    }

    func checkInEntry(id: String) -> CheckInEntry? {
        checkInEntries.first { $0.id == id }
    }

    func checkInAISummary(id: String) -> CheckInAISummary? {
        checkInAISummaries.first { $0.id == id }
    }

    func checkInAISummary(mediaId: String) -> CheckInAISummary? {
        checkInAISummaries.first { $0.mediaId == mediaId }
    }

    private func rebuildTimelineFeedCaches() {
        let feedCheckIns = TimelineFeedBuilder.checkInFeedEntries(
            items: checkInItems,
            entries: checkInEntries,
            media: checkInMedia,
            tags: tags
        )
        checkInFeedEntries = feedCheckIns
        timelineFeedItems = TimelineFeedBuilder.timelineFeedItems(moments: items, checkIns: feedCheckIns)
    }

    func canEdit(_ item: TimelineItem) -> Bool {
        item.post.deletedAt == nil && !WelcomeSampleContent.isSample(item)
    }

    func refreshPendingCounts() throws {
        guard let database else {
            pendingOperationCount = 0
            pendingUploadCount = 0
            return
        }

        pendingOperationCount = try database.pendingOperationCount()
        pendingUploadCount = try database.pendingUploadCount()
    }

    func refreshSyncedPreferencesFromAppSettings() {
        showTagsInTimeline = AppSettings.showTagsInTimeline
        showCheckInSummaries = AppSettings.showCheckInSummaries
        memoryLinksEnabled = AppSettings.memoryLinksEnabled
        aiTitleAutoInsertEnabled = AppSettings.aiTitleAutoInsertEnabled
        appAppearanceMode = AppSettings.appAppearanceMode
        appLanguageMode = AppSettings.appLanguageMode
        aiLanguageMode = AppSettings.aiLanguageMode
        aiAnalysisEnabled = AppSettings.aiAnalysisEnabled
        aiExternalProcessingConsentAccepted = AppSettings.aiExternalProcessingConsentAccepted
        useTextProviderForTranscription = AppSettings.useTextProviderForTranscription
        transcriptionProviderMode = AppSettings.transcriptionProviderMode
        autoWeeklyReviewEnabled = AppSettings.autoWeeklyReviewEnabled
        publishWeeklyReviewToMoments = AppSettings.publishWeeklyReviewToMoments
        markdownMathRenderingEnabled = AppSettings.markdownMathRenderingEnabled
        markdownRemoteImagesEnabled = AppSettings.markdownRemoteImagesEnabled
        markdownRawHTMLRenderingEnabled = AppSettings.markdownRawHTMLRenderingEnabled
        refreshMemoryLink()
    }

    func pendingOperationTypeCounts() -> [OutboxOperationTypeCount] {
        guard let database else {
            return []
        }

        return (try? database.pendingOperationTypeCounts()) ?? []
    }

    var activePrimaryTags: [TimelineTag] {
        tags.filter { $0.type == "primary" && !$0.isArchived }
    }

    var activeTopicTags: [TimelineTag] {
        tags.filter { $0.type == "topic" && !$0.isArchived }
    }

    var aliasesByTagId: [String: [TimelineTagAlias]] {
        Dictionary(grouping: tagAliases.filter { $0.deletedAt == nil }, by: \.tagId)
    }

    func setShowTagsInTimeline(_ value: Bool) {
        AppSettings.showTagsInTimeline = value
        showTagsInTimeline = value
        enqueueCloudKitPreferenceChange(reason: "preference_show_tags")
    }

    func setShowCheckInSummaries(_ value: Bool) {
        AppSettings.showCheckInSummaries = value
        showCheckInSummaries = value
        enqueueCloudKitPreferenceChange(reason: "preference_checkin_summaries")
    }

    func setMemoryLinksEnabled(_ value: Bool) {
        AppSettings.memoryLinksEnabled = value
        memoryLinksEnabled = value
        refreshMemoryLink()
        enqueueCloudKitPreferenceChange(reason: "preference_memory_links")
    }

    func markMemoryLinkOpened(_ link: MemoryLink) {
        do {
            try database?.markMemoryLinkOpened(postId: link.postId, shownDate: link.shownDate)
        } catch {
            // Memory link history should never block opening the moment.
        }
    }

    private func refreshMemoryLink(now: Date = Date()) {
        guard memoryLinksEnabled else {
            currentMemoryLink = nil
            return
        }

        do {
            guard let database else {
                currentMemoryLink = nil
                return
            }

            let history = try database.fetchMemoryLinkHistory()
            let link = MemoryLinkSelector.select(
                from: items.filter { !WelcomeSampleContent.isSample($0) },
                history: history,
                now: now,
                calendar: .current
            )
            currentMemoryLink = link
            if let link {
                try database.recordMemoryLinkShown(link, shownAt: now)
            }
        } catch {
            currentMemoryLink = nil
        }
    }

    func setAITitleAutoInsertEnabled(_ value: Bool) {
        AppSettings.aiTitleAutoInsertEnabled = value
        aiTitleAutoInsertEnabled = value
        enqueueCloudKitPreferenceChange(reason: "preference_ai_title")
    }

    func acceptWelcomeOnboarding() {
        AppSettings.welcomeOnboardingShown = true
        welcomeOnboardingRequest = nil
    }

    func setAppAppearanceMode(_ mode: AppAppearanceMode) {
        AppSettings.appAppearanceMode = mode
        appAppearanceMode = mode
        enqueueCloudKitPreferenceChange(reason: "preference_appearance")
    }

    func setMarkdownMathRenderingEnabled(_ value: Bool) {
        AppSettings.markdownMathRenderingEnabled = value
        markdownMathRenderingEnabled = value
        enqueueCloudKitPreferenceChange(reason: "preference_markdown")
    }

    func setMarkdownRemoteImagesEnabled(_ value: Bool) {
        AppSettings.markdownRemoteImagesEnabled = value
        markdownRemoteImagesEnabled = value
        enqueueCloudKitPreferenceChange(reason: "preference_markdown")
    }

    func setMarkdownRawHTMLRenderingEnabled(_ value: Bool) {
        AppSettings.markdownRawHTMLRenderingEnabled = value
        markdownRawHTMLRenderingEnabled = value
        enqueueCloudKitPreferenceChange(reason: "preference_markdown")
    }

    var resolvedAppLanguage: AppResolvedLanguage {
        appLanguageMode.resolvedLanguage
    }

    func setAppLanguageMode(_ mode: AppLanguageMode) {
        if mode != appLanguageMode {
            AppSettings.preferredSpeechTranscriptionLocaleIdentifier = nil
        }
        AppSettings.appLanguageMode = mode
        appLanguageMode = mode
        enqueueCloudKitPreferenceChange(reason: "preference_app_language")
    }

    func setAILanguageMode(_ mode: AILanguageMode) {
        if mode != aiLanguageMode {
            AppSettings.preferredSpeechTranscriptionLocaleIdentifier = nil
        }
        AppSettings.aiLanguageMode = mode
        aiLanguageMode = mode
        enqueueCloudKitPreferenceChange(reason: "preference_ai_language")
    }

    func setAIAnalysisEnabled(_ value: Bool) {
        guard value else {
            AppSettings.aiAnalysisEnabled = false
            aiAnalysisEnabled = false
            enqueueCloudKitPreferenceChange(reason: "preference_ai_analysis")
            return
        }

        guard aiExternalProcessingConsentAccepted else {
            AppSettings.aiAnalysisEnabled = false
            aiAnalysisEnabled = false
            presentAIExternalProcessingConsent()
            return
        }

        AppSettings.aiAnalysisEnabled = value
        aiAnalysisEnabled = value
        enqueueCloudKitPreferenceChange(reason: "preference_ai_analysis")
    }

    func presentAIExternalProcessingConsent() {
        aiExternalProcessingConsentRequest = AIExternalProcessingConsentRequest()
    }

    func showAIExternalProcessingConsentIfNeeded() {
        guard aiAnalysisEnabled && !aiExternalProcessingConsentAccepted else {
            return
        }

        presentAIExternalProcessingConsent()
    }

    func acceptAIExternalProcessingConsent() {
        AppSettings.aiExternalProcessingConsentAccepted = true
        aiExternalProcessingConsentAccepted = true
        aiExternalProcessingConsentRequest = nil
        AppSettings.aiAnalysisEnabled = true
        aiAnalysisEnabled = true
        enqueueCloudKitPreferenceChange(reason: "preference_ai_consent")
    }

    func declineAIExternalProcessingConsent() {
        aiExternalProcessingConsentRequest = nil
        guard !aiExternalProcessingConsentAccepted else {
            return
        }

        AppSettings.aiAnalysisEnabled = false
        aiAnalysisEnabled = false
        enqueueCloudKitPreferenceChange(reason: "preference_ai_consent_decline")
    }

    func resetAIExternalProcessingConsent() {
        AppSettings.aiExternalProcessingConsentAccepted = false
        aiExternalProcessingConsentAccepted = false
        aiExternalProcessingConsentRequest = nil
        AppSettings.aiAnalysisEnabled = false
        aiAnalysisEnabled = false
        enqueueCloudKitPreferenceChange(reason: "preference_ai_consent_reset")
    }

    func requireAIExternalProcessingConsent() throws {
        guard aiExternalProcessingConsentAccepted else {
            presentAIExternalProcessingConsent()
            throw AITextAnalysisError.externalProcessingConsentRequired
        }
    }

    func saveAIProviderProfile(_ profile: AIProviderProfile) {
        var profiles = aiProviderProfiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles = profiles
            .enumerated()
            .map { index, existing in
                var updated = existing
                updated.sortOrder = index
                return updated
            }

        AppSettings.aiProviderProfiles = profiles
        aiProviderProfiles = profiles
        clearAIProviderFailureState(profileId: profile.id)
    }

    func deleteAIProviderProfile(id: String) {
        let profiles = aiProviderProfiles
            .filter { $0.id != id }
            .enumerated()
            .map { index, profile in
                var updated = profile
                updated.sortOrder = index
                return updated
            }
        try? KeychainStore.clearAIProviderAPIKey(profileId: id)
        AppSettings.aiProviderProfiles = profiles
        aiProviderProfiles = profiles
        clearAIProviderFailureState(profileId: id)
    }

    func clearAIProviderFailureState(profileId: String) {
        var state = aiProviderFallbackState
        state.recordSuccess(profileId: profileId)
        AppSettings.aiProviderFallbackState = state
        aiProviderFallbackState = state
    }

    func moveAIProviderProfiles(from source: IndexSet, to destination: Int) {
        var profiles = aiProviderProfiles.sorted { $0.sortOrder < $1.sortOrder }
        profiles.move(fromOffsets: source, toOffset: destination)
        profiles = profiles.enumerated().map { index, profile in
            var updated = profile
            updated.sortOrder = index
            return updated
        }

        AppSettings.aiProviderProfiles = profiles
        aiProviderProfiles = profiles
    }

    func setUseTextProviderForTranscription(_ value: Bool) {
        AppSettings.useTextProviderForTranscription = value
        useTextProviderForTranscription = value
        enqueueCloudKitPreferenceChange(reason: "preference_transcription")
    }

    func setTranscriptionProviderMode(_ mode: TranscriptionProviderMode) {
        AppSettings.transcriptionProviderMode = mode
        transcriptionProviderMode = AppSettings.transcriptionProviderMode
        enqueueCloudKitPreferenceChange(reason: "preference_transcription")
    }

    func setLocalTranscriptionGatewaySettings(_ settings: LocalTranscriptionGatewaySettings) {
        AppSettings.localTranscriptionGatewaySettings = settings
        localTranscriptionGatewaySettings = AppSettings.localTranscriptionGatewaySettings
    }

    func setAutomaticSyncEnabled(_ value: Bool) {
        AppSettings.automaticSyncEnabled = value
        automaticSyncEnabled = value

        if value {
            Task {
                await syncPendingWorkIfNeeded(showErrors: false)
            }
        } else {
            needsFollowUpSync = false
            cancelScheduledSyncRetry()
            aiSummaryFollowUpSyncTask?.cancel()
            aiSummaryFollowUpSyncTask = nil
            syncMessage = "Local-only"
        }
    }

    func refreshReviews() async {
        weeklyReviews = localReviewsIncludingSyncedReviewMoments()
    }

    func generateWeeklyReview() async {
        guard !isReviewGenerationInFlight else {
            return
        }

        reviewGenerationInFlightId = "manual-generate"
        syncMessage = "Generating review"
        defer {
            reviewGenerationInFlightId = nil
        }

        do {
            guard aiAnalysisEnabled else {
                throw AITextAnalysisError.noConfiguredProvider
            }
            let source = localWeeklyReviewSource()
            let result = try await generateTextArtifact(AIArtifactGenerationRequest(
                feature: .weeklyReview,
                title: "Weekly Review",
                sourceText: source.text,
                languageMode: aiLanguageMode,
                topicVocabulary: activeTopicTags.map(\.name)
            ))
            var reviews = AppSettings.localWeeklyReviews.filter { $0.deletedAt == nil }
            reviews.insert(makeLocalReview(result: result, start: source.start, end: source.end, trigger: "manual"), at: 0)
            saveLocalReviews(reviews)
            syncMessage = "Review ready"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerateReview(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight else {
            return
        }

        reviewGenerationInFlightId = review.id
        syncMessage = "Regenerating review"
        defer {
            reviewGenerationInFlightId = nil
        }

        do {
            guard aiAnalysisEnabled else {
                throw AITextAnalysisError.noConfiguredProvider
            }
            let source = localWeeklyReviewSource()
            let result = try await generateTextArtifact(
                AIArtifactGenerationRequest(
                    feature: .weeklyReview,
                    title: review.content.title ?? "Weekly Review",
                    sourceText: source.text,
                    languageMode: aiLanguageMode,
                    topicVocabulary: activeTopicTags.map(\.name)
                ),
                forceRetry: true
            )
            var reviews = AppSettings.localWeeklyReviews.filter { $0.deletedAt == nil && $0.id != review.id }
            reviews.insert(makeLocalReview(
                result: result,
                start: source.start,
                end: source.end,
                trigger: "manual_regenerate",
                regeneratedFromReviewId: review.id
            ), at: 0)
            saveLocalReviews(reviews)
            syncMessage = "Review ready"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteReview(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight, !isReviewMutationInFlight(review) else {
            return
        }

        reviewMutationIds.insert(review.id)
        syncMessage = "Deleting review"
        defer {
            reviewMutationIds.remove(review.id)
        }

        saveLocalReviews(AppSettings.localWeeklyReviews.filter { $0.id != review.id })
        syncMessage = "Review deleted"
    }

    func deleteReviews(at offsets: IndexSet) async {
        let reviews = offsets.compactMap { index in
            weeklyReviews.indices.contains(index) ? weeklyReviews[index] : nil
        }
        for review in reviews {
            await deleteReview(review)
        }
    }

    func isReviewMutationInFlight(_ review: ReviewPayload) -> Bool {
        review.status == "generating" || reviewMutationIds.contains(review.id)
    }

    var isReviewGenerationInFlight: Bool {
        reviewGenerationInFlightId != nil || weeklyReviews.contains { $0.status == "generating" }
    }

    func publishReviewAsMoment(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight else {
            return
        }

        let text = reviewMomentText(review)
        let published = await createPost(
            text: text,
            imageData: [],
            occurredAt: review.parsedRangeEnd ?? Date(),
            primaryTagId: "tag-primary-review"
        )
        if published, let postId = items.first(where: { $0.post.text == text })?.post.id {
            var reviews = AppSettings.localWeeklyReviews.filter { $0.id != review.id }
            reviews.insert(copyReview(review, publishedPostId: postId), at: 0)
            saveLocalReviews(reviews)
            syncMessage = "Review published"
        }
    }

    @discardableResult
    func sendReviewFeedback(
        review: ReviewPayload,
        type: String,
        enabled: Bool,
        note: String? = nil
    ) async -> ReviewPayload? {
        guard isAuthenticated else {
            return nil
        }

        do {
            let token = try KeychainStore.deviceToken()
            let updatedReview = try await withAvailableAPIClient(token: token) { client in
                try await client.sendReviewFeedback(reviewId: review.id, type: type, enabled: enabled, note: note)
            }
            weeklyReviews.removeAll { $0.id == updatedReview.id }
            weeklyReviews.insert(updatedReview, at: 0)
            syncMessage = "Feedback saved"
            return updatedReview
        } catch {
            handleSyncError(error, showErrors: true)
            return nil
        }
    }

    func setAutoWeeklyReviewEnabled(_ value: Bool) {
        applyLocalReviewSettings(
            autoWeeklyEnabled: value,
            publishWeeklyToMoments: value ? publishWeeklyReviewToMoments : false
        )
    }

    func setPublishWeeklyReviewToMoments(_ value: Bool) {
        applyLocalReviewSettings(
            autoWeeklyEnabled: autoWeeklyReviewEnabled,
            publishWeeklyToMoments: autoWeeklyReviewEnabled && value
        )
    }

    private func applyLocalReviewSettings(
        autoWeeklyEnabled: Bool,
        publishWeeklyToMoments: Bool
    ) {
        AppSettings.autoWeeklyReviewEnabled = autoWeeklyEnabled
        AppSettings.publishWeeklyReviewToMoments = publishWeeklyToMoments
        autoWeeklyReviewEnabled = autoWeeklyEnabled
        publishWeeklyReviewToMoments = publishWeeklyToMoments
        enqueueCloudKitPreferenceChange(reason: "preference_weekly_review")
    }

    private func enqueueCloudKitPreferenceChange(reason: String) {
        do {
            try enqueueCloudKitPreferenceUpsert(reason: reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
