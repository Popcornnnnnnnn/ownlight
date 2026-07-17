import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance } from "fastify";

import { collectAIUsageDiagnostics } from "../ai/usage-ledger.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import { collectServerStorageStats } from "../storage/stats.js";
import {
  collectAISummaryDiagnostics,
  collectSyncDiagnostics,
  collectTagDiagnostics,
} from "./admin-diagnostics.js";
import {
  adminPostInclude,
  authenticateAdminOrReply,
  authenticateOrReply,
  deleteMediaFiles,
  encodeCursor,
  parseBody,
  parseCursor,
  parseDeletedFilter,
  parseLimit,
  parseQuery,
  postWhere,
  readRecentLogs,
  serializeAdminPost,
  serializeDevice,
  softDeletePost,
  uniqueMediaPaths,
} from "./admin-helpers.js";
import { sendBadRequest, sendNotFound } from "./http-errors.js";

const DEFAULT_LOG_LIMIT = 100;
const MAX_LOG_LIMIT = 500;
const DEFAULT_POST_LIMIT = 50;
const MAX_POST_LIMIT = 100;
const MAX_SEARCH_LIMIT = 100;

interface AdminRouteContext {
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

export async function registerAdminRoutes(
  app: FastifyInstance,
  context: AdminRouteContext,
): Promise<void> {
  app.get("/api/v1/admin/posts", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const deleted = parseDeletedFilter(query.deleted);
    if (!deleted) {
      return sendBadRequest(reply, "deleted must be one of: active, deleted, all");
    }

    const q = query.q?.trim();
    const limit = parseLimit(query.limit, DEFAULT_POST_LIMIT, q ? MAX_SEARCH_LIMIT : MAX_POST_LIMIT);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const cursor = q ? null : parseCursor(query.cursor);
    if (!q && query.cursor && !cursor) {
      return sendBadRequest(reply, "cursor is invalid");
    }

    const where = postWhere({
      deleted,
      deviceId: query.deviceId,
      q,
      cursor,
    });

    const posts = await context.prisma.post.findMany({
      where,
      orderBy: [
        {
          occurredAt: "desc",
        },
        {
          id: "desc",
        },
      ],
      take: q ? Math.min(limit, MAX_SEARCH_LIMIT) : limit,
      include: adminPostInclude,
    });

    return reply.send({
      posts: posts.map(serializeAdminPost),
      nextCursor: !q && posts.length === limit ? encodeCursor(posts[posts.length - 1]!) : null,
      searchLimited: Boolean(q),
    });
  });

  app.get<{ Params: { postId: string } }>(
    "/api/v1/admin/posts/:postId",
    async (request, reply) => {
      const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const post = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
        include: adminPostInclude,
      });

      if (!post) {
        return sendNotFound(reply, "Post not found");
      }

      return reply.send({
        post: serializeAdminPost(post),
      });
    },
  );

  app.delete<{ Params: { postId: string } }>(
    "/api/v1/admin/posts/:postId",
    async (request, reply) => {
      const adminDevice = await authenticateAdminOrReply(request, reply, context.prisma);
      if (!adminDevice) {
        return reply;
      }
      const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
      if (maintenanceReply) {
        return maintenanceReply;
      }

      const existing = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
      });

      if (!existing) {
        return sendNotFound(reply, "Post not found");
      }

      if (!existing.deletedAt) {
        await softDeletePost(context.prisma, request.params.postId, adminDevice.id);
        await context.fileLogger.info("admin.post_soft_deleted", {
          postId: request.params.postId,
          adminDeviceId: adminDevice.id,
        });
      }

      const post = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
        include: adminPostInclude,
      });

      return reply.send({
        post: post ? serializeAdminPost(post) : null,
      });
    },
  );

  app.get<{ Params: { deviceId: string } }>(
    "/api/v1/admin/devices/:deviceId/clean-posts/preview",
    async (request, reply) => {
      const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const device = await context.prisma.device.findUnique({
        where: {
          id: request.params.deviceId,
        },
      });

      if (!device) {
        return sendNotFound(reply, "Device not found");
      }

      const candidateCount = await context.prisma.post.count({
        where: {
          createdByDeviceId: device.id,
        },
      });

      return reply.send({
        device: serializeDevice(device),
        candidateCount,
      });
    },
  );

  app.post<{ Params: { deviceId: string }; Body: unknown }>(
    "/api/v1/admin/devices/:deviceId/clean-posts",
    async (request, reply) => {
      const adminDevice = await authenticateAdminOrReply(request, reply, context.prisma);
      if (!adminDevice) {
        return reply;
      }
      const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
      if (maintenanceReply) {
        return maintenanceReply;
      }

      const body = parseBody(request.body);
      const confirmDeviceName = body.confirmDeviceName?.trim();

      const device = await context.prisma.device.findUnique({
        where: {
          id: request.params.deviceId,
        },
      });

      if (!device) {
        return sendNotFound(reply, "Device not found");
      }

      if (confirmDeviceName !== device.name) {
        return sendBadRequest(reply, "confirmDeviceName must match the device name");
      }

      const posts = await context.prisma.post.findMany({
        where: {
          createdByDeviceId: device.id,
        },
        include: {
          media: true,
        },
      });

      const deletedAt = new Date();
      const postIds = posts.map((post) => post.id);
      const mediaPaths = uniqueMediaPaths(posts.flatMap((post) => post.media));

      if (postIds.length > 0) {
        await context.prisma.$transaction(async (tx) => {
          for (const post of posts) {
            await tx.serverChange.create({
              data: {
                entityType: "post",
                entityId: post.id,
                changeType: "post_deleted",
                payloadJson: JSON.stringify({
                  id: post.id,
                  deletedAt: deletedAt.toISOString(),
                  cleanup: true,
                }),
              },
            });
          }

          await tx.post.deleteMany({
            where: {
              id: {
                in: postIds,
              },
            },
          });
        });
      }

      const mediaCleanup = await deleteMediaFiles(context.paths.dataDir, mediaPaths);
      await context.fileLogger.warn("admin.device_posts_cleaned", {
        deviceId: device.id,
        deviceName: device.name,
        adminDeviceId: adminDevice.id,
        postCount: postIds.length,
        deletedMediaFiles: mediaCleanup.deleted,
        failedMediaFiles: mediaCleanup.failed,
      });

      return reply.send({
        device: serializeDevice(device),
        deletedPosts: postIds.length,
        deletedMediaFiles: mediaCleanup.deleted,
        failedMediaFiles: mediaCleanup.failed,
      });
    },
  );

  app.get("/api/v1/admin/status", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const [
      activeDevices,
      revokedDevices,
      posts,
      deletedPosts,
      media,
      storage,
      aiSummaries,
      aiUsage,
      tags,
      sync,
    ] =
      await Promise.all([
        context.prisma.device.count({
          where: {
            revokedAt: null,
          },
        }),
        context.prisma.device.count({
          where: {
            revokedAt: {
              not: null,
            },
          },
        }),
        context.prisma.post.count({
          where: {
            deletedAt: null,
          },
        }),
        context.prisma.post.count({
          where: {
            deletedAt: {
              not: null,
            },
          },
        }),
        context.prisma.media.count(),
        collectServerStorageStats(context.paths),
        collectAISummaryDiagnostics(context.prisma),
        collectAIUsageDiagnostics(context.prisma),
        collectTagDiagnostics(context.prisma),
        collectSyncDiagnostics(context.prisma),
      ]);

    return reply.send({
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      dataDir: context.paths.dataDir,
      uptimeSeconds: Math.round(process.uptime()),
      counts: {
        activeDevices,
        revokedDevices,
        posts,
        deletedPosts,
        media,
      },
      storage,
      aiSummaries,
      aiUsage,
      tags,
      sync,
    });
  });

  app.get("/api/v1/admin/logs", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const limit = parseLimit(query.limit, DEFAULT_LOG_LIMIT, MAX_LOG_LIMIT);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 500");
    }

    return reply.send({
      logs: await readRecentLogs(context.paths.logsDir, limit),
    });
  });
}
