const ENABLED_VALUES = new Set(["1", "true", "yes", "on"]);

export function shouldStartLegacyReviewScheduler(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.PRIVATE_MOMENTS_ENABLE_LEGACY_REVIEW_SCHEDULER;
  return typeof value === "string" && ENABLED_VALUES.has(value.trim().toLowerCase());
}
