import test from "node:test";
import assert from "node:assert/strict";

import type { Review } from "@prisma/client";

import { ReviewService } from "./review-service.js";

function reviewFixture(overrides: Partial<Review> = {}): Review {
  const now = new Date("2026-05-06T00:00:00.000Z");
  return {
    id: "review-1",
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    status: "ready",
    trigger: "manual",
    contentJson: "{}",
    inputDigestHash: null,
    promptVersion: "weekly-review-v2",
    provider: "test",
    model: "test-model",
    language: null,
    errorCode: null,
    errorMessage: null,
    generatedAt: now,
    regeneratedFromReviewId: null,
    publishedPostId: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ...overrides,
  };
}

test("deleteReview is idempotent for already soft-deleted reviews", async () => {
  let stored = reviewFixture();
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { info: async () => undefined },
    prisma: {
      review: {
        findUnique: async () => stored,
        update: async ({ data }: { data: Partial<Review> }) => {
          stored = { ...stored, ...data } as Review;
          return stored;
        },
      },
    },
  } as never);

  const first = await service.deleteReview(stored.id);
  const second = await service.deleteReview(stored.id);

  assert.ok(first?.deletedAt);
  assert.equal(second?.id, stored.id);
  assert.ok(second?.deletedAt);
});

test("publishAsMoment marks generated review posts with the Review primary tag", async () => {
  const stored = reviewFixture({
    contentJson: JSON.stringify({
      title: "Weekly Review",
      subtitle: "2 moments · 1 comment",
      bodyMarkdown: "## Focus\nA concise weekly reflection.",
      keywords: [{ label: "Focus" }],
      notableMoments: [],
      uncertainty: [],
    }),
  });
  let postTagUpsert: unknown = null;
  let serverChangeVersion = 0;

  const tx = {
    post: {
      create: async ({ data }: { data: Record<string, unknown> }) => ({
        ...data,
        isPinned: false,
        pinnedAt: null,
      }),
      update: async () => undefined,
    },
    tag: {
      findUnique: async () => ({
        id: "tag-primary-review",
        type: "primary",
        isArchived: false,
      }),
    },
    postTag: {
      upsert: async (input: unknown) => {
        postTagUpsert = input;
        return {
          id: "post-tag-1",
          postId: `review-${stored.id}`,
          tagId: "tag-primary-review",
          role: "primary",
          source: "ai",
          confidence: 1,
          aiSummaryId: null,
          createdAt: new Date("2026-05-06T00:00:00.000Z"),
          updatedAt: new Date("2026-05-06T00:00:00.000Z"),
          deletedAt: null,
        };
      },
    },
    serverChange: {
      create: async ({ data }: { data: Record<string, unknown> }) => ({
        ...data,
        version: serverChangeVersion += 1,
      }),
    },
    review: {
      update: async ({ data }: { data: Partial<Review> }) => ({
        ...stored,
        ...data,
      }),
    },
  };

  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { info: async () => undefined },
    prisma: {
      review: {
        findFirst: async () => stored,
      },
      $transaction: async (callback: (transaction: typeof tx) => Promise<Review>) => callback(tx),
    },
  } as never);

  const result = await service.publishAsMoment(stored.id);

  assert.equal(result?.postId, `review-${stored.id}`);
  assert.equal((postTagUpsert as { create?: { tagId?: string; source?: string; role?: string } }).create?.tagId, "tag-primary-review");
  assert.equal((postTagUpsert as { create?: { tagId?: string; source?: string; role?: string } }).create?.source, "ai");
  assert.equal((postTagUpsert as { create?: { tagId?: string; source?: string; role?: string } }).create?.role, "primary");
});

test("generate returns the active generating review instead of creating another one", async () => {
  const active = reviewFixture({
    id: "active-review",
    status: "generating",
    updatedAt: new Date(),
  });
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { warn: async () => undefined },
    prisma: {
      review: {
        findMany: async () => [],
        findFirst: async () => active,
        create: async () => {
          assert.fail("generate should not create a duplicate while another review is generating");
        },
      },
    },
  } as never);

  const review = await service.generate({
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    trigger: "manual",
  });

  assert.equal(review.id, active.id);
  assert.equal(review.status, "generating");
});

test("generate marks stale generating reviews failed before allowing another active review", async () => {
  const stale = reviewFixture({
    id: "stale-review",
    status: "generating",
    updatedAt: new Date("2026-05-05T00:00:00.000Z"),
  });
  const active = reviewFixture({
    id: "active-review",
    status: "generating",
    updatedAt: new Date("2026-05-06T00:00:00.000Z"),
  });
  let staleUpdate: Partial<Review> | null = null;
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { warn: async () => undefined },
    prisma: {
      review: {
        findMany: async () => [stale],
        update: async ({ data }: { data: Partial<Review> }) => {
          staleUpdate = data;
          return { ...stale, ...data } as Review;
        },
        findFirst: async () => active,
        create: async () => {
          assert.fail("generate should not create a duplicate while another fresh review is generating");
        },
      },
    },
  } as never);

  const review = await service.generate({
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    trigger: "manual",
  });

  assert.equal(review.id, active.id);
  assert.equal(staleUpdate?.status, "failed");
  assert.equal(staleUpdate?.errorCode, "review_generation_timeout");
});

test("setFeedback rebuilds active preferences and high-priority guidance", async () => {
  const createdAt = new Date("2026-05-06T00:00:00.000Z");
  let feedbackRows: Array<{
    id: string;
    reviewId: string;
    type: string;
    note: string | null;
    metadataJson: string;
    createdAt: Date;
  }> = [];
  let memoryValue: Record<string, unknown> | null = null;
  let sequence = 0;

  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { warn: async () => undefined, info: async () => undefined },
    prisma: {
      reviewFeedback: {
        deleteMany: async ({ where }: { where: { reviewId: string; type: string } }) => {
          feedbackRows = feedbackRows.filter((row) => !(row.reviewId === where.reviewId && row.type === where.type));
          return { count: 1 };
        },
        create: async ({ data }: { data: { reviewId: string; type: string; note: string | null; metadataJson: string } }) => {
          const row = {
            id: `feedback-${sequence += 1}`,
            reviewId: data.reviewId,
            type: data.type,
            note: data.note,
            metadataJson: data.metadataJson,
            createdAt: new Date(createdAt.getTime() + sequence * 1000),
          };
          feedbackRows.unshift(row);
          return row;
        },
        findMany: async () => feedbackRows,
      },
      reviewMemory: {
        upsert: async ({ create, update }: { create: { valueJson: string }; update: { valueJson: string } }) => {
          memoryValue = JSON.parse(update.valueJson || create.valueJson) as Record<string, unknown>;
          return { id: "memory-1", scope: "periodic_review", key: "feedback_preferences", valueJson: update.valueJson || create.valueJson };
        },
      },
    },
  } as never);

  await service.setFeedback("review-1", { type: "useful", enabled: true });
  await service.setFeedback("review-1", { type: "too_dry", enabled: true });
  await service.setFeedback("review-1", { type: "custom_guidance", enabled: true, note: "Focus much more on the main weekly tension." });
  await service.setFeedback("review-1", { type: "useful", enabled: false });

  assert.deepEqual(
    feedbackRows.map((row) => row.type).sort(),
    ["custom_guidance", "too_dry"],
  );
  assert.deepEqual(memoryValue?.activeTypes, ["too_dry"]);
  assert.equal(
    (memoryValue?.highPriorityGuidance as { note?: string } | null)?.note,
    "Focus much more on the main weekly tension.",
  );
});
