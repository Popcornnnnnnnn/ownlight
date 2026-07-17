import path from "node:path";
import { fileURLToPath } from "node:url";

import type { GatewayConfig } from "./types.js";

export const DEFAULT_GATEWAY_MODEL = "mlx-community/whisper-large-v3-turbo";

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3322;
const DEFAULT_TIMEOUT_MS = 600_000;
const DEFAULT_MAX_FILE_BYTES = 50 * 1024 * 1024;

function packageRoot(): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
}

function repoRoot(): string {
  const root = packageRoot();
  return path.basename(root) === "dist" ? path.resolve(root, "..", "..") : path.resolve(root, "..");
}

function parseIntEnv(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function resolveFromRepoRoot(value: string | undefined, fallback: string): string {
  const candidate = value?.trim() || fallback;
  return path.isAbsolute(candidate) ? candidate : path.resolve(repoRoot(), candidate);
}

export function loadGatewayConfig(env: NodeJS.ProcessEnv = process.env): GatewayConfig {
  return {
    host: env.TRANSCRIPTION_GATEWAY_HOST?.trim() || DEFAULT_HOST,
    port: parseIntEnv(env.TRANSCRIPTION_GATEWAY_PORT, DEFAULT_PORT),
    token: env.TRANSCRIPTION_GATEWAY_TOKEN?.trim() || "",
    defaultModel: env.TRANSCRIPTION_GATEWAY_MODEL?.trim() || DEFAULT_GATEWAY_MODEL,
    pythonPath: resolveFromRepoRoot(env.TRANSCRIPTION_GATEWAY_PYTHON, "server/.venv/bin/python"),
    scriptPath: resolveFromRepoRoot(env.TRANSCRIPTION_GATEWAY_SCRIPT, "server/scripts/local-transcribe.py"),
    timeoutMs: parseIntEnv(env.TRANSCRIPTION_GATEWAY_TIMEOUT_MS, DEFAULT_TIMEOUT_MS),
    maxFileBytes: parseIntEnv(env.TRANSCRIPTION_GATEWAY_MAX_FILE_BYTES, DEFAULT_MAX_FILE_BYTES)
  };
}
