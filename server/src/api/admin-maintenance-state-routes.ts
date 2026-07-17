import type { FastifyInstance } from "fastify";

import {
  MaintenanceJobAlreadyRunningError,
  parseMaintenanceJobStatus,
  parseMaintenanceJobType,
  serializeMaintenanceJob,
} from "../maintenance/maintenance-jobs.js";
import {
  type AdminMaintenanceRouteContext,
  authenticateAdminOrReply,
  authenticateOrReply,
  collectSafeSyncHealthSnapshot,
  parseLimit,
  parseQuery,
  serializeOptionalJob,
} from "./admin-maintenance-helpers.js";
import { sendBadRequest, sendConflict, sendNotFound } from "./http-errors.js";

const DEFAULT_JOB_LIMIT = 25;
const MAX_JOB_LIMIT = 100;

export async function registerAdminMaintenanceStateRoutes(
  app: FastifyInstance,
  context: AdminMaintenanceRouteContext,
): Promise<void> {
  app.get("/api/v1/admin/maintenance/state", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      maintenance: context.maintenanceMode.snapshot(),
      runningJob: await serializeOptionalJob(context.maintenanceJobs.getRunningJob()),
    });
  });

  app.get("/api/v1/admin/maintenance/jobs", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const limit = parseLimit(query.limit, DEFAULT_JOB_LIMIT, MAX_JOB_LIMIT);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const type = parseMaintenanceJobType(query.type);
    if (query.type && !type) {
      return sendBadRequest(reply, "type is invalid");
    }

    const status = parseMaintenanceJobStatus(query.status);
    if (query.status && !status) {
      return sendBadRequest(reply, "status is invalid");
    }

    const jobs = await context.maintenanceJobs.listJobs({
      limit,
      type,
      status,
    });

    return reply.send({
      jobs: jobs.map(serializeMaintenanceJob),
    });
  });

  app.get<{ Params: { jobId: string } }>(
    "/api/v1/admin/maintenance/jobs/:jobId",
    async (request, reply) => {
      const authenticated = await authenticateOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const job = await context.maintenanceJobs.getJob(request.params.jobId);
      if (!job) {
        return sendNotFound(reply, "Maintenance job not found");
      }

      return reply.send({
        job: serializeMaintenanceJob(job),
      });
    },
  );

  app.post("/api/v1/admin/maintenance/jobs/sync-health-refresh", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const job = await context.maintenanceJobs.createJob({
      type: "sync_health_refresh",
      stage: "queued",
      metadata: {
        source: "admin",
      },
    });

    try {
      const { job: completedJob } = await context.maintenanceJobs.runJob(job.id, async () => {
        const snapshot = await collectSafeSyncHealthSnapshot(context.prisma);
        await context.maintenanceJobs.updateJob(job.id, {
          stage: "collecting",
          progress: 50,
          metadata: snapshot,
        });
      });

      return reply.send({
        job: serializeMaintenanceJob(completedJob),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }

      throw error;
    }
  });
}
