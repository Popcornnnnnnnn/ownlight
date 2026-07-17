import test from "node:test";
import assert from "node:assert/strict";

import {
  checkLocalArchiveDatabase,
  checkDeviceListing,
  parseArgs,
  runPreflight,
} from "./preflight-ios-device.mjs";

test("parseArgs reads value and flag arguments", () => {
  assert.deepEqual(
    parseArgs(["--server-url", "https://example.com", "--device", "wwz", "--strict"]),
    {
      "server-url": "https://example.com",
      device: "wwz",
      strict: "1",
    },
  );
});

test("runPreflight fails when live schema is older than expected", async () => {
  const lines = [];
  const result = await runPreflight({
    argv: ["--server-url", "https://example.com", "--device", "wwz"],
    env: {},
    out: { log: (line) => lines.push(line) },
    deps: {
      readRootEnvLocal: () => null,
      checkHealth: async () => ({ ok: true, value: { schemaVersion: 17 } }),
      readExpectedSchemaVersion: () => 18,
      checkLocalArchiveDatabase: () => [],
      checkDeviceListing: () => ({ level: "pass", name: "device", message: "wwz available" }),
    },
  });

  assert.equal(result.exitCode, 1);
  assert.equal(result.failures.length, 1);
  assert.match(lines[0], /\[FAIL\] schema: server schema 17 is older than expected 18/);
  assert.match(lines[1], /\[PASS\] server: https:\/\/example\.com is reachable/);
});

test("runPreflight fails when server is unreachable", async () => {
  const result = await runPreflight({
    argv: [],
    env: { PRIVATE_MOMENTS_DEVICE_SERVER_URL: "http://127.0.0.1:3210" },
    out: { log: () => {} },
    deps: {
      readRootEnvLocal: () => null,
      checkHealth: async () => ({ ok: false, error: "connect ECONNREFUSED" }),
      readExpectedSchemaVersion: () => 18,
      checkLocalArchiveDatabase: () => [],
      checkDeviceListing: () => ({ level: "pass", name: "device", message: "wwz available" }),
    },
  });

  assert.equal(result.exitCode, 1);
  assert.equal(result.failures.length, 1);
  assert.equal(result.failures[0].name, "server");
  assert.match(result.failures[0].message, /ECONNREFUSED/);
});

test("runPreflight reports warnings but passes when strict mode is off", async () => {
  const lines = [];
  const result = await runPreflight({
    argv: [],
    env: { PRIVATE_MOMENTS_DEVICE_NAME: "wwz" },
    out: { log: (line) => lines.push(line) },
    deps: {
      readRootEnvLocal: () => null,
      checkHealth: async () => ({ ok: true, value: { schemaVersion: 18 } }),
      readExpectedSchemaVersion: () => 18,
      checkLocalArchiveDatabase: () => [
        { level: "warn", name: "server sync queue", message: "2 unapplied server sync operation(s)" },
      ],
      checkDeviceListing: () => ({ level: "warn", name: "device", message: "wwz was not found in devicectl output" }),
    },
  });

  assert.equal(result.exitCode, 0);
  assert.equal(result.warnings.length, 2);
  assert.match(lines.at(-1), /PRIVATE_MOMENTS_PREFLIGHT_STRICT=1/);
});

test("runPreflight fails on warnings when strict mode is enabled", async () => {
  const result = await runPreflight({
    argv: ["--strict"],
    env: {},
    out: { log: () => {} },
    deps: {
      readRootEnvLocal: () => null,
      checkHealth: async () => ({ ok: true, value: { schemaVersion: 18 } }),
      readExpectedSchemaVersion: () => 18,
      checkLocalArchiveDatabase: () => [
        { level: "warn", name: "server media", message: "1 media and 0 check-in media item(s) not uploaded" },
      ],
      checkDeviceListing: () => ({ level: "pass", name: "device", message: "wwz available" }),
    },
  });

  assert.equal(result.exitCode, 1);
  assert.equal(result.failures.length, 0);
  assert.equal(result.warnings.length, 1);
});

test("checkLocalArchiveDatabase surfaces queue and media warnings from sqlite results", () => {
  const results = checkLocalArchiveDatabase("/tmp/project", {
    liveDatabasePath: () => "/tmp/project/server/dev.db",
    fileExists: () => true,
    hasCommand: () => true,
    queryInteger: (_dbPath, sql) => {
      if (sql.includes("maintenance_jobs WHERE status = 'running'")) {
        return 1;
      }
      if (sql.includes("unixepoch('now', '-24 hours')")) {
        return 3;
      }
      if (sql.includes("rejected_at IS NOT NULL")) {
        return 4;
      }
      if (sql.includes("applied_at IS NULL")) {
        return 2;
      }
      if (sql.includes("FROM media")) {
        return 4;
      }
      if (sql.includes("FROM checkin_media")) {
        return 1;
      }
      return 0;
    },
    queryString: () => "",
  });

  assert.deepEqual(
    results.map((item) => [item.name, item.level]),
    [
      ["maintenance", "warn"],
      ["server sync queue", "warn"],
      ["server rejected ops", "warn"],
      ["server media", "warn"],
      ["last backup", "warn"],
    ],
  );
  assert.match(results[3].message, /4 media and 1 check-in media item/);
});

test("checkLocalArchiveDatabase does not warn for historical-only rejected sync operations", () => {
  const results = checkLocalArchiveDatabase("/tmp/project", {
    liveDatabasePath: () => "/tmp/project/server/dev.db",
    fileExists: () => true,
    hasCommand: () => true,
    queryInteger: (_dbPath, sql) => {
      if (sql.includes("unixepoch('now', '-24 hours')")) {
        return 0;
      }
      if (sql.includes("rejected_at IS NOT NULL")) {
        return 3;
      }
      return 0;
    },
    queryString: () => "succeeded:1777985069051",
  });

  const rejectedCheck = results.find((item) => item.name === "server rejected ops");
  assert.equal(rejectedCheck.level, "pass");
  assert.match(rejectedCheck.message, /3 historical retained/);
});

test("checkDeviceListing warns when the paired iPhone is missing", () => {
  const result = checkDeviceListing("wwz", "/tmp/project", {
    hasCommand: () => true,
    run: () => ({
      status: 0,
      stdout: "Other iPhone (available)\nAnother Device (paired)",
    }),
  });

  assert.equal(result.level, "warn");
  assert.match(result.message, /wwz was not found/);
});
