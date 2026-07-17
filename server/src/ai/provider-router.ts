import type { AISummaryConfig } from "../config/app-config.js";

export type AIProviderRole = "primary" | "fallback";
export type AIProviderResponseFormat = "json_schema" | "json_object";
export type AIPrimaryStatus = "unknown" | "healthy" | "down";

export interface AIResolvedProvider {
  role: AIProviderRole;
  provider: string;
  baseUrl: string;
  apiKey?: string;
  model: string;
  responseFormat: AIProviderResponseFormat;
}

export interface AIProviderRequest {
  inputChars: number;
  preferPro?: boolean;
}

export interface AIProviderExecutionResult<T> {
  value: T;
  source: AIResolvedProvider;
}

interface AIProviderRouterOptions {
  fetch?: typeof fetch;
  now?: () => number;
}

const routers = new WeakMap<AISummaryConfig, AIProviderRouter>();
const DEFAULT_HEALTHY_PROBE_INTERVAL_MS = 60_000;
const DEFAULT_DOWN_PROBE_INTERVAL_MS = 15_000;
const DEFAULT_HEALTH_TIMEOUT_MS = 1_000;
const DEFAULT_HEALTH_STALE_MS = 120_000;
const DEFAULT_LONG_CONTENT_THRESHOLD_CHARS = 8_000;

export function getAIProviderRouter(config: AISummaryConfig): AIProviderRouter {
  const existing = routers.get(config);
  if (existing) {
    return existing;
  }

  const router = new AIProviderRouter(config);
  routers.set(config, router);
  return router;
}

export async function executeWithConfiguredAIProvider<T>(
  config: AISummaryConfig,
  request: AIProviderRequest,
  operation: (provider: AIResolvedProvider) => Promise<T>,
): Promise<AIProviderExecutionResult<T>> {
  return executeWithAIProvider(getAIProviderRouter(config), request, operation);
}

export async function executeWithAIProvider<T>(
  router: AIProviderRouter,
  request: AIProviderRequest,
  operation: (provider: AIResolvedProvider) => Promise<T>,
): Promise<AIProviderExecutionResult<T>> {
  const selected = await router.selectProvider(request);

  try {
    return {
      value: await operation(selected),
      source: selected,
    };
  } catch (error) {
    if (selected.role !== "primary" || !router.hasFallback || !shouldFallbackAfterError(error)) {
      throw error;
    }

    router.markPrimaryDown();
    const fallback = router.fallbackProvider(request);
    return {
      value: await operation(fallback),
      source: fallback,
    };
  }
}

export class AIProviderRouter {
  private status: AIPrimaryStatus = "unknown";
  private lastProbeAt = 0;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private timer: NodeJS.Timeout | null = null;
  private inFlightProbe: Promise<AIPrimaryStatus> | null = null;

  constructor(
    readonly config: AISummaryConfig,
    options: AIProviderRouterOptions = {},
  ) {
    this.fetchImpl = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
  }

  get primaryStatus(): AIPrimaryStatus {
    return this.status;
  }

  get hasFallback(): boolean {
    return Boolean(this.config.fallback?.apiKey?.trim());
  }

  start(): void {
    if (!this.hasFallback || !this.config.primaryHealthUrl || this.timer) {
      return;
    }

    void this.probePrimary().finally(() => {
      this.scheduleNextProbe();
    });
  }

  stop(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  async selectProvider(request: AIProviderRequest): Promise<AIResolvedProvider> {
    if (!this.hasFallback) {
      return this.primaryProvider();
    }

    if (this.status === "down") {
      return this.fallbackProvider(request);
    }

    if (this.status === "unknown" || this.isStatusStale()) {
      const status = await this.probePrimary();
      return status === "healthy" ? this.primaryProvider() : this.fallbackProvider(request);
    }

    return this.primaryProvider();
  }

  async probePrimary(): Promise<AIPrimaryStatus> {
    if (!this.config.primaryHealthUrl) {
      this.status = "healthy";
      this.lastProbeAt = this.now();
      return this.status;
    }

    if (this.inFlightProbe) {
      return this.inFlightProbe;
    }

    this.inFlightProbe = this.runPrimaryProbe().finally(() => {
      this.inFlightProbe = null;
    });
    return this.inFlightProbe;
  }

  markPrimaryDown(): void {
    this.status = this.config.primaryHealthUrl ? "down" : "unknown";
    this.lastProbeAt = this.now();
  }

  primaryProvider(): AIResolvedProvider {
    return {
      role: "primary",
      provider: this.config.provider,
      baseUrl: this.config.baseUrl,
      apiKey: this.config.apiKey,
      model: this.config.model,
      responseFormat: "json_schema",
    };
  }

  fallbackProvider(request: AIProviderRequest): AIResolvedProvider {
    if (!this.config.fallback?.apiKey?.trim()) {
      return this.primaryProvider();
    }

    return {
      role: "fallback",
      provider: this.config.fallback.provider,
      baseUrl: this.config.fallback.baseUrl,
      apiKey: this.config.fallback.apiKey,
      model: request.preferPro || request.inputChars > this.longContentThresholdChars
        ? this.config.fallback.proModel
        : this.config.fallback.fastModel,
      responseFormat: "json_object",
    };
  }

  private scheduleNextProbe(): void {
    if (!this.hasFallback || !this.config.primaryHealthUrl) {
      return;
    }

    const delay = this.status === "down"
      ? this.primaryHealthDownIntervalMs
      : this.primaryHealthHealthyIntervalMs;
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.probePrimary().finally(() => {
        this.scheduleNextProbe();
      });
    }, delay);
    this.timer.unref();
  }

  private async runPrimaryProbe(): Promise<AIPrimaryStatus> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.primaryHealthTimeoutMs);

    try {
      const response = await this.fetchImpl(this.config.primaryHealthUrl ?? "", {
        method: "GET",
        signal: controller.signal,
      });
      this.status = response.ok ? "healthy" : "down";
    } catch {
      this.status = "down";
    } finally {
      clearTimeout(timeout);
      this.lastProbeAt = this.now();
    }

    return this.status;
  }

  private isStatusStale(): boolean {
    return this.now() - this.lastProbeAt > this.primaryHealthStaleMs;
  }

  private get primaryHealthHealthyIntervalMs(): number {
    return this.config.primaryHealthHealthyIntervalMs ?? DEFAULT_HEALTHY_PROBE_INTERVAL_MS;
  }

  private get primaryHealthDownIntervalMs(): number {
    return this.config.primaryHealthDownIntervalMs ?? DEFAULT_DOWN_PROBE_INTERVAL_MS;
  }

  private get primaryHealthTimeoutMs(): number {
    return this.config.primaryHealthTimeoutMs ?? DEFAULT_HEALTH_TIMEOUT_MS;
  }

  private get primaryHealthStaleMs(): number {
    return this.config.primaryHealthStaleMs ?? DEFAULT_HEALTH_STALE_MS;
  }

  private get longContentThresholdChars(): number {
    return this.config.longContentThresholdChars ?? DEFAULT_LONG_CONTENT_THRESHOLD_CHARS;
  }
}

export function shouldFallbackAfterError(error: unknown): boolean {
  const code = errorCode(error);
  if (!code) {
    return false;
  }

  if (
    code === "provider_timeout" ||
    code === "provider_request_failed" ||
    code === "tag_provider_timeout" ||
    code === "tag_provider_failed" ||
    code === "audio_input_timeout" ||
    code === "audio_input_failed"
  ) {
    return true;
  }

  const match = code.match(/^(provider|tag_provider|audio_input)_http_(\d+)$/);
  if (!match) {
    return false;
  }

  const status = Number(match[2]);
  return status === 429 || (status >= 500 && status <= 599);
}

function errorCode(error: unknown): string | null {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
  )
    ? error.code
    : null;
}
