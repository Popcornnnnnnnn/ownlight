import assert from "node:assert/strict";
import test from "node:test";

import { LoginRateLimiter } from "./login-rate-limit.js";

test("LoginRateLimiter blocks repeated failures by IP and then expires", () => {
  let now = 1_000;
  const limiter = new LoginRateLimiter({
    maxFailures: 2,
    windowMs: 1_000,
    now: () => now,
  });
  const key = {
    remoteAddress: "203.0.113.10",
    platform: "ios",
    deviceKey: "device-1",
    deviceName: "phone",
  };

  assert.equal(limiter.retryAfterSeconds(key), null);
  limiter.recordFailure(key);
  assert.equal(limiter.retryAfterSeconds(key), null);
  limiter.recordFailure(key);
  assert.equal(limiter.retryAfterSeconds(key), 1);

  now += 1_001;
  assert.equal(limiter.retryAfterSeconds(key), null);
});

test("LoginRateLimiter resets both IP and device buckets after success", () => {
  const limiter = new LoginRateLimiter({
    maxFailures: 1,
    windowMs: 10_000,
    now: () => 1_000,
  });
  const key = {
    remoteAddress: "203.0.113.11",
    platform: "web",
    deviceName: "Mac Admin Browser",
  };

  limiter.recordFailure(key);
  assert.equal(limiter.retryAfterSeconds(key), 10);
  limiter.reset(key);
  assert.equal(limiter.retryAfterSeconds(key), null);
});
