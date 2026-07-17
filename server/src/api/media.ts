import { createReadStream } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";

import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import { safeRegularFileStatsInside } from "../storage/file-safety.js";
import {
  isAllowedUpload,
  parseQuery,
  parseUploadFields,
  pathForVariantOrGeneratedThumbnail,
  relativeUploadPath,
  type MediaRouteContext,
  upsertMediaRecord,
} from "./media-storage.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";
import {
  contentTypeForMediaPath,
  mediaUploadErrorCode,
  parseMediaIds,
  parseMediaVariant,
} from "./media-helpers.js";
import { isPathInside, parseContentLength, writeUploadedFile } from "./upload-helpers.js";

const UPLOAD_STREAM_TIMEOUT_MS = 240_000;

export async function registerMediaRoutes(
  app: FastifyInstance,
  context: MediaRouteContext,
): Promise<void> {
  app.post<{ Body: { mediaIds?: unknown; variant?: unknown } }>(
    "/api/v1/media/batch-download",
    async (request, reply) => {
      try {
        await authenticateDevice(request, context.prisma);
      } catch (error) {
        if (error instanceof UnauthorizedError) {
          return sendUnauthorized(reply, error.message);
        }

        throw error;
      }

      const mediaIds = parseMediaIds(request.body?.mediaIds);
      const variant = parseMediaVariant(
        typeof request.body?.variant === "string" ? request.body.variant : "thumbnail",
      );
      if (mediaIds.length === 0) {
        return sendBadRequest(reply, "mediaIds must contain at least one id");
      }
      if (!variant) {
        return sendBadRequest(reply, "variant must be one of: compressed, original, thumbnail");
      }

      const downloadedMedia = [];
      for (const mediaId of mediaIds) {
        const media = await context.prisma.media.findUnique({
          where: {
            id: mediaId,
          },
        });
        if (!media || media.deletedAt) {
          continue;
        }

        const relativePath = await pathForVariantOrGeneratedThumbnail(context, media, variant);
        if (!relativePath) {
          continue;
        }

        const absolutePath = path.join(context.paths.dataDir, relativePath);
        if (
          !isPathInside(context.paths.dataDir, absolutePath) ||
          !(await safeRegularFileStatsInside(context.paths.dataDir, absolutePath))
        ) {
          continue;
        }

        const data = await readFile(absolutePath);
        downloadedMedia.push({
          id: media.id,
          variant,
          contentType: contentTypeForMediaPath(relativePath),
          fileName: path.basename(relativePath),
          base64: data.toString("base64"),
        });
      }

      await context.fileLogger.info("media.batch_download", {
        requestedCount: mediaIds.length,
        returnedCount: downloadedMedia.length,
        variant,
      });

      return reply.send({
        media: downloadedMedia,
      });
    },
  );

  app.get<{ Params: { mediaId: string } }>(
    "/api/v1/media/:mediaId",
    async (request, reply) => {
      try {
        await authenticateDevice(request, context.prisma);
      } catch (error) {
        if (error instanceof UnauthorizedError) {
          return sendUnauthorized(reply, error.message);
        }

        throw error;
      }

      const query = parseQuery(request.query);
      const variant = parseMediaVariant(query.variant ?? "compressed");
      if (!variant) {
        return sendBadRequest(reply, "variant must be one of: compressed, original, thumbnail");
      }

      const media = await context.prisma.media.findUnique({
        where: {
          id: request.params.mediaId,
        },
      });

      if (!media || media.deletedAt) {
        return sendNotFound(reply, "Media not found");
      }

      const relativePath = await pathForVariantOrGeneratedThumbnail(context, media, variant);
      if (!relativePath) {
        return sendNotFound(reply, "Requested media variant not found");
      }

      const absolutePath = path.join(context.paths.dataDir, relativePath);
      if (!isPathInside(context.paths.dataDir, absolutePath)) {
        return sendNotFound(reply, "Media file not found");
      }

      const fileStats = await safeRegularFileStatsInside(context.paths.dataDir, absolutePath);
      if (!fileStats) {
        return sendNotFound(reply, "Media file not found");
      }
      await context.fileLogger.info("media.download", {
        mediaId: request.params.mediaId,
        variant,
        sizeBytes: fileStats.size,
      });

      reply.header("Content-Type", contentTypeForMediaPath(relativePath));
      reply.header("Content-Length", String(fileStats.size));
      reply.header("Connection", "close");
      if (variant === "thumbnail" || fileStats.size <= 1_000_000) {
        return reply.send(await readFile(absolutePath));
      }

      return reply.send(createReadStream(absolutePath));
    },
  );

  app.post("/api/v1/media/upload", async (request, reply) => {
    try {
      await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const file = await request.file();
    if (!file) {
      return sendBadRequest(reply, "multipart file is required");
    }

    const fields = parseUploadFields(file.fields, reply);
    if (!fields) {
      file.file.resume();
      return reply;
    }

    if (!isAllowedUpload(file.mimetype, fields)) {
      file.file.resume();
      return sendBadRequest(reply, "Unsupported media upload type");
    }

    const post = await context.prisma.post.findUnique({
      where: {
        id: fields.postId,
      },
    });

    if (!post || post.deletedAt) {
      file.file.resume();
      return sendNotFound(reply, "Post not found");
    }

    const relativePath = relativeUploadPath(fields, file.mimetype, file.filename);
    const absolutePath = path.resolve(context.paths.dataDir, relativePath);
    if (!isPathInside(path.resolve(context.paths.dataDir), absolutePath)) {
      file.file.resume();
      return sendBadRequest(reply, "Upload path must stay inside the data directory");
    }

    const uploadStartedAt = Date.now();
    await context.fileLogger.info("media.upload_started", {
      mediaId: fields.mediaId,
      postId: fields.postId,
      kind: fields.kind,
      variant: fields.variant,
      mimeType: file.mimetype,
      expectedBytes: parseContentLength(request.headers["content-length"]),
    });

    let writeResult: { sizeBytes: number; checksum: string };
    try {
      writeResult = await writeUploadedFile(file, absolutePath, {
        timeoutMs: UPLOAD_STREAM_TIMEOUT_MS,
        timeoutMessage: "Media upload timed out",
      });
      await context.fileLogger.info("media.upload_received", {
        mediaId: fields.mediaId,
        postId: fields.postId,
        kind: fields.kind,
        variant: fields.variant,
        sizeBytes: writeResult.sizeBytes,
        elapsedMs: Date.now() - uploadStartedAt,
      });

      const media = await upsertMediaRecord(context.prisma, fields, relativePath, writeResult);
      await context.fileLogger.info("media.upload_completed", {
        mediaId: media.id,
        postId: media.postId,
        kind: media.kind,
        variant: fields.variant,
        status: media.status,
        sizeBytes: writeResult.sizeBytes,
        elapsedMs: Date.now() - uploadStartedAt,
      });

      return reply.send({
        media: {
          id: media.id,
          postId: media.postId,
          variant: fields.variant,
          status: media.status,
          path: relativePath,
          sizeBytes: writeResult.sizeBytes,
          checksum: writeResult.checksum,
        },
      });
    } catch (error) {
      await context.fileLogger.warn("media.upload_failed", {
        mediaId: fields.mediaId,
        postId: fields.postId,
        kind: fields.kind,
        variant: fields.variant,
        errorCode: mediaUploadErrorCode(error),
        message: error instanceof Error ? error.message : String(error),
        elapsedMs: Date.now() - uploadStartedAt,
      });
      throw error;
    }
  });
}
