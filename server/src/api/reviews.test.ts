import test from "node:test";
import assert from "node:assert/strict";

import { sanitizeReviewContentForClient } from "./reviews.js";

test("sanitizeReviewContentForClient strips legacy fallback notable copy and uncertainty error details", () => {
  const content = sanitizeReviewContentForClient({
    title: "最近 7 天回顾",
    oneLiner: "这段时间一共留下 59 条 moments，主要价值是把零散记录先稳定地收拢起来。",
    themes: [
      {
        title: "零散记录被重新收拢",
        body: "单条记录可能很碎，但放在一起能看出你在持续把想法和现场情况留存下来。",
      },
    ],
    emotionalReflection: {
      tone: "mixed",
      body: "从记录密度看，这一周并不是空白的。",
    },
    notableMoments: [
      {
        title: "修复 regenerate 后的状态问题",
        note: "这条记录在本地兜底回顾中被保留下来，适合作为之后重新阅读的入口。",
        momentIds: ["moment-1"],
      },
      {
        title: "Keep this note",
        note: "这条是用户可读的正常说明。",
        momentIds: ["moment-2"],
      },
    ],
    uncertainty: [
      "AI provider 生成失败（provider_http_502），这篇是 server 根据本地 moments 输入包生成的保守兜底版本；细节深度会低于正常 AI review。",
      "这条额外说明应该保留。",
    ],
  }, "zh");

  assert.deepEqual(content.notableMoments, [
    {
      title: "修复 regenerate 后的状态问题",
      note: "",
      momentIds: ["moment-1"],
    },
    {
      title: "Keep this note",
      note: "这条是用户可读的正常说明。",
      momentIds: ["moment-2"],
    },
  ]);
  assert.deepEqual(content.uncertainty, [
    "这篇是 server 根据本地 moments 输入包生成的保守兜底版本；细节深度会低于正常 AI review，建议之后重新生成一次。",
    "这条额外说明应该保留。",
  ]);
  assert.match(String(content.bodyMarkdown), /^这段时间一共留下 59 条 moments/m);
  assert.match(String(content.bodyMarkdown), /^## 反复出现的线索$/m);
});

test("sanitizeReviewContentForClient normalizes English legacy fallback strings", () => {
  const content = sanitizeReviewContentForClient({
    notableMoments: [
      {
        title: "Debug session",
        note: "This entry is kept as a lightweight revisit anchor in the local fallback review.",
        momentIds: ["moment-1"],
      },
    ],
    uncertainty: [
      "The AI provider failed (provider_http_502), so this is a conservative local fallback generated from the review input pack. It is less detailed than a normal AI review.",
    ],
  }, "en");

  assert.deepEqual(content.notableMoments, [
    {
      title: "Debug session",
      note: "",
      momentIds: ["moment-1"],
    },
  ]);
  assert.deepEqual(content.uncertainty, [
    "This is a conservative local fallback generated from the review input pack. It is less detailed than a normal AI review, so regenerate later if needed.",
  ]);
});
