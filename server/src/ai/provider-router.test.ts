import assert from "node:assert/strict";
import test from "node:test";

import type { AISummaryConfig } from "../config/app-config.js";
import { AISummaryProviderError } from "./media-summary.js";
import { AIProviderRouter, executeWithAIProvider } from "./provider-router.js";

function testConfig(): AISummaryConfig {
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

test("AIProviderRouter uses fallback while primary is down and automatically switches back after recovery", async () => {
  let primaryHealthy = false;
  const router = new AIProviderRouter(testConfig(), {
    fetch: async () => new Response(null, { status: primaryHealthy ? 200 : 503 }),
  });

  await router.probePrimary();
  assert.equal(router.primaryStatus, "down");
  assert.equal((await router.selectProvider({ inputChars: 100 })).provider, "deepseek");

  primaryHealthy = true;
  await router.probePrimary();
  const selected = await router.selectProvider({ inputChars: 100 });

  assert.equal(router.primaryStatus, "healthy");
  assert.equal(selected.provider, "openai");
  assert.equal(selected.model, "gpt-5.5");
});

test("executeWithAIProvider falls back on transient primary errors without permanently disabling primary", async () => {
  const router = new AIProviderRouter(testConfig(), {
    fetch: async () => new Response(null, { status: 200 }),
  });
  await router.probePrimary();

  const calls: string[] = [];
  const result = await executeWithAIProvider(
    router,
    { inputChars: 100 },
    async (provider) => {
      calls.push(provider.provider);
      if (provider.role === "primary") {
        throw new AISummaryProviderError("provider_timeout", "primary timed out");
      }
      return "fallback-ok";
    },
  );

  assert.deepEqual(calls, ["openai", "deepseek"]);
  assert.equal(result.value, "fallback-ok");
  assert.equal(result.source.provider, "deepseek");
  assert.equal(router.primaryStatus, "down");

  await router.probePrimary();
  assert.equal((await router.selectProvider({ inputChars: 100 })).provider, "openai");
});

test("executeWithAIProvider does not fall back on non-transient primary errors", async () => {
  const router = new AIProviderRouter(testConfig(), {
    fetch: async () => new Response(null, { status: 200 }),
  });
  await router.probePrimary();

  await assert.rejects(
    executeWithAIProvider(
      router,
      { inputChars: 100 },
      async () => {
        throw new AISummaryProviderError("provider_http_401", "bad key");
      },
    ),
    (error: unknown) =>
      error instanceof AISummaryProviderError && error.code === "provider_http_401",
  );
});

test("executeWithAIProvider does not keep fallback pinned without a health URL", async () => {
  const config = {
    ...testConfig(),
    primaryHealthUrl: undefined,
  };
  const router = new AIProviderRouter(config);

  const firstCalls: string[] = [];
  await executeWithAIProvider(
    router,
    { inputChars: 100 },
    async (provider) => {
      firstCalls.push(provider.provider);
      if (provider.role === "primary") {
        throw new AISummaryProviderError("provider_timeout", "primary timed out");
      }
      return "fallback-ok";
    },
  );

  const selected = await router.selectProvider({ inputChars: 100 });

  assert.deepEqual(firstCalls, ["openai", "deepseek"]);
  assert.equal(selected.provider, "openai");
});

test("AIProviderRouter chooses DeepSeek pro model for long content and weekly reviews", async () => {
  const router = new AIProviderRouter(testConfig(), {
    fetch: async () => new Response(null, { status: 503 }),
  });
  await router.probePrimary();

  assert.equal((await router.selectProvider({ inputChars: 200 })).model, "deepseek-v4-flash");
  assert.equal((await router.selectProvider({ inputChars: 8_001 })).model, "deepseek-v4-pro");
  assert.equal((await router.selectProvider({ inputChars: 200, preferPro: true })).model, "deepseek-v4-pro");
});
