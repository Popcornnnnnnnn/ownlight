import type { PrismaClient } from "@prisma/client";

export async function collectTagDiagnostics(prisma: PrismaClient): Promise<Record<string, unknown>> {
  const [total, primary, topics, archived, aiAssignments, manualAssignments] = await Promise.all([
    prisma.tag.count(),
    prisma.tag.count({ where: { type: "primary", isArchived: false } }),
    prisma.tag.count({ where: { type: "topic", isArchived: false } }),
    prisma.tag.count({ where: { isArchived: true } }),
    prisma.postTag.count({ where: { source: "ai", deletedAt: null } }),
    prisma.postTag.count({ where: { source: "manual", deletedAt: null } }),
  ]);

  return {
    total,
    primary,
    topics,
    archived,
    aiAssignments,
    manualAssignments,
  };
}

export async function collectAISummaryDiagnostics(prisma: PrismaClient): Promise<Record<string, unknown>> {
  const [total, transcribing, summarizing, ready, failed, deleted, recent] = await Promise.all([
    prisma.aiSummary.count(),
    prisma.aiSummary.count({ where: { status: "transcribing", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "summarizing", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "ready", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "failed", deletedAt: null } }),
    prisma.aiSummary.count({ where: { deletedAt: { not: null } } }),
    prisma.aiSummary.findMany({
      where: {
        deletedAt: null,
        status: {
          in: ["transcribing", "summarizing", "failed"],
        },
      },
      orderBy: {
        updatedAt: "desc",
      },
      take: 5,
      select: {
        id: true,
        mediaId: true,
        status: true,
        errorCode: true,
        inputTranscriptLength: true,
        inputDurationSeconds: true,
        updatedAt: true,
      },
    }),
  ]);

  return {
    total,
    transcribing,
    summarizing,
    ready,
    failed,
    deleted,
    recent: recent.map((summary) => ({
      id: summary.id,
      mediaId: summary.mediaId,
      status: summary.status,
      errorCode: summary.errorCode,
      inputTranscriptLength: summary.inputTranscriptLength,
      inputDurationSeconds: summary.inputDurationSeconds,
      ageSeconds: Math.max(0, Math.round((Date.now() - summary.updatedAt.getTime()) / 1_000)),
      retryHint: aiSummaryRetryHint(summary.status),
      updatedAt: summary.updatedAt.toISOString(),
    })),
  };
}

export async function collectSyncDiagnostics(prisma: PrismaClient): Promise<Record<string, unknown>> {
  const [
    serverChange,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChange,
    lastOperation,
  ] = await Promise.all([
    prisma.serverChange.aggregate({
      _max: {
        version: true,
      },
    }),
    prisma.syncOperation.count({
      where: {
        appliedAt: null,
        rejectedAt: null,
      },
    }),
    prisma.syncOperation.count({
      where: {
        rejectedAt: {
          not: null,
        },
      },
    }),
    prisma.media.count({
      where: {
        status: "failed",
        deletedAt: null,
      },
    }),
    prisma.aiSummary.count({
      where: {
        deletedAt: null,
        status: {
          in: ["transcribing", "summarizing", "failed"],
        },
      },
    }),
    prisma.serverChange.findFirst({
      orderBy: {
        createdAt: "desc",
      },
      select: {
        createdAt: true,
      },
    }),
    prisma.syncOperation.findFirst({
      orderBy: {
        receivedAt: "desc",
      },
      select: {
        receivedAt: true,
        appliedAt: true,
        rejectedAt: true,
      },
    }),
  ]);

  return {
    latestServerChangeVersion: serverChange._max.version ?? 0,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChangeAt: lastServerChange?.createdAt.toISOString() ?? null,
    lastSyncOperationAt: lastOperation?.receivedAt.toISOString() ?? null,
    lastSuccessfulSyncAt: lastOperation?.appliedAt?.toISOString() ?? null,
    lastRejectedSyncAt: lastOperation?.rejectedAt?.toISOString() ?? null,
  };
}

function aiSummaryRetryHint(status: string): string {
  if (status === "failed") {
    return "Open the summary on iPhone and tap Regenerate.";
  }

  if (status === "transcribing") {
    return "If this stays here, check local transcription and server logs.";
  }

  if (status === "summarizing") {
    return "If this stays here, check AI provider timeout and server logs.";
  }

  return "No action needed.";
}
