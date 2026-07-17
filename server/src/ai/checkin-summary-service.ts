import { randomUUID } from "node:crypto";
import { access } from "node:fs/promises";
import path from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

import type { CheckInAiSummary, Prisma, PrismaClient } from "@prisma/client";

import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import type { DataPaths } from "../storage/data-dir.js";
import {
  AISummaryProviderError,
  generateMediaSummaryFromFile,
  MEDIA_SUMMARY_PROMPT_VERSION,
  summaryText,
  type AILanguagePreference,
  type MediaSummaryOutput,
} from "./media-summary.js";
import { recordAIUsageEvent } from "./usage-ledger.js";

export interface CheckInSummaryJobContext {
  config: AppConfig;
  paths: DataPaths;
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

export interface CheckInSummaryJobInput {
  entryId: string;
  mediaId: string;
  requestedByDeviceId: string | null;
  forceRegenerate?: boolean;
  aiLanguage?: AILanguagePreference;
}

const inFlightCheckInSummaries = new Set<string>();
let checkInSummaryQueueTail: Promise<void> = Promise.resolve();
const MAX_GENERATION_ATTEMPTS = 2;
const SUMMARY_RETRY_DELAY_MS = 2_000;
const RETRYABLE_ERROR_CODES = new Set([
  "provider_timeout",
  "provider_request_failed",
  "transcription_timeout",
  "transcription_failed",
  "local_transcription_timeout",
  "audio_input_timeout",
  "audio_input_failed",
]);

export function enqueueCheckInSummaryJob(
  context: CheckInSummaryJobContext,
  input: CheckInSummaryJobInput,
): void {
  if (inFlightCheckInSummaries.has(input.mediaId)) {
    return;
  }

  inFlightCheckInSummaries.add(input.mediaId);
  const runJob = async () => {
    try {
      await generateAndSaveCheckInSummary(context, input);
    } catch (error: unknown) {
      await context.fileLogger.warn("checkin_ai.summary_job_failed", {
        entryId: input.entryId,
        mediaId: input.mediaId,
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      inFlightCheckInSummaries.delete(input.mediaId);
    }
  };

  checkInSummaryQueueTail = checkInSummaryQueueTail
    .catch(() => undefined)
    .then(runJob);
  void checkInSummaryQueueTail;
}

export async function generateAndSaveCheckInSummary(
  context: CheckInSummaryJobContext,
  input: CheckInSummaryJobInput,
): Promise<CheckInAiSummary | null> {
  if (!hasAnySummaryApiKey(context.config.aiSummary)) {
    await context.fileLogger.info("checkin_ai.summary_skipped_not_configured", {
      entryId: input.entryId,
      mediaId: input.mediaId,
    });
    return null;
  }

  const jobStartedAt = Date.now();
  const media = await context.prisma.checkInMedia.findUnique({
    where: {
      id: input.mediaId,
    },
    include: {
      entry: true,
    },
  });

  if (!media || media.deletedAt || media.entryId !== input.entryId || media.entry.deletedAt) {
    throw new AISummaryProviderError("media_not_found", "Check-in media not found");
  }

  if (media.kind !== "audio") {
    return markCheckInSummaryDeletedForMedia(context.prisma, media.id);
  }

  const existing = await context.prisma.checkInAiSummary.findUnique({
    where: {
      mediaId: media.id,
    },
  });

  if (existing && !input.forceRegenerate && existing.deletedAt === null) {
    if (existing.status === "ready" || existing.status === "transcribing" || existing.status === "summarizing") {
      return existing;
    }
  }

  if (!media.compressedPath) {
    return saveAndLogSummaryFailure(context, {
      existingId: existing?.id,
      entryId: media.entryId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: "media_file_missing",
      errorMessage: "Check-in media file is not available on the Mac server",
    });
  }

  const filePath = path.join(context.paths.dataDir, media.compressedPath);
  if (!isPathInside(context.paths.dataDir, filePath) || !(await fileExists(filePath))) {
    return saveAndLogSummaryFailure(context, {
      existingId: existing?.id,
      entryId: media.entryId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: "media_file_missing",
      errorMessage: "Check-in media file is not available on the Mac server",
    });
  }

  const transcribing = await saveSummaryStatus(context.prisma, {
    existingId: existing?.id,
    entryId: media.entryId,
    mediaId: media.id,
    deviceId: input.requestedByDeviceId,
    durationSeconds: media.durationSeconds,
    provider: context.config.aiSummary.provider,
    model: context.config.aiSummary.model,
  });

  await context.fileLogger.info("checkin_ai.summary_started", {
    summaryId: transcribing.id,
    entryId: media.entryId,
    mediaId: media.id,
    stage: "transcribing",
    provider: context.config.aiSummary.provider,
    model: context.config.aiSummary.model,
    transcriptionProvider: context.config.aiSummary.transcriptionProvider,
    transcriptionModel: context.config.aiSummary.transcriptionModel,
    elapsedMs: Date.now() - jobStartedAt,
  });

  let transcriptReadyAt: number | null = null;
  try {
    const output = await generateMediaSummaryFromFileWithRetry(context, {
      summaryId: transcribing.id,
      entryId: media.entryId,
      mediaId: media.id,
      jobStartedAt,
      getTranscriptReadyAt: () => transcriptReadyAt,
      onTranscriptReady: async () => {
        transcriptReadyAt = Date.now();
        await saveSummaryStage(context.prisma, transcribing.id, "summarizing");
        await context.fileLogger.info("checkin_ai.summary_stage", {
          summaryId: transcribing.id,
          entryId: media.entryId,
          mediaId: media.id,
          stage: "summarizing",
          elapsedMs: transcriptReadyAt - jobStartedAt,
          transcriptionMs: transcriptReadyAt - jobStartedAt,
        });
      },
      filePath,
      fileName: path.basename(filePath),
      mimeType: media.mimeType,
      durationSeconds: media.durationSeconds,
      aiLanguage: input.aiLanguage ?? "auto",
    });

    const ready = await saveSummaryReady(
      context.prisma,
      transcribing.id,
      output.summary,
      {
        transcriptHash: output.transcriptHash,
        transcriptLength: output.transcriptLength,
      },
      output.source,
    );

    const completedAt = Date.now();
    await context.fileLogger.info("checkin_ai.summary_ready", {
      summaryId: ready.id,
      entryId: ready.entryId,
      mediaId: ready.mediaId,
      provider: ready.provider,
      model: ready.model,
      inputTranscriptLength: ready.inputTranscriptLength,
      elapsedMs: completedAt - jobStartedAt,
      transcriptionMs: transcriptReadyAt ? transcriptReadyAt - jobStartedAt : null,
      summarizationMs: transcriptReadyAt ? completedAt - transcriptReadyAt : null,
    });

    return ready;
  } catch (error) {
    const providerError =
      error instanceof AISummaryProviderError
        ? error
        : new AISummaryProviderError("summary_failed", "Check-in AI summary failed");

    await context.fileLogger.warn("checkin_ai.summary_stage_failed", {
      summaryId: transcribing.id,
      entryId: media.entryId,
      mediaId: media.id,
      stage: transcriptReadyAt ? "summarizing" : "transcribing",
      elapsedMs: Date.now() - jobStartedAt,
      errorCode: providerError.code,
    });

    return saveAndLogSummaryFailure(context, {
      existingId: transcribing.id,
      entryId: media.entryId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: providerError.code,
      errorMessage: providerError.message,
    });
  }
}

interface GenerateMediaSummaryRetryInput {
  summaryId: string;
  entryId: string;
  mediaId: string;
  jobStartedAt: number;
  getTranscriptReadyAt: () => number | null;
  onTranscriptReady: () => Promise<void>;
  filePath: string;
  fileName: string;
  mimeType: string | null;
  durationSeconds: number | null;
  aiLanguage: AILanguagePreference;
}

async function generateMediaSummaryFromFileWithRetry(
  context: CheckInSummaryJobContext,
  input: GenerateMediaSummaryRetryInput,
): Promise<Awaited<ReturnType<typeof generateMediaSummaryFromFile>>> {
  for (let attempt = 1; attempt <= MAX_GENERATION_ATTEMPTS; attempt += 1) {
    try {
      await context.fileLogger.info("checkin_ai.summary_attempt_started", {
        summaryId: input.summaryId,
        entryId: input.entryId,
        mediaId: input.mediaId,
        attempt,
        maxAttempts: MAX_GENERATION_ATTEMPTS,
        stage: "transcribing",
        elapsedMs: Date.now() - input.jobStartedAt,
      });

      return await generateMediaSummaryFromFile(
        context.config.aiSummary,
        {
          filePath: input.filePath,
          fileName: input.fileName,
          mimeType: input.mimeType,
          durationSeconds: input.durationSeconds,
          aiLanguage: input.aiLanguage,
        },
        {
          onTranscriptReady: input.onTranscriptReady,
          usageContext: {
            feature: "checkin_media_summary",
            subjectType: "checkin_media",
            subjectId: input.mediaId,
            promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
            recorder: (event) => recordAIUsageEvent(context.prisma, event),
          },
        },
      );
    } catch (error) {
      const providerError =
        error instanceof AISummaryProviderError
          ? error
          : new AISummaryProviderError("summary_failed", "Check-in AI summary failed");
      const canRetry = attempt < MAX_GENERATION_ATTEMPTS && isRetryableErrorCode(providerError.code);

      if (!canRetry) {
        throw providerError;
      }

      await context.fileLogger.warn("checkin_ai.summary_retry_scheduled", {
        summaryId: input.summaryId,
        entryId: input.entryId,
        mediaId: input.mediaId,
        attempt,
        nextAttempt: attempt + 1,
        maxAttempts: MAX_GENERATION_ATTEMPTS,
        stage: input.getTranscriptReadyAt() ? "summarizing" : "transcribing",
        elapsedMs: Date.now() - input.jobStartedAt,
        errorCode: providerError.code,
      });
      await sleep(SUMMARY_RETRY_DELAY_MS);
    }
  }

  throw new AISummaryProviderError("summary_failed", "Check-in AI summary failed");
}

function isRetryableErrorCode(code: string): boolean {
  if (RETRYABLE_ERROR_CODES.has(code)) {
    return true;
  }

  return /^(provider|transcription|audio_input)_http_(429|5\d\d)$/.test(code);
}

function hasAnySummaryApiKey(config: AppConfig["aiSummary"]): boolean {
  return Boolean(config.apiKey?.trim() || config.fallback?.apiKey?.trim());
}

interface SaveSummaryStatusInput {
  existingId: string | undefined;
  entryId: string;
  mediaId: string;
  deviceId: string | null;
  durationSeconds: number | null;
  provider: string;
  model: string;
}

async function saveSummaryStatus(
  prisma: PrismaClient,
  input: SaveSummaryStatusInput,
): Promise<CheckInAiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.checkInAiSummary.upsert({
      where: {
        mediaId: input.mediaId,
      },
      create: {
        id: input.existingId ?? randomUUID(),
        entryId: input.entryId,
        mediaId: input.mediaId,
        status: "transcribing",
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider,
        model: input.model,
        inputDurationSeconds: input.durationSeconds,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
      update: {
        status: "transcribing",
        inputDurationSeconds: input.durationSeconds,
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider,
        model: input.model,
        errorCode: null,
        errorMessage: null,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
    });

    await emitCheckInAISummaryChange(tx, summary, "checkin_ai_summary_updated");
    return summary;
  });
}

async function saveSummaryStage(
  prisma: PrismaClient,
  summaryId: string,
  status: "summarizing",
): Promise<CheckInAiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.checkInAiSummary.update({
      where: {
        id: summaryId,
      },
      data: {
        status,
        errorCode: null,
        errorMessage: null,
      },
    });

    await emitCheckInAISummaryChange(tx, summary, "checkin_ai_summary_updated");
    return summary;
  });
}

async function saveSummaryReady(
  prisma: PrismaClient,
  summaryId: string,
  output: MediaSummaryOutput,
  transcriptStats: { transcriptHash: string | null; transcriptLength: number | null },
  source: { provider: string; model: string },
): Promise<CheckInAiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.checkInAiSummary.update({
      where: {
        id: summaryId,
      },
      data: {
        status: "ready",
        format: output.format,
        language: output.language,
        overview: output.overview,
        keyPointsJson: JSON.stringify(output.keyPoints),
        sectionsJson: JSON.stringify(output.sections),
        summaryText: summaryText(output),
        documentTitle: output.documentTitle,
        oneLiner: output.oneLiner,
        documentBlocksJson: JSON.stringify(output.documentBlocks),
        inputTranscriptHash: transcriptStats.transcriptHash,
        inputTranscriptLength: transcriptStats.transcriptLength,
        provider: source.provider,
        model: source.model,
        errorCode: null,
        errorMessage: null,
      },
    });

    await emitCheckInAISummaryChange(tx, summary, "checkin_ai_summary_updated");
    return summary;
  });
}

interface SaveSummaryFailureInput {
  existingId: string | undefined;
  entryId: string;
  mediaId: string;
  deviceId: string | null;
  durationSeconds: number | null;
  provider?: string;
  model?: string;
  errorCode: string;
  errorMessage: string;
}

async function saveAndLogSummaryFailure(
  context: CheckInSummaryJobContext,
  input: SaveSummaryFailureInput,
): Promise<CheckInAiSummary> {
  const summary = await saveSummaryFailure(context.prisma, input);

  await context.fileLogger.warn("checkin_ai.summary_failed", {
    summaryId: summary.id,
    entryId: summary.entryId,
    mediaId: summary.mediaId,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
  });

  return summary;
}

async function saveSummaryFailure(
  prisma: PrismaClient,
  input: SaveSummaryFailureInput,
): Promise<CheckInAiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.checkInAiSummary.upsert({
      where: {
        mediaId: input.mediaId,
      },
      create: {
        id: input.existingId ?? randomUUID(),
        entryId: input.entryId,
        mediaId: input.mediaId,
        status: "failed",
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        inputDurationSeconds: input.durationSeconds,
        provider: input.provider ?? null,
        model: input.model ?? null,
        errorCode: input.errorCode,
        errorMessage: input.errorMessage,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
      update: {
        status: "failed",
        inputDurationSeconds: input.durationSeconds,
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider ?? null,
        model: input.model ?? null,
        errorCode: input.errorCode,
        errorMessage: input.errorMessage,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
    });

    await emitCheckInAISummaryChange(tx, summary, "checkin_ai_summary_updated");
    return summary;
  });
}

export async function markCheckInSummaryDeletedForMedia(
  prisma: PrismaClient | Prisma.TransactionClient,
  mediaId: string,
  deletedAt: Date = new Date(),
): Promise<CheckInAiSummary | null> {
  const existing = await prisma.checkInAiSummary.findUnique({
    where: {
      mediaId,
    },
  });

  if (!existing || existing.deletedAt) {
    return existing;
  }

  if ("$transaction" in prisma) {
    return prisma.$transaction(async (tx) => {
      const summary = await tx.checkInAiSummary.update({
        where: {
          mediaId,
        },
        data: {
          status: "deleted",
          deletedAt,
          updatedAt: deletedAt,
        },
      });

      await emitCheckInAISummaryChange(tx, summary, "checkin_ai_summary_deleted");
      return summary;
    });
  }

  const summary = await prisma.checkInAiSummary.update({
    where: {
      mediaId,
    },
    data: {
      status: "deleted",
      deletedAt,
      updatedAt: deletedAt,
    },
  });

  await emitCheckInAISummaryChange(prisma, summary, "checkin_ai_summary_deleted");
  return summary;
}

async function emitCheckInAISummaryChange(
  tx: Prisma.TransactionClient,
  summary: CheckInAiSummary,
  changeType: "checkin_ai_summary_updated" | "checkin_ai_summary_deleted",
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "checkin_ai_summary",
      entityId: summary.id,
      changeType,
      payloadJson: JSON.stringify(serializeCheckInAISummary(summary)),
    },
  });

  await tx.checkInEntry.update({
    where: {
      id: summary.entryId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export function serializeCheckInAISummary(summary: CheckInAiSummary): Record<string, unknown> {
  return {
    id: summary.id,
    entryId: summary.entryId,
    mediaId: summary.mediaId,
    status: summary.status,
    format: summary.format,
    language: summary.language,
    overview: summary.overview,
    keyPoints: parseJsonArray(summary.keyPointsJson),
    sections: parseJsonArray(summary.sectionsJson),
    summaryText: summary.summaryText,
    documentTitle: summary.documentTitle,
    oneLiner: summary.oneLiner,
    documentBlocks: parseJsonArray(summary.documentBlocksJson),
    inputTranscriptLength: summary.inputTranscriptLength,
    inputDurationSeconds: summary.inputDurationSeconds,
    promptVersion: summary.promptVersion,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
    errorMessage: summary.errorMessage,
    createdAt: summary.createdAt.toISOString(),
    updatedAt: summary.updatedAt.toISOString(),
    deletedAt: summary.deletedAt?.toISOString() ?? null,
  };
}

function parseJsonArray(value: string): unknown[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function fileExists(absolutePath: string): Promise<boolean> {
  try {
    await access(absolutePath);
    return true;
  } catch {
    return false;
  }
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}
