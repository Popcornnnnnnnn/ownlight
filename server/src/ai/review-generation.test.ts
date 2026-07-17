import test from "node:test";
import assert from "node:assert/strict";

import type { AISummaryConfig } from "../config/app-config.js";
import { AISummaryProviderError } from "./media-summary.js";
import {
  createLocalFallbackReview,
  generateReview,
  generateReviewWithSource,
  REVIEW_PROMPT_VERSION,
  validateReviewOutput,
  type ReviewInputPack,
} from "./review-generation.js";

const inputPack: ReviewInputPack = {
  kind: "weekly",
  rangeMode: "rolling_7_days",
  rangeStart: "2026-05-01T00:00:00.000Z",
  rangeEnd: "2026-05-08T00:00:00.000Z",
  generatedAt: "2026-05-08T00:00:00.000Z",
  totals: {
    moments: 12,
    textMoments: 8,
    imageMoments: 2,
    audioMoments: 2,
    videoMoments: 0,
    comments: 3,
    favorites: 1,
  },
  rhythm: {
    byDay: [{ date: "2026-05-07", count: 3 }],
    byHourBucket: [{ bucket: "evening", count: 5 }],
  },
  moments: [],
  reviewMemory: [],
};

const inputPackWithMoments: ReviewInputPack = {
  ...inputPack,
  moments: [
    {
      id: "moment-1",
      occurredAt: "2026-05-07T12:00:00.000Z",
      text: "# 测试 Weekly Review\n修复 regenerate 后的状态问题",
      mediaKinds: ["audio"],
      comments: ["需要继续确认真机表现"],
      tags: ["产品", "开发"],
      favorite: true,
      aiSummaries: [],
    },
    {
      id: "moment-2",
      occurredAt: "2026-05-07T20:00:00.000Z",
      text: "为什么 provider 会返回 502",
      mediaKinds: [],
      comments: [],
      tags: ["开发"],
      favorite: false,
      aiSummaries: [],
    },
  ],
};

test("validateReviewOutput rejects sparse ready-looking output for non-empty ranges", () => {
  assert.throws(
    () => validateReviewOutput({
      title: "这一周：产品在长出来，生活也在不断试运行",
      bodyMarkdown: "",
      keywords: [],
      notableMoments: [],
      uncertainty: [],
    }, inputPack),
    (error) => error instanceof AISummaryProviderError && error.code === "empty_review_content",
  );
});

test("validateReviewOutput accepts substantive output for non-empty ranges", () => {
  const output = validateReviewOutput({
    title: "Weekly Review",
    bodyMarkdown: [
      "This week kept returning to the same product thread instead of scattering into unrelated errands.",
      "",
      "Small corrections accumulated into something clearer by the end of the week, especially around the parts that had already caused friction once before.",
      "",
      "## What mattered",
      "- The review flow stayed visible across multiple notes, so it felt like an active line rather than a one-off annoyance.",
      "- Comments and favorite moments both pointed back to verification, which made the week read as careful iteration instead of random maintenance.",
      "- Even the unresolved provider question helped define the boundary of what still needs another pass.",
    ].join("\n"),
    keywords: [{ label: "Product", note: "Several notes were about shaping and testing product behavior." }],
    notableMoments: [{ title: "Review flow", note: "Worth revisiting as a product decision.", momentIds: ["moment-1"] }],
    uncertainty: [],
  }, inputPack);

  assert.equal(output.title, "Weekly Review");
  assert.equal(output.subtitle, "12 moments · 3 comments");
  assert.equal(output.keywords.length, 1);
});

test("validateReviewOutput accepts a strong body even when revisit anchors are omitted", () => {
  const output = validateReviewOutput({
    title: "Weekly Review",
    bodyMarkdown: [
      "这一周的主线并没有散掉，很多记录都绕着同一个产品问题来回推进，所以最后留下来的不是一堆孤立更新，而是一条还算连续的判断链。",
      "",
      "前半段更多是在确认哪里真的让人卡住，后半段则开始把这些卡点重新组织成更具体的取舍。即使还有一些问题没完全关上，这一版材料也已经足够形成一篇完整回顾，而不是只够拼一个兜底骨架。",
      "",
      "## 还留在桌面上的问题",
      "- provider 的稳定性还需要继续观察，但已经不再盖过正文主线。",
      "- 某些入口的交互仍然要靠真机感受来校正。",
    ].join("\n"),
    keywords: [{ label: "开发", note: "大部分记录都围绕修复、验证和产品判断展开。" }],
    notableMoments: [],
    uncertainty: [],
  }, inputPackWithMoments);

  assert.equal(output.subtitle, "12 moments · 3 comments");
  assert.equal(output.notableMoments.length, 0);
});

test("validateReviewOutput drops notable moment anchors that do not exist in the input pack", () => {
  const output = validateReviewOutput({
    title: "Weekly Review",
    bodyMarkdown: [
      "A focused week with several concrete product steps, and the material stayed coherent enough to suggest one main thread instead of a loose stack of updates.",
      "",
      "The main thread stayed visible throughout the range because the notes, comments, and follow-up questions kept circling the same product surface from slightly different angles.",
      "",
      "## What stayed visible",
      "- Verification pressure kept shaping the work more than expansion did.",
      "- The review and regenerate path continued to act like a useful stress point.",
      "- The remaining uncertainty was narrow enough to name without overwhelming the whole week.",
    ].join("\n"),
    keywords: [{ label: "Product", note: "Several notes were about shaping and testing product behavior." }],
    notableMoments: [
      { title: "Real anchor", note: "A valid revisit anchor.", momentIds: ["moment-1", "missing"] },
      { title: "Broken anchor", note: "This should not survive.", momentIds: ["missing"] },
    ],
    uncertainty: [],
  }, inputPackWithMoments);

  assert.equal(output.notableMoments.length, 1);
  assert.deepEqual(output.notableMoments[0]?.momentIds, ["moment-1"]);
});

test("weekly review prompt version tracks the quality-calibration prompt", () => {
  assert.equal(REVIEW_PROMPT_VERSION, "weekly-review-v3");
});

test("createLocalFallbackReview returns substantive content for non-empty ranges", () => {
  const output = createLocalFallbackReview(
    inputPackWithMoments,
    new AISummaryProviderError("provider_http_502", "AI provider returned HTTP 502"),
  );

  assert.ok(output.title.length > 0);
  assert.equal(output.subtitle, "12 moments · 3 comments");
  assert.ok(output.bodyMarkdown.length > 180);
  assert.ok(output.keywords.length > 0);
  assert.ok(output.uncertainty.some((item) => item.includes("保守兜底版本")));
  assert.equal(output.notableMoments.every((item) => item.note === ""), true);
});

test("generateReview falls back after retryable provider HTTP failures", async (t) => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return new Response("bad gateway", { status: 502 });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const output = await generateReview({
    provider: "test",
    baseUrl: "https://provider.invalid/v1",
    apiKey: "test-key",
    model: "test-model",
    transcriptionProvider: "local",
    transcriptionModel: "test-transcribe",
    localTranscriptionPythonPath: "python",
    localTranscriptionScriptPath: "script.py",
    localTranscriptionModel: "local-model",
    localTranscriptionTimeoutMs: 1000,
    timeoutMs: 1000,
  }, inputPackWithMoments);

  assert.equal(calls, 3);
  assert.equal(output.subtitle, "12 moments · 3 comments");
  assert.ok(output.bodyMarkdown.length > 180);
  assert.ok(output.uncertainty.some((item) => item.includes("保守兜底版本")));
});

test("generateReview reuses the best sparse provider draft when later retries degrade", async (t) => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    if (calls < 3) {
      return Response.json({
        choices: [
          {
            message: {
              content: JSON.stringify({
                title: "Provider Draft",
                bodyMarkdown: "这一周有一些值得回看的记录和推进，但主线还没有完全收拢。",
                keywords: [{ label: "开发", note: "不少记录都围绕修复和验证展开。" }],
                notableMoments: [],
                uncertainty: [],
              }),
            },
          },
        ],
      });
    }

    return Response.json({
      choices: [
        {
          message: {
            content: "{\"title\":\"Broken\"",
          },
        },
      ],
    });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const output = await generateReview({
    provider: "test",
    baseUrl: "https://provider.invalid/v1",
    apiKey: "test-key",
    model: "test-model",
    transcriptionProvider: "local",
    transcriptionModel: "test-transcribe",
    localTranscriptionPythonPath: "python",
    localTranscriptionScriptPath: "script.py",
    localTranscriptionModel: "local-model",
    localTranscriptionTimeoutMs: 1000,
    timeoutMs: 1000,
  }, inputPackWithMoments);

  assert.equal(calls, 3);
  assert.equal(output.title, "Provider Draft");
  assert.ok(output.bodyMarkdown.length > 180);
  assert.ok(output.notableMoments.length > 0);
  assert.ok(
    output.uncertainty.some((item) => item.includes("内容过稀")),
    "expected recovered review to disclose partial local completion",
  );
});

test("generateReviewWithSource uses DeepSeek pro json_object fallback for weekly reviews when primary is down", async (t) => {
  const originalFetch = globalThis.fetch;
  const requestBodies: unknown[] = [];
  globalThis.fetch = async (input, init) => {
    const url = String(input);
    if (url === "http://127.0.0.1:3000/health") {
      return new Response(null, { status: 503 });
    }

    requestBodies.push(JSON.parse(String(init?.body)) as unknown);
    return Response.json({
      choices: [
        {
          message: {
            content: JSON.stringify({
              title: "Fallback Weekly Review",
              bodyMarkdown: [
                "This week had enough concrete material to produce a grounded review.",
                "",
                "## Main thread",
                "- Provider routing was the central maintenance theme.",
                "- The fallback path stayed visible without changing the app's product shape.",
                "- The review stayed calm and specific instead of becoming generic.",
              ].join("\n"),
              keywords: [{ label: "Provider routing", note: "Several notes relate to fallback behavior." }],
              notableMoments: [{ title: "Provider routing", note: "Worth revisiting.", momentIds: ["moment-1"] }],
              uncertainty: [],
            }),
          },
        },
      ],
    });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const result = await generateReviewWithSource(testAIConfig(), inputPackWithMoments);

  assert.equal(result.source.provider, "deepseek");
  assert.equal(result.source.model, "deepseek-v4-pro");
  assert.equal(result.output.title, "Fallback Weekly Review");
  assert.equal((requestBodies[0] as { response_format?: { type?: string }; model?: string }).response_format?.type, "json_object");
  assert.equal((requestBodies[0] as { model?: string }).model, "deepseek-v4-pro");
});

function testAIConfig(): AISummaryConfig {
  return {
    provider: "openai",
    baseUrl: "http://127.0.0.1:3000/v1",
    apiKey: "primary-key",
    model: "gpt-5.5",
    fallback: {
      provider: "deepseek",
      baseUrl: "https://api.deepseek.com",
      apiKey: "fallback-key",
      fastModel: "deepseek-v4-flash",
      proModel: "deepseek-v4-pro",
    },
    primaryHealthUrl: "http://127.0.0.1:3000/health",
    primaryHealthHealthyIntervalMs: 60_000,
    primaryHealthDownIntervalMs: 15_000,
    primaryHealthTimeoutMs: 100,
    primaryHealthStaleMs: 120_000,
    longContentThresholdChars: 8_000,
    transcriptionProvider: "local",
    transcriptionModel: "transcribe",
    localTranscriptionPythonPath: "python",
    localTranscriptionScriptPath: "script.py",
    localTranscriptionModel: "local-model",
    localTranscriptionTimeoutMs: 1_000,
    timeoutMs: 1_000,
  };
}
