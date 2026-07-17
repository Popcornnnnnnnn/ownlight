const DEFAULT_MAX_FAILURES = 8;
const DEFAULT_WINDOW_MS = 15 * 60 * 1000;

interface LoginRateLimitOptions {
  maxFailures?: number;
  windowMs?: number;
  now?: () => number;
}

interface LoginFailureBucket {
  failures: number;
  resetAt: number;
}

export interface LoginRateLimitKey {
  remoteAddress: string;
  platform: string;
  deviceKey?: string;
  deviceName: string;
}

export class LoginRateLimiter {
  private readonly maxFailures: number;
  private readonly windowMs: number;
  private readonly now: () => number;
  private readonly buckets = new Map<string, LoginFailureBucket>();

  constructor(options: LoginRateLimitOptions = {}) {
    this.maxFailures = options.maxFailures ?? DEFAULT_MAX_FAILURES;
    this.windowMs = options.windowMs ?? DEFAULT_WINDOW_MS;
    this.now = options.now ?? Date.now;
  }

  retryAfterSeconds(key: LoginRateLimitKey): number | null {
    const now = this.now();
    const blockedForMs = this.keysFor(key).reduce((blockedFor, bucketKey) => {
      const bucket = this.activeBucket(bucketKey, now);
      if (!bucket || bucket.failures < this.maxFailures) {
        return blockedFor;
      }

      return Math.max(blockedFor, bucket.resetAt - now);
    }, 0);

    return blockedForMs > 0 ? Math.ceil(blockedForMs / 1000) : null;
  }

  recordFailure(key: LoginRateLimitKey): void {
    const now = this.now();
    for (const bucketKey of this.keysFor(key)) {
      const bucket = this.activeBucket(bucketKey, now);
      if (!bucket) {
        this.buckets.set(bucketKey, {
          failures: 1,
          resetAt: now + this.windowMs,
        });
        continue;
      }

      bucket.failures += 1;
    }
  }

  reset(key: LoginRateLimitKey): void {
    for (const bucketKey of this.keysFor(key)) {
      this.buckets.delete(bucketKey);
    }
  }

  private activeBucket(bucketKey: string, now: number): LoginFailureBucket | null {
    const bucket = this.buckets.get(bucketKey);
    if (!bucket) {
      return null;
    }

    if (bucket.resetAt <= now) {
      this.buckets.delete(bucketKey);
      return null;
    }

    return bucket;
  }

  private keysFor(key: LoginRateLimitKey): string[] {
    const deviceIdentity = key.deviceKey?.trim() || key.deviceName.trim();
    return [
      `ip:${key.remoteAddress || "unknown"}`,
      `device:${key.platform}:${deviceIdentity || "unknown"}`,
    ];
  }
}
