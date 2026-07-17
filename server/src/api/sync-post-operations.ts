import type { Device, Prisma } from "@prisma/client";

import { cleanedAITitle, hasLeadingMarkdownTitle, insertAITitleIntoText } from "./sync-ai-title.js";
import {
  OperationRejectedError,
  type SyncOperationInput,
} from "./sync-types.js";
import {
  getBoolean,
  getDate,
  getMediaOrder,
  getNullableDate,
  getNullableString,
  getString,
  getStringAllowingEmpty,
} from "./sync-payload.js";
import { upsertPostTag } from "../tags/tagging.js";

const MAX_COMMENT_LENGTH = 500;
const MAX_TRANSCRIPTION_LENGTH = 100_000;

export async function applyCreatePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const text = getStringAllowingEmpty(operation.payload, "text");
  const occurredAt = getDate(operation.payload, "occurredAt");
  const isFavorite = getBoolean(operation.payload, "isFavorite") ?? false;
  const isPinned = getBoolean(operation.payload, "isPinned") ?? false;
  const pinnedAt = getNullableDate(operation.payload, "pinnedAt") ?? (isPinned ? operation.clientCreatedAt : null);
  const primaryTagId = getNullableString(operation.payload, "primaryTagId");

  if (text === null) {
    throw new OperationRejectedError("create_post.payload.text is required");
  }

  if (!occurredAt) {
    throw new OperationRejectedError("create_post.payload.occurredAt must be an ISO date");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (existingPost) {
    throw new OperationRejectedError("Post already exists");
  }

  await tx.post.create({
    data: {
      id: operation.entityId,
      text,
      isFavorite,
      isPinned,
      pinnedAt,
      occurredAt,
      clientCreatedAt: operation.clientCreatedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      createdByDeviceId: device.id,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_created",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        text,
        isFavorite,
        isPinned,
        pinnedAt: pinnedAt?.toISOString() ?? null,
        occurredAt: occurredAt.toISOString(),
        deletedAt: null,
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });

  if (primaryTagId) {
    const tag = await tx.tag.findUnique({
      where: {
        id: primaryTagId,
      },
    });
    if (!tag || tag.type !== "primary" || tag.isArchived) {
      throw new OperationRejectedError("create_post.payload.primaryTagId must reference an active primary tag");
    }

    await upsertPostTag(tx, {
      postId: operation.entityId,
      tagId: primaryTagId,
      role: "primary",
      source: "manual",
      confidence: null,
      aiSummaryId: null,
      now: operation.clientCreatedAt,
    });
  }
}

export async function applyUpdatePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const text = getStringAllowingEmpty(operation.payload, "text");
  const occurredAt = getDate(operation.payload, "occurredAt");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const mediaOrder = getMediaOrder(operation.payload, "media");

  if (text === null) {
    throw new OperationRejectedError("update_post.payload.text is required");
  }

  if (!occurredAt) {
    throw new OperationRejectedError("update_post.payload.occurredAt must be an ISO date");
  }

  if (!mediaOrder) {
    throw new OperationRejectedError("update_post.payload.media must be an array");
  }

  const mediaIds = new Set(mediaOrder.map((media) => media.id));
  if (mediaIds.size !== mediaOrder.length) {
    throw new OperationRejectedError("update_post.payload.media contains duplicate media ids");
  }

  if (text.trim().length === 0 && mediaOrder.length === 0) {
    throw new OperationRejectedError("update_post cannot leave a post empty");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
    include: {
      media: {
        where: {
          deletedAt: null,
        },
      },
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  const existingMediaIds = new Set(existingPost.media.map((media) => media.id));
  const mediaFromOtherPosts = await tx.media.findMany({
    where: {
      id: {
        in: Array.from(mediaIds),
      },
      postId: {
        not: operation.entityId,
      },
    },
    select: {
      id: true,
    },
  });

  if (mediaFromOtherPosts.length > 0) {
    throw new OperationRejectedError("update_post.payload.media contains media from another post");
  }

  const removedMedia = existingPost.media.filter((media) => !mediaIds.has(media.id));
  const deletedAt = updatedAt;

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      text,
      occurredAt,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  for (const media of mediaOrder) {
    if (!existingMediaIds.has(media.id)) {
      continue;
    }

    await tx.media.update({
      where: {
        id: media.id,
      },
      data: {
        sortOrder: media.sortOrder,
      },
    });
  }

  if (removedMedia.length > 0) {
    await tx.media.updateMany({
      where: {
        id: {
          in: removedMedia.map((media) => media.id),
        },
      },
      data: {
        deletedAt,
        status: "deleted",
      },
    });
  }

  let latestVersion = 0;
  const postChange = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        text,
        isFavorite: existingPost.isFavorite,
        isPinned: existingPost.isPinned,
        pinnedAt: existingPost.pinnedAt?.toISOString() ?? null,
        occurredAt: occurredAt.toISOString(),
        updatedAt: updatedAt.toISOString(),
        media: mediaOrder,
        deletedAt: null,
      }),
    },
  });
  latestVersion = postChange.version;

  for (const media of removedMedia) {
    const mediaChange = await tx.serverChange.create({
      data: {
        entityType: "media",
        entityId: media.id,
        changeType: "media_deleted",
        payloadJson: JSON.stringify({
          id: media.id,
          postId: operation.entityId,
          deletedAt: deletedAt.toISOString(),
        }),
      },
    });
    latestVersion = mediaChange.version;
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: latestVersion,
    },
  });
}

export async function applyInsertAITitle(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const summaryId = getString(operation.payload, "summaryId");
  const mediaId = getString(operation.payload, "mediaId");
  const insertedAt = getDate(operation.payload, "insertedAt") ?? operation.clientCreatedAt;

  if (!summaryId) {
    throw new OperationRejectedError("insert_ai_title.payload.summaryId is required");
  }

  if (!mediaId) {
    throw new OperationRejectedError("insert_ai_title.payload.mediaId is required");
  }

  const [post, summary] = await Promise.all([
    tx.post.findUnique({
      where: {
        id: operation.entityId,
      },
      include: {
        media: {
          where: {
            deletedAt: null,
          },
          orderBy: {
            sortOrder: "asc",
          },
          select: {
            id: true,
            sortOrder: true,
          },
        },
      },
    }),
    tx.aiSummary.findUnique({
      where: {
        id: summaryId,
      },
      include: {
        media: true,
      },
    }),
  ]);

  if (!post || post.deletedAt) {
    return;
  }

  if (
    !summary ||
    summary.deletedAt ||
    summary.status !== "ready" ||
    summary.postId !== post.id ||
    summary.mediaId !== mediaId ||
    summary.media.kind !== "audio" ||
    summary.media.deletedAt
  ) {
    return;
  }

  const title = cleanedAITitle(summary.documentTitle);
  if (!title || hasLeadingMarkdownTitle(post.text)) {
    return;
  }

  const text = insertAITitleIntoText(title, post.text);
  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      text,
      clientUpdatedAt: insertedAt,
      updatedByDeviceId: device.id,
    },
  });

  const mediaOrder = post.media.map((media) => ({
    id: media.id,
    sortOrder: media.sortOrder,
  }));
  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: post.id,
      changeType: "post_updated",
      payloadJson: JSON.stringify({
        id: post.id,
        text,
        isFavorite: post.isFavorite,
        isPinned: post.isPinned,
        pinnedAt: post.pinnedAt?.toISOString() ?? null,
        occurredAt: post.occurredAt.toISOString(),
        updatedAt: insertedAt.toISOString(),
        updateSource: "ai_title",
        media: mediaOrder,
        deletedAt: null,
      }),
    },
  });

  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function applyUpdatePostFavorite(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const isFavorite = getBoolean(operation.payload, "isFavorite");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;

  if (isFavorite === null) {
    throw new OperationRejectedError("update_post_favorite.payload.isFavorite must be a boolean");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isFavorite,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_favorite_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        isFavorite,
        updatedAt: updatedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function applyUpdatePostPin(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const isPinned = getBoolean(operation.payload, "isPinned");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const pinnedAt = getNullableDate(operation.payload, "pinnedAt") ?? (isPinned ? updatedAt : null);

  if (isPinned === null) {
    throw new OperationRejectedError("update_post_pin.payload.isPinned must be a boolean");
  }

  if (isPinned && !pinnedAt) {
    throw new OperationRejectedError("update_post_pin.payload.pinnedAt must be an ISO date when isPinned is true");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isPinned,
      pinnedAt: isPinned ? pinnedAt : null,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_pin_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        isPinned,
        pinnedAt: isPinned ? pinnedAt!.toISOString() : null,
        updatedAt: updatedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function applyDeletePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingPost) {
    throw new OperationRejectedError("Post not found");
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      updatedByDeviceId: device.id,
    },
  });

  await tx.media.updateMany({
    where: {
      postId: operation.entityId,
      deletedAt: null,
    },
    data: {
      deletedAt,
      status: "deleted",
    },
  });

  await tx.comment.updateMany({
    where: {
      postId: operation.entityId,
      deletedAt: null,
    },
    data: {
      deletedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_deleted",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function applyUpdateMediaTranscription(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const postId = getString(operation.payload, "postId");
  const transcriptionText = getStringAllowingEmpty(operation.payload, "transcriptionText");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;

  if (!postId) {
    throw new OperationRejectedError("update_media_transcription.payload.postId is required");
  }

  if (transcriptionText === null) {
    throw new OperationRejectedError(
      "update_media_transcription.payload.transcriptionText is required",
    );
  }

  const trimmedText = transcriptionText.trim();
  if (trimmedText.length === 0) {
    throw new OperationRejectedError(
      "update_media_transcription.payload.transcriptionText cannot be empty",
    );
  }

  if (trimmedText.length > MAX_TRANSCRIPTION_LENGTH) {
    throw new OperationRejectedError(
      `update_media_transcription.payload.transcriptionText cannot exceed ${MAX_TRANSCRIPTION_LENGTH} characters`,
    );
  }

  const media = await tx.media.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!media || media.deletedAt || media.postId !== postId) {
    throw new OperationRejectedError("Media not found");
  }

  await tx.media.update({
    where: {
      id: operation.entityId,
    },
    data: {
      transcriptionText: trimmedText,
      updatedAt,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "media",
      entityId: operation.entityId,
      changeType: "media_transcription_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId,
        transcriptionText: trimmedText,
        updatedAt: updatedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: postId,
    },
    data: {
      serverVersion: change.version,
      updatedByDeviceId: device.id,
    },
  });
}

export async function applyCreateComment(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const postId = getString(operation.payload, "postId");
  const text = getStringAllowingEmpty(operation.payload, "text");
  const createdAt = getDate(operation.payload, "createdAt") ?? operation.clientCreatedAt;

  if (!postId) {
    throw new OperationRejectedError("create_comment.payload.postId is required");
  }

  if (text === null) {
    throw new OperationRejectedError("create_comment.payload.text is required");
  }

  const trimmedText = text.trim();
  if (trimmedText.length === 0) {
    throw new OperationRejectedError("create_comment.payload.text cannot be empty");
  }

  if (trimmedText.length > MAX_COMMENT_LENGTH) {
    throw new OperationRejectedError(
      `create_comment.payload.text cannot exceed ${MAX_COMMENT_LENGTH} characters`,
    );
  }

  const post = await tx.post.findUnique({
    where: {
      id: postId,
    },
  });

  if (!post || post.deletedAt) {
    throw new OperationRejectedError("Parent post not found");
  }

  const existingComment = await tx.comment.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (existingComment) {
    throw new OperationRejectedError("Comment already exists");
  }

  await tx.comment.create({
    data: {
      id: operation.entityId,
      postId,
      text: trimmedText,
      createdAt,
      updatedAt: createdAt,
      clientCreatedAt: createdAt,
      clientUpdatedAt: createdAt,
      createdByDeviceId: device.id,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "comment",
      entityId: operation.entityId,
      changeType: "comment_created",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId,
        text: trimmedText,
        createdAt: createdAt.toISOString(),
        updatedAt: createdAt.toISOString(),
        deletedAt: null,
      }),
    },
  });

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function applyDeleteComment(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const existingComment = await tx.comment.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingComment) {
    throw new OperationRejectedError("Comment not found");
  }

  if (existingComment.deletedAt) {
    return;
  }

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      clientUpdatedAt: deletedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "comment",
      entityId: operation.entityId,
      changeType: "comment_deleted",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId: existingComment.postId,
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}
