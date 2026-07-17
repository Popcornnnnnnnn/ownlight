import test from "node:test";
import assert from "node:assert/strict";

import { shouldStartLegacyReviewScheduler } from "./review-scheduler-policy.js";

test("legacy weekly review scheduler is disabled by default", () => {
  assert.equal(shouldStartLegacyReviewScheduler({}), false);
});

test("legacy weekly review scheduler only starts behind explicit opt-in", () => {
  assert.equal(
    shouldStartLegacyReviewScheduler({
      PRIVATE_MOMENTS_ENABLE_LEGACY_REVIEW_SCHEDULER: "1",
    }),
    true,
  );
  assert.equal(
    shouldStartLegacyReviewScheduler({
      PRIVATE_MOMENTS_ENABLE_LEGACY_REVIEW_SCHEDULER: "true",
    }),
    true,
  );
});
