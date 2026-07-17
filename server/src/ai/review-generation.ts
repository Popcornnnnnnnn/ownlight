import { createHash } from "node:crypto";

import type { AISummaryConfig } from "../config/app-config.js";
import { AISummaryProviderError, type AISourceMetadata } from "./media-summary.js";
import {
  executeWithConfiguredAIProvider,
  type AIResolvedProvider,
} from "./provider-router.js";
import { recordCompletionUsage, type AIUsageContext } from "./usage.js";

export const REVIEW_PROMPT_VERSION = "weekly-review-v3";
const REVIEW_PROVIDER_MAX_ATTEMPTS = 3;
const REVIEW_PROVIDER_RETRY_DELAYS_MS = [400, 1200];

export type ReviewKind = "weekly" | "monthly" | "custom";
export type ReviewRangeMode = "rolling_7_days" | "calendar_week" | "calendar_month" | "custom";
export type ReviewTrigger = "manual" | "scheduled" | "regenerate";

export interface ReviewInputPack {
  kind: ReviewKind;
  rangeMode: ReviewRangeMode;
  rangeStart: string;
  rangeEnd: string;
  generatedAt: string;
  totals: {
    moments: number;
    textMoments: number;
    imageMoments: number;
    audioMoments: number;
    videoMoments: number;
    comments: number;
    favorites: number;
  };
  rhythm: {
    byDay: Array<{ date: string; count: number }>;
    byHourBucket: Array<{ bucket: string; count: number }>;
  };
  moments: ReviewInputMoment[];
  feedbackPreferences?: {
    activeTypes: string[];
  };
  highPriorityGuidance?: string;
  reviewMemory: ReviewMemoryHint[];
}

export interface ReviewInputMoment {
  id: string;
  occurredAt: string;
  text: string;
  mediaKinds: string[];
  comments: string[];
  tags: string[];
  favorite: boolean;
  aiSummaries: ReviewInputAISummary[];
}

export interface ReviewInputAISummary {
  mediaId: string;
  kind: string;
  documentTitle: string | null;
  oneLiner: string | null;
  summaryText: string | null;
  documentBlocks: unknown[];
}

export interface ReviewMemoryHint {
  key: string;
  value: unknown;
}

export interface ReviewOutput {
  title: string;
  subtitle: string;
  bodyMarkdown: string;
  keywords: Array<{ label: string; note: string }>;
  notableMoments: Array<{
    title: string;
    note: string;
    momentIds: string[];
  }>;
  uncertainty: string[];
}

export interface ReviewGenerationResult {
  output: ReviewOutput;
  source: AISourceMetadata;
}

export function reviewInputDigest(input: ReviewInputPack): string {
  return createHash("sha256").update(JSON.stringify(input), "utf8").digest("hex");
}

export async function generateReview(
  config: AISummaryConfig,
  input: ReviewInputPack,
  usageContext?: AIUsageContext,
): Promise<ReviewOutput> {
  return (await generateReviewWithSource(config, input, usageContext)).output;
}

export async function generateReviewWithSource(
  config: AISummaryConfig,
  input: ReviewInputPack,
  usageContext?: AIUsageContext,
): Promise<ReviewGenerationResult> {
  if (!hasAnyReviewApiKey(config)) {
    throw new AISummaryProviderError("not_configured", "AI review provider is not configured");
  }

  let lastError: unknown;
  let recoveredCandidate: ReviewGenerationResult | null = null;
  for (let attempt = 1; attempt <= REVIEW_PROVIDER_MAX_ATTEMPTS; attempt += 1) {
    try {
      const response = await callReviewCompletions(config, input, usageContext);
      try {
        return {
          output: validateReviewOutput(response.value, input),
          source: sourceMetadata(response.source),
        };
      } catch (error) {
        const recovered = recoverSparseReviewOutput(response.value, input, error);
        if (recovered) {
          recoveredCandidate = chooseBetterRecoveredReviewResult(recoveredCandidate, {
            output: recovered,
            source: sourceMetadata(response.source),
          });
        }
        throw error;
      }
    } catch (error) {
      lastError = error;
      if (attempt >= REVIEW_PROVIDER_MAX_ATTEMPTS || !isRetryableReviewProviderError(error)) {
        break;
      }

      await delay(REVIEW_PROVIDER_RETRY_DELAYS_MS[attempt - 1] ?? 1200);
    }
  }

  if (recoveredCandidate) {
    return recoveredCandidate;
  }

  if (shouldUseLocalFallback(lastError)) {
    return {
      output: createLocalFallbackReview(input, lastError),
      source: {
        provider: "local",
        model: "review-fallback",
      },
    };
  }

  throw lastError;
}

async function callReviewCompletions(
  config: AISummaryConfig,
  input: ReviewInputPack,
  usageContext?: AIUsageContext,
): Promise<{ value: unknown; source: AIResolvedProvider }> {
  const systemContent = reviewSystemPrompt();
  const userContent = JSON.stringify(input);
  const inputChars = systemContent.length + userContent.length + JSON.stringify(reviewJsonSchema()).length;

  return executeWithConfiguredAIProvider(config, { inputChars, preferPro: true }, async (provider) => {
    if (!provider.apiKey) {
      throw new AISummaryProviderError("not_configured", "AI review provider is not configured");
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
    const startedAt = Date.now();

    try {
      const response = await fetch(`${provider.baseUrl}/chat/completions`, {
        method: "POST",
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${provider.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: provider.model,
          temperature: 0.6,
          store: false,
          messages: [
            {
              role: "system",
              content: systemContent,
            },
            {
              role: "user",
              content: userContent,
            },
          ],
          response_format: responseFormatForProvider(provider, "periodic_review", reviewJsonSchema()),
        }),
      });

      if (!response.ok) {
        await recordCompletionUsage(usageContext, {
          provider: provider.provider,
          model: provider.model,
          status: "failed",
          inputChars,
          durationMs: Date.now() - startedAt,
          errorCode: `provider_http_${response.status}`,
        });
        throw new AISummaryProviderError(
          `provider_http_${response.status}`,
          `AI provider returned HTTP ${response.status}`,
        );
      }

      const parsed = (await response.json()) as unknown;
      const content = extractMessageContent(parsed);
      if (!content) {
        await recordCompletionUsage(usageContext, {
          provider: provider.provider,
          model: provider.model,
          status: "failed",
          inputChars,
          response: parsed,
          durationMs: Date.now() - startedAt,
          errorCode: "empty_response",
        });
        throw new AISummaryProviderError("empty_response", "AI provider returned no review");
      }

      try {
        const parsedContent = parseJsonContent(content);
        await recordCompletionUsage(usageContext, {
          provider: provider.provider,
          model: provider.model,
          status: "success",
          inputChars,
          outputChars: content.length,
          response: parsed,
          durationMs: Date.now() - startedAt,
        });
        return parsedContent;
      } catch {
        await recordCompletionUsage(usageContext, {
          provider: provider.provider,
          model: provider.model,
          status: "failed",
          inputChars,
          outputChars: content.length,
          response: parsed,
          durationMs: Date.now() - startedAt,
          errorCode: "invalid_json",
        });
        throw new AISummaryProviderError("invalid_json", "AI provider returned invalid JSON");
      }
    } catch (error) {
      if (error instanceof AISummaryProviderError) {
        throw error;
      }

      if (error instanceof Error && error.name === "AbortError") {
        await recordCompletionUsage(usageContext, {
          provider: provider.provider,
          model: provider.model,
          status: "failed",
          inputChars,
          durationMs: Date.now() - startedAt,
          errorCode: "provider_timeout",
        });
        throw new AISummaryProviderError("provider_timeout", "AI provider request timed out");
      }

      await recordCompletionUsage(usageContext, {
        provider: provider.provider,
        model: provider.model,
        status: "failed",
        inputChars,
        durationMs: Date.now() - startedAt,
        errorCode: "provider_request_failed",
      });
      throw new AISummaryProviderError("provider_request_failed", "AI provider request failed");
    } finally {
      clearTimeout(timeout);
    }
  });
}

function responseFormatForProvider(
  provider: AIResolvedProvider,
  name: string,
  schema: Record<string, unknown>,
): Record<string, unknown> {
  if (provider.responseFormat === "json_object") {
    return {
      type: "json_object",
    };
  }

  return {
    type: "json_schema",
    json_schema: {
      name,
      strict: true,
      schema,
    },
  };
}

function sourceMetadata(provider: AIResolvedProvider): AISourceMetadata {
  return {
    provider: provider.provider,
    model: provider.model,
  };
}

function hasAnyReviewApiKey(config: AISummaryConfig): boolean {
  return Boolean(config.apiKey?.trim() || config.fallback?.apiKey?.trim());
}

function reviewSystemPrompt(): string {
  return [
    "You write Private Moments periodic reviews.",
    "The product is a no-audience private personal timeline. Treat the input as an aggregate life stream, not evidence for judging individual entries.",
    "The review should be retrospective first, with calm observation and moderate encouragement. It may comfort or affirm the user when the week shows effort or difficulty.",
    "Do not diagnose mental health, do not moralize, do not convert life into KPI/todos, and do not cite moment IDs except inside notableMoments.",
    "Use the same dominant language as the input unless the range is mixed; Chinese is acceptable when the input is Chinese-heavy.",
    "Write a living title, not a generic range label. Avoid defaulting to titles like '最近 7 天回顾' or 'Last 7 Days Review' unless the input is nearly empty.",
    "The subtitle is computed by the server. Do not repeat raw date ranges or count-only labels as the title.",
    "Put the main synthesis into bodyMarkdown. It may cover the weekly thread, recurring themes, emotional texture, rhythm, progress, open loops, and any quiet suggestion if helpful, but it does not need to force those into explicit template sections every time.",
    "In bodyMarkdown, you may use short paragraphs, optional H2 headings, and simple '-' bullet lines. Do not use code fences, tables, blockquotes, or headings deeper than H2.",
    "Avoid generic template language. Use concrete signals from the provided text, tags, media kinds, comments, favorites, and rhythm counts without inventing facts.",
    "If the input includes feedbackPreferences or reviewMemory.feedback_preferences, treat it as soft steering from prior reviews and adapt silently without mentioning the memory.",
    "If the input includes highPriorityGuidance, treat it as the highest-priority adjustment request for this next review unless it would force you to invent facts.",
    "When past feedback says too_much_inference, stay closer to explicit evidence and reduce interpretive leaps.",
    "When past feedback says too_dry, keep the review grounded but add more synthesis, texture, and connective tissue across the week.",
    "When past feedback says missed_point, prioritize the central weekly tension or theme instead of only listing fragments.",
    "When past feedback says hide_theme, avoid centering that theme again unless the current week strongly requires it.",
    "When past feedback says useful, preserve the aspects that made the review feel grounded and helpful.",
    "Do not claim completion, productivity, mood, health, or intent unless the input directly supports it.",
    "For non-empty input, write substantive content in bodyMarkdown. Empty arrays or a very short body are only acceptable when the input range is truly empty.",
    "If notableMoments are included, put moment IDs only there. bodyMarkdown should summarize the whole range without binding claims to individual evidence.",
    "Return only one valid JSON object. Do not wrap it in Markdown, code fences, or explanatory text.",
  ].join("\n");
}

function reviewJsonSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "title",
      "bodyMarkdown",
      "keywords",
      "notableMoments",
      "uncertainty",
    ],
    properties: {
      title: { type: "string", minLength: 1 },
      bodyMarkdown: { type: "string", minLength: 1 },
      keywords: {
        type: "array",
        minItems: 1,
        maxItems: 5,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["label", "note"],
          properties: {
            label: { type: "string" },
            note: { type: "string" },
          },
        },
      },
      notableMoments: {
        type: "array",
        maxItems: 8,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["title", "note", "momentIds"],
          properties: {
            title: { type: "string" },
            note: { type: "string" },
            momentIds: { type: "array", maxItems: 4, items: { type: "string" } },
          },
        },
      },
      uncertainty: { type: "array", maxItems: 5, items: { type: "string" } },
    },
  };
}

export function validateReviewOutput(value: unknown, input?: ReviewInputPack): ReviewOutput {
  if (!isRecord(value)) {
    throw new AISummaryProviderError("invalid_response", "AI review response was invalid");
  }

  const validMomentIds = new Set(input?.moments.map((moment) => moment.id) ?? []);
  const output = {
    title: getString(value.title, "Untitled review").slice(0, 80),
    subtitle: input ? reviewSubtitleFromTotals(input.totals) : getString(value.subtitle, ""),
    bodyMarkdown: normalizeReviewBodyMarkdown(getString(value.bodyMarkdown, "")),
    keywords: getObjectArray(value.keywords)
      .map((item) => ({
        label: getString(item.label, "").slice(0, 40),
        note: getString(item.note, ""),
      }))
      .filter((item) => item.label && item.note)
      .slice(0, 5),
    notableMoments: getObjectArray(value.notableMoments)
      .map((item) => ({
        title: getString(item.title, "").slice(0, 80),
        note: getString(item.note, ""),
        momentIds: getStringArray(item.momentIds)
          .filter((momentId) => validMomentIds.size === 0 || validMomentIds.has(momentId))
          .slice(0, 4),
      }))
      .filter((item) => item.title && (validMomentIds.size === 0 || item.momentIds.length > 0))
      .slice(0, 8),
    uncertainty: getStringArray(value.uncertainty).slice(0, 5),
  };

  if (input) {
    assertSubstantiveReviewOutput(output, input);
  }

  return output;
}

function assertSubstantiveReviewOutput(output: ReviewOutput, input: ReviewInputPack): void {
  if (input.totals.moments === 0) {
    return;
  }

  if (reviewOutputQualityScore(output) < 3) {
    throw new AISummaryProviderError(
      "empty_review_content",
      "AI provider returned a review with too little usable content",
    );
  }
}

export function createLocalFallbackReview(input: ReviewInputPack, cause: unknown): ReviewOutput {
  const language = dominantInputLanguage(input);
  const zh = language === "zh";
  const totals = input.totals;
  const topTags = topValues(input.moments.flatMap((moment) => moment.tags), 5);
  const mediaKeywords = mediaKeywordLabels(input, zh);
  const notableMoments = fallbackNotableMoments(input, zh);
  const rhythmDescription = fallbackRhythm(input, zh);
  const progressItems = fallbackProgressItems(input, zh);
  const openLoopItems = fallbackOpenLoopItems(input, zh);
  const keywordLabels = [...topTags, ...mediaKeywords, zh ? "记录节奏" : "Capture rhythm"];

  if (totals.moments === 0) {
    return {
      title: zh ? "这一周先留白" : "A Quiet Weekly Review",
      subtitle: reviewSubtitleFromTotals(totals),
      bodyMarkdown: normalizeReviewBodyMarkdown(
        zh
          ? "这个时间段里还没有可用于总结的 moments。\n\n如果这段时间确实发生了值得保留的事，可以补一两条 moment。"
          : "There were no moments in this range to summarize.\n\nAdd one or two moments if anything from this period still feels worth keeping.",
      ),
      keywords: [],
      notableMoments: [],
      uncertainty: [fallbackUncertainty(cause, zh)],
    };
  }

  return {
    title: fallbackTitle(input, zh),
    subtitle: reviewSubtitleFromTotals(totals),
    bodyMarkdown: fallbackBodyMarkdown(input, zh, topTags, progressItems, openLoopItems, rhythmDescription),
    keywords: keywordLabels.slice(0, 5).map((label) => ({
      label,
      note: fallbackKeywordNote(totals, zh),
    })),
    notableMoments,
    uncertainty: [fallbackUncertainty(cause, zh)],
  };
}

function fallbackTitle(input: ReviewInputPack, zh: boolean): string {
  const topTags = topValues(input.moments.flatMap((moment) => moment.tags), 2);
  const openLoopLead = fallbackOpenLoopItems(input, zh)[0];
  if (zh) {
    if (topTags.length >= 2) {
      return `这一周一直在 ${topTags[0]} 和 ${topTags[1]} 之间来回`;
    }
    if (topTags.length === 1) {
      return `这一周慢慢靠近 ${topTags[0]}`;
    }
    if (openLoopLead) {
      return "这一周留下的问题线索没有散掉";
    }
    return "这一周先把线索收了回来";
  }

  if (topTags.length >= 2) {
    return `The Week Kept Swinging Between ${topTags[0]} And ${topTags[1]}`;
  }
  if (topTags.length === 1) {
    return `The Week Slowly Circled Around ${topTags[0]}`;
  }
  if (openLoopLead) {
    return "The Week Left A Few Threads Open";
  }
  return "The Week Held Onto A Few Useful Threads";
}

function fallbackNotableMoments(input: ReviewInputPack, zh: boolean): ReviewOutput["notableMoments"] {
  const candidates = [...input.moments]
    .filter((moment) => moment.favorite || moment.text.trim() || moment.aiSummaries.length > 0)
    .sort((left, right) => {
      if (left.favorite !== right.favorite) {
        return left.favorite ? -1 : 1;
      }
      return right.occurredAt.localeCompare(left.occurredAt);
    })
    .slice(0, 4);

  return candidates.map((moment) => {
    const title = firstMeaningfulLine(moment) || (zh ? "值得回看的 moment" : "Moment Worth Revisiting");
    return {
      title: clampText(title, 80),
      note: "",
      momentIds: [moment.id],
    };
  });
}

function fallbackBodyMarkdown(
  input: ReviewInputPack,
  zh: boolean,
  topTags: string[],
  progressItems: string[],
  openLoopItems: string[],
  rhythm: { body: string; observations: string[] },
): string {
  const totals = input.totals;
  const intro = zh
    ? `这周留下来的记录不算少。${totals.moments} 条 moments 和 ${totals.comments} 条 comments 并不一定说明一切都清楚了，但至少说明很多线索没有直接散掉。`
    : `This week left behind a real volume of material. ${totals.moments} moments and ${totals.comments} comments do not make everything clear, but they do keep the important threads from disappearing.`;
  const tagParagraph = topTags.length > 0
    ? zh
      ? `反复出现的线索主要围绕 ${topTags.join("、")}。这更像是这一周不断回到的问题域，而不是几个彼此无关的碎片。`
      : `The recurring signals cluster mostly around ${topTags.join(", ")}. That reads more like one returning field of attention than a pile of unrelated fragments.`
    : zh
      ? `这周的主题没有特别整齐地收束成一个标签，但记录之间仍然能看出持续回返的关注点。`
      : "The week does not collapse neatly into one label, but the entries still suggest a recurring center of attention.";
  const progressHeading = zh ? "## 已经推进的部分" : "## What Moved";
  const openLoopsHeading = zh ? "## 还没有关上的地方" : "## What Stayed Open";
  const rhythmHeading = zh ? "## 节奏" : "## Rhythm";
  const progressLines = progressItems.map((item) => `- ${item}`);
  const openLoopLines = openLoopItems.map((item) => `- ${item}`);
  const rhythmLines = [
    rhythm.body,
    ...rhythm.observations.map((item) => `- ${item}`),
  ].filter(Boolean);

  return normalizeReviewBodyMarkdown([
    intro,
    "",
    tagParagraph,
    "",
    progressHeading,
    ...progressLines,
    "",
    openLoopsHeading,
    ...openLoopLines,
    "",
    rhythmHeading,
    ...rhythmLines,
    "",
    zh
      ? "不需要把这一周的每条信号都立刻变成任务，先保留最想继续追的一两个问题就够了。"
      : "It is enough to keep one or two threads alive; this review does not need to turn every signal into a task.",
  ].join("\n"));
}

function fallbackProgressItems(input: ReviewInputPack, zh: boolean): string[] {
  const matches = input.moments
    .map(firstMeaningfulLine)
    .filter((line) => /完成|实现|修复|验证|测试|发布|上线|build|fixed|done|implemented|verified|test/i.test(line))
    .slice(-4)
    .map((line) => clampText(line, 120));

  if (matches.length > 0) {
    return matches;
  }

  return [
    zh
      ? `持续记录了 ${input.totals.moments} 条 moments，让这一周的上下文没有完全散掉。`
      : `Captured ${input.totals.moments} moments, keeping the week from disappearing into fragments.`,
  ];
}

function fallbackOpenLoopItems(input: ReviewInputPack, zh: boolean): string[] {
  const matches = input.moments
    .map(firstMeaningfulLine)
    .filter((line) => /问题|报错|需要|待|下一步|为什么|怎么|bug|error|todo|pending|next|fix/i.test(line))
    .slice(-5)
    .map((line) => clampText(line, 120));

  if (matches.length > 0) {
    return matches;
  }

  return [
    zh
      ? "本地兜底无法可靠判断真正的开放循环，建议等 provider 恢复后重新生成一次。"
      : "The local fallback cannot reliably identify every open loop; regenerate once the provider is stable.",
  ];
}

function fallbackRhythm(
  input: ReviewInputPack,
  zh: boolean,
): { body: string; observations: string[] } {
  const activeDays = input.rhythm.byDay.filter((day) => day.count > 0);
  const busiestDay = [...activeDays].sort((left, right) => right.count - left.count)[0];
  const busiestBucket = [...input.rhythm.byHourBucket].sort((left, right) => right.count - left.count)[0];
  const bucketLabel = busiestBucket ? localizedBucket(busiestBucket.bucket, zh) : null;

  return {
    body: zh
      ? `这段时间有 ${activeDays.length} 天留下记录${busiestDay ? `，其中 ${busiestDay.date} 最密集` : ""}${bucketLabel ? `，较多出现在${bucketLabel}` : ""}。`
      : `This range has captures on ${activeDays.length} days${busiestDay ? `, with ${busiestDay.date} being the densest` : ""}${bucketLabel ? ` and more activity around ${bucketLabel}` : ""}.`,
    observations: [
      zh
        ? "记录节奏本身比单条内容更适合作为这一版兜底回顾的主要依据。"
        : "Capture rhythm is a safer signal for this fallback than over-reading any single moment.",
    ],
  };
}

function mediaKeywordLabels(input: ReviewInputPack, zh: boolean): string[] {
  const labels: string[] = [];
  if (input.totals.audioMoments > 0) {
    labels.push(zh ? "音频记录" : "Audio");
  }
  if (input.totals.imageMoments > 0) {
    labels.push(zh ? "图片记录" : "Images");
  }
  if (input.totals.videoMoments > 0) {
    labels.push(zh ? "视频记录" : "Video");
  }
  return labels;
}

function fallbackKeywordNote(totals: ReviewInputPack["totals"], zh: boolean): string {
  return zh
    ? `来自 ${totals.moments} 条 moments 的本地聚合线索。`
    : `A local aggregate signal from ${totals.moments} moments.`;
}

function fallbackUncertainty(cause: unknown, zh: boolean): string {
  return zh
    ? "这篇是 server 根据本地 moments 输入包生成的保守兜底版本；细节深度会低于正常 AI review，建议之后重新生成一次。"
    : "This is a conservative local fallback generated from the review input pack. It is less detailed than a normal AI review, so regenerate later if needed.";
}

function partialRecoveryUncertainty(zh: boolean): string {
  return zh
    ? "AI provider 返回了可解析但内容过稀的 Weekly Review；缺失部分已用本地聚合信号补齐。"
    : "The AI provider returned a parseable but sparse weekly review, so missing sections were completed with local aggregate signals.";
}

export function reviewSubtitleFromTotals(totals: ReviewInputPack["totals"]): string {
  return `${totals.moments} moments · ${totals.comments} comments`;
}

export function normalizeReviewBodyMarkdown(value: string): string {
  return value
    .split(/\r?\n/)
    .map((line) => {
      let normalized = line.trimEnd();
      if (/^\s*```/.test(normalized)) {
        return "";
      }
      normalized = normalized.replace(/^\s{0,3}#{3,}\s*/, "## ");
      normalized = normalized.replace(/^\s*>\s?/, "");
      return normalized;
    })
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function synthesizeLegacyReviewBodyMarkdown(
  content: Record<string, unknown>,
  language: string | null,
): string {
  const zh = language !== "en";
  const lines: string[] = [];
  const oneLiner = getString(content.oneLiner, "").trim();
  if (oneLiner) {
    lines.push(oneLiner, "");
  }

  const themes = getObjectArray(content.themes)
    .map((item) => ({
      title: getString(item.title, "").trim(),
      body: getString(item.body, "").trim(),
    }))
    .filter((item) => item.title && item.body);
  if (themes.length > 0) {
    lines.push(zh ? "## 反复出现的线索" : "## Themes");
    for (const theme of themes) {
      lines.push(`${theme.title}\n${theme.body}`, "");
    }
  }

  const reflection = isRecord(content.emotionalReflection) ? getString(content.emotionalReflection.body, "").trim() : "";
  if (reflection) {
    lines.push(zh ? "## 当下的反应" : "## State Response", reflection, "");
  }

  const progress = isRecord(content.progressAndOpenLoops) ? getStringArray(content.progressAndOpenLoops.progress) : [];
  if (progress.length > 0) {
    lines.push(zh ? "## 已经推进的部分" : "## Progress");
    for (const item of progress) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  const openLoops = isRecord(content.progressAndOpenLoops) ? getStringArray(content.progressAndOpenLoops.openLoops) : [];
  if (openLoops.length > 0) {
    lines.push(zh ? "## 还没有关上的地方" : "## Open Loops");
    for (const item of openLoops) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  const rhythm = isRecord(content.rhythm) ? {
    body: getString(content.rhythm.body, "").trim(),
    observations: getStringArray(content.rhythm.observations),
  } : { body: "", observations: [] };
  if (rhythm.body || rhythm.observations.length > 0) {
    lines.push(zh ? "## 节奏" : "## Rhythm");
    if (rhythm.body) {
      lines.push(rhythm.body);
    }
    for (const item of rhythm.observations) {
      lines.push(`- ${item}`);
    }
    lines.push("");
  }

  const gentleSuggestions = getStringArray(content.gentleSuggestions);
  if (gentleSuggestions.length > 0) {
    lines.push(zh ? "## 轻一点的建议" : "## Quiet Suggestions");
    for (const item of gentleSuggestions) {
      lines.push(`- ${item}`);
    }
  }

  return normalizeReviewBodyMarkdown(lines.join("\n"));
}

function firstMeaningfulLine(moment: ReviewInputMoment): string {
  const textLine = moment.text
    .split("\n")
    .map((line) => line.replace(/^#{1,6}\s*/, "").trim())
    .find(Boolean);
  if (textLine) {
    return textLine;
  }

  for (const summary of moment.aiSummaries) {
    const line = summary.documentTitle || summary.oneLiner || summary.summaryText;
    if (line?.trim()) {
      return line.trim();
    }
  }

  return "";
}

function clampText(value: string, maxLength: number): string {
  const trimmed = value.trim();
  return trimmed.length > maxLength ? `${trimmed.slice(0, maxLength)}...` : trimmed;
}

function topValues(values: string[], limit: number): string[] {
  const counts = new Map<string, number>();
  for (const value of values) {
    const normalized = value.trim();
    if (normalized) {
      counts.set(normalized, (counts.get(normalized) ?? 0) + 1);
    }
  }

  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .slice(0, limit)
    .map(([value]) => value);
}

function dominantInputLanguage(input: ReviewInputPack): "zh" | "en" {
  const text = input.moments
    .flatMap((moment) => [
      moment.text,
      ...moment.comments,
      ...moment.aiSummaries.flatMap((summary) => [
        summary.documentTitle ?? "",
        summary.oneLiner ?? "",
        summary.summaryText ?? "",
      ]),
    ])
    .join("\n");
  const cjk = [...text].filter((character) => /[\u3400-\u9fff]/u.test(character)).length;
  const latin = [...text].filter((character) => /[a-z]/iu.test(character)).length;
  return cjk >= 8 || cjk >= latin ? "zh" : "en";
}

function localizedBucket(bucket: string, zh: boolean): string {
  const labels: Record<string, { zh: string; en: string }> = {
    morning: { zh: "上午", en: "morning" },
    afternoon: { zh: "下午", en: "afternoon" },
    evening: { zh: "晚上", en: "evening" },
    late_night: { zh: "深夜", en: "late night" },
  };
  const label = labels[bucket];
  return label ? (zh ? label.zh : label.en) : bucket;
}

function isRetryableReviewProviderError(error: unknown): boolean {
  if (!(error instanceof AISummaryProviderError)) {
    return false;
  }

  if (["provider_timeout", "provider_request_failed", "invalid_json", "empty_response", "empty_review_content"].includes(error.code)) {
    return true;
  }

  const match = error.code.match(/^provider_http_(\d+)$/);
  if (!match) {
    return false;
  }

  const status = Number(match[1]);
  return status === 429 || status >= 500;
}

function shouldUseLocalFallback(error: unknown): boolean {
  return isRetryableReviewProviderError(error);
}

function recoverSparseReviewOutput(
  value: unknown,
  input: ReviewInputPack,
  cause: unknown,
): ReviewOutput | null {
  if (!(cause instanceof AISummaryProviderError) || cause.code !== "empty_review_content") {
    return null;
  }

  let partial: ReviewOutput;
  try {
    partial = validateReviewOutput(value);
  } catch {
    return null;
  }

  const fallback = createLocalFallbackReview(input, cause);
  const recovered = {
    title: partial.title && partial.title !== "Untitled review" ? partial.title : fallback.title,
    subtitle: fallback.subtitle,
    bodyMarkdown: mergeMarkdownBodies(partial.bodyMarkdown, fallback.bodyMarkdown),
    keywords: mergeKeywordEntries(partial.keywords, fallback.keywords, 5),
    notableMoments: mergeNotableMoments(partial.notableMoments, fallback.notableMoments, 8),
    uncertainty: mergeUniqueStrings(
      partial.uncertainty,
      [partialRecoveryUncertainty(dominantInputLanguage(input) === "zh")],
      5,
    ),
  } satisfies ReviewOutput;

  return validateReviewOutput(recovered, input);
}

function chooseBetterRecoveredReviewResult(
  current: ReviewGenerationResult | null,
  candidate: ReviewGenerationResult,
): ReviewGenerationResult {
  if (!current) {
    return candidate;
  }

  return reviewOutputQualityScore(candidate.output) >= reviewOutputQualityScore(current.output) ? candidate : current;
}

function reviewOutputQualityScore(output: ReviewOutput): number {
  let score = 0;

  if (output.bodyMarkdown.length >= 260) {
    score += 3;
  } else if (output.bodyMarkdown.length >= 180) {
    score += 2;
  } else if (output.bodyMarkdown.length >= 120) {
    score += 1;
  }

  if (output.keywords.length >= 1) {
    score += 1;
  }

  if (output.notableMoments.length >= 1) {
    score += 1;
  }

  return score;
}

function mergeUniqueStrings(primary: string[], fallback: string[], limit: number): string[] {
  const merged: string[] = [];
  const seen = new Set<string>();
  for (const value of [...primary, ...fallback]) {
    const normalized = value.trim();
    if (!normalized) {
      continue;
    }
    const key = normalized.toLocaleLowerCase("en-US");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push(normalized);
    if (merged.length >= limit) {
      break;
    }
  }
  return merged;
}

function mergeKeywordEntries(
  primary: ReviewOutput["keywords"],
  fallback: ReviewOutput["keywords"],
  limit: number,
): ReviewOutput["keywords"] {
  const merged: ReviewOutput["keywords"] = [];
  const seen = new Set<string>();
  for (const item of [...primary, ...fallback]) {
    const label = item.label.trim();
    const note = item.note.trim();
    if (!label || !note) {
      continue;
    }
    const key = label.toLocaleLowerCase("en-US");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push({ label, note });
    if (merged.length >= limit) {
      break;
    }
  }
  return merged;
}

function mergeMarkdownBodies(primary: string, fallback: string): string {
  const normalizedPrimary = normalizeReviewBodyMarkdown(primary);
  const normalizedFallback = normalizeReviewBodyMarkdown(fallback);
  if (!normalizedPrimary) {
    return normalizedFallback;
  }
  if (normalizedPrimary.length >= 220) {
    return normalizedPrimary;
  }
  return normalizeReviewBodyMarkdown(`${normalizedPrimary}\n\n${normalizedFallback}`);
}

function mergeNotableMoments(
  primary: ReviewOutput["notableMoments"],
  fallback: ReviewOutput["notableMoments"],
  limit: number,
): ReviewOutput["notableMoments"] {
  const merged: ReviewOutput["notableMoments"] = [];
  const seen = new Set<string>();
  for (const item of [...primary, ...fallback]) {
    const title = item.title.trim();
    const note = item.note.trim();
    const momentIds = item.momentIds.filter(Boolean);
    if (!title || momentIds.length === 0) {
      continue;
    }
    const key = momentIds.join("|");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push({ title, note, momentIds });
    if (merged.length >= limit) {
      break;
    }
  }
  return merged;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function extractMessageContent(value: unknown): string | null {
  if (!isRecord(value) || !Array.isArray(value.choices)) {
    return null;
  }

  const firstChoice = value.choices[0] as unknown;
  if (!isRecord(firstChoice) || !isRecord(firstChoice.message)) {
    return null;
  }

  const content = firstChoice.message.content;
  if (typeof content === "string") {
    return content;
  }

  if (Array.isArray(content)) {
    const text = content
      .map((part) => (isRecord(part) && typeof part.text === "string" ? part.text : ""))
      .join("")
      .trim();
    return text.length > 0 ? text : null;
  }

  return null;
}

function parseJsonContent(content: string): unknown {
  const trimmed = content.trim();
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
    if (fenced) {
      return JSON.parse(fenced[1].trim()) as unknown;
    }

    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1)) as unknown;
    }

    throw new Error("No JSON object found");
  }
}

function getString(value: unknown, fallback: string): string {
  return typeof value === "string" ? value.trim() : fallback;
}

function getStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean)
    : [];
}

function getObjectArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
