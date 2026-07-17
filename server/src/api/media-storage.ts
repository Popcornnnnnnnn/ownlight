import { execFile } from "node:child_process";
import { mkdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import type { PrismaClient } from "@prisma/client";
import type { FastifyReply } from "fastify";

import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import type { MaintenanceModeService } from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import {
  extensionForMediaMimeType,
  isAllowedMediaUpload,
  parseMediaUploadFields,
  relativeMediaPath,
  type MediaUploadFields as UploadFields,
} from "./media-upload-fields.js";
import {
  parseMediaVariant,
  pathForMediaVariant,
  type MediaVariant,
} from "./media-helpers.js";
import { sendBadRequest } from "./http-errors.js";
import { fileExists, isPathInside } from "./upload-helpers.js";

const execFileAsync = promisify(execFile);
const THUMBNAIL_MAX_EDGE = "800";
const THUMBNAIL_MAX_BYTES = 180_000;

export interface MediaRouteContext {
  config: AppConfig;
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
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

export function parseUploadFields(
  fields: Parameters<typeof parseMediaUploadFields>[0],
  reply: FastifyReply,
): UploadFields | null {
  const parsed = parseMediaUploadFields(fields);
  if (!parsed.ok) {
    sendBadRequest(reply, parsed.message);
    return null;
  }

  return parsed.fields;
}

export function isAllowedUpload(
  mimeType: string,
  fields: UploadFields,
): boolean {
  return isAllowedMediaUpload(mimeType, fields.kind, fields.variant);
}

export function relativeUploadPath(fields: UploadFields, mimeType: string, filename: string): string {
  const extension = extensionForMediaMimeType(mimeType, filename);
  return relativeMediaPath(fields.variant, fields.mediaId, extension);
}

export async function pathForVariantOrGeneratedThumbnail(
  context: MediaRouteContext,
  media: {
    id: string;
    kind: string;
    compressedPath: string | null;
    originalPath: string | null;
    thumbnailPath: string | null;
  },
  variant: MediaVariant,
): Promise<string | null> {
  if (variant === "thumbnail" && media.kind === "image" && media.compressedPath) {
    return generateThumbnailFromCompressed(context, media.id, media.compressedPath, media.thumbnailPath);
  }

  const existingPath = pathForMediaVariant(media, variant);
  if (existingPath) {
    return existingPath;
  }

  if (variant !== "thumbnail" || media.kind !== "image" || !media.compressedPath) {
    return null;
  }

  return generateThumbnailFromCompressed(context, media.id, media.compressedPath);
}

export async function upsertMediaRecord(
  prisma: PrismaClient,
  fields: UploadFields,
  relativePath: string,
  writeResult: { sizeBytes: number; checksum: string },
) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.media.findUnique({
      where: {
        id: fields.mediaId,
      },
    });

    const pathData = pathDataForVariant(fields.variant, relativePath, writeResult.sizeBytes);
    const status =
      fields.variant === "compressed" || existing?.compressedPath ? "uploaded" : "pending";

    const media = !existing
      ? await tx.media.create({
          data: {
            id: fields.mediaId,
            postId: fields.postId,
            kind: fields.kind,
            status,
            mimeType: fields.variant === "thumbnail" ? null : fields.mimeType,
            durationSeconds: fields.variant === "thumbnail" ? null : fields.durationSeconds,
            transcriptionText:
              fields.variant === "thumbnail" ? null : fields.transcriptionText,
            width: fields.variant === "thumbnail" ? null : fields.width,
            height: fields.variant === "thumbnail" ? null : fields.height,
            originalPreserved: fields.originalPreserved || fields.variant === "original",
            sortOrder: fields.sortOrder,
            checksum: writeResult.checksum,
            ...pathData,
          },
        })
      : await tx.media.update({
          where: {
            id: fields.mediaId,
          },
          data: {
            status,
            kind: fields.kind,
            mimeType:
              fields.variant === "thumbnail" ? existing.mimeType : fields.mimeType ?? existing.mimeType,
            durationSeconds:
              fields.variant === "thumbnail"
                ? existing.durationSeconds
                : fields.durationSeconds ?? existing.durationSeconds,
            transcriptionText:
              fields.variant === "thumbnail"
                ? existing.transcriptionText
                : fields.transcriptionText ?? existing.transcriptionText,
            width: fields.variant === "thumbnail" ? existing.width : fields.width ?? existing.width,
            height: fields.variant === "thumbnail" ? existing.height : fields.height ?? existing.height,
            originalPreserved:
              existing.originalPreserved || fields.originalPreserved || fields.variant === "original",
            sortOrder: fields.sortOrder,
            checksum: writeResult.checksum,
            ...pathData,
          },
        });

    const change = await tx.serverChange.create({
      data: {
        entityType: "media",
        entityId: media.id,
        changeType: "media_uploaded",
        payloadJson: JSON.stringify({
          id: media.id,
          postId: media.postId,
          kind: media.kind,
          status: media.status,
          variant: fields.variant,
          path: relativePath,
          mimeType: media.mimeType,
          durationSeconds: media.durationSeconds,
          transcriptionText: media.transcriptionText,
          width: media.width,
          height: media.height,
          originalPreserved: media.originalPreserved,
          sortOrder: media.sortOrder,
          checksum: media.checksum,
          compressedSizeBytes: media.compressedSizeBytes,
          originalSizeBytes: media.originalSizeBytes,
        }),
      },
    });

    await tx.post.update({
      where: {
        id: fields.postId,
      },
      data: {
        serverVersion: change.version,
      },
    });

    return media;
  });
}

async function generateThumbnailFromCompressed(
  context: MediaRouteContext,
  mediaId: string,
  compressedPath: string,
  existingThumbnailPath: string | null = null,
): Promise<string | null> {
  const inputPath = path.join(context.paths.dataDir, compressedPath);
  if (!isPathInside(context.paths.dataDir, inputPath) || !(await fileExists(inputPath))) {
    return null;
  }

  const relativePath = existingThumbnailPath ?? relativeMediaPath("thumbnail", mediaId, ".jpg");
  const outputPath = path.join(context.paths.dataDir, relativePath);
  if (!isPathInside(context.paths.dataDir, outputPath)) {
    return null;
  }

  await mkdir(path.dirname(outputPath), { recursive: true });

  if (await fileExists(outputPath)) {
    const thumbnailStats = await stat(outputPath);
    if (thumbnailStats.size <= THUMBNAIL_MAX_BYTES) {
      return relativePath;
    }

    await rm(outputPath, { force: true });
  }

  if (!(await fileExists(outputPath))) {
    try {
      await execFileAsync("sips", [
        "-s",
        "format",
        "jpeg",
        "-s",
        "formatOptions",
        "75",
        "-Z",
        THUMBNAIL_MAX_EDGE,
        inputPath,
        "--out",
        outputPath,
      ]);
    } catch (error) {
      await rm(outputPath, { force: true });
      await context.fileLogger.warn("media.thumbnail_failed", {
        mediaId,
        message: error instanceof Error ? error.message : String(error),
      });
      return null;
    }
  }

  await context.prisma.media.update({
    where: {
      id: mediaId,
    },
    data: {
      thumbnailPath: relativePath,
    },
  });

  await context.fileLogger.info("media.thumbnail_ready", {
    mediaId,
    path: relativePath,
  });

  return relativePath;
}

function pathDataForVariant(
  variant: MediaVariant,
  relativePath: string,
  sizeBytes: number,
): Record<string, string | number> {
  if (variant === "compressed") {
    return {
      compressedPath: relativePath,
      compressedSizeBytes: sizeBytes,
    };
  }

  if (variant === "original") {
    return {
      originalPath: relativePath,
      originalSizeBytes: sizeBytes,
    };
  }

  return {
    thumbnailPath: relativePath,
  };
}
