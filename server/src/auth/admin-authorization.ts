import type { Device } from "@prisma/client";

const ADMIN_PLATFORMS = new Set(["mac", "web"]);

export function adminEnabledForPlatform(platform: string): boolean {
  return ADMIN_PLATFORMS.has(platform);
}

export function isAdminDevice(device: Pick<Device, "adminEnabled">): boolean {
  return device.adminEnabled;
}
