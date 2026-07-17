import type { Review } from "@prisma/client";

import type { ReviewOutput } from "../ai/review-generation.js";

export function reviewToMarkdown(content: ReviewOutput, review: Review): string {
  const lines = [
    `# ${content.title || "Weekly Review"}`,
    "",
    content.subtitle,
    "",
    content.bodyMarkdown,
    "",
    "## Keywords",
    ...content.keywords.map((keyword) => `- ${keyword.label}`),
    "",
    `Range: ${review.rangeStart.toISOString().slice(0, 10)} to ${review.rangeEnd.toISOString().slice(0, 10)}`,
  ];

  return lines.filter((line, index, all) => line.length > 0 || all[index - 1]?.length).join("\n");
}
