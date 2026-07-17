import type { PrismaClient, Review, ReviewFeedback, ReviewSetting } from "@prisma/client";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import { normalizeReviewBodyMarkdown, synthesizeLegacyReviewBodyMarkdown } from "../ai/review-generation.js";
import { validateReviewRange } from "../reviews/review-limits.js";
import type { ReviewService } from "../reviews/review-service.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";

interface ReviewsRouteContext {
  prisma: PrismaClient;
  reviews: ReviewService;
  maintenanceMode: MaintenanceModeService;
}

const REVIEW_FEEDBACK_TYPES = [
  "useful",
  "too_much_inference",
  "too_dry",
  "missed_point",
  "hide_theme",
  "custom_guidance",
] as const;

const LEGACY_FALLBACK_NOTABLE_NOTES = new Set([
  "这条记录在本地兜底回顾中被保留下来，适合作为之后重新阅读的入口。",
  "This entry is kept as a lightweight revisit anchor in the local fallback review.",
]);

const GENERIC_FALLBACK_UNCERTAINTY = {
  zh: "这篇是 server 根据本地 moments 输入包生成的保守兜底版本；细节深度会低于正常 AI review，建议之后重新生成一次。",
  en: "This is a conservative local fallback generated from the review input pack. It is less detailed than a normal AI review, so regenerate later if needed.",
} as const;

export async function registerReviewRoutes(
  app: FastifyInstance,
  context: ReviewsRouteContext,
): Promise<void> {
  app.get("/api/v1/reviews", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const query = parseQuery(request.query);
    const reviews = await context.reviews.listReviews({
      kind: parseReviewKind(query.kind ?? null),
      limit: parseLimit(query.limit),
    });
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, reviews.map((review) => review.id));

    return reply.send({
      reviews: reviews.map((review) => serializeReview(review, feedbackStates.get(review.id))),
    });
  });

  app.get<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const review = await context.reviews.getReview(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [review.id]);

    return reply.send({
      review: serializeReview(review, feedbackStates.get(review.id)),
    });
  });

  app.delete<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const review = await context.reviews.deleteReview(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [review.id]);

    return reply.send({
      review: serializeReview(review, feedbackStates.get(review.id)),
    });
  });

  app.post("/api/v1/reviews/generate", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const body = parseGenerateBody(request.body);
    if (!body.ok) {
      sendBadRequest(reply, body.message);
      return reply;
    }

    const review = await context.reviews.startGeneration(body.input);
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [review.id]);
    return reply.send({
      review: serializeReview(review, feedbackStates.get(review.id)),
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/regenerate", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const review = await context.reviews.startRegeneration(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [review.id]);

    return reply.send({
      review: serializeReview(review, feedbackStates.get(review.id)),
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/feedback", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const body = parseFeedbackBody(request.body, reply);
    if (!body) {
      return reply;
    }

    const review = await context.reviews.getReview(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }

    await context.reviews.setFeedback(review.id, body);
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [review.id]);
    return reply.send({
      review: serializeReview(review, feedbackStates.get(review.id)),
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/publish", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const result = await context.reviews.publishAsMoment(request.params.reviewId);
    if (!result) {
      return sendNotFound(reply, "Ready review not found");
    }
    const feedbackStates = await loadReviewFeedbackStates(context.prisma, [result.review.id]);

    return reply.send({
      review: serializeReview(result.review, feedbackStates.get(result.review.id)),
      postId: result.postId,
    });
  });

  app.get("/api/v1/reviews/settings", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    return reply.send({
      settings: serializeReviewSettings(await context.reviews.getSettings()),
    });
  });

  app.put("/api/v1/reviews/settings", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const body = parseSettingsBody(request.body, reply);
    if (!body) {
      return reply;
    }

    const settings = await context.reviews.updateSettings(body);
    return reply.send({
      settings: serializeReviewSettings(settings),
    });
  });
}

async function authenticateOrReply(
  request: FastifyRequest,
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<boolean> {
  try {
    await authenticateDevice(request, prisma);
    return true;
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      sendUnauthorized(reply, error.message);
      return false;
    }

    throw error;
  }
}

function serializeReview(
  review: Review,
  feedback = emptyReviewFeedbackState(),
): Record<string, unknown> {
  return {
    id: review.id,
    kind: review.kind,
    rangeMode: review.rangeMode,
    rangeStart: review.rangeStart.toISOString(),
    rangeEnd: review.rangeEnd.toISOString(),
    status: review.status,
    trigger: review.trigger,
    content: sanitizeReviewContentForClient(parseJsonObject(review.contentJson), review.language),
    promptVersion: review.promptVersion,
    provider: review.provider,
    model: review.model,
    language: review.language,
    errorCode: review.errorCode,
    errorMessage: review.errorMessage,
    generatedAt: review.generatedAt?.toISOString() ?? null,
    regeneratedFromReviewId: review.regeneratedFromReviewId,
    publishedPostId: review.publishedPostId,
    createdAt: review.createdAt.toISOString(),
    updatedAt: review.updatedAt.toISOString(),
    deletedAt: review.deletedAt?.toISOString() ?? null,
    feedback,
  };
}

export function sanitizeReviewContentForClient(
  content: Record<string, unknown>,
  language: string | null,
): Record<string, unknown> {
  const sanitized: Record<string, unknown> = { ...content };
  const preferredLanguage = language === "en" ? "en" : "zh";

  sanitized.bodyMarkdown = typeof content.bodyMarkdown === "string"
    ? normalizeReviewBodyMarkdown(content.bodyMarkdown)
    : synthesizeLegacyReviewBodyMarkdown(content, language);

  if (Array.isArray(content.notableMoments)) {
    sanitized.notableMoments = content.notableMoments.map((item) => {
      if (!isRecord(item)) {
        return item;
      }
      const note = typeof item.note === "string" ? sanitizeLegacyNotableMomentNote(item.note) : item.note;
      return {
        ...item,
        note,
      };
    });
  }

  if (Array.isArray(content.uncertainty)) {
    sanitized.uncertainty = content.uncertainty
      .map((item) => (typeof item === "string" ? sanitizeLegacyUncertainty(item, preferredLanguage) : ""))
      .filter((item) => item.trim().length > 0);
  }

  return sanitized;
}

function sanitizeLegacyNotableMomentNote(note: string): string {
  const trimmed = note.trim();
  return LEGACY_FALLBACK_NOTABLE_NOTES.has(trimmed) ? "" : trimmed;
}

function sanitizeLegacyUncertainty(value: string, language: "zh" | "en"): string {
  const trimmed = value.trim();
  if (/^AI provider 生成失败（.+?）/.test(trimmed)) {
    return GENERIC_FALLBACK_UNCERTAINTY.zh;
  }
  if (/^The AI provider failed \(.+?\), so this is a conservative local fallback generated from the review input pack\./.test(trimmed)) {
    return GENERIC_FALLBACK_UNCERTAINTY.en;
  }
  return trimmed;
}

function serializeReviewSettings(settings: ReviewSetting): Record<string, unknown> {
  return {
    autoWeeklyEnabled: settings.autoWeeklyEnabled,
    publishWeeklyToMoments: settings.publishWeeklyToMoments,
    lastAutoWeeklyDate: settings.lastAutoWeeklyDate,
    updatedAt: settings.updatedAt.toISOString(),
  };
}

export function parseGenerateBody(body: unknown, now = new Date()): {
  ok: true;
  input: Parameters<ReviewService["generate"]>[0];
} | {
  ok: false;
  message: string;
} {
  if (!isRecord(body)) {
    return {
      ok: true,
      input: {
        kind: "weekly",
        rangeMode: "rolling_7_days",
        rangeStart: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
        rangeEnd: now,
        trigger: "manual",
      },
    };
  }

  const kind = parseReviewKind(getString(body, "kind")) ?? "weekly";
  const rangeMode = parseReviewRangeMode(getString(body, "rangeMode")) ?? "rolling_7_days";
  const rangeEnd = parseDate(getString(body, "rangeEnd")) ?? now;
  const rangeStart = parseDate(getString(body, "rangeStart")) ?? new Date(rangeEnd.getTime() - 7 * 24 * 60 * 60 * 1000);
  const validationError = validateReviewRange(rangeStart, rangeEnd);

  if (validationError) {
    return {
      ok: false,
      message: validationError,
    };
  }

  return {
    ok: true,
    input: {
      kind,
      rangeMode,
      rangeStart,
      rangeEnd,
      trigger: "manual",
    },
  };
}

function parseFeedbackBody(
  body: unknown,
  reply: FastifyReply,
): { type: string; enabled: boolean; note: string | null } | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  const type = getString(body, "type");
  if (!type || !REVIEW_FEEDBACK_TYPES.includes(type as typeof REVIEW_FEEDBACK_TYPES[number])) {
    sendBadRequest(reply, "Unsupported feedback type");
    return null;
  }

  const note = getString(body, "note");
  const enabled = typeof body.enabled === "boolean" ? body.enabled : true;
  if (type === "custom_guidance" && enabled && !note) {
    sendBadRequest(reply, "custom_guidance requires a note");
    return null;
  }

  return {
    type,
    enabled,
    note,
  };
}

function parseSettingsBody(
  body: unknown,
  reply: FastifyReply,
): { autoWeeklyEnabled?: boolean; publishWeeklyToMoments?: boolean } | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  return {
    ...(typeof body.autoWeeklyEnabled === "boolean" ? { autoWeeklyEnabled: body.autoWeeklyEnabled } : {}),
    ...(typeof body.publishWeeklyToMoments === "boolean" ? { publishWeeklyToMoments: body.publishWeeklyToMoments } : {}),
  };
}

function parseReviewKind(value: string | null): "weekly" | "monthly" | "custom" | undefined {
  if (value === "weekly" || value === "monthly" || value === "custom") {
    return value;
  }

  return undefined;
}

function parseReviewRangeMode(value: string | null): "rolling_7_days" | "calendar_week" | "calendar_month" | "custom" | undefined {
  if (value === "rolling_7_days" || value === "calendar_week" || value === "calendar_month" || value === "custom") {
    return value;
  }

  return undefined;
}

type ReviewFeedbackState = {
  selectedTypes: string[];
  customNote: string | null;
  customNoteUpdatedAt: string | null;
};

async function loadReviewFeedbackStates(
  prisma: PrismaClient,
  reviewIds: string[],
): Promise<Map<string, ReviewFeedbackState>> {
  const ids = [...new Set(reviewIds.filter((value) => value.length > 0))];
  const states = new Map<string, ReviewFeedbackState>();
  if (ids.length === 0) {
    return states;
  }

  const rows = await prisma.reviewFeedback.findMany({
    where: {
      reviewId: {
        in: ids,
      },
    },
    orderBy: {
      createdAt: "desc",
    },
  });

  for (const reviewId of ids) {
    states.set(reviewId, summarizeReviewFeedback(rows.filter((row) => row.reviewId === reviewId)));
  }

  return states;
}

function summarizeReviewFeedback(rows: ReviewFeedback[]): ReviewFeedbackState {
  const selectedTypes: string[] = [];
  let customNote: string | null = null;
  let customNoteUpdatedAt: string | null = null;

  for (const row of rows) {
    if (row.type === "custom_guidance") {
      if (!customNote && row.note?.trim()) {
        customNote = row.note.trim();
        customNoteUpdatedAt = row.createdAt.toISOString();
      }
      continue;
    }

    if (!selectedTypes.includes(row.type)) {
      selectedTypes.push(row.type);
    }
  }

  return {
    selectedTypes,
    customNote,
    customNoteUpdatedAt,
  };
}

function emptyReviewFeedbackState(): ReviewFeedbackState {
  return {
    selectedTypes: [],
    customNote: null,
    customNoteUpdatedAt: null,
  };
}

function parseLimit(value: string | undefined): number | undefined {
  if (!value) {
    return undefined;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : undefined;
}

function parseDate(value: string | null): Date | null {
  if (!value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function parseQuery(query: unknown): Record<string, string | undefined> {
  if (!isRecord(query)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(query)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }
  return parsed;
}

function parseJsonObject(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    return isRecord(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function getString(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value.trim() : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
