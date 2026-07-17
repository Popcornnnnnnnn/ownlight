import type { Device, PrismaClient } from "@prisma/client";
import type { FastifyReply, FastifyRequest } from "fastify";

import { isAdminDevice } from "../auth/admin-authorization.js";
import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { ExportImportService } from "../maintenance/export-import-service.js";
import type { MaintenanceModeService } from "../maintenance/maintenance-mode.js";
import {
  serializeMaintenanceJob,
  type MaintenanceJobService,
} from "../maintenance/maintenance-jobs.js";
import type { ResticService } from "../maintenance/restic-service.js";
import { sendBadRequest, sendForbidden, sendUnauthorized } from "./http-errors.js";

export interface AdminMaintenanceRouteContext {
  prisma: PrismaClient;
  exportImport: ExportImportService;
  maintenanceJobs: MaintenanceJobService;
  maintenanceMode: MaintenanceModeService;
  restic: ResticService;
}

export async function collectSafeSyncHealthSnapshot(
  prisma: PrismaClient,
): Promise<Record<string, unknown>> {
  const [
    serverChange,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChange,
    lastOperation,
  ] = await Promise.all([
    prisma.serverChange.aggregate({
      _max: {
        version: true,
      },
    }),
    prisma.syncOperation.count({
      where: {
        appliedAt: null,
        rejectedAt: null,
      },
    }),
    prisma.syncOperation.count({
      where: {
        rejectedAt: {
          not: null,
        },
      },
    }),
    prisma.media.count({
      where: {
        status: "failed",
        deletedAt: null,
      },
    }),
    prisma.aiSummary.count({
      where: {
        deletedAt: null,
        status: {
          in: ["transcribing", "summarizing", "failed"],
        },
      },
    }),
    prisma.serverChange.findFirst({
      orderBy: {
        createdAt: "desc",
      },
      select: {
        createdAt: true,
      },
    }),
    prisma.syncOperation.findFirst({
      orderBy: {
        receivedAt: "desc",
      },
      select: {
        receivedAt: true,
        appliedAt: true,
        rejectedAt: true,
      },
    }),
  ]);

  return {
    latestServerChangeVersion: serverChange._max.version ?? 0,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChangeAt: lastServerChange?.createdAt.toISOString() ?? null,
    lastSyncOperationAt: lastOperation?.receivedAt.toISOString() ?? null,
    lastSuccessfulSyncAt: lastOperation?.appliedAt?.toISOString() ?? null,
    lastRejectedSyncAt: lastOperation?.rejectedAt?.toISOString() ?? null,
  };
}

export async function serializeOptionalJob(
  jobPromise: ReturnType<MaintenanceJobService["getRunningJob"]>,
): Promise<Record<string, unknown> | null> {
  const job = await jobPromise;
  return job ? serializeMaintenanceJob(job) : null;
}

export async function authenticateOrReply(
  request: FastifyRequest,
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
  request: FastifyRequest,
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
    if (typeof value === "string") {
      parsed[key] = value;
    } else if (typeof value === "boolean") {
      parsed[key] = value ? "true" : "false";
    }
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

export function sendArchiveActionError(reply: FastifyReply, error: unknown): FastifyReply {
  if (error instanceof Error) {
    return sendBadRequest(reply, error.message);
  }

  return sendBadRequest(reply, "Archive operation failed");
}
