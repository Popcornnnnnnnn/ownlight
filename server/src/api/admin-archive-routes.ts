import type { FastifyInstance } from "fastify";

import {
  MaintenanceJobAlreadyRunningError,
  serializeMaintenanceJob,
} from "../maintenance/maintenance-jobs.js";
import {
  type AdminMaintenanceRouteContext,
  authenticateAdminOrReply,
  authenticateOrReply,
  parseBody,
  sendArchiveActionError,
} from "./admin-maintenance-helpers.js";
import { sendBadRequest, sendConflict, sendNotFound } from "./http-errors.js";

const CLEAR_STALE_PENDING_PROMOTE_CONFIRMATION = "CLEAR STALE PENDING PROMOTE";

export async function registerAdminArchiveRoutes(
  app: FastifyInstance,
  context: AdminMaintenanceRouteContext,
): Promise<void> {
  app.get("/api/v1/admin/archive/repository", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      repository: await context.restic.getRepositoryState(),
    });
  });

  app.post("/api/v1/admin/archive/repository", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.repositoryPath) {
      return sendBadRequest(reply, "repositoryPath is required");
    }

    return reply.send({
      repository: await context.restic.configureRepository(body.repositoryPath),
    });
  });

  app.post("/api/v1/admin/archive/repository/init", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    try {
      return reply.send({
        repository: await context.restic.initializeRepository(),
      });
    } catch (error) {
      return sendArchiveActionError(reply, error);
    }
  });

  app.get("/api/v1/admin/archive/snapshots", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    try {
      return reply.send({
        snapshots: await context.restic.listSnapshots(),
      });
    } catch (error) {
      return sendArchiveActionError(reply, error);
    }
  });

  app.get("/api/v1/admin/archive/pending-promote", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      pendingPromote: await context.restic.getPendingPromoteState(),
    });
  });

  app.post("/api/v1/admin/archive/pending-promote/clear", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (body.confirmation !== CLEAR_STALE_PENDING_PROMOTE_CONFIRMATION) {
      return sendBadRequest(reply, `confirmation must be exactly: ${CLEAR_STALE_PENDING_PROMOTE_CONFIRMATION}`);
    }

    const pendingPromote = await context.restic.getPendingPromoteState();
    if (!pendingPromote) {
      return sendNotFound(reply, "Pending promote instructions not found");
    }
    if (!pendingPromote.stale) {
      return sendConflict(reply, "Pending promote instructions are still active");
    }

    await context.restic.clearPendingPromoteState();
    return reply.send({
      cleared: true,
    });
  });

  app.get("/api/v1/admin/archive/pending-promote/readiness", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      readiness: await context.restic.runPendingPromoteReadinessDrill(),
    });
  });

  app.post("/api/v1/admin/archive/schedule", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (body.enabled !== "true" && body.enabled !== "false") {
      return sendBadRequest(reply, "enabled is required");
    }
    if (!body.timeOfDay) {
      return sendBadRequest(reply, "timeOfDay is required");
    }

    return reply.send({
      repository: await context.restic.updateSchedule({
        enabled: body.enabled === "true",
        timeOfDay: body.timeOfDay,
      }),
    });
  });

  app.post("/api/v1/admin/archive/jobs/backup", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const created = await context.maintenanceJobs.createJob({
      type: "backup_create",
      stage: "queued",
      metadata: {
        source: "manual",
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "creating_snapshot",
          progress: 10,
        });
        const metadata = await context.restic.createBackup(created.id, "manual");
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "backup_written",
          progress: 90,
          metadata,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/check", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const created = await context.maintenanceJobs.createJob({
      type: "backup_check",
      stage: "queued",
      metadata: {},
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        const metadata = await context.restic.checkRepository();
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "checked",
          progress: 90,
          metadata,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/restore", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.snapshotId) {
      return sendBadRequest(reply, "snapshotId is required");
    }
    const snapshotId = body.snapshotId;
    const restoreName = body.restoreName;

    const created = await context.maintenanceJobs.createJob({
      type: "backup_restore",
      stage: "queued",
      metadata: {
        snapshotId,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "restoring",
          progress: 10,
        });
        const metadata = await context.restic.restoreSnapshot(snapshotId, restoreName);
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "verified",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.restorePath === "string" ? metadata.restorePath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/promote", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.restoredDataDir || !body.confirmation) {
      return sendBadRequest(reply, "restoredDataDir and confirmation are required");
    }
    const restoredDataDir = body.restoredDataDir;
    const confirmation = body.confirmation;

    const created = await context.maintenanceJobs.createJob({
      type: "backup_promote",
      stage: "queued",
      metadata: {
        restoredDataDir,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        context.maintenanceMode.enter(created.id, "Promoting restored archive");
        try {
          await context.maintenanceJobs.updateJob(created.id, {
            stage: "pre_promote_backup",
            progress: 10,
          });
          const metadata = await context.restic.promoteRestore(
            created.id,
            restoredDataDir,
            confirmation,
          );
          await context.maintenanceJobs.updateJob(created.id, {
            stage: "pending_restart",
            progress: 90,
            metadata,
            artifactPath: typeof metadata.pendingPromotePath === "string"
              ? metadata.pendingPromotePath
              : null,
          });
        } finally {
          context.maintenanceMode.exit(created.id);
        }
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      context.maintenanceMode.exit(created.id);
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/export", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    const created = await context.maintenanceJobs.createJob({
      type: "export_create",
      stage: "queued",
      metadata: {
        mode: body.from || body.to ? "date_range" : "all",
        from: body.from ?? null,
        to: body.to ?? null,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "exporting",
          progress: 10,
        });
        const metadata = await context.exportImport.createExport({
          from: body.from,
          to: body.to,
        });
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "exported",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.packagePath === "string" ? metadata.packagePath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/import", async (request, reply) => {
    const authenticated = await authenticateAdminOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.packagePath) {
      return sendBadRequest(reply, "packagePath is required");
    }
    const packagePath = body.packagePath;

    const created = await context.maintenanceJobs.createJob({
      type: "import_restore",
      stage: "queued",
      metadata: {
        packagePath,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "importing",
          progress: 10,
        });
        const metadata = await context.exportImport.importPackage({
          packagePath,
          importName: body.importName,
        });
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "imported",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.importPath === "string" ? metadata.importPath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });
}
