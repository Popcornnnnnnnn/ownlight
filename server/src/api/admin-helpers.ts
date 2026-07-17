import { readdir, readFile, unlink } from "node:fs/promises";
import path from "node:path";

import type { Device, Media, Post, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyReply } from "fastify";

import { isAdminDevice } from "../auth/admin-authorization.js";
import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { sendForbidden, sendUnauthorized } from "./http-errors.js";

export type DeletedFilter = "active" | "deleted" | "all";

export type AdminPost = Post & {
  createdByDevice: Device | null;
  updatedByDevice: Device | null;
  media: Media[];
};

export interface TimelineCursor {
  occurredAt: string;
  id: string;
}

export const adminPostInclude = {
  createdByDevice: true,
  updatedByDevice: true,
  media: {
    orderBy: {
      sortOrder: "asc",
    },
  },
} satisfies Prisma.PostInclude;

export async function authenticateOrReply(
  request: Parameters<typeof authenticateDevice>[0],
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<Device | null> {
  try {
    return await authenticateDevice(request, prisma);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      sendUnauthorized(reply, error.message);
      return null;
    }

    throw error;
  }
}

export async function authenticateAdminOrReply(
  request: Parameters<typeof authenticateDevice>[0],
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<Device | null> {
  const device = await authenticateOrReply(request, reply, prisma);
  if (!device) {
    return null;
  }

  if (!isAdminDevice(device)) {
    sendForbidden(reply, "Admin routes require a Mac or web session");
    return null;
  }

  return device;
}

export function postWhere({
  cursor,
  deleted,
  deviceId,
  q,
}: {
  cursor: TimelineCursor | null;
  deleted: DeletedFilter;
  deviceId: string | undefined;
  q: string | undefined;
}): Prisma.PostWhereInput {
  const where: Prisma.PostWhereInput = {};

  if (deleted === "active") {
    where.deletedAt = null;
  } else if (deleted === "deleted") {
    where.deletedAt = {
      not: null,
    };
  }

  if (deviceId) {
    where.createdByDeviceId = deviceId;
  }

  if (q) {
    where.OR = [
      {
        text: {
          contains: q,
        },
      },
      {
        media: {
          some: {
            deletedAt: null,
            transcriptionText: {
              contains: q,
            },
          },
        },
      },
      {
        comments: {
          some: {
            deletedAt: null,
            text: {
              contains: q,
            },
          },
        },
      },
    ];
  }

  if (cursor) {
    where.OR = [
      {
        occurredAt: {
          lt: new Date(cursor.occurredAt),
        },
      },
      {
        occurredAt: new Date(cursor.occurredAt),
        id: {
          lt: cursor.id,
        },
      },
    ];
  }

  return where;
}

export function serializeAdminPost(post: AdminPost): Record<string, unknown> {
  const activeMedia = post.media.filter((media) => !media.deletedAt);

  return {
    id: post.id,
    text: post.text,
    isFavorite: post.isFavorite,
    isPinned: post.isPinned,
    pinnedAt: post.pinnedAt?.toISOString() ?? null,
    occurredAt: post.occurredAt.toISOString(),
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    deletedAt: post.deletedAt?.toISOString() ?? null,
    clientCreatedAt: post.clientCreatedAt?.toISOString() ?? null,
    clientUpdatedAt: post.clientUpdatedAt?.toISOString() ?? null,
    serverVersion: post.serverVersion,
    createdByDevice: post.createdByDevice ? serializeDevice(post.createdByDevice) : null,
    updatedByDevice: post.updatedByDevice ? serializeDevice(post.updatedByDevice) : null,
    mediaCount: activeMedia.length,
    totalMediaCount: post.media.length,
    media: post.media.map((media) => ({
      id: media.id,
      kind: media.kind,
      status: media.status,
      sortOrder: media.sortOrder,
      originalPreserved: media.originalPreserved,
      width: media.width,
      height: media.height,
      mimeType: media.mimeType,
      durationSeconds: media.durationSeconds,
      transcriptionText: media.transcriptionText,
      compressedSizeBytes: media.compressedSizeBytes,
      originalSizeBytes: media.originalSizeBytes,
      checksum: media.checksum,
      deletedAt: media.deletedAt?.toISOString() ?? null,
      compressedUrl:
        media.compressedPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=compressed`
          : null,
      originalUrl:
        media.originalPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=original`
          : null,
      thumbnailUrl:
        media.thumbnailPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=thumbnail`
          : null,
    })),
  };
}

export function serializeDevice(device: Device): Record<string, unknown> {
  return {
    id: device.id,
    name: device.name,
    platform: device.platform,
    lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
    revokedAt: device.revokedAt?.toISOString() ?? null,
    createdAt: device.createdAt.toISOString(),
  };
}

export async function softDeletePost(
  prisma: PrismaClient,
  postId: string,
  adminDeviceId: string,
): Promise<void> {
  const deletedAt = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.post.update({
      where: {
        id: postId,
      },
      data: {
        deletedAt,
        updatedByDeviceId: adminDeviceId,
      },
    });

    await tx.media.updateMany({
      where: {
        postId,
        deletedAt: null,
      },
      data: {
        deletedAt,
        status: "deleted",
      },
    });

    await tx.comment.updateMany({
      where: {
        postId,
        deletedAt: null,
      },
      data: {
        deletedAt,
        updatedByDeviceId: adminDeviceId,
      },
    });

    const change = await tx.serverChange.create({
      data: {
        entityType: "post",
        entityId: postId,
        changeType: "post_deleted",
        payloadJson: JSON.stringify({
          id: postId,
          deletedAt: deletedAt.toISOString(),
        }),
      },
    });

    await tx.post.update({
      where: {
        id: postId,
      },
      data: {
        serverVersion: change.version,
      },
    });
  });
}

export function uniqueMediaPaths(media: Media[]): string[] {
  return [
    ...new Set(
      media.flatMap((item) =>
        [item.compressedPath, item.originalPath, item.thumbnailPath].filter(isString),
      ),
    ),
  ];
}

export async function deleteMediaFiles(
  dataDir: string,
  relativePaths: string[],
): Promise<{ deleted: number; failed: number }> {
  let deleted = 0;
  let failed = 0;

  for (const relativePath of relativePaths) {
    const absolutePath = path.join(dataDir, relativePath);
    if (!isPathInside(dataDir, absolutePath)) {
      failed += 1;
      continue;
    }

    try {
      await unlink(absolutePath);
      deleted += 1;
    } catch (error) {
      if (isNotFoundError(error)) {
        continue;
      }

      failed += 1;
    }
  }

  return {
    deleted,
    failed,
  };
}

export async function readRecentLogs(logsDir: string, limit: number): Promise<unknown[]> {
  const files = (await readdir(logsDir))
    .filter((file) => file.endsWith(".jsonl"))
    .sort()
    .reverse();

  const logs: unknown[] = [];
  for (const file of files) {
    const content = await readFile(path.join(logsDir, file), "utf8");
    const lines = content.trim().split("\n").filter(Boolean).reverse();

    for (const line of lines) {
      logs.push(parseLogLine(line));
      if (logs.length >= limit) {
        return logs;
      }
    }
  }

  return logs;
}

export function parseQuery(query: unknown): Record<string, string | undefined> {
  if (typeof query !== "object" || query === null || Array.isArray(query)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(query)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }

  return parsed;
}

export function parseBody(body: unknown): Record<string, string | undefined> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(body)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }

  return parsed;
}

export function parseLimit(
  value: string | undefined,
  defaultLimit: number,
  maxLimit: number,
): number | null {
  if (!value) {
    return defaultLimit;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maxLimit) {
    return null;
  }

  return parsed;
}

export function parseDeletedFilter(value: string | undefined): DeletedFilter | null {
  if (!value) {
    return "active";
  }

  if (value === "active" || value === "deleted" || value === "all") {
    return value;
  }

  return null;
}

export function parseCursor(value: string | undefined): TimelineCursor | null {
  if (!value) {
    return null;
  }

  try {
    const parsed = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as {
      occurredAt?: unknown;
      id?: unknown;
    };

    if (typeof parsed.occurredAt !== "string" || typeof parsed.id !== "string") {
      return null;
    }

    if (Number.isNaN(new Date(parsed.occurredAt).getTime())) {
      return null;
    }

    return {
      occurredAt: parsed.occurredAt,
      id: parsed.id,
    };
  } catch {
    return null;
  }
}

export function encodeCursor(post: Post): string {
  const cursor: TimelineCursor = {
    occurredAt: post.occurredAt.toISOString(),
    id: post.id,
  };

  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}

function parseLogLine(line: string): unknown {
  try {
    return JSON.parse(line) as unknown;
  } catch {
    return {
      raw: line,
    };
  }
}

function isString(value: string | null): value is string {
  return typeof value === "string" && value.length > 0;
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
