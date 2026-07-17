import type { Device, PrismaClient } from "@prisma/client";
import type { FastifyInstance } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import { sendForbidden, sendUnauthorized } from "./http-errors.js";
import { parseJsonObject } from "./sync-payload.js";
import { applyOrReplayOperation, parseSyncRequestBody } from "./sync-route-helpers.js";
import { type RejectedOperation } from "./sync-types.js";

interface SyncRouteContext {
  prisma: PrismaClient;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

export async function registerSyncRoutes(
  app: FastifyInstance,
  context: SyncRouteContext,
): Promise<void> {
  app.post("/api/v1/sync", async (request, reply) => {
    let device: Device;
    try {
      device = await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }

    const body = parseSyncRequestBody(request.body, reply);
    if (!body) {
      return reply;
    }

    if (body.deviceId !== device.id) {
      return sendForbidden(reply, "Request deviceId does not match bearer token");
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const acceptedOps: string[] = [];
    const rejectedOps: RejectedOperation[] = [];

    for (const operation of body.localChanges) {
      const result = await applyOrReplayOperation(context.prisma, device, operation);
      if (result.accepted) {
        acceptedOps.push(operation.opId);
      } else {
        rejectedOps.push({
          opId: operation.opId,
          reason: result.reason,
        });
      }
    }

    const serverChanges = await context.prisma.serverChange.findMany({
      where: {
        version: {
          gt: body.lastSyncCursor,
        },
      },
      orderBy: {
        version: "asc",
      },
      take: 500,
    });

    const nextSyncCursor =
      serverChanges.length > 0
        ? serverChanges[serverChanges.length - 1]!.version
        : body.lastSyncCursor;

    await context.fileLogger.info("sync.completed", {
      deviceId: device.id,
      acceptedOps: acceptedOps.length,
      rejectedOps: rejectedOps.length,
      nextSyncCursor,
    });

    return reply.send({
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      acceptedOps,
      rejectedOps,
      serverChanges: serverChanges.map((change) => ({
        version: change.version,
        entityType: change.entityType,
        entityId: change.entityId,
        changeType: change.changeType,
        payload: parseJsonObject(change.payloadJson),
        createdAt: change.createdAt,
      })),
      nextSyncCursor,
    });
  });
}
