#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export async function runPreflight({
  argv = [],
  env = process.env,
  out = console,
  deps = createSystemDeps(rootDir),
} = {}) {
  const args = parseArgs(argv);
  const cloudflareEndpoint = env.PRIVATE_MOMENTS_FALLBACK_SERVER_URL ?? deps.readRootEnvLocal("PRIVATE_MOMENTS_FALLBACK_SERVER_URL");
  const serverUrl = args["server-url"] ?? env.PRIVATE_MOMENTS_DEVICE_SERVER_URL ?? cloudflareEndpoint ?? "http://127.0.0.1:3210";
  const deviceName = args.device ?? env.PRIVATE_MOMENTS_DEVICE_NAME ?? "Your iPhone";
  const strict = env.PRIVATE_MOMENTS_PREFLIGHT_STRICT === "1" || args.strict === "1";

  const health = await deps.checkHealth(serverUrl);
  const checks = [];
  pushSchemaCheck(checks, health, deps.readExpectedSchemaVersion());
  checks.push(
    health.ok
      ? pass("server", `${serverUrl} is reachable`)
      : fail("server", `${serverUrl} is not reachable: ${health.error}`),
  );
  checks.push(...deps.checkLocalArchiveDatabase());
  checks.push(deps.checkDeviceListing(deviceName));

  const failures = checks.filter((check) => check.level === "fail");
  const warnings = checks.filter((check) => check.level === "warn");

  for (const check of checks) {
    out.log(formatCheck(check));
  }

  if (warnings.length > 0) {
    out.log("[INFO] warning(s) found. Set PRIVATE_MOMENTS_PREFLIGHT_STRICT=1 to fail on warnings.");
  }

  return {
    argv,
    serverUrl,
    deviceName,
    strict,
    checks,
    failures,
    warnings,
    exitCode: failures.length > 0 || (strict && warnings.length > 0) ? 1 : 0,
  };
}

export function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--")) {
      continue;
    }

    const key = value.slice(2);
    const next = values[index + 1];
    if (next && !next.startsWith("--")) {
      parsed[key] = next;
      index += 1;
    } else {
      parsed[key] = "1";
    }
  }
  return parsed;
}

export async function checkHealth(baseUrl) {
  try {
    const response = await fetch(`${baseUrl.replace(/\/$/, "")}/api/v1/health`, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) {
      return { ok: false, error: `HTTP ${response.status}` };
    }

    const value = await response.json();
    return { ok: true, value };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

export function readExpectedSchemaVersion(targetRootDir = rootDir) {
  const appConfigPath = path.join(targetRootDir, "server", "src", "config", "app-config.ts");
  if (!existsSync(appConfigPath)) {
    return null;
  }

  const match = readFileSync(appConfigPath, "utf8").match(/SCHEMA_VERSION\s*=\s*(\d+)/);
  return match ? Number(match[1]) : null;
}

export function checkLocalArchiveDatabase(targetRootDir = rootDir, deps = {}) {
  const {
    liveDatabasePath: getLiveDatabasePath = liveDatabasePath,
    fileExists = existsSync,
    hasCommand = commandExists,
    queryInteger = queryInt,
    queryString = queryText,
  } = deps;
  const databasePath = getLiveDatabasePath(targetRootDir);
  if (!databasePath) {
    return [warn("database", "DATABASE_URL was not found in server/.env; skipped local archive queue checks")];
  }

  if (!fileExists(databasePath)) {
    return [warn("database", `database file not found at ${databasePath}`)];
  }

  if (!hasCommand("sqlite3")) {
    return [warn("database", "sqlite3 is not available; skipped local archive queue checks")];
  }

  const runningJobs = queryInteger(databasePath, "SELECT COUNT(*) FROM maintenance_jobs WHERE status = 'running';", targetRootDir);
  const rejectedOps = queryInteger(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE rejected_at IS NOT NULL;", targetRootDir);
  const recentRejectedOps = queryInteger(
    databasePath,
    "SELECT COUNT(*) FROM sync_operations WHERE rejected_at IS NOT NULL AND rejected_at >= (unixepoch('now', '-24 hours') * 1000);",
    targetRootDir,
  );
  const pendingOps = queryInteger(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE applied_at IS NULL AND rejected_at IS NULL;", targetRootDir);
  const mediaNotUploaded = queryInteger(databasePath, "SELECT COUNT(*) FROM media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');", targetRootDir);
  const checkInMediaNotUploaded = queryInteger(databasePath, "SELECT COUNT(*) FROM checkin_media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');", targetRootDir);
  const latestBackup = queryString(databasePath, "SELECT COALESCE(status || ':' || created_at, '') FROM maintenance_jobs WHERE type = 'backup_create' ORDER BY created_at DESC LIMIT 1;", targetRootDir);

  const results = [
    runningJobs > 0
      ? warn("maintenance", `${runningJobs} maintenance job(s) are still running`)
      : pass("maintenance", "no running maintenance job"),
    pendingOps > 0
      ? warn("server sync queue", `${pendingOps} unapplied server sync operation(s)`)
      : pass("server sync queue", "no unapplied server sync operations"),
    recentRejectedOps > 0
      ? warn("server rejected ops", `${recentRejectedOps} rejected operation(s) in the last 24 hours; inspect Sync Health before install`)
      : pass(
          "server rejected ops",
          rejectedOps > 0
            ? `no recent rejected operations (${rejectedOps} historical retained)`
            : "no rejected operations",
        ),
    mediaNotUploaded + checkInMediaNotUploaded > 0
      ? warn("server media", `${mediaNotUploaded} media and ${checkInMediaNotUploaded} check-in media item(s) not uploaded`)
      : pass("server media", "all active server media rows are uploaded or deleted"),
  ];

  if (latestBackup) {
    results.push(pass("last backup", latestBackup));
  } else {
    results.push(warn("last backup", "no backup_create job found in the local archive database"));
  }

  return results;
}

export function liveDatabasePath(targetRootDir = rootDir) {
  const envPath = path.join(targetRootDir, "server", ".env");
  if (!existsSync(envPath)) {
    return null;
  }

  const env = readFileSync(envPath, "utf8");
  const match = env.match(/^DATABASE_URL=(.+)$/m);
  if (!match) {
    return null;
  }

  let value = match[1].trim().replace(/^["']|["']$/g, "");
  if (!value.startsWith("file:")) {
    return null;
  }

  value = value.slice("file:".length);
  return path.isAbsolute(value) ? value : path.resolve(targetRootDir, "server", value);
}

export function readRootEnvLocal(key, targetRootDir = rootDir) {
  const envLocalPath = path.join(targetRootDir, ".env.local");
  if (!existsSync(envLocalPath)) {
    return null;
  }

  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = readFileSync(envLocalPath, "utf8").match(new RegExp(`^${escapedKey}=(.+)$`, "m"));
  return match ? match[1].trim().replace(/^["']|["']$/g, "") : null;
}

export function queryInt(databasePath, sql, targetRootDir = rootDir) {
  const value = queryText(databasePath, sql, targetRootDir);
  return Number.parseInt(value, 10) || 0;
}

export function queryText(databasePath, sql, targetRootDir = rootDir) {
  const result = spawnSync("sqlite3", [databasePath, sql], {
    cwd: targetRootDir,
    encoding: "utf8",
    timeout: 10_000,
  });
  return result.status === 0 ? result.stdout.trim() : "";
}

export function checkDeviceListing(name, targetRootDir = rootDir, deps = {}) {
  const {
    hasCommand = commandExists,
    run = (command, args) => spawnSync(command, args, {
      cwd: targetRootDir,
      encoding: "utf8",
      timeout: 15_000,
    }),
  } = deps;

  if (!hasCommand("xcrun")) {
    return warn("device", "xcrun is not available; skipped paired iPhone visibility check");
  }

  const result = run("xcrun", ["devicectl", "list", "devices"]);
  if (result.status !== 0) {
    return warn("device", "devicectl device list failed; keep the iPhone unlocked and trusted before install");
  }

  const line = result.stdout
    .split("\n")
    .map((item) => item.trim())
    .find((item) => item.includes(name));

  if (!line) {
    return warn("device", `${name} was not found in devicectl output`);
  }

  return pass("device", line);
}

export function commandExists(command) {
  return spawnSync("sh", ["-lc", `command -v ${shellEscape(command)} >/dev/null 2>&1`], {
    stdio: "ignore",
  }).status === 0;
}

export function shellEscape(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

export function formatCheck(check) {
  const label = check.level === "pass" ? "PASS" : check.level === "warn" ? "WARN" : "FAIL";
  return `[${label}] ${check.name}: ${check.message}`;
}

export function pass(name, message) {
  return { level: "pass", name, message };
}

export function warn(name, message) {
  return { level: "warn", name, message };
}

export function fail(name, message) {
  return { level: "fail", name, message };
}

export function pushSchemaCheck(checks, health, expectedSchemaVersion) {
  if (!health.ok) {
    return;
  }

  if (expectedSchemaVersion !== null && health.value.schemaVersion < expectedSchemaVersion) {
    checks.push(
      fail(
        "schema",
        `server schema ${health.value.schemaVersion} is older than expected ${expectedSchemaVersion}`,
      ),
    );
    return;
  }

  checks.push(
    pass(
      "schema",
      expectedSchemaVersion === null
        ? `server schema ${health.value.schemaVersion}`
        : `server schema ${health.value.schemaVersion} matches expected ${expectedSchemaVersion}`,
    ),
  );
}

export function createSystemDeps(targetRootDir = rootDir) {
  return {
    checkHealth,
    readExpectedSchemaVersion: () => readExpectedSchemaVersion(targetRootDir),
    checkLocalArchiveDatabase: () => checkLocalArchiveDatabase(targetRootDir),
    checkDeviceListing: (deviceName) => checkDeviceListing(deviceName, targetRootDir),
    readRootEnvLocal: (key) => readRootEnvLocal(key, targetRootDir),
  };
}

async function main() {
  const result = await runPreflight({ argv: process.argv.slice(2) });
  if (result.exitCode !== 0) {
    process.exit(result.exitCode);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
