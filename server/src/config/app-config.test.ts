import assert from "node:assert/strict";
import test from "node:test";

import { loadConfig } from "./app-config.js";

test("loadConfig leaves fallback disabled when no fallback key is configured", () => {
  const config = loadConfig({
    AI_SUMMARY_API_KEY: "primary-key",
  });

  assert.equal(config.aiSummary.fallback, undefined);
});

test("loadConfig parses DeepSeek fallback defaults when fallback key is configured", () => {
  const config = loadConfig({
    AI_SUMMARY_API_KEY: "primary-key",
    AI_SUMMARY_FALLBACK_API_KEY: "fallback-key",
  });

  assert.equal(config.aiSummary.fallback?.provider, "deepseek");
  assert.equal(config.aiSummary.fallback?.baseUrl, "https://api.deepseek.com");
  assert.equal(config.aiSummary.fallback?.apiKey, "fallback-key");
  assert.equal(config.aiSummary.fallback?.fastModel, "deepseek-v4-flash");
  assert.equal(config.aiSummary.fallback?.proModel, "deepseek-v4-pro");
  assert.equal(config.aiSummary.longContentThresholdChars, 8_000);
});

test("loadConfig ignores fallback provider details when fallback key is missing", () => {
  const config = loadConfig({
    AI_SUMMARY_API_KEY: "primary-key",
    AI_SUMMARY_FALLBACK_BASE_URL: "https://api.deepseek.com",
    AI_SUMMARY_FALLBACK_FAST_MODEL: "deepseek-v4-flash",
    AI_SUMMARY_FALLBACK_PRO_MODEL: "deepseek-v4-pro",
  });

  assert.equal(config.aiSummary.fallback, undefined);
});

test("loadConfig rejects invalid AI summary long-content threshold", () => {
  assert.throws(
    () => loadConfig({
      AI_SUMMARY_API_KEY: "primary-key",
      AI_SUMMARY_LONG_CONTENT_THRESHOLD_CHARS: "not-a-number",
    }),
    /Invalid positive integer value: not-a-number/,
  );
});
