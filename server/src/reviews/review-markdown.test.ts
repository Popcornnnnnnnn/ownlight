import test from "node:test";
import assert from "node:assert/strict";

import type { Review } from "@prisma/client";

import type { ReviewOutput } from "../ai/review-generation.js";
import { reviewToMarkdown } from "./review-markdown.js";

test("reviewToMarkdown stays within the app-supported H1/H2 subset", () => {
  const content: ReviewOutput = {
    title: "Weekly Review",
    subtitle: "12 moments · 3 comments",
    bodyMarkdown: "A quiet week.\n\n## What moved\n- Finished a draft.",
    keywords: [{ label: "Study", note: "Several focused sessions." }],
    notableMoments: [],
    uncertainty: [],
  };
  const review = {
    rangeStart: new Date("2026-05-01T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-08T00:00:00.000Z"),
  } as Review;

  const markdown = reviewToMarkdown(content, review);

  assert.match(markdown, /^# Weekly Review/m);
  assert.match(markdown, /^12 moments · 3 comments$/m);
  assert.match(markdown, /^## What moved$/m);
  assert.doesNotMatch(markdown, /^### /m);
  assert.match(markdown, /^- Study$/m);
});
