import type { FastifyInstance } from "fastify";

import { registerAdminArchiveRoutes } from "./admin-archive-routes.js";
import type { AdminMaintenanceRouteContext } from "./admin-maintenance-helpers.js";
import { registerAdminMaintenanceStateRoutes } from "./admin-maintenance-state-routes.js";

export async function registerAdminMaintenanceRoutes(
  app: FastifyInstance,
  context: AdminMaintenanceRouteContext,
): Promise<void> {
  await registerAdminMaintenanceStateRoutes(app, context);
  await registerAdminArchiveRoutes(app, context);
}
