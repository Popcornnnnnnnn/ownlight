import type { Device, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyReply } from "fastify";

import { applyCheckInOperation } from "./sync-checkins.js";
import { shouldReplayPreviouslyUnsupportedOperation } from "./sync-operations.js";
import {
  OperationRejectedError,
  type SyncOperationInput,
  type SyncRequestBody,
} from "./sync-types.js";
import { parseSyncRequestBodyValue } from "./sync-payload.js";
import { sendBadRequest } from "./http-errors.js";
import {
  applyCreateComment,
  applyCreatePost,
  applyDeleteComment,
  applyDeletePost,
  applyInsertAITitle,
  applyUpdateMediaTranscription,
  applyUpdatePost,
  applyUpdatePostFavorite,
  applyUpdatePostPin,
} from "./sync-post-operations.js";
import {
  applyArchiveTag,
  applyDeleteTag,
  applyDeleteTagAlias,
  applyMergeTag,
  applyRestoreTag,
  applySetPostTags,
  applyUpsertTag,
  applyUpsertTagAlias,
} from "./sync-tag-operations.js";

export async function applyOrReplayOperation(
  prisma: PrismaClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<{ accepted: true } | { accepted: false; reason: string }> {
  const existing = await prisma.syncOperation.findUnique({
    where: {
      deviceId_opId: {
        deviceId: device.id,
        opId: operation.opId,
      },
    },
  });

  if (existing?.appliedAt) {
    return { accepted: true };
  }

  const shouldReplayUnsupportedRejection =
    existing?.rejectedAt && shouldReplayPreviouslyUnsupportedOperation(existing, operation);

  if (existing?.rejectedAt && !shouldReplayUnsupportedRejection) {
    return {
      accepted: false,
      reason: existing.rejectionReason ?? "Operation was previously rejected",
    };
  }

  try {
    await prisma.$transaction(async (tx) => {
      const syncOperation = existing
        ? await tx.syncOperation.update({
            where: {
              id: existing.id,
            },
            data: {
              type: operation.type,
              entityType: operation.entityType,
              entityId: operation.entityId,
              payloadJson: JSON.stringify(operation.payload),
              rejectedAt: null,
              rejectionReason: null,
            },
          })
        : await tx.syncOperation.create({
            data: {
              opId: operation.opId,
              deviceId: device.id,
              type: operation.type,
              entityType: operation.entityType,
              entityId: operation.entityId,
              payloadJson: JSON.stringify(operation.payload),
            },
          });

      await applyOperation(tx, device, operation);

      await tx.syncOperation.update({
        where: {
          id: syncOperation.id,
        },
        data: {
          appliedAt: new Date(),
          rejectedAt: null,
          rejectionReason: null,
        },
      });
    });

    return { accepted: true };
  } catch (error) {
    if (!(error instanceof OperationRejectedError)) {
      throw error;
    }

    await markOperationRejected(prisma, device, operation, error.message);

    return {
      accepted: false,
      reason: error.message,
    };
  }
}

export function parseSyncRequestBody(
  body: unknown,
  reply: FastifyReply,
): SyncRequestBody | null {
  const parsed = parseSyncRequestBodyValue(body);
  if (!parsed.ok) {
    sendBadRequest(reply, parsed.message);
    return null;
  }

  return parsed.value;
}

async function applyOperation(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  if (operation.type === "create_post" && operation.entityType === "post") {
    await applyCreatePost(tx, device, operation);
    return;
  }

  if (operation.type === "update_post" && operation.entityType === "post") {
    await applyUpdatePost(tx, device, operation);
    return;
  }

  if (operation.type === "insert_ai_title" && operation.entityType === "post") {
    await applyInsertAITitle(tx, device, operation);
    return;
  }

  if (operation.type === "update_post_favorite" && operation.entityType === "post") {
    await applyUpdatePostFavorite(tx, device, operation);
    return;
  }

  if (operation.type === "update_post_pin" && operation.entityType === "post") {
    await applyUpdatePostPin(tx, device, operation);
    return;
  }

  if (operation.type === "delete_post" && operation.entityType === "post") {
    await applyDeletePost(tx, device, operation);
    return;
  }

  if (operation.type === "update_media_transcription" && operation.entityType === "media") {
    await applyUpdateMediaTranscription(tx, device, operation);
    return;
  }

  if (operation.type === "create_comment" && operation.entityType === "comment") {
    await applyCreateComment(tx, device, operation);
    return;
  }

  if (operation.type === "delete_comment" && operation.entityType === "comment") {
    await applyDeleteComment(tx, device, operation);
    return;
  }

  if (operation.type === "upsert_tag" && operation.entityType === "tag") {
    await applyUpsertTag(tx, operation);
    return;
  }

  if (operation.type === "archive_tag" && operation.entityType === "tag") {
    await applyArchiveTag(tx, operation);
    return;
  }

  if (operation.type === "restore_tag" && operation.entityType === "tag") {
    await applyRestoreTag(tx, operation);
    return;
  }

  if (operation.type === "delete_tag" && operation.entityType === "tag") {
    await applyDeleteTag(tx, operation);
    return;
  }

  if (operation.type === "merge_tag" && operation.entityType === "tag") {
    await applyMergeTag(tx, operation);
    return;
  }

  if (operation.type === "upsert_tag_alias" && operation.entityType === "tag_alias") {
    await applyUpsertTagAlias(tx, operation);
    return;
  }

  if (operation.type === "delete_tag_alias" && operation.entityType === "tag_alias") {
    await applyDeleteTagAlias(tx, operation);
    return;
  }

  if (operation.type === "set_post_tags" && operation.entityType === "post") {
    await applySetPostTags(tx, operation);
    return;
  }

  if (await applyCheckInOperation(tx, operation)) {
    return;
  }

  throw new OperationRejectedError(`Unsupported operation type: ${operation.type}`);
}

async function markOperationRejected(
  prisma: PrismaClient,
  device: Device,
  operation: SyncOperationInput,
  reason: string,
): Promise<void> {
  await prisma.syncOperation.upsert({
    where: {
      deviceId_opId: {
        deviceId: device.id,
        opId: operation.opId,
      },
    },
    create: {
      opId: operation.opId,
      deviceId: device.id,
      type: operation.type,
      entityType: operation.entityType,
      entityId: operation.entityId,
      payloadJson: JSON.stringify(operation.payload),
      rejectedAt: new Date(),
      rejectionReason: reason,
    },
    update: {
      rejectedAt: new Date(),
      rejectionReason: reason,
    },
  });
}
