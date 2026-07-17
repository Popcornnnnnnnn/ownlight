import { randomUUID } from "node:crypto";

import type { PostTag, Prisma, PrismaClient, Tag, TagAlias } from "@prisma/client";

import type { MediaSummaryOutput, MediaSummaryTagSuggestion } from "../ai/media-summary.js";
import type { FileLogger } from "../logging/file-logger.js";

export const DEFAULT_PRIMARY_TAGS = [
  {
    id: "tag-primary-diary",
    name: "日记",
    colorHex: "#D7E3F4",
  },
  {
    id: "tag-primary-idea",
    name: "想法",
    colorHex: "#E3DCF4",
  },
  {
    id: "tag-primary-learning",
    name: "学习整理",
    colorHex: "#DDEBD8",
  },
  {
    id: "tag-primary-emotion",
    name: "情绪",
    colorHex: "#F4DEE4",
  },
  {
    id: "tag-primary-casual",
    name: "碎碎念",
    colorHex: "#E7E2DA",
  },
  {
    id: "tag-primary-review",
    name: "复盘",
    colorHex: "#F0E4D4",
  },
] as const;

const DEFAULT_PRIMARY_TAG_ENGLISH_NAMES: Record<(typeof DEFAULT_PRIMARY_TAGS)[number]["id"], string> = {
  "tag-primary-diary": "Diary",
  "tag-primary-idea": "Thoughts",
  "tag-primary-learning": "Study",
  "tag-primary-emotion": "Mood",
  "tag-primary-casual": "Random",
  "tag-primary-review": "Review",
};

export const MAX_TAG_NAME_LENGTH = 40;
export const MAX_TOPIC_TAGS_PER_POST = 3;
const MIN_PRIMARY_CONFIDENCE = 0.6;
const MIN_TOPIC_CONFIDENCE = 0.5;
export const TOPIC_AREA_IDS = new Set([
  "technology",
  "product_design",
  "learning_knowledge",
  "work",
  "life",
  "health_fitness",
  "emotion_relationships",
]);
const GENERIC_TOPIC_CORES = new Set([
  "ai",
  "app",
  "ios",
  "学习",
  "开发",
  "工作",
  "生活",
  "运动",
  "技术",
  "问题",
  "总结",
  "复盘",
]);

interface TopicTagReuseAlias {
  alias: string;
  normalizedAlias?: string;
}

export interface TopicTagReuseCandidate {
  id: string;
  name: string;
  normalizedName?: string;
  aliases?: TopicTagReuseAlias[];
}

export function normalizeTagName(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/g, " ").toLocaleLowerCase("zh-Hans-CN");
}

export function findReusableTopicTagForName(
  rawName: string,
  candidates: TopicTagReuseCandidate[],
): TopicTagReuseCandidate | null {
  const name = cleanedTagName(rawName);
  if (!name) {
    return null;
  }

  const normalizedName = normalizeTagName(name);
  const compactName = compactTopicTagName(name);
  let best: { candidate: TopicTagReuseCandidate; score: number } | null = null;

  for (const candidate of candidates) {
    for (const term of topicTagCandidateTerms(candidate)) {
      const score = topicTagReuseScore({
        suggestedNormalizedName: normalizedName,
        suggestedCompactName: compactName,
        term,
      });
      if (score > (best?.score ?? 0)) {
        best = {
          candidate,
          score,
        };
      }
    }
  }

  return best ? best.candidate : null;
}

interface TopicTagCandidateTerm {
  value: string;
  normalizedName: string;
  compactName: string;
  source: "name" | "alias";
}

function topicTagCandidateTerms(candidate: TopicTagReuseCandidate): TopicTagCandidateTerm[] {
  const terms: TopicTagCandidateTerm[] = [
    {
      value: candidate.name,
      normalizedName: candidate.normalizedName ?? normalizeTagName(candidate.name),
      compactName: compactTopicTagName(candidate.name),
      source: "name",
    },
  ];

  for (const alias of candidate.aliases ?? []) {
    terms.push({
      value: alias.alias,
      normalizedName: alias.normalizedAlias ?? normalizeTagName(alias.alias),
      compactName: compactTopicTagName(alias.alias),
      source: "alias",
    });
  }

  return terms.filter((term) => term.value.trim().length > 0 && term.compactName.length > 0);
}

function topicTagReuseScore(input: {
  suggestedNormalizedName: string;
  suggestedCompactName: string;
  term: TopicTagCandidateTerm;
}): number {
  if (input.term.normalizedName === input.suggestedNormalizedName) {
    return input.term.source === "name" ? 100 : 98;
  }

  if (input.term.compactName === input.suggestedCompactName) {
    return input.term.source === "name" ? 94 : 92;
  }

  if (isReusableTopicContainment(input.suggestedCompactName, input.term.compactName)) {
    const shorterLength = Math.min(
      Array.from(input.suggestedCompactName).length,
      Array.from(input.term.compactName).length,
    );
    return (input.term.source === "name" ? 80 : 78) + Math.min(shorterLength, 20) / 100;
  }

  return 0;
}

function isReusableTopicContainment(suggestedCompactName: string, candidateCompactName: string): boolean {
  if (!suggestedCompactName || !candidateCompactName || suggestedCompactName === candidateCompactName) {
    return false;
  }

  const shorter =
    suggestedCompactName.length < candidateCompactName.length
      ? suggestedCompactName
      : candidateCompactName;
  if (GENERIC_TOPIC_CORES.has(shorter) || Array.from(shorter).length < 3) {
    return false;
  }

  return (
    suggestedCompactName.includes(candidateCompactName) ||
    candidateCompactName.includes(suggestedCompactName)
  );
}

function compactTopicTagName(value: string): string {
  return normalizeTagName(value).replace(/[\s\p{P}\p{S}_]+/gu, "");
}

export function canonicalDefaultPrimaryTagForId(
  id: string,
): (typeof DEFAULT_PRIMARY_TAGS)[number] | null {
  return DEFAULT_PRIMARY_TAGS.find((tag) => tag.id === id) ?? null;
}

function defaultPrimaryTagIdForName(name: string): string | null {
  const normalizedName = normalizeTagName(name);

  for (const tag of DEFAULT_PRIMARY_TAGS) {
    if (normalizeTagName(tag.name) === normalizedName) {
      return tag.id;
    }

    if (normalizeTagName(DEFAULT_PRIMARY_TAG_ENGLISH_NAMES[tag.id]) === normalizedName) {
      return tag.id;
    }
  }

  return null;
}

export function isValidTagType(value: string): value is "primary" | "topic" {
  return value === "primary" || value === "topic";
}

export function isValidPostTagRole(value: string): value is "primary" | "topic" {
  return value === "primary" || value === "topic";
}

export function isValidPostTagSource(value: string): value is "manual" | "ai" {
  return value === "manual" || value === "ai";
}

export function resolveTopicAreaId(
  value: string | null | undefined,
  topicName?: string | null,
): string {
  const normalizedAreaId = normalizeTopicAreaId(value);
  return normalizedAreaId ?? inferTopicAreaId(topicName);
}

function normalizeTopicAreaId(value: string | null | undefined): string | null {
  if (!value) {
    return null;
  }

  const cleaned = normalizeAreaInput(value);
  const mapped = new Map<string, string>([
    ["technology", "technology"],
    ["tech", "technology"],
    ["coding", "technology"],
    ["development", "technology"],
    ["software", "technology"],
    ["技术", "technology"],
    ["编程", "technology"],
    ["开发", "technology"],
    ["软件", "technology"],
    ["productdesign", "product_design"],
    ["product", "product_design"],
    ["design", "product_design"],
    ["产品", "product_design"],
    ["设计", "product_design"],
    ["产品与设计", "product_design"],
    ["产品设计", "product_design"],
    ["learningknowledge", "learning_knowledge"],
    ["learning", "learning_knowledge"],
    ["knowledge", "learning_knowledge"],
    ["study", "learning_knowledge"],
    ["research", "learning_knowledge"],
    ["学习", "learning_knowledge"],
    ["知识", "learning_knowledge"],
    ["学习与知识", "learning_knowledge"],
    ["读书", "learning_knowledge"],
    ["研究", "learning_knowledge"],
    ["work", "work"],
    ["business", "work"],
    ["office", "work"],
    ["工作", "work"],
    ["工作事务", "work"],
    ["事务", "work"],
    ["项目", "work"],
    ["life", "life"],
    ["daily", "life"],
    ["personal", "life"],
    ["生活", "life"],
    ["生活记录", "life"],
    ["日常", "life"],
    ["个人", "life"],
    ["healthfitness", "health_fitness"],
    ["health", "health_fitness"],
    ["fitness", "health_fitness"],
    ["exercise", "health_fitness"],
    ["sport", "health_fitness"],
    ["健康", "health_fitness"],
    ["运动", "health_fitness"],
    ["健康与运动", "health_fitness"],
    ["健身", "health_fitness"],
    ["emotionrelationships", "emotion_relationships"],
    ["emotion", "emotion_relationships"],
    ["relationship", "emotion_relationships"],
    ["relationships", "emotion_relationships"],
    ["mood", "emotion_relationships"],
    ["情绪", "emotion_relationships"],
    ["关系", "emotion_relationships"],
    ["情绪与关系", "emotion_relationships"],
    ["亲密关系", "emotion_relationships"],
  ]);
  return mapped.get(cleaned) ?? null;
}

function inferTopicAreaId(value: string | null | undefined): string {
  if (!value) {
    return "life";
  }

  const normalized = normalizeAreaInput(value);
  if (!normalized) {
    return "life";
  }

  if (containsAny(normalized, [
    "ai", "llm", "gpt", "claude", "codex", "mcp", "api", "http", "https", "dns", "ssh",
    "ios", "swift", "swiftui", "python", "typescript", "javascript", "sqlite", "database",
    "server", "cloudflare", "tailscale", "github", "git", "docker", "代码", "编程", "开发",
    "软件", "服务器", "数据库", "接口", "网络", "安全", "证书", "中间人", "模型", "大模型", "技术",
  ])) {
    return "technology";
  }

  if (containsAny(normalized, [
    "product", "design", "ui", "ux", "figma", "feature", "roadmap", "filter", "topic", "tag",
    "app设计", "产品", "设计", "界面", "交互", "功能", "路线图", "筛选", "标签", "体验",
  ])) {
    return "product_design";
  }

  if (containsAny(normalized, [
    "learning", "study", "knowledge", "research", "paper", "thesis", "book", "course", "reading",
    "学习", "知识", "论文", "研究", "读书", "课程", "笔记", "整理",
  ])) {
    return "learning_knowledge";
  }

  if (containsAny(normalized, [
    "work", "office", "business", "meeting", "client", "deadline", "job", "工作", "会议", "客户",
    "岗位", "面试", "任务", "同事",
  ])) {
    return "work";
  }

  if (containsAny(normalized, [
    "health", "fitness", "exercise", "sport", "run", "sleep", "medicine", "rehab", "gym",
    "健康", "运动", "跑步", "健身", "睡眠", "康复", "训练", "饮食", "药",
  ])) {
    return "health_fitness";
  }

  if (containsAny(normalized, [
    "emotion", "relationship", "mood", "family", "friend", "love", "stress", "anxiety",
    "情绪", "关系", "心情", "家人", "朋友", "压力", "焦虑", "亲密",
  ])) {
    return "emotion_relationships";
  }

  return "life";
}

function normalizeAreaInput(value: string): string {
  return value.normalize("NFKC").trim().toLowerCase().replace(/[\s\p{P}\p{S}_]+/gu, "");
}

function containsAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(normalizeAreaInput(needle)));
}

export function cleanedTagName(value: string): string | null {
  const cleaned = value.normalize("NFKC").trim().replace(/\s+/g, " ");
  if (!cleaned || cleaned.length > MAX_TAG_NAME_LENGTH) {
    return null;
  }

  return cleaned;
}

export async function ensureDefaultTags(
  prisma: PrismaClient,
  fileLogger: FileLogger,
): Promise<void> {
  const now = new Date();
  let createdOrUpdatedCount = 0;

  await prisma.$transaction(async (tx) => {
    for (const tag of DEFAULT_PRIMARY_TAGS) {
      const existing = await tx.tag.findUnique({
        where: {
          id: tag.id,
        },
      });

      if (!existing) {
        const created = await tx.tag.create({
          data: {
            id: tag.id,
            type: "primary",
            name: tag.name,
            normalizedName: normalizeTagName(tag.name),
            colorHex: tag.colorHex,
            isDefault: true,
            isArchived: false,
            aiUsableAsPrimary: true,
            updatedAt: now,
          },
        });
        await emitTagChange(tx, created);
        createdOrUpdatedCount += 1;
        continue;
      }

      if (
        existing.name !== tag.name ||
        existing.type !== "primary" ||
        existing.normalizedName !== normalizeTagName(tag.name) ||
        existing.isDefault !== true ||
        existing.isArchived !== false ||
        existing.aiUsableAsPrimary !== true
      ) {
        const updated = await tx.tag.update({
          where: {
            id: tag.id,
          },
          data: {
            type: "primary",
            name: tag.name,
            normalizedName: normalizeTagName(tag.name),
            isDefault: true,
            isArchived: false,
            archivedAt: null,
            aiUsableAsPrimary: true,
          },
        });
        await emitTagChange(tx, updated);
        createdOrUpdatedCount += 1;
      }
    }
  });

  if (createdOrUpdatedCount > 0) {
    await fileLogger.info("tags.defaults_seeded", {
      count: createdOrUpdatedCount,
    });
  }
}

export async function applyAITagsFromSummary(
  tx: Prisma.TransactionClient,
  input: {
    postId: string;
    mediaKind: string;
    summaryId: string;
    output: MediaSummaryOutput;
    forceRegenerate: boolean;
  },
): Promise<{
  appliedPrimary: number;
  appliedTopics: number;
  primarySkippedReason: string | null;
  skippedReason: string | null;
}> {
  if (input.forceRegenerate) {
    return { appliedPrimary: 0, appliedTopics: 0, primarySkippedReason: null, skippedReason: "force_regenerate" };
  }

  if (input.mediaKind !== "audio") {
    return { appliedPrimary: 0, appliedTopics: 0, primarySkippedReason: null, skippedReason: "non_audio_media" };
  }

  const post = await tx.post.findUnique({
    where: {
      id: input.postId,
    },
    include: {
      tags: {
        where: {
          deletedAt: null,
        },
      },
    },
  });

  if (!post || post.deletedAt) {
    return { appliedPrimary: 0, appliedTopics: 0, primarySkippedReason: null, skippedReason: "post_missing" };
  }

  if (post.tagsUserEditedAt) {
    return { appliedPrimary: 0, appliedTopics: 0, primarySkippedReason: null, skippedReason: "user_edited" };
  }

  if (post.aiTagProcessedAt) {
    return { appliedPrimary: 0, appliedTopics: 0, primarySkippedReason: null, skippedReason: "already_processed" };
  }

  const now = new Date();
  let appliedPrimary = 0;
  let appliedTopics = 0;
  let primarySkippedReason: string | null = "primary_disabled";
  const primarySuggestion: MediaSummaryTagSuggestion | null = null;

  const existingTopicTagIds = new Set(post.tags.filter((tag) => tag.role === "topic").map((tag) => tag.tagId));
  const topicSuggestions = uniqueTopicSuggestions(input.output.suggestedTags.topics);
  for (const suggestion of topicSuggestions) {
    if (appliedTopics >= MAX_TOPIC_TAGS_PER_POST) {
      break;
    }

    if (suggestion.confidence < MIN_TOPIC_CONFIDENCE) {
      continue;
    }

    const topic = await resolveOrCreateTopicTag(tx, suggestion);
    if (!topic || existingTopicTagIds.has(topic.id)) {
      continue;
    }

    await upsertPostTag(tx, {
      postId: post.id,
      tagId: topic.id,
      role: "topic",
      source: "ai",
      confidence: suggestion.confidence,
      aiSummaryId: input.summaryId,
      now,
    });
    existingTopicTagIds.add(topic.id);
    appliedTopics += 1;
  }

  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      aiTagProcessedAt: now,
    },
  });
  await emitPostTagStateChange(tx, post.id, {
    aiTagProcessedAt: now,
    tagsUserEditedAt: post.tagsUserEditedAt,
  });

  return {
    appliedPrimary,
    appliedTopics,
    primarySkippedReason: appliedPrimary > 0 ? null : primarySkippedReason,
    skippedReason: skippedAITagApplicationReason({
      primarySuggestion,
      topicSuggestions,
      appliedPrimary,
      appliedTopics,
      hadExistingPrimary: false,
    }),
  };
}

function skippedAITagApplicationReason(input: {
  primarySuggestion: MediaSummaryTagSuggestion | null;
  topicSuggestions: MediaSummaryTagSuggestion[];
  appliedPrimary: number;
  appliedTopics: number;
  hadExistingPrimary: boolean;
}): string | null {
  if (input.appliedPrimary > 0 || input.appliedTopics > 0) {
    return null;
  }

  if (!input.primarySuggestion && input.topicSuggestions.length === 0) {
    return "no_suggestions";
  }

  const hadLowPrimary = input.primarySuggestion !== null && input.primarySuggestion.confidence < MIN_PRIMARY_CONFIDENCE;
  const hadLowTopic = input.topicSuggestions.some((suggestion) => suggestion.confidence < MIN_TOPIC_CONFIDENCE);
  const hadEligibleTopic = input.topicSuggestions.some((suggestion) => suggestion.confidence >= MIN_TOPIC_CONFIDENCE);

  if (hadLowPrimary || (hadLowTopic && !hadEligibleTopic)) {
    return "low_confidence";
  }

  if (input.hadExistingPrimary && input.topicSuggestions.length === 0) {
    return "primary_locked_no_topics";
  }

  return "no_matching_tags";
}

async function resolvePrimarySuggestion(
  tx: Prisma.TransactionClient,
  suggestion: MediaSummaryTagSuggestion | null,
): Promise<Tag | null> {
  if (!suggestion || suggestion.confidence < MIN_PRIMARY_CONFIDENCE) {
    return null;
  }

  const name = cleanedTagName(suggestion.name);
  if (!name) {
    return null;
  }

  const defaultPrimaryTagId = defaultPrimaryTagIdForName(name);
  if (defaultPrimaryTagId) {
    return tx.tag.findFirst({
      where: {
        id: defaultPrimaryTagId,
        type: "primary",
        isArchived: false,
        aiUsableAsPrimary: true,
      },
    });
  }

  return tx.tag.findFirst({
    where: {
      type: "primary",
      normalizedName: normalizeTagName(name),
      isArchived: false,
      aiUsableAsPrimary: true,
    },
  });
}

function uniqueTopicSuggestions(
  suggestions: MediaSummaryTagSuggestion[],
): MediaSummaryTagSuggestion[] {
  const seen = new Set<string>();
  const result: MediaSummaryTagSuggestion[] = [];

  for (const suggestion of suggestions) {
    const name = cleanedTagName(suggestion.name);
    if (!name) {
      continue;
    }

    const normalized = normalizeTagName(name);
    if (seen.has(normalized)) {
      continue;
    }

    seen.add(normalized);
    result.push({
      name,
      confidence: suggestion.confidence,
    });
  }

  return result;
}

async function resolveOrCreateTopicTag(
  tx: Prisma.TransactionClient,
  suggestion: MediaSummaryTagSuggestion,
): Promise<Tag | null> {
  const name = cleanedTagName(suggestion.name);
  if (!name) {
    return null;
  }

  const normalizedName = normalizeTagName(name);
  const areaId = resolveTopicAreaId(suggestion.area ?? null, name);
  const activeTopicCandidates = await tx.tag.findMany({
    where: {
      type: "topic",
      isArchived: false,
    },
    include: {
      aliases: {
        where: {
          deletedAt: null,
        },
      },
    },
  });
  const reusableTopic = findReusableTopicTagForName(name, activeTopicCandidates);

  if (reusableTopic) {
    const tag = activeTopicCandidates.find((candidate) => candidate.id === reusableTopic.id) ?? null;
    if (tag && !TOPIC_AREA_IDS.has(tag.areaId ?? "")) {
      const updated = await tx.tag.update({
        where: {
          id: tag.id,
        },
        data: {
          areaId,
        },
      });
      await emitTagChange(tx, updated);
      return updated;
    }

    return tag;
  }

  const existing = await tx.tag.findUnique({
    where: {
      normalizedName,
    },
  });

  if (existing) {
    return existing.type === "topic" && !existing.isArchived ? existing : null;
  }

  const tag = await tx.tag.create({
    data: {
      id: randomUUID(),
      type: "topic",
      name,
      normalizedName,
      isDefault: false,
      isArchived: false,
      aiUsableAsPrimary: false,
      areaId,
    },
  });
  await emitTagChange(tx, tag);
  return tag;
}

export async function upsertPostTag(
  tx: Prisma.TransactionClient,
  input: {
    postId: string;
    tagId: string;
    role: "primary" | "topic";
    source: "manual" | "ai";
    confidence: number | null;
    aiSummaryId: string | null;
    now: Date;
  },
): Promise<PostTag> {
  const postTag = await tx.postTag.upsert({
    where: {
      postId_tagId: {
        postId: input.postId,
        tagId: input.tagId,
      },
    },
    create: {
      id: randomUUID(),
      postId: input.postId,
      tagId: input.tagId,
      role: input.role,
      source: input.source,
      confidence: input.confidence,
      aiSummaryId: input.aiSummaryId,
      updatedAt: input.now,
      deletedAt: null,
    },
    update: {
      role: input.role,
      source: input.source,
      confidence: input.confidence,
      aiSummaryId: input.aiSummaryId,
      updatedAt: input.now,
      deletedAt: null,
    },
  });

  await emitPostTagChange(tx, postTag, "post_tag_updated");
  return postTag;
}

export async function emitTagChange(tx: Prisma.TransactionClient, tag: Tag): Promise<void> {
  await tx.serverChange.create({
    data: {
      entityType: "tag",
      entityId: tag.id,
      changeType: "tag_updated",
      payloadJson: JSON.stringify(serializeTag(tag)),
    },
  });
}

export async function emitTagDeletedChange(
  tx: Prisma.TransactionClient,
  tag: Tag,
  deletedAt: Date,
): Promise<void> {
  await tx.serverChange.create({
    data: {
      entityType: "tag",
      entityId: tag.id,
      changeType: "tag_deleted",
      payloadJson: JSON.stringify({
        ...serializeTag(tag),
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });
}

export async function emitTagAliasChange(
  tx: Prisma.TransactionClient,
  alias: TagAlias,
  changeType: "tag_alias_updated" | "tag_alias_deleted",
): Promise<void> {
  await tx.serverChange.create({
    data: {
      entityType: "tag_alias",
      entityId: alias.id,
      changeType,
      payloadJson: JSON.stringify(serializeTagAlias(alias)),
    },
  });
}

export async function emitPostTagChange(
  tx: Prisma.TransactionClient,
  postTag: PostTag,
  changeType: "post_tag_updated" | "post_tag_deleted",
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "post_tag",
      entityId: postTag.id,
      changeType,
      payloadJson: JSON.stringify(serializePostTag(postTag)),
    },
  });

  await tx.post.update({
    where: {
      id: postTag.postId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export async function emitPostTagStateChange(
  tx: Prisma.TransactionClient,
  postId: string,
  state: {
    aiTagProcessedAt: Date | null;
    tagsUserEditedAt: Date | null;
  },
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: postId,
      changeType: "post_tag_state_updated",
      payloadJson: JSON.stringify({
        postId,
        aiTagProcessedAt: state.aiTagProcessedAt?.toISOString() ?? null,
        tagsUserEditedAt: state.tagsUserEditedAt?.toISOString() ?? null,
      }),
    },
  });

  await tx.post.update({
    where: {
      id: postId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export function serializeTag(tag: Tag): Record<string, unknown> {
  return {
    id: tag.id,
    type: tag.type,
    name: tag.name,
    normalizedName: tag.normalizedName,
    colorHex: tag.colorHex,
    isDefault: tag.isDefault,
    isArchived: tag.isArchived,
    aiUsableAsPrimary: tag.aiUsableAsPrimary,
    areaId: tag.areaId,
    createdAt: tag.createdAt.toISOString(),
    updatedAt: tag.updatedAt.toISOString(),
    archivedAt: tag.archivedAt?.toISOString() ?? null,
  };
}

export function serializeTagAlias(alias: TagAlias): Record<string, unknown> {
  return {
    id: alias.id,
    tagId: alias.tagId,
    alias: alias.alias,
    normalizedAlias: alias.normalizedAlias,
    createdAt: alias.createdAt.toISOString(),
    deletedAt: alias.deletedAt?.toISOString() ?? null,
  };
}

export function serializePostTag(postTag: PostTag): Record<string, unknown> {
  return {
    id: postTag.id,
    postId: postTag.postId,
    tagId: postTag.tagId,
    role: postTag.role,
    source: postTag.source,
    confidence: postTag.confidence,
    aiSummaryId: postTag.aiSummaryId,
    createdAt: postTag.createdAt.toISOString(),
    updatedAt: postTag.updatedAt.toISOString(),
    deletedAt: postTag.deletedAt?.toISOString() ?? null,
  };
}
