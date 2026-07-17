import { randomUUID } from "node:crypto";

import type { Prisma } from "@prisma/client";

import {
  cleanedTagName,
  canonicalDefaultPrimaryTagForId,
  emitPostTagChange,
  emitPostTagStateChange,
  emitTagAliasChange,
  emitTagChange,
  emitTagDeletedChange,
  isValidPostTagRole,
  isValidTagType,
  normalizeTagName,
  resolveTopicAreaId,
  upsertPostTag,
} from "../tags/tagging.js";
import {
  OperationRejectedError,
  type SyncOperationInput,
} from "./sync-types.js";
import {
  getBoolean,
  getDate,
  getNullableString,
  getOptionalString,
  getString,
  getStringArray,
} from "./sync-payload.js";

const MAX_TAG_ALIAS_LENGTH = 40;
export async function applyUpsertTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const type = getString(operation.payload, "type");
  const rawName = getString(operation.payload, "name");
  const colorHex = getOptionalString(operation.payload, "colorHex");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const isDefault = getBoolean(operation.payload, "isDefault") ?? false;
  const aiUsableAsPrimary = getBoolean(operation.payload, "aiUsableAsPrimary") ?? false;
  const rawAreaId = getOptionalString(operation.payload, "areaId");

  if (!type || !isValidTagType(type)) {
    throw new OperationRejectedError("upsert_tag.payload.type must be primary or topic");
  }

  const defaultPrimaryTag = canonicalDefaultPrimaryTagForId(operation.entityId);
  const name = defaultPrimaryTag ? defaultPrimaryTag.name : rawName ? cleanedTagName(rawName) : null;
  if (!name) {
    throw new OperationRejectedError("upsert_tag.payload.name is invalid");
  }

  const finalType = defaultPrimaryTag ? "primary" : type;
  const finalColorHex = defaultPrimaryTag ? colorHex ?? defaultPrimaryTag.colorHex : colorHex;
  const finalIsDefault = defaultPrimaryTag ? true : isDefault;
  const finalAiUsableAsPrimary = defaultPrimaryTag ? true : finalType === "primary" ? aiUsableAsPrimary : false;
  const normalizedName = normalizeTagName(name);
  const resolvedAreaId = finalType === "topic" ? resolveTopicAreaId(rawAreaId, name) : null;
  const updateData: Prisma.TagUpdateInput = {
    type: finalType,
    name,
    normalizedName,
    colorHex: finalColorHex,
    isDefault: finalIsDefault,
    isArchived: false,
    archivedAt: null,
    aiUsableAsPrimary: finalAiUsableAsPrimary,
  };
  if (finalType === "primary") {
    updateData.areaId = null;
  } else {
    updateData.areaId = resolvedAreaId;
  }
  const existingByName = await tx.tag.findUnique({
    where: {
      normalizedName,
    },
  });
  if (existingByName && existingByName.id !== operation.entityId) {
    throw new OperationRejectedError("Tag name already exists");
  }

  const tag = await tx.tag.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      type: finalType,
      name,
      normalizedName,
      colorHex: finalColorHex,
      isDefault: finalIsDefault,
      isArchived: false,
      aiUsableAsPrimary: finalAiUsableAsPrimary,
      areaId: resolvedAreaId,
      updatedAt,
    },
    update: updateData,
  });

  await emitTagChange(tx, tag);
}

export async function applyArchiveTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const archivedAt = getDate(operation.payload, "archivedAt") ?? operation.clientCreatedAt;
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    throw new OperationRejectedError("Tag not found");
  }

  const updated = await tx.tag.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isArchived: true,
      archivedAt,
    },
  });
  await emitTagChange(tx, updated);
}

export async function applyRestoreTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    throw new OperationRejectedError("Tag not found");
  }

  const updated = await tx.tag.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isArchived: false,
      archivedAt: null,
    },
  });
  await emitTagChange(tx, updated);
}

export async function applyDeleteTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    return;
  }

  if (tag.isDefault) {
    throw new OperationRejectedError("Default primary tags cannot be deleted");
  }

  if (!tag.isArchived) {
    throw new OperationRejectedError("Only archived tags can be deleted");
  }

  const activeAssignments = await tx.postTag.findMany({
    where: {
      tagId: tag.id,
      deletedAt: null,
    },
  });

  for (const assignment of activeAssignments) {
    const deleted = await tx.postTag.update({
      where: {
        id: assignment.id,
      },
      data: {
        updatedAt: deletedAt,
        deletedAt,
      },
    });
    await emitPostTagChange(tx, deleted, "post_tag_deleted");
  }

  const activeAliases = await tx.tagAlias.findMany({
    where: {
      tagId: tag.id,
      deletedAt: null,
    },
  });

  for (const alias of activeAliases) {
    const deletedAlias = await tx.tagAlias.update({
      where: {
        id: alias.id,
      },
      data: {
        deletedAt,
      },
    });
    await emitTagAliasChange(tx, deletedAlias, "tag_alias_deleted");
  }

  await tx.tag.delete({
    where: {
      id: tag.id,
    },
  });
  await emitTagDeletedChange(tx, tag, deletedAt);
}

export async function applyMergeTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const targetTagId = getString(operation.payload, "targetTagId");
  const rawAlias = getOptionalString(operation.payload, "alias");
  const mergedAt = getDate(operation.payload, "mergedAt") ?? operation.clientCreatedAt;

  if (!targetTagId) {
    throw new OperationRejectedError("merge_tag.payload.targetTagId is required");
  }

  if (targetTagId === operation.entityId) {
    throw new OperationRejectedError("merge_tag target must be different from source");
  }

  const [sourceTag, targetTag] = await Promise.all([
    tx.tag.findUnique({ where: { id: operation.entityId } }),
    tx.tag.findUnique({ where: { id: targetTagId } }),
  ]);

  if (!sourceTag || sourceTag.type !== "topic") {
    throw new OperationRejectedError("merge_tag source must be an existing topic tag");
  }

  if (!targetTag || targetTag.type !== "topic" || targetTag.isArchived) {
    throw new OperationRejectedError("merge_tag target must be an active topic tag");
  }

  const sourceAssignments = await tx.postTag.findMany({
    where: {
      tagId: sourceTag.id,
      deletedAt: null,
    },
  });

  for (const sourceAssignment of sourceAssignments) {
    const existingTarget = await tx.postTag.findUnique({
      where: {
        postId_tagId: {
          postId: sourceAssignment.postId,
          tagId: targetTag.id,
        },
      },
    });

    if (existingTarget) {
      const revivedTarget = await tx.postTag.update({
        where: {
          id: existingTarget.id,
        },
        data: {
          role: "topic",
          source: existingTarget.deletedAt ? sourceAssignment.source : existingTarget.source,
          confidence: existingTarget.deletedAt ? sourceAssignment.confidence : existingTarget.confidence,
          aiSummaryId: existingTarget.deletedAt ? sourceAssignment.aiSummaryId : existingTarget.aiSummaryId,
          updatedAt: mergedAt,
          deletedAt: null,
        },
      });
      await emitPostTagChange(tx, revivedTarget, "post_tag_updated");

      const deletedSource = await tx.postTag.update({
        where: {
          id: sourceAssignment.id,
        },
        data: {
          updatedAt: mergedAt,
          deletedAt: mergedAt,
        },
      });
      await emitPostTagChange(tx, deletedSource, "post_tag_deleted");
      continue;
    }

    const moved = await tx.postTag.update({
      where: {
        id: sourceAssignment.id,
      },
      data: {
        tagId: targetTag.id,
        role: "topic",
        updatedAt: mergedAt,
      },
    });
    await emitPostTagChange(tx, moved, "post_tag_updated");
  }

  const aliasName = cleanedTagName(rawAlias ?? sourceTag.name);
  if (aliasName) {
    const normalizedAlias = normalizeTagName(aliasName);
    const existingAlias = await tx.tagAlias.findUnique({
      where: {
        normalizedAlias,
      },
    });
    const conflictingTag = await tx.tag.findUnique({
      where: {
        normalizedName: normalizedAlias,
      },
    });

    if (!conflictingTag || conflictingTag.id === targetTag.id || conflictingTag.id === sourceTag.id) {
      if (!existingAlias || existingAlias.tagId === targetTag.id) {
        const alias = await tx.tagAlias.upsert({
          where: {
            normalizedAlias,
          },
          create: {
            id: randomUUID(),
            tagId: targetTag.id,
            alias: aliasName,
            normalizedAlias,
            deletedAt: null,
          },
          update: {
            tagId: targetTag.id,
            alias: aliasName,
            deletedAt: null,
          },
        });
        await emitTagAliasChange(tx, alias, "tag_alias_updated");
      }
    }
  }

  const archived = await tx.tag.update({
    where: {
      id: sourceTag.id,
    },
    data: {
      isArchived: true,
      archivedAt: mergedAt,
      updatedAt: mergedAt,
    },
  });
  await emitTagChange(tx, archived);
}

export async function applyUpsertTagAlias(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const tagId = getString(operation.payload, "tagId");
  const rawAlias = getString(operation.payload, "alias");

  if (!tagId) {
    throw new OperationRejectedError("upsert_tag_alias.payload.tagId is required");
  }

  const alias = rawAlias ? cleanedTagName(rawAlias) : null;
  if (!alias || alias.length > MAX_TAG_ALIAS_LENGTH) {
    throw new OperationRejectedError("upsert_tag_alias.payload.alias is invalid");
  }

  const tag = await tx.tag.findUnique({
    where: {
      id: tagId,
    },
  });
  if (!tag || tag.isArchived) {
    throw new OperationRejectedError("Tag not found");
  }

  const normalizedAlias = normalizeTagName(alias);
  const existingByAlias = await tx.tagAlias.findUnique({
    where: {
      normalizedAlias,
    },
  });
  if (existingByAlias && existingByAlias.id !== operation.entityId) {
    throw new OperationRejectedError("Tag alias already exists");
  }

  const existingTag = await tx.tag.findUnique({
    where: {
      normalizedName: normalizedAlias,
    },
  });
  if (existingTag && existingTag.id !== tagId) {
    throw new OperationRejectedError("Tag alias conflicts with another tag");
  }

  const saved = await tx.tagAlias.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      tagId,
      alias,
      normalizedAlias,
      deletedAt: null,
    },
    update: {
      tagId,
      alias,
      normalizedAlias,
      deletedAt: null,
    },
  });

  await emitTagAliasChange(tx, saved, "tag_alias_updated");
}

export async function applyDeleteTagAlias(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const alias = await tx.tagAlias.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!alias) {
    throw new OperationRejectedError("Tag alias not found");
  }

  const deleted = await tx.tagAlias.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
    },
  });

  await emitTagAliasChange(tx, deleted, "tag_alias_deleted");
}

export async function applySetPostTags(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const primaryTagId = getNullableString(operation.payload, "primaryTagId");
  const topicTagIds = getStringArray(operation.payload, "topicTagIds", 20);

  if (topicTagIds === null) {
    throw new OperationRejectedError("set_post_tags.payload.topicTagIds must be an array");
  }

  const post = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
    include: {
      tags: {
        where: {
          deletedAt: null,
        },
      },
    },
  });
  if (!post || post.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  const desiredTagIds = new Set(topicTagIds);
  if (primaryTagId) {
    desiredTagIds.add(primaryTagId);
  }

  const tags = desiredTagIds.size > 0
    ? await tx.tag.findMany({
        where: {
          id: {
            in: Array.from(desiredTagIds),
          },
          isArchived: false,
        },
      })
    : [];
  const tagsById = new Map(tags.map((tag) => [tag.id, tag]));

  if (primaryTagId) {
    const tag = tagsById.get(primaryTagId);
    if (!tag || tag.type !== "primary") {
      throw new OperationRejectedError("set_post_tags.payload.primaryTagId must reference an active primary tag");
    }
  }

  for (const topicTagId of topicTagIds) {
    const tag = tagsById.get(topicTagId);
    if (!tag || tag.type !== "topic") {
      throw new OperationRejectedError("set_post_tags.payload.topicTagIds must reference active topic tags");
    }
  }

  const desired = new Map<string, "primary" | "topic">();
  if (primaryTagId) {
    desired.set(primaryTagId, "primary");
  }
  for (const topicTagId of topicTagIds) {
    desired.set(topicTagId, "topic");
  }

  for (const existing of post.tags) {
    const desiredRole = desired.get(existing.tagId);
    if (desiredRole === existing.role) {
      if (existing.source !== "manual") {
        const updated = await tx.postTag.update({
          where: {
            id: existing.id,
          },
          data: {
            source: "manual",
            confidence: null,
            aiSummaryId: null,
            updatedAt,
          },
        });
        await emitPostTagChange(tx, updated, "post_tag_updated");
      }
      desired.delete(existing.tagId);
      continue;
    }

    const deleted = await tx.postTag.update({
      where: {
        id: existing.id,
      },
      data: {
        deletedAt: updatedAt,
        updatedAt,
      },
    });
    await emitPostTagChange(tx, deleted, "post_tag_deleted");
  }

  for (const [tagId, role] of desired) {
    if (!isValidPostTagRole(role)) {
      continue;
    }

    await upsertPostTag(tx, {
      postId: post.id,
      tagId,
      role,
      source: "manual",
      confidence: null,
      aiSummaryId: null,
      now: updatedAt,
    });
  }

  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      tagsUserEditedAt: updatedAt,
      clientUpdatedAt: updatedAt,
    },
  });
  await emitPostTagStateChange(tx, post.id, {
    aiTagProcessedAt: post.aiTagProcessedAt,
    tagsUserEditedAt: updatedAt,
  });
}
