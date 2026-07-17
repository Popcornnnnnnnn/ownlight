import Foundation

extension TimelineStore {
    func generateTextArtifact(
        _ request: AIArtifactGenerationRequest,
        forceRetry: Bool = false
    ) async throws -> AIArtifactGenerationResult {
        guard aiAnalysisEnabled else {
            throw AITextAnalysisError.noConfiguredProvider
        }
        try requireAIExternalProcessingConsent()

        let now = Date()
        let candidates = aiProviderProfiles
            .filter { profile in
                profile.isConfiguredForRequests
                    && !aiProviderFallbackState.needsAttention(profileId: profile.id)
                    && (forceRetry || !aiProviderFallbackState.isCoolingDown(profileId: profile.id, now: now))
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.displayName < rhs.displayName
                }

                return lhs.sortOrder < rhs.sortOrder
            }

        guard !candidates.isEmpty else {
            throw AITextAnalysisError.noConfiguredProvider
        }

        var lastRecoverableError: Error?

        for profile in candidates {
            guard let apiKey = try KeychainStore.aiProviderAPIKey(profileId: profile.id), !apiKey.isEmpty else {
                let error = AITextAnalysisError.missingAPIKey(profile.displayName)
                recordAIProviderFailure(profileId: profile.id, category: .needsAttention, message: error.localizedDescription)
                throw error
            }

            do {
                let result: AIArtifactGenerationResult
                if let aiTextAnalysisOverride {
                    result = try await aiTextAnalysisOverride(request, profile, apiKey)
                } else {
                    result = try await AITextAnalysisClient().generate(request: request, profile: profile, apiKey: apiKey)
                }
                var state = aiProviderFallbackState
                state.recordSuccess(profileId: profile.id)
                AppSettings.aiProviderFallbackState = state
                aiProviderFallbackState = state
                return result
            } catch {
                let category = (error as? AITextAnalysisError)?.failureCategory ?? .transient
                recordAIProviderFailure(profileId: profile.id, category: category, message: error.localizedDescription)
                switch category {
                case .transient, .artifactGeneration:
                    lastRecoverableError = error
                    continue
                case .needsAttention:
                    throw error
                }
            }
        }

        throw lastRecoverableError ?? AITextAnalysisError.noConfiguredProvider
    }

    private func recordAIProviderFailure(
        profileId: String,
        category: AIProviderFailureCategory,
        message: String?
    ) {
        var state = aiProviderFallbackState
        state.recordFailure(profileId: profileId, category: category, message: message)
        AppSettings.aiProviderFallbackState = state
        aiProviderFallbackState = state
    }

    func transcribeTimelineMediaIfNeeded(_ media: TimelineMedia, database: LocalDatabase) async throws -> String {
        if let existing = media.transcriptionText?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }

        try database.updateMediaTranscriptionStatus(
            mediaId: media.id,
            status: "transcribing",
            error: nil,
            updatedAt: Date()
        )
        try await reload()

        do {
            let inputURL = try await LocalAudioExtractor.audioURLForTranscription(media: media)
            let transcript = try await transcribeAudio(inputURL, media: media)
            try database.updateMediaTranscription(
                mediaId: media.id,
                transcriptionText: transcript,
                updatedAt: Date(),
                operation: nil
            )
            return transcript
        } catch {
            try? database.updateMediaTranscriptionStatus(
                mediaId: media.id,
                status: "failed",
                error: error.localizedDescription,
                updatedAt: Date()
            )
            throw error
        }
    }

    func transcribeCheckInMediaIfNeeded(_ media: CheckInMedia, database: LocalDatabase) async throws -> String {
        if let existing = media.transcriptionText?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }

        try database.updateCheckInMediaTranscriptionStatus(
            mediaId: media.id,
            status: "transcribing",
            error: nil,
            updatedAt: Date()
        )
        try await reload()

        let timelineMedia = TimelineMedia(
            id: media.id,
            postId: media.entryId,
            kind: media.kind,
            localCompressedPath: media.localCompressedPath,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: media.remoteCompressedPath,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: media.uploadStatus,
            mimeType: media.mimeType,
            durationSeconds: media.durationSeconds,
            transcriptionText: media.transcriptionText,
            transcriptionStatus: media.transcriptionStatus,
            transcriptionError: media.transcriptionError,
            transcriptionUpdatedAt: media.transcriptionUpdatedAt,
            sortOrder: media.sortOrder,
            checksum: media.checksum,
            createdAt: media.createdAt,
            updatedAt: media.updatedAt
        )

        do {
            let inputURL = try await LocalAudioExtractor.audioURLForTranscription(media: timelineMedia)
            let transcript = try await transcribeAudio(inputURL, media: timelineMedia)
            try database.updateCheckInMediaTranscription(
                mediaId: media.id,
                transcriptionText: transcript,
                updatedAt: Date()
            )
            return transcript
        } catch {
            try? database.updateCheckInMediaTranscriptionStatus(
                mediaId: media.id,
                status: "failed",
                error: error.localizedDescription,
                updatedAt: Date()
            )
            throw error
        }
    }

    private func transcribeAudio(_ inputURL: URL, media: TimelineMedia) async throws -> String {
        switch transcriptionProviderMode {
        case .localGateway, .customOpenAICompatible:
            try requireAIExternalProcessingConsent()
            let settings = localTranscriptionGatewaySettings
            let gatewayURLString = settings.normalizedURLString
            guard !gatewayURLString.isEmpty else {
                throw LocalTranscriptionGatewayError.invalidURL
            }
            guard let token = try KeychainStore.transcriptionProviderAPIKey(),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalTranscriptionGatewayError.missingToken
            }
            let request = LocalTranscriptionGatewayTranscriptionRequest(
                audioURL: inputURL,
                media: media,
                gatewayURLString: gatewayURLString,
                model: settings.normalizedModel,
                token: token
            )
            if let localTranscriptionGatewayOverride {
                return try await localTranscriptionGatewayOverride(request)
            }
            let transcript = try await localTranscriptionGatewayClient.transcribe(
                audioURL: inputURL,
                urlString: gatewayURLString,
                token: token,
                model: settings.normalizedModel
            )
            return transcript.text
        case .iPhoneOnDevice:
            if let speechTranscriptionOverride {
                return try await speechTranscriptionOverride(inputURL, media)
            }
            return try await LocalSpeechTranscriber.transcribe(
                url: inputURL,
                aiLanguageMode: aiLanguageMode,
                appLanguageMode: appLanguageMode
            )
        }
    }

    func makeTimelineAISummary(
        media: TimelineMedia,
        existing: TimelineAISummary?,
        status: String,
        now: Date,
        result: AIArtifactGenerationResult? = nil,
        transcriptLength: Int? = nil
    ) throws -> TimelineAISummary {
        TimelineAISummary(
            id: existing?.id ?? "iphone-\(media.id)",
            postId: media.postId,
            mediaId: media.id,
            status: status,
            format: "document_v1",
            language: aiLanguageMode.rawValue,
            overview: result?.summaryText ?? existing?.overview,
            keyPoints: result?.keyPoints ?? existing?.keyPoints ?? [],
            sections: existing?.sections ?? [],
            summaryText: result?.summaryText ?? existing?.summaryText,
            documentTitle: result?.documentTitle ?? existing?.documentTitle,
            oneLiner: result?.oneLiner ?? existing?.oneLiner,
            documentBlocks: result?.documentBlocks ?? existing?.documentBlocks ?? [],
            inputTranscriptLength: transcriptLength ?? existing?.inputTranscriptLength,
            inputDurationSeconds: media.durationSeconds,
            inputTokenCount: result?.tokenUsage?.inputTokens ?? existing?.inputTokenCount,
            outputTokenCount: result?.tokenUsage?.outputTokens ?? existing?.outputTokenCount,
            totalTokenCount: result?.tokenUsage?.resolvedTotalTokens ?? existing?.totalTokenCount,
            promptVersion: "media-summary-v4",
            provider: selectedProviderDisplayName,
            model: selectedProviderModel,
            errorCode: nil,
            errorMessage: nil,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    func makeCheckInAISummary(
        media: CheckInMedia,
        existing: CheckInAISummary?,
        status: String,
        now: Date,
        result: AIArtifactGenerationResult? = nil,
        transcriptLength: Int? = nil
    ) -> CheckInAISummary {
        CheckInAISummary(
            id: existing?.id ?? "iphone-checkin-\(media.id)",
            entryId: media.entryId,
            mediaId: media.id,
            status: status,
            format: "document_v1",
            language: aiLanguageMode.rawValue,
            overview: result?.summaryText ?? existing?.overview,
            keyPoints: result?.keyPoints ?? existing?.keyPoints ?? [],
            sections: existing?.sections ?? [],
            summaryText: result?.summaryText ?? existing?.summaryText,
            documentTitle: result?.documentTitle ?? existing?.documentTitle,
            oneLiner: result?.oneLiner ?? existing?.oneLiner,
            documentBlocks: result?.documentBlocks ?? existing?.documentBlocks ?? [],
            inputTranscriptLength: transcriptLength ?? existing?.inputTranscriptLength,
            inputDurationSeconds: media.durationSeconds,
            inputTokenCount: result?.tokenUsage?.inputTokens ?? existing?.inputTokenCount,
            outputTokenCount: result?.tokenUsage?.outputTokens ?? existing?.outputTokenCount,
            totalTokenCount: result?.tokenUsage?.resolvedTotalTokens ?? existing?.totalTokenCount,
            promptVersion: "checkin-summary-v1",
            provider: selectedProviderDisplayName,
            model: selectedProviderModel,
            errorCode: nil,
            errorMessage: nil,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    func applyAISuggestedTags(
        _ names: [String],
        areaId: String?,
        postId: String,
        summaryId: String,
        database: LocalDatabase
    ) throws {
        let cleanedNames = uniqueSuggestedTopicNames(names)
        guard !cleanedNames.isEmpty else {
            return
        }
        guard let post = try database.fetchPost(id: postId), post.tagsUserEditedAt == nil else {
            return
        }

        let existingAssignments = try database.fetchAssignedTags(postId: postId)
        let existingTopicIds = Set(existingAssignments.filter { $0.role == "topic" && $0.deletedAt == nil }.map(\.tagId))
        let activeTopics = try database.fetchTags(type: "topic")
            .filter { !$0.isArchived && !WelcomeSampleContent.isSampleTagId($0.id) }
        let aliasesByTagId = Dictionary(
            grouping: try database.fetchTagAliases()
                .filter { !WelcomeSampleContent.isSampleTagId($0.tagId) },
            by: \.tagId
        )
        var assignedTagIds = existingTopicIds
        let now = Date()

        for name in cleanedNames.prefix(5) {
            let resolvedArea = TopicTagArea.fromProviderValue(areaId, topicName: name)
            let normalized = LocalDatabase.normalizedTagName(name)
            let matchedTag = reusableTopicTag(
                named: name,
                normalizedName: normalized,
                candidates: activeTopics,
                aliasesByTagId: aliasesByTagId
            )
            let existingTag = matchedTag == nil ? try database.fetchTag(normalizedName: normalized) : nil
            var tag = matchedTag ?? existingTag ?? TimelineTag(
                id: UUID().uuidString,
                type: "topic",
                name: name,
                normalizedName: normalized,
                colorHex: nil,
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil,
                areaId: resolvedArea.rawValue
            )

            if tag.isTopic, !TopicTagArea.isFixedAreaId(tag.areaId) {
                tag.areaId = resolvedArea.rawValue
                tag.updatedAt = now
            }

            try database.upsertTag(tag)
            try enqueueCloudKitTagUpsert(tagId: tag.id, reason: "ai_topic_tag", now: now)
            guard !assignedTagIds.contains(tag.id) else {
                continue
            }
            assignedTagIds.insert(tag.id)
            let assignedTag = TimelineAssignedTag(
                id: UUID().uuidString,
                postId: postId,
                tagId: tag.id,
                role: "topic",
                source: "ai",
                confidence: nil,
                aiSummaryId: summaryId,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                tag: tag
            )
            try database.upsertAssignedTag(assignedTag)
            try enqueueCloudKitPostTagUpsert(assignmentId: assignedTag.id, reason: "ai_topic_assignment", now: now)
        }
    }

    private func uniqueSuggestedTopicNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 }
            .filter { name in
                seen.insert(LocalDatabase.normalizedTagName(name)).inserted
            }
    }

    private func reusableTopicTag(
        named name: String,
        normalizedName: String,
        candidates: [TimelineTag],
        aliasesByTagId: [String: [TimelineTagAlias]]
    ) -> TimelineTag? {
        let compactName = compactTopicTagName(name)
        var best: (tag: TimelineTag, score: Int)?

        for candidate in candidates where candidate.isTopic && !candidate.isArchived {
            let terms = [candidate.name] + (aliasesByTagId[candidate.id] ?? []).map(\.alias)
            for term in terms {
                let score = topicReuseScore(
                    normalizedName: normalizedName,
                    compactName: compactName,
                    candidateName: term
                )
                guard score > 0 else {
                    continue
                }

                if best == nil || score > best!.score {
                    best = (candidate, score)
                }
            }
        }

        return best?.tag
    }

    private func topicReuseScore(
        normalizedName: String,
        compactName: String,
        candidateName: String
    ) -> Int {
        let normalizedCandidate = LocalDatabase.normalizedTagName(candidateName)
        let compactCandidate = compactTopicTagName(candidateName)

        if normalizedName == normalizedCandidate {
            return 100
        }

        if !compactName.isEmpty, compactName == compactCandidate {
            return 90
        }

        guard compactName.count >= 3,
              compactCandidate.count >= 3,
              !isGenericTopicCore(compactName),
              !isGenericTopicCore(compactCandidate) else {
            return 0
        }

        if compactName.contains(compactCandidate) {
            return 70 + min(compactCandidate.count, 20)
        }

        if compactCandidate.contains(compactName) {
            return 60 + min(compactName.count, 20)
        }

        return 0
    }

    private func compactTopicTagName(_ value: String) -> String {
        LocalDatabase.normalizedTagName(value)
            .replacingOccurrences(of: "[\\s\\p{P}\\p{S}_]+", with: "", options: .regularExpression)
    }

    private func isGenericTopicCore(_ value: String) -> Bool {
        [
            "ai",
            "app",
            "ios",
            "技术",
            "产品",
            "设计",
            "学习",
            "知识",
            "工作",
            "生活",
            "健康",
            "运动",
            "情绪",
            "关系"
        ].contains(value)
    }

    func scheduleAIForMediaIfNeeded(_ media: [TimelineMedia]) {
        guard aiAnalysisEnabled else {
            return
        }
        for item in media where item.isAudio || item.isVideo {
            Task {
                await requestAISummary(for: item)
            }
        }
    }

    func requestCheckInAISummary(for media: CheckInMedia, forceRegenerate: Bool = false) async {
        guard media.isAudio || media.isVideo else {
            return
        }
        do {
            guard aiAnalysisEnabled else {
                throw AITextAnalysisError.noConfiguredProvider
            }
            guard let database else {
                throw StoreError.notReady
            }
            let now = Date()
            let existing = try database.fetchCheckInAISummary(mediaId: media.id)
            try database.upsertCheckInAISummary(makeCheckInAISummary(
                media: media,
                existing: existing,
                status: "transcribing",
                now: now
            ))
            try await reload()

            let transcript = try await transcribeCheckInMediaIfNeeded(media, database: database)
            try database.upsertCheckInAISummary(makeCheckInAISummary(
                media: media,
                existing: try database.fetchCheckInAISummary(mediaId: media.id),
                status: "summarizing",
                now: Date(),
                transcriptLength: transcript.count
            ))
            try await reload()

            let result = try await generateTextArtifact(
                AIArtifactGenerationRequest(
                    feature: .checkInSummary,
                    title: checkInEntry(id: media.entryId)?.note,
                    sourceText: transcript,
                    languageMode: aiLanguageMode,
                    topicVocabulary: activeTopicTags.map(\.name)
                ),
                forceRetry: forceRegenerate
            )
            let ready = makeCheckInAISummary(
                media: media,
                existing: try database.fetchCheckInAISummary(mediaId: media.id),
                status: "ready",
                now: Date(),
                result: result,
                transcriptLength: transcript.count
            )
            try database.upsertCheckInAISummary(ready)
            try enqueueCloudKitCheckInAISummaryUpsert(
                summaryId: ready.id,
                reason: "checkin_ai_summary_ready",
                now: ready.updatedAt
            )
            try await reload()
        } catch {
            await markCheckInAISummaryFailed(media: media, error: error)
        }
    }

    func scheduleCheckInAIForMediaIfNeeded(_ media: CheckInMedia?) {
        guard aiAnalysisEnabled, let media, media.isAudio || media.isVideo else {
            return
        }
        Task {
            await requestCheckInAISummary(for: media)
        }
    }

    private var selectedProviderDisplayName: String? {
        AIProviderRouter.selectProfile(profiles: aiProviderProfiles, fallbackState: aiProviderFallbackState)?.displayName
    }

    private var selectedProviderModel: String? {
        AIProviderRouter.selectProfile(profiles: aiProviderProfiles, fallbackState: aiProviderFallbackState)?.model
    }

    private func markCheckInAISummaryFailed(media: CheckInMedia, error: Error) async {
        do {
            guard let database else {
                return
            }
            let now = Date()
            let existing = try database.fetchCheckInAISummary(mediaId: media.id)
            var failed = makeCheckInAISummary(
                media: media,
                existing: existing,
                status: "failed",
                now: now
            )
            failed.errorCode = "request_failed"
            failed.errorMessage = error.localizedDescription
            try database.upsertCheckInAISummary(failed)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
