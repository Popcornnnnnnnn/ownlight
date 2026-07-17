import Foundation

extension TimelineStore {
    func aiSummary(id: String) -> TimelineAISummary? {
        for item in items {
            if let summary = item.aiSummaries.first(where: { $0.id == id }) {
                return summary
            }
        }

        return nil
    }

    func requestAISummary(for media: TimelineMedia, forceRegenerate: Bool = false) async {
        guard !WelcomeSampleContent.isSampleMediaId(media.id) else {
            return
        }

        aiSummaryRequestsInFlight.insert(media.id)
        defer {
            aiSummaryRequestsInFlight.remove(media.id)
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }
            guard aiAnalysisEnabled else {
                throw AITextAnalysisError.noConfiguredProvider
            }

            let transcript = try await transcribeTimelineMediaIfNeeded(media, database: database)
            let now = Date()
            let summarizing = try makeTimelineAISummary(
                media: media,
                existing: database.fetchAISummary(mediaId: media.id),
                status: "summarizing",
                now: now
            )
            try database.upsertAISummary(summarizing)
            try await reload()

            let result = try await generateTextArtifact(
                AIArtifactGenerationRequest(
                    feature: .mediaSummary,
                    title: item(id: media.postId)?.post.text,
                    sourceText: transcript,
                    languageMode: aiLanguageMode,
                    topicVocabulary: activeTopicTags.map(\.name)
                ),
                forceRetry: forceRegenerate
            )
            let ready = try makeTimelineAISummary(
                media: media,
                existing: database.fetchAISummary(mediaId: media.id),
                status: "ready",
                now: Date(),
                result: result,
                transcriptLength: transcript.count
            )
            try database.upsertAISummary(ready)
            try applyAISuggestedTags(
                result.suggestedTags,
                areaId: result.suggestedAreaId,
                postId: media.postId,
                summaryId: ready.id,
                database: database
            )
            try insertAITitleIfNeeded(for: ready, database: database)
            try enqueueCloudKitAISummaryUpsert(summaryId: ready.id, reason: "ai_summary_ready", now: ready.updatedAt)
            try await reload()
        } catch {
            await markAISummaryRequestFailed(media: media, error: error)
        }
    }

    func deleteAISummary(_ summary: TimelineAISummary) async {
        guard !WelcomeSampleContent.isSampleAISummaryId(summary.id) else {
            return
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }
            var deleted = summary
            let now = Date()
            deleted.status = "deleted"
            deleted.updatedAt = now
            deleted.deletedAt = now
            try database.upsertAISummary(deleted)
            try enqueueCloudKitAISummaryDelete(summaryId: summary.id, reason: "ai_summary_delete", now: now)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markAISummaryRequestFailed(media: TimelineMedia, error: Error) async {
        do {
            guard let database else {
                return
            }

            let now = Date()
            let existing = try database.fetchAISummary(mediaId: media.id)
            let failure = aiSummaryFailure(for: error)
            let failed = TimelineAISummary(
                id: existing?.id ?? "local-\(media.id)",
                postId: media.postId,
                mediaId: media.id,
                status: "failed",
                format: existing?.format,
                language: existing?.language,
                overview: existing?.overview,
                keyPoints: existing?.keyPoints ?? [],
                sections: existing?.sections ?? [],
                summaryText: existing?.summaryText,
                documentTitle: existing?.documentTitle,
                oneLiner: existing?.oneLiner,
                documentBlocks: existing?.documentBlocks ?? [],
                inputTranscriptLength: existing?.inputTranscriptLength,
                inputDurationSeconds: media.durationSeconds,
                inputTokenCount: existing?.inputTokenCount,
                outputTokenCount: existing?.outputTokenCount,
                totalTokenCount: existing?.totalTokenCount,
                promptVersion: existing?.promptVersion ?? "media-summary-v1",
                provider: existing?.provider,
                model: existing?.model,
                errorCode: failure.code,
                errorMessage: failure.message,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                deletedAt: nil
            )

            try database.upsertAISummary(failed)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func aiSummaryFailure(for error: Error) -> (code: String, message: String) {
        if let error = error as? AITextAnalysisError {
            switch error {
            case .noConfiguredProvider:
                return ("ai_provider_missing", error.localizedDescription)
            case .externalProcessingConsentRequired:
                return ("ai_external_consent_required", error.localizedDescription)
            case .missingAPIKey:
                return ("ai_api_key_missing", error.localizedDescription)
            case .unsupportedResponse:
                return ("ai_provider_response_unreadable", error.localizedDescription)
            case .provider(let statusCode, _):
                return ("ai_provider_http_\(statusCode)", error.localizedDescription)
            case .invalidProviderURL:
                return ("ai_provider_url_invalid", error.localizedDescription)
            }
        }

        if let error = error as? LocalTranscriptionGatewayError {
            switch error {
            case .invalidURL:
                return ("transcription_gateway_url_invalid", error.localizedDescription)
            case .missingToken:
                return ("transcription_gateway_token_missing", error.localizedDescription)
            case .provider(let statusCode, _):
                return ("transcription_gateway_http_\(statusCode)", error.localizedDescription)
            case .unsupportedResponse:
                return ("transcription_gateway_response_unreadable", error.localizedDescription)
            case .emptyTranscript:
                return ("transcription_empty", error.localizedDescription)
            }
        }

        if error is DecodingError {
            return (
                "response_decode_failed",
                "The provider returned data Ownlight could not read. Check the Base URL, model, and response format."
            )
        }

        return ("request_failed", error.localizedDescription)
    }
}
