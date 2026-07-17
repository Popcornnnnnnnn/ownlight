import Foundation

extension TimelineStore {
    func localWeeklyReviewSource(now: Date = Date()) -> (text: String, start: Date, end: Date) {
        let calendar = Calendar.current
        let end = now
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-604_800)
        var lines: [String] = []

        for item in items where item.post.deletedAt == nil
            && !WelcomeSampleContent.isSample(item)
            && item.post.occurredAt >= start
            && item.post.occurredAt <= end {
            let date = MomentDateFormatter.dayJumpTitle(for: item.post.occurredAt)
            let text = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append("- \(date): \(text)")
            }
            for summary in item.aiSummaries where summary.isReady {
                if let oneLiner = summary.oneLiner?.trimmingCharacters(in: .whitespacesAndNewlines), !oneLiner.isEmpty {
                    lines.append("  AI summary: \(oneLiner)")
                }
            }
        }

        for entry in checkInFeedEntries where entry.entry.occurredAt >= start && entry.entry.occurredAt <= end {
            let date = MomentDateFormatter.dayJumpTitle(for: entry.entry.occurredAt)
            let note = entry.entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- \(date) check-in \(entry.item.name): \(note.isEmpty ? "completed" : note)")
        }

        if lines.isEmpty {
            lines.append("No visible moments or check-ins were captured in this period.")
        }
        return (lines.joined(separator: "\n"), start, end)
    }

    func makeLocalReview(
        result: AIArtifactGenerationResult,
        start: Date,
        end: Date,
        trigger: String,
        regeneratedFromReviewId: String? = nil,
        publishedPostId: String? = nil
    ) -> ReviewPayload {
        let now = Date()
        let content = result.reviewContent ?? ReviewContentPayload(
            title: result.documentTitle,
            subtitle: nil,
            bodyMarkdown: result.summaryText,
            oneLiner: result.oneLiner,
            keywords: nil,
            themes: nil,
            emotionalReflection: nil,
            progressAndOpenLoops: nil,
            rhythm: nil,
            notableMoments: nil,
            gentleSuggestions: nil,
            uncertainty: nil
        )
        let provider = AIProviderRouter.selectProfile(
            profiles: aiProviderProfiles,
            fallbackState: aiProviderFallbackState
        )
        return ReviewPayload(
            id: "iphone-review-\(UUID().uuidString)",
            kind: "weekly",
            rangeMode: "weekly",
            rangeStart: Self.isoString(start),
            rangeEnd: Self.isoString(end),
            status: "ready",
            trigger: trigger,
            content: content,
            promptVersion: "weekly-review-v1",
            provider: provider?.displayName,
            model: provider?.model,
            language: aiLanguageMode.rawValue,
            errorCode: nil,
            errorMessage: nil,
            generatedAt: Self.isoString(now),
            regeneratedFromReviewId: regeneratedFromReviewId,
            publishedPostId: publishedPostId,
            createdAt: Self.isoString(now),
            updatedAt: Self.isoString(now),
            deletedAt: nil,
            feedback: nil
        )
    }

    func saveLocalReviews(_ reviews: [ReviewPayload]) {
        let sorted = reviews.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        AppSettings.localWeeklyReviews = sorted
        weeklyReviews = sorted
    }

    func localReviewsIncludingSyncedReviewMoments() -> [ReviewPayload] {
        let storedReviews = AppSettings.localWeeklyReviews.filter { $0.deletedAt == nil }
        var reviewsById = Dictionary(uniqueKeysWithValues: storedReviews.map { ($0.id, $0) })
        let publishedPostIds = Set(storedReviews.compactMap(\.publishedPostId))
        var didImport = false

        for item in items where item.post.deletedAt == nil && !WelcomeSampleContent.isSample(item) {
            guard let reviewId = Self.syncedReviewId(fromPublishedPostId: item.post.id),
                  reviewsById[reviewId] == nil,
                  !publishedPostIds.contains(item.post.id) else {
                continue
            }

            reviewsById[reviewId] = makeHistoricalServerReview(from: item.post, reviewId: reviewId)
            didImport = true
        }

        let reviews = Array(reviewsById.values).sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        if didImport {
            AppSettings.localWeeklyReviews = reviews
        }
        return reviews
    }

    func reviewMomentText(_ review: ReviewPayload) -> String {
        if let body = review.content.bodyMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }

        var lines: [String] = []
        if let title = review.content.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("## \(title)")
        }
        if let oneLiner = review.content.oneLiner?.trimmingCharacters(in: .whitespacesAndNewlines), !oneLiner.isEmpty {
            lines.append(oneLiner)
        }
        if let suggestions = review.content.gentleSuggestions, !suggestions.isEmpty {
            lines.append(suggestions.map { "- \($0)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    func copyReview(_ review: ReviewPayload, publishedPostId: String? = nil, deletedAt: String? = nil) -> ReviewPayload {
        let now = Self.isoString(Date())
        return ReviewPayload(
            id: review.id,
            kind: review.kind,
            rangeMode: review.rangeMode,
            rangeStart: review.rangeStart,
            rangeEnd: review.rangeEnd,
            status: deletedAt == nil ? review.status : "deleted",
            trigger: review.trigger,
            content: review.content,
            promptVersion: review.promptVersion,
            provider: review.provider,
            model: review.model,
            language: review.language,
            errorCode: review.errorCode,
            errorMessage: review.errorMessage,
            generatedAt: review.generatedAt,
            regeneratedFromReviewId: review.regeneratedFromReviewId,
            publishedPostId: publishedPostId ?? review.publishedPostId,
            createdAt: review.createdAt,
            updatedAt: now,
            deletedAt: deletedAt,
            feedback: review.feedback
        )
    }

    private func makeHistoricalServerReview(from post: TimelinePost, reviewId: String) -> ReviewPayload {
        let rangeEnd = post.occurredAt
        let rangeStart = Calendar.current.date(byAdding: .day, value: -7, to: rangeEnd)
            ?? rangeEnd.addingTimeInterval(-604_800)
        let createdAt = Self.isoString(post.localCreatedAt)
        let updatedAt = Self.isoString(post.localUpdatedAt)
        let title = Self.reviewTitle(fromMarkdown: post.text)

        return ReviewPayload(
            id: reviewId,
            kind: "weekly",
            rangeMode: "rolling_7_days",
            rangeStart: Self.isoString(rangeStart),
            rangeEnd: Self.isoString(rangeEnd),
            status: "ready",
            trigger: "scheduled",
            content: ReviewContentPayload(
                title: title,
                subtitle: nil,
                bodyMarkdown: post.text,
                oneLiner: nil,
                keywords: nil,
                themes: nil,
                emotionalReflection: nil,
                progressAndOpenLoops: nil,
                rhythm: nil,
                notableMoments: nil,
                gentleSuggestions: nil,
                uncertainty: nil
            ),
            promptVersion: "server-published-review-moment",
            provider: "Mac Server (historical)",
            model: nil,
            language: nil,
            errorCode: nil,
            errorMessage: nil,
            generatedAt: createdAt,
            regeneratedFromReviewId: nil,
            publishedPostId: post.id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            feedback: nil
        )
    }

    private static func syncedReviewId(fromPublishedPostId postId: String) -> String? {
        guard postId.hasPrefix("review-") else {
            return nil
        }

        let reviewId = String(postId.dropFirst("review-".count))
        return reviewId.isEmpty ? nil : reviewId
    }

    private static func reviewTitle(fromMarkdown text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
