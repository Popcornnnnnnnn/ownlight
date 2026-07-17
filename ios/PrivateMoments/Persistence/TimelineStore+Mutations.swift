import Foundation

extension TimelineStore {
    func createPost(
        text: String,
        imageData: [Data],
        video: PreparedMomentMedia? = nil,
        audio: [PreparedMomentMedia] = [],
        document: PreparedMomentMedia? = nil,
        occurredAt: Date,
        primaryTagId: String? = nil
    ) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !imageData.isEmpty || video != nil || !audio.isEmpty || document != nil else {
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let occurredAt = MomentOccurrenceDate.clampedToNow(occurredAt, now: now)
            let postId = UUID().uuidString
            let media = try persistPreparedMedia(
                postId: postId,
                imageData: imageData,
                video: video,
                audio: audio,
                document: document,
                createdAt: now
            )
            let payload = try makeCreatePostPayload(text: trimmedText, occurredAt: occurredAt, primaryTagId: primaryTagId)

            let post = TimelinePost(
                id: postId,
                text: trimmedText,
                isFavorite: false,
                isPinned: false,
                pinnedAt: nil,
                aiTagProcessedAt: nil,
                tagsUserEditedAt: nil,
                occurredAt: occurredAt,
                localCreatedAt: now,
                localUpdatedAt: now,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "pending",
                deletedAt: nil
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "create_post",
                entityType: "post",
                entityId: postId,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.insertPost(post, media: media, operation: operation, primaryTagId: primaryTagId)
            try enqueueCloudKitMomentUpsert(postId: postId, reason: "moment_create", now: now)
            try enqueueCloudKitMediaCreation(media, now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            scheduleAIForMediaIfNeeded(media)

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            if WelcomeSampleContent.isSample(item) {
                try database.softDeleteWelcomeSample(deletedAt: now)
                AppSettings.welcomeSampleDeleted = true
                try await reload()
                try refreshPendingCounts()
                return
            }

            let payload = try makeDeletePostPayload(deletedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_post",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.softDeletePost(postId: item.post.id, deletedAt: now, operation: operation)
            try enqueueCloudKitMomentTreeDelete(item, now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let nextValue = !item.post.isFavorite
            if WelcomeSampleContent.isSample(item) {
                try database.updateWelcomeSampleFavorite(
                    isFavorite: nextValue,
                    updatedAt: now
                )
                try await reload()
                try refreshPendingCounts()
                return
            }

            let payload = try makeFavoritePayload(isFavorite: nextValue, updatedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post_favorite",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updateFavorite(
                postId: item.post.id,
                isFavorite: nextValue,
                updatedAt: now,
                operation: operation
            )
            try enqueueCloudKitMomentUpsert(postId: item.post.id, reason: "moment_favorite", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePinned(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let nextValue = !item.post.isPinned
            let pinnedAt = nextValue ? now : nil
            if WelcomeSampleContent.isSample(item) {
                try database.updateWelcomeSamplePinned(
                    isPinned: nextValue,
                    pinnedAt: pinnedAt,
                    updatedAt: now
                )
                try await reload()
                try refreshPendingCounts()
                return
            }

            let payload = try makePinPayload(isPinned: nextValue, pinnedAt: pinnedAt, updatedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post_pin",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updatePinned(
                postId: item.post.id,
                isPinned: nextValue,
                pinnedAt: pinnedAt,
                updatedAt: now,
                operation: operation
            )
            try enqueueCloudKitMomentUpsert(postId: item.post.id, reason: "moment_pin", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePost(
        item: TimelineItem,
        text: String,
        occurredAt: Date,
        mediaItems: [MomentEditMediaItem]
    ) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !mediaItems.isEmpty else {
            errorMessage = "Add text or at least one image before saving."
            return false
        }

        guard canEdit(item) else {
            errorMessage = "Wait until this moment finishes syncing before editing."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let occurredAt = MomentOccurrenceDate.clampedToNow(occurredAt, now: now)
            let existingMediaIds = Set(item.media.map(\.id))
            let finalMediaIds = Set(mediaItems.map(\.id))
            let removedMedia = item.media.filter { !finalMediaIds.contains($0.id) }
            let media = try await Self.materializeEditedMedia(postId: item.post.id, mediaItems: mediaItems, updatedAt: now)
            let newMedia = media.filter { !existingMediaIds.contains($0.id) }
            let payload = try makeUpdatePostPayload(
                text: trimmedText,
                occurredAt: occurredAt,
                updatedAt: now,
                media: media
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updatePost(
                postId: item.post.id,
                text: trimmedText,
                occurredAt: occurredAt,
                localEditedAt: now,
                finalMedia: media,
                operation: operation
            )
            try enqueueCloudKitMomentUpsert(postId: item.post.id, reason: "moment_update", now: now)
            for media in removedMedia {
                try enqueueCloudKitMediaDelete(
                    mediaId: media.id,
                    reason: "moment_media_remove",
                    now: now
                )
            }
            try enqueueCloudKitMediaCreation(newMedia, now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createComment(postId: String, text: String) async -> TimelineComment? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        guard trimmedText.count <= 500 else {
            errorMessage = "Comments can be up to 500 characters."
            return nil
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            guard let post = try database.fetchPost(id: postId), post.deletedAt == nil else {
                throw StoreError.commentTargetUnavailable
            }

            let now = Date()
            let commentId = UUID().uuidString
            let comment = TimelineComment(
                id: commentId,
                postId: post.id,
                text: trimmedText,
                createdAt: now,
                updatedAt: now,
                serverVersion: nil,
                deletedAt: nil
            )

            if WelcomeSampleContent.isSamplePostId(post.id) {
                try database.insertWelcomeSampleComment(comment)
                try await reload()
                try refreshPendingCounts()
                return comment
            }

            let payload = try makeCreateCommentPayload(postId: post.id, text: trimmedText, createdAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "create_comment",
                entityType: "comment",
                entityId: commentId,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.insertComment(comment, operation: operation)
            try enqueueCloudKitCommentUpsert(commentId: comment.id, reason: "comment_create", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return comment
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteComment(_ comment: TimelineComment) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let deletedAt = Date()
            if WelcomeSampleContent.isSamplePostId(comment.postId) {
                try database.softDeleteWelcomeSampleComment(commentId: comment.id, deletedAt: deletedAt)
                try await reload()
                try refreshPendingCounts()
                return
            }

            let payload = try makeDeleteCommentPayload(postId: comment.postId, deletedAt: deletedAt)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_comment",
                entityType: "comment",
                entityId: comment.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: deletedAt,
                updatedAt: deletedAt,
                sentAt: nil
            )

            try database.softDeleteComment(comment: comment, deletedAt: deletedAt, operation: operation)
            try enqueueCloudKitCommentDelete(commentId: comment.id, reason: "comment_delete", now: deletedAt)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTags(item: TimelineItem, primaryTagId: String?, topicTagIds: [String]) async -> Bool {
        guard canEdit(item) else {
            errorMessage = "Wait until this moment finishes syncing before editing tags."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let existingAssignments = try database.fetchAssignedTags(postId: item.post.id)
            let desiredTagIds = Set(([primaryTagId].compactMap { $0 }) + topicTagIds)
            let payload = try makeSetPostTagsPayload(
                primaryTagId: primaryTagId,
                topicTagIds: topicTagIds,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "set_post_tags",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.setPostTags(
                postId: item.post.id,
                primaryTagId: primaryTagId,
                topicTagIds: topicTagIds,
                updatedAt: now,
                operation: operation
            )
            try enqueueCloudKitMomentUpsert(postId: item.post.id, reason: "moment_tags", now: now)
            for assignedTag in existingAssignments where !desiredTagIds.contains(assignedTag.tagId) {
                try enqueueCloudKitPostTagDelete(
                    assignmentId: assignedTag.id,
                    reason: "post_tag_delete",
                    now: now
                )
            }
            for assignedTag in try database.fetchAssignedTags(postId: item.post.id) where desiredTagIds.contains(assignedTag.tagId) {
                try enqueueCloudKitPostTagUpsert(
                    assignmentId: assignedTag.id,
                    reason: "post_tag_upsert",
                    now: now
                )
            }
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTag(type: String, name: String, colorHex: String? = nil, areaId: String? = nil) async -> TimelineTag? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 40 else {
            errorMessage = "Tags can be up to 40 characters."
            return nil
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let normalizedName = LocalDatabase.normalizedTagName(cleanedName)
            if let existingTag = try database.fetchTag(normalizedName: normalizedName) {
                errorMessage = duplicateTagMessage(existingTag, requestedType: type)
                return nil
            }

            let tag = TimelineTag(
                id: UUID().uuidString,
                type: type,
                name: cleanedName,
                normalizedName: normalizedName,
                colorHex: colorHex,
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil,
                areaId: type == "topic" ? TopicTagArea.fromProviderValue(areaId, topicName: cleanedName).rawValue : nil
            )
            let payload = try makeUpsertTagPayload(
                type: type,
                name: cleanedName,
                colorHex: colorHex,
                aiUsableAsPrimary: false,
                areaId: tag.areaId,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTag(tag, operation: operation)
            try enqueueCloudKitTagUpsert(tagId: tag.id, reason: "tag_create", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return tag
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateTag(_ tag: TimelineTag, name: String, colorHex: String? = nil, areaId: String? = nil) async -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 40 else {
            errorMessage = "Tags can be up to 40 characters."
            return false
        }

        if tag.isDefaultPrimaryTag && cleanedName != tag.name {
            errorMessage = "Default primary tags cannot be renamed."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let normalizedName = LocalDatabase.normalizedTagName(cleanedName)
            if let existingTag = try database.fetchTag(normalizedName: normalizedName),
               existingTag.id != tag.id {
                errorMessage = duplicateTagMessage(existingTag, requestedType: tag.type)
                return false
            }

            var updatedTag = tag
            updatedTag.name = cleanedName
            updatedTag.normalizedName = normalizedName
            updatedTag.colorHex = updatedTag.type == "primary" ? colorHex : nil
            if updatedTag.type == "topic" {
                updatedTag.areaId = TopicTagArea.fromProviderValue(
                    areaId ?? updatedTag.areaId,
                    topicName: updatedTag.name
                ).rawValue
            }
            updatedTag.updatedAt = now

            let payload = try makeUpsertTagPayload(
                type: updatedTag.type,
                name: updatedTag.name,
                colorHex: updatedTag.colorHex,
                isDefault: updatedTag.isDefaultPrimaryTag,
                aiUsableAsPrimary: updatedTag.aiUsableAsPrimary,
                areaId: updatedTag.areaId,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag",
                entityType: "tag",
                entityId: updatedTag.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTag(updatedTag, operation: operation)
            try enqueueCloudKitTagUpsert(tagId: updatedTag.id, reason: "tag_update", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func archiveTag(_ tag: TimelineTag) async -> Bool {
        if tag.isDefaultPrimaryTag {
            errorMessage = "Default primary tags cannot be archived."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "archive_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeArchiveTagPayload(archivedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.archiveTag(tag, archivedAt: now, operation: operation)
            try enqueueCloudKitTagUpsert(tagId: tag.id, reason: "tag_archive", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restoreTag(_ tag: TimelineTag) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "restore_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeRestoreTagPayload(restoredAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.restoreTag(tag, restoredAt: now, operation: operation)
            try enqueueCloudKitTagUpsert(tagId: tag.id, reason: "tag_restore", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTag(_ tag: TimelineTag) async -> Bool {
        guard tag.isArchived else {
            errorMessage = "Archive tags before deleting them permanently."
            return false
        }

        if tag.isDefaultPrimaryTag {
            errorMessage = "Default primary tags cannot be deleted."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let assignedTags = try database.fetchAssignedTags(tagId: tag.id, includeDeleted: false)
            let aliases = try database.fetchTagAliases(includeDeleted: false).filter { $0.tagId == tag.id }
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeDeleteTagPayload(deletedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.deleteArchivedTag(tag, operation: operation)
            try enqueueCloudKitTagDelete(tagId: tag.id, reason: "tag_delete", now: now)
            for alias in aliases {
                try enqueueCloudKitTagAliasDelete(aliasId: alias.id, reason: "tag_delete_alias", now: now)
            }
            for assignedTag in assignedTags {
                try enqueueCloudKitPostTagDelete(
                    assignmentId: assignedTag.id,
                    reason: "tag_delete_assignment",
                    now: now
                )
            }
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTagAlias(tag: TimelineTag, alias: String) async -> Bool {
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAlias.isEmpty, cleanedAlias.count <= 40 else {
            errorMessage = "Aliases can be up to 40 characters."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let tagAlias = TimelineTagAlias(
                id: UUID().uuidString,
                tagId: tag.id,
                alias: cleanedAlias,
                normalizedAlias: LocalDatabase.normalizedTagName(cleanedAlias),
                createdAt: now,
                deletedAt: nil
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag_alias",
                entityType: "tag_alias",
                entityId: tagAlias.id,
                payloadJson: try makeUpsertTagAliasPayload(tagId: tag.id, alias: cleanedAlias),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTagAlias(tagAlias, operation: operation)
            try enqueueCloudKitTagAliasUpsert(aliasId: tagAlias.id, reason: "tag_alias_create", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTagAlias(_ alias: TimelineTagAlias) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_tag_alias",
                entityType: "tag_alias",
                entityId: alias.id,
                payloadJson: try makeDeleteTagAliasPayload(deletedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.softDeleteTagAlias(alias, deletedAt: now, operation: operation)
            try enqueueCloudKitTagAliasDelete(aliasId: alias.id, reason: "tag_alias_delete", now: now)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func mergeTopicTag(_ sourceTag: TimelineTag, into targetTag: TimelineTag) async -> Bool {
        guard sourceTag.type == "topic", targetTag.type == "topic", sourceTag.id != targetTag.id else {
            errorMessage = "Choose two different topic tags to merge."
            return false
        }

        guard !targetTag.isArchived else {
            errorMessage = "Merge into an active topic tag."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let aliasId = UUID().uuidString
            let sourceAssignments = try database.fetchAssignedTags(tagId: sourceTag.id, includeDeleted: false)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "merge_tag",
                entityType: "tag",
                entityId: sourceTag.id,
                payloadJson: try makeMergeTagPayload(targetTagId: targetTag.id, alias: sourceTag.name, mergedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.mergeTopicTag(
                sourceTag: sourceTag,
                targetTag: targetTag,
                aliasName: sourceTag.name,
                aliasId: aliasId,
                mergedAt: now,
                operation: operation
            )
            try enqueueCloudKitTagUpsert(tagId: sourceTag.id, reason: "tag_merge_source_archive", now: now)
            try enqueueCloudKitTagAliasUpsert(aliasId: aliasId, reason: "tag_merge_alias", now: now)

            var enqueuedTargetAssignmentIds = Set<String>()
            for sourceAssignment in sourceAssignments {
                let currentAssignments = try database.fetchAssignedTags(postId: sourceAssignment.postId)
                let targetAssignments = currentAssignments.filter { $0.tagId == targetTag.id }
                for targetAssignment in targetAssignments where enqueuedTargetAssignmentIds.insert(targetAssignment.id).inserted {
                    try enqueueCloudKitPostTagUpsert(
                        assignmentId: targetAssignment.id,
                        reason: "tag_merge_assignment",
                        now: now
                    )
                }

                if !targetAssignments.contains(where: { $0.id == sourceAssignment.id }) {
                    try enqueueCloudKitPostTagDelete(
                        assignmentId: sourceAssignment.id,
                        reason: "tag_merge_source_assignment",
                        now: now
                    )
                }
            }
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func syncSoonIfAuthenticated() {
        if isAuthenticated && automaticSyncEnabled {
            Task {
                await syncNow(userInitiated: false)
            }
        }
    }
}

private func duplicateTagMessage(_ tag: TimelineTag, requestedType: String) -> String {
    let existingType = tag.type == "primary" ? "Primary Tag" : "Topic Tag"
    let requestedTypeTitle = requestedType == "primary" ? "Primary Tag" : "Topic Tag"
    let archivedPrefix = tag.isArchived ? "archived " : ""

    if tag.type == requestedType {
        return "A \(archivedPrefix)\(existingType.lowercased()) named \"\(tag.name)\" already exists."
    }

    return "A \(archivedPrefix)\(existingType.lowercased()) named \"\(tag.name)\" already exists. Tag names are shared across \(requestedTypeTitle)s and \(existingType)s."
}
