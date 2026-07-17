import assert from "node:assert/strict";
import { test } from "node:test";

import { buildGatewayApp } from "./app.js";
import type { GatewayConfig, TranscriptionRequest } from "./types.js";

function testConfig(): GatewayConfig {
  return {
    host: "127.0.0.1",
    port: 3322,
    token: "secret-token",
    defaultModel: "mlx-community/whisper-large-v3-turbo",
    pythonPath: "/tmp/python",
    scriptPath: "/tmp/local-transcribe.py",
    timeoutMs: 1_000,
    maxFileBytes: 2_000_000
  };
}

function multipartBody(
  boundary: string,
  parts: Array<{ name: string; value: string } | { name: string; filename: string; contentType: string; value: string }>
): Buffer {
  const chunks: Buffer[] = [];
  for (const part of parts) {
    chunks.push(Buffer.from(`--${boundary}\r\n`));
    if ("filename" in part) {
      chunks.push(
        Buffer.from(
          `Content-Disposition: form-data; name="${part.name}"; filename="${part.filename}"\r\n` +
            `Content-Type: ${part.contentType}\r\n\r\n`
        )
      );
    } else {
      chunks.push(Buffer.from(`Content-Disposition: form-data; name="${part.name}"\r\n\r\n`));
    }
    chunks.push(Buffer.from(part.value));
    chunks.push(Buffer.from("\r\n"));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return Buffer.concat(chunks);
}

function authHeaders(boundary?: string): Record<string, string> {
  return {
    authorization: "Bearer secret-token",
    ...(boundary ? { "content-type": `multipart/form-data; boundary=${boundary}` } : {})
  };
}

async function waitFor(condition: () => boolean): Promise<void> {
  const deadline = Date.now() + 1_000;
  while (Date.now() < deadline) {
    if (condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("Timed out waiting for test condition.");
}

function deferred<T>(): { promise: Promise<T>; resolve: (value: T | PromiseLike<T>) => void } {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((innerResolve) => {
    resolve = innerResolve;
  });
  return { promise, resolve };
}

test("GET /health returns service and model status", async () => {
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async () => ({ text: "unused", model: "unused" })
  });

  const response = await app.inject({
    method: "GET",
    url: "/health",
    headers: authHeaders()
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    ok: true,
    service: "private-moments-transcription-gateway",
    provider: "local-gateway",
    engine: "mlx-whisper",
    status: "ready",
    model: "mlx-community/whisper-large-v3-turbo",
    concurrency: 1
  });
});

test("GET /v1/models exposes the default model for OpenAI-compatible clients", async () => {
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async () => ({ text: "unused", model: "unused" })
  });

  const response = await app.inject({
    method: "GET",
    url: "/v1/models",
    headers: authHeaders()
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    object: "list",
    data: [
      {
        id: "mlx-community/whisper-large-v3-turbo",
        object: "model",
        owned_by: "local-gateway"
      }
    ]
  });
});

test("requests without the expected bearer token are rejected", async () => {
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async () => ({ text: "unused", model: "unused" })
  });

  const missing = await app.inject({ method: "GET", url: "/health" });
  const wrong = await app.inject({
    method: "GET",
    url: "/health",
    headers: { authorization: "Bearer wrong-token" }
  });

  assert.equal(missing.statusCode, 401);
  assert.equal(wrong.statusCode, 401);
});

test("POST /v1/audio/transcriptions accepts OpenAI-compatible multipart uploads", async () => {
  let captured: TranscriptionRequest | undefined;
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async (request) => {
      captured = request;
      return {
        text: "今天讨论本地转录网关。",
        language: "zh",
        segments: [{ start: 0, end: 1.2, text: "今天讨论本地转录网关。" }],
        model: request.model
      };
    }
  });
  const boundary = "private-moments-boundary";
  const payload = multipartBody(boundary, [
    { name: "model", value: "mlx-community/whisper-turbo" },
    { name: "language", value: "zh" },
    { name: "response_format", value: "json" },
    { name: "file", filename: "note.m4a", contentType: "audio/mp4", value: "audio-bytes" }
  ]);

  const response = await app.inject({
    method: "POST",
    url: "/v1/audio/transcriptions",
    headers: authHeaders(boundary),
    payload
  });

  assert.equal(response.statusCode, 200);
  assert.equal(captured?.model, "mlx-community/whisper-turbo");
  assert.equal(captured?.language, "zh");
  assert.equal(captured?.fileName, "note.m4a");
  assert.equal(captured?.mimeType, "audio/mp4");
  assert.deepEqual(response.json(), {
    text: "今天讨论本地转录网关。",
    language: "zh",
    segments: [{ start: 0, end: 1.2, text: "今天讨论本地转录网关。" }],
    model: "mlx-community/whisper-turbo",
    provider: "local-gateway"
  });
});

test("empty transcription output returns a clear failed response", async () => {
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async () => ({ text: "   ", model: "mlx-community/whisper-large-v3-turbo" })
  });
  const boundary = "empty-boundary";
  const payload = multipartBody(boundary, [
    { name: "file", filename: "empty.m4a", contentType: "audio/mp4", value: "audio-bytes" }
  ]);

  const response = await app.inject({
    method: "POST",
    url: "/v1/audio/transcriptions",
    headers: authHeaders(boundary),
    payload
  });

  assert.equal(response.statusCode, 422);
  assert.equal(response.json().error, "empty_transcript");
});

test("transcription requests are serialized with single concurrency", async () => {
  const started: string[] = [];
  const releaseFirst = deferred<void>();
  const firstFinished = deferred<void>();
  let callCount = 0;
  const app = buildGatewayApp({
    config: testConfig(),
    transcribe: async (request) => {
      callCount += 1;
      started.push(request.fileName);
      if (callCount === 1) {
        await releaseFirst.promise;
        firstFinished.resolve();
      }
      return { text: `transcript ${request.fileName}`, model: request.model };
    }
  });

  const firstBoundary = "first-boundary";
  const secondBoundary = "second-boundary";
  const first = app.inject({
    method: "POST",
    url: "/v1/audio/transcriptions",
    headers: authHeaders(firstBoundary),
    payload: multipartBody(firstBoundary, [
      { name: "file", filename: "first.m4a", contentType: "audio/mp4", value: "first" }
    ])
  });
  await waitFor(() => started.length === 1);
  const second = app.inject({
    method: "POST",
    url: "/v1/audio/transcriptions",
    headers: authHeaders(secondBoundary),
    payload: multipartBody(secondBoundary, [
      { name: "file", filename: "second.m4a", contentType: "audio/mp4", value: "second" }
    ])
  });
  await new Promise((resolve) => setTimeout(resolve, 25));

  assert.deepEqual(started, ["first.m4a"]);
  releaseFirst.resolve();
  await firstFinished.promise;
  const responses = await Promise.all([first, second]);

  assert.deepEqual(started, ["first.m4a", "second.m4a"]);
  assert.equal(responses[0].statusCode, 200);
  assert.equal(responses[1].statusCode, 200);
});
