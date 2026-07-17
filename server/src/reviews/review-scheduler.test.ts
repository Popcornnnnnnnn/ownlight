import test from "node:test";
import assert from "node:assert/strict";

import { ReviewScheduler } from "./review-scheduler.js";

test("scheduler publishes ready weekly review when publish toggle is enabled", async () => {
  let updatedLastAutoWeeklyDate: string | null = null;
  let publishedReviewId: string | null = null;
  const logFields: Record<string, unknown>[] = [];

  const scheduler = new ReviewScheduler({
    getSettings: async () => ({
      autoWeeklyEnabled: true,
      publishWeeklyToMoments: true,
      lastAutoWeeklyDate: null,
    }),
    updateSettings: async (input: { lastAutoWeeklyDate?: string | null }) => {
      updatedLastAutoWeeklyDate = input.lastAutoWeeklyDate ?? null;
    },
    createRollingWeeklyReview: async () => ({
      id: "weekly-review-1",
      status: "ready",
      publishedPostId: null,
    }),
    publishAsMoment: async (reviewId: string) => {
      publishedReviewId = reviewId;
      return {
        review: {
          id: reviewId,
          publishedPostId: `review-${reviewId}`,
        },
        postId: `review-${reviewId}`,
      };
    },
  } as never, {
    info: async (_event: string, fields: Record<string, unknown>) => {
      logFields.push(fields);
    },
    error: async () => undefined,
  } as never);

  await (scheduler as unknown as { tick(now: Date): Promise<void> }).tick(new Date(2026, 4, 24, 21, 5));

  assert.equal(updatedLastAutoWeeklyDate, "2026-05-24");
  assert.equal(publishedReviewId, "weekly-review-1");
  assert.equal(logFields[0]?.publishedPostId, "review-weekly-review-1");
});

test("scheduler does not publish generated weekly review when publish toggle is disabled", async () => {
  let publishCalls = 0;

  const scheduler = new ReviewScheduler({
    getSettings: async () => ({
      autoWeeklyEnabled: true,
      publishWeeklyToMoments: false,
      lastAutoWeeklyDate: null,
    }),
    updateSettings: async () => undefined,
    createRollingWeeklyReview: async () => ({
      id: "weekly-review-1",
      status: "ready",
      publishedPostId: null,
    }),
    publishAsMoment: async () => {
      publishCalls += 1;
      return null;
    },
  } as never, {
    info: async () => undefined,
    error: async () => undefined,
  } as never);

  await (scheduler as unknown as { tick(now: Date): Promise<void> }).tick(new Date(2026, 4, 24, 21, 5));

  assert.equal(publishCalls, 0);
});
