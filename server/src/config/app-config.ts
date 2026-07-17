import path from "node:path";
import { homedir } from "node:os";

export const SERVER_VERSION = "0.1.0";
export const SCHEMA_VERSION = 19;

export interface AppConfig {
  host: string;
  port: number;
  logLevel: string;
  dataDir: string;
  databaseUrl: string;
  initialPassword?: string;
  aiSummary: AISummaryConfig;
}

export interface AISummaryConfig {
  provider: string;
  baseUrl: string;
  apiKey?: string;
  model: string;
  fallback?: AISummaryFallbackConfig;
  primaryHealthUrl?: string;
  primaryHealthHealthyIntervalMs?: number;
  primaryHealthDownIntervalMs?: number;
  primaryHealthTimeoutMs?: number;
  primaryHealthStaleMs?: number;
  longContentThresholdChars?: number;
  transcriptionProvider: string;
  transcriptionModel: string;
  localTranscriptionPythonPath: string;
  localTranscriptionScriptPath: string;
  localTranscriptionModel: string;
  localTranscriptionTimeoutMs: number;
  timeoutMs: number;
}

export interface AISummaryFallbackConfig {
  provider: string;
  baseUrl: string;
  apiKey?: string;
  fastModel: string;
  proModel: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const dataDir = path.resolve(
    env.PRIVATE_MOMENTS_DATA_DIR ??
      path.join(homedir(), "Library", "Application Support", "PrivateMoments"),
  );

  return {
    host: env.HOST ?? "127.0.0.1",
    port: parsePort(env.PORT),
    logLevel: env.LOG_LEVEL ?? "info",
    dataDir,
    databaseUrl: env.DATABASE_URL ?? `file:${path.join(dataDir, "app.sqlite")}`,
    initialPassword: env.PRIVATE_MOMENTS_INITIAL_PASSWORD,
    aiSummary: {
      provider: env.AI_SUMMARY_PROVIDER ?? "openai",
      baseUrl: trimTrailingSlash(env.AI_SUMMARY_BASE_URL ?? "https://api.openai.com/v1"),
      apiKey: env.AI_SUMMARY_API_KEY,
      model: env.AI_SUMMARY_MODEL ?? "gpt-4o-mini",
      fallback: loadFallbackConfig(env),
      primaryHealthUrl: env.AI_SUMMARY_PRIMARY_HEALTH_URL,
      primaryHealthHealthyIntervalMs: parsePositiveInteger(env.AI_SUMMARY_PRIMARY_HEALTHY_INTERVAL_MS, 60_000),
      primaryHealthDownIntervalMs: parsePositiveInteger(env.AI_SUMMARY_PRIMARY_DOWN_INTERVAL_MS, 15_000),
      primaryHealthTimeoutMs: parsePositiveInteger(env.AI_SUMMARY_PRIMARY_HEALTH_TIMEOUT_MS, 1_000),
      primaryHealthStaleMs: parsePositiveInteger(env.AI_SUMMARY_PRIMARY_HEALTH_STALE_MS, 120_000),
      longContentThresholdChars: parsePositiveInteger(env.AI_SUMMARY_LONG_CONTENT_THRESHOLD_CHARS, 8_000),
      transcriptionProvider: env.AI_TRANSCRIPTION_PROVIDER ?? "local",
      transcriptionModel: env.AI_TRANSCRIPTION_MODEL ?? "gpt-4o-mini-transcribe",
      localTranscriptionPythonPath: path.resolve(
        env.AI_LOCAL_TRANSCRIPTION_PYTHON ?? path.join(process.cwd(), ".venv/bin/python"),
      ),
      localTranscriptionScriptPath: path.resolve(
        env.AI_LOCAL_TRANSCRIPTION_SCRIPT ?? path.join(process.cwd(), "scripts/local-transcribe.py"),
      ),
      localTranscriptionModel: env.AI_LOCAL_TRANSCRIPTION_MODEL ?? "mlx-community/whisper-turbo",
      localTranscriptionTimeoutMs: parsePositiveInteger(env.AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS, 600_000),
      timeoutMs: parsePositiveInteger(env.AI_SUMMARY_TIMEOUT_MS, 60_000),
    },
  };
}

function loadFallbackConfig(env: NodeJS.ProcessEnv): AISummaryFallbackConfig | undefined {
  if (!env.AI_SUMMARY_FALLBACK_API_KEY?.trim()) {
    return undefined;
  }

  return {
    provider: env.AI_SUMMARY_FALLBACK_PROVIDER ?? "deepseek",
    baseUrl: trimTrailingSlash(env.AI_SUMMARY_FALLBACK_BASE_URL ?? "https://api.deepseek.com"),
    apiKey: env.AI_SUMMARY_FALLBACK_API_KEY,
    fastModel: env.AI_SUMMARY_FALLBACK_FAST_MODEL ?? "deepseek-v4-flash",
    proModel: env.AI_SUMMARY_FALLBACK_PRO_MODEL ?? "deepseek-v4-pro",
  };
}

function parsePort(value: string | undefined): number {
  if (!value) {
    return 3210;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid PORT value: ${value}`);
  }

  return parsed;
}

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`Invalid positive integer value: ${value}`);
  }

  return parsed;
}

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
