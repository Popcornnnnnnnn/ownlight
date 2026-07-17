import assert from "node:assert/strict";
import test from "node:test";

import {
  AISummaryProviderError,
  combineAudioTranscriptSegments,
  generateMediaSummaryWithSource,
} from "./media-summary.js";
import type { AISummaryConfig } from "../config/app-config.js";

test("combineAudioTranscriptSegments labels non-empty recordings in order", () => {
  assert.equal(
    combineAudioTranscriptSegments([
      { label: "Recording 1", transcriptText: " first thought " },
      { label: "Recording 2", transcriptText: "" },
      { label: "Recording 3", transcriptText: "follow-up thought" },
    ]),
    "Recording 1\nfirst thought\n\nRecording 3\nfollow-up thought",
  );
});

test("combineAudioTranscriptSegments rejects all-empty recording groups", () => {
  assert.throws(
    () => combineAudioTranscriptSegments([{ label: "Recording 1", transcriptText: "   " }]),
    (error: unknown) =>
      error instanceof AISummaryProviderError && error.code === "empty_transcript",
  );
});

test("generateMediaSummaryWithSource uses DeepSeek json_object fallback when primary health is down", async (t) => {
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
              format: "document",
              language: "en",
              documentTitle: "Fallback note",
              oneLiner: "The fallback provider summarized the note.",
              blocks: [
                {
                  kind: "paragraph",
                  level: 0,
                  text: "A concise provider fallback summary.",
                  items: [],
                },
              ],
              suggestedTags: {
                area: "产品与设计",
                topics: [{ name: "Provider fallback", confidence: 0.9 }],
              },
            }),
          },
        },
      ],
      usage: {
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
      },
    });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const result = await generateMediaSummaryWithSource(testAIConfig(), {
    transcriptText: "Short note about provider fallback.",
    durationSeconds: 12,
  });

  assert.equal(result.source.provider, "deepseek");
  assert.equal(result.source.model, "deepseek-v4-flash");
  assert.equal(result.summary.documentTitle, "Fallback note");
  assert.equal(requestBodies.length, 1);
  assert.equal((requestBodies[0] as { response_format?: { type?: string } }).response_format?.type, "json_object");
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
