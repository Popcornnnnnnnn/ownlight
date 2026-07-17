#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import {
  commandExists,
  commandOutput,
  liveDataDir,
  liveDatabasePath,
  makeReporter,
  parseArgs,
  rootDir,
  sqliteInt,
  sqliteValue,
} from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_DOCTOR_STRICT === "1";
const reporter = makeReporter({ strict });
const databasePath = liveDatabasePath();
const dataDir = liveDataDir();
const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z");
const drillDir = path.resolve(args["out-dir"] ?? path.join(rootDir, ".tmp", "archive-drills", timestamp));

mkdirSync(drillDir, { recursive: true });

checkInputs();
const copiedDatabase = copyAndVerifyDatabase();
const mediaReport = checkMediaFiles();
const archiveConfig = checkArchiveConfig();
const pendingPromote = checkPendingPromoteReadiness();
writeReport({ copiedDatabase, mediaReport, archiveConfig, pendingPromote });

reporter.printAndExit();

function checkInputs() {
  if (!databasePath || !existsSync(databasePath)) {
    reporter.fail("live database", "live database is missing", databasePath ?? "DATABASE_URL missing");
  } else {
    reporter.pass("live database", "live database exists", databasePath);
  }

  if (!dataDir || !existsSync(dataDir)) {
    reporter.fail("data dir", "data directory is missing", dataDir ?? "PRIVATE_MOMENTS_DATA_DIR missing");
  } else {
    reporter.pass("data dir", "data directory exists", dataDir);
  }
}

function copyAndVerifyDatabase() {
  if (!databasePath || !existsSync(databasePath)) {
    return null;
  }

  const target = path.join(drillDir, "app.sqlite");
  copyFileSync(databasePath, target);
  const quickCheck = sqliteValue(target, "PRAGMA quick_check;");
  const counts = {
    posts: sqliteInt(target, "SELECT COUNT(*) FROM posts;"),
    media: sqliteInt(target, "SELECT COUNT(*) FROM media;"),
    checkInEntries: sqliteInt(target, "SELECT COUNT(*) FROM checkin_entries;"),
    serverChanges: sqliteInt(target, "SELECT COALESCE(MAX(version), 0) FROM server_changes;"),
  };

  if (quickCheck === "ok") {
    reporter.pass("database copy", "copied SQLite database passes quick_check", target);
  } else {
    reporter.fail("database copy", "copied SQLite database failed quick_check", quickCheck);
  }

  reporter.pass(
    "database copy counts",
    `posts=${counts.posts}, media=${counts.media}, checkIns=${counts.checkInEntries}, latestChange=${counts.serverChanges}`,
  );
  return { path: target, quickCheck, counts };
}

function checkMediaFiles() {
  if (!databasePath || !dataDir || !existsSync(databasePath)) {
    return null;
  }

  const rows = sqliteValue(
    databasePath,
    [
      "SELECT COALESCE(compressed_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(compressed_path, '') <> '';",
      "SELECT COALESCE(original_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(original_path, '') <> '';",
      "SELECT COALESCE(thumbnail_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(thumbnail_path, '') <> '';",
      "SELECT COALESCE(compressed_path, '') FROM checkin_media WHERE deleted_at IS NULL AND COALESCE(compressed_path, '') <> '';",
    ].join("\n"),
  )
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  const uniquePaths = [...new Set(rows)];
  const missing = [];
  for (const storedPath of uniquePaths) {
    const absolute = path.isAbsolute(storedPath) ? storedPath : path.join(dataDir, storedPath);
    if (!existsSync(absolute)) {
      missing.push(storedPath);
    }
  }

  if (missing.length === 0) {
    reporter.pass("media files", `${uniquePaths.length} referenced media file path(s) exist`);
  } else {
    reporter.warn("media files", `${missing.length} referenced media file path(s) are missing`, missing.slice(0, 5).join(", "));
  }

  return { referenced: uniquePaths.length, missing };
}

function checkArchiveConfig() {
  if (!dataDir) {
    return null;
  }

  const archiveConfigPath = path.join(dataDir, "archive", "archive-config.json");
  if (!existsSync(archiveConfigPath)) {
    reporter.warn("archive config", "archive-config.json is missing; configure Archive before relying on scheduled backups");
    return null;
  }

  const config = JSON.parse(readFileSync(archiveConfigPath, "utf8"));
  if (config.repositoryPath) {
    reporter.pass("archive repository path", config.repositoryPath);
  } else {
    reporter.warn("archive repository path", "repositoryPath is not configured");
  }

  if (config.keyFilePath) {
    reporter.pass("archive key path", config.keyFilePath);
  } else {
    reporter.warn("archive key path", "keyFilePath is not configured");
  }

  if (commandExists("restic")) {
    const restic = commandOutput("restic", ["version"]);
    reporter.pass("restic", restic.stdout.trim() || "restic is installed");
  } else {
    reporter.warn("restic", "restic is not on PATH; Archive backup/restore execution will be unavailable");
  }

  const pendingPromotePath = path.join(dataDir, "archive", "pending-promote.json");
  if (existsSync(pendingPromotePath)) {
    reporter.warn("pending promote", "pending-promote.json exists; finish, validate, or clear promote before treating the archive as normal", pendingPromotePath);
  } else {
    reporter.pass("pending promote", "no pending promote artifact");
  }

  return config;
}

function checkPendingPromoteReadiness() {
  if (!dataDir) {
    return null;
  }

  const pendingPromotePath = path.join(dataDir, "archive", "pending-promote.json");
  if (!existsSync(pendingPromotePath)) {
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(readFileSync(pendingPromotePath, "utf8"));
  } catch (error) {
    reporter.warn(
      "pending promote readiness",
      "pending-promote.json is malformed; clear it before the next promote drill",
      error instanceof Error ? error.message : String(error),
    );
    return {
      ready: false,
      reasons: ["malformed_instructions"],
    };
  }

  const restoredDataDir = typeof parsed.restoredDataDir === "string" ? parsed.restoredDataDir : null;
  const currentDataDir = typeof parsed.currentDataDir === "string" ? parsed.currentDataDir : null;
  const requiredEnv =
    parsed && typeof parsed.requiredEnv === "object" && parsed.requiredEnv !== null ? parsed.requiredEnv : {};
  const targetDataDir =
    typeof requiredEnv.PRIVATE_MOMENTS_DATA_DIR === "string" ? requiredEnv.PRIVATE_MOMENTS_DATA_DIR : null;
  const targetDatabaseUrl =
    typeof requiredEnv.DATABASE_URL === "string" ? requiredEnv.DATABASE_URL : null;
  const prePromoteBackup =
    parsed && typeof parsed.prePromoteBackup === "object" && parsed.prePromoteBackup !== null
      ? parsed.prePromoteBackup
      : {};
  const reasons = [];

  if (!restoredDataDir) {
    reasons.push("missing_restored_data_dir");
  } else {
    const restoredDatabase = path.join(restoredDataDir, "app.sqlite");
    const restoredManifest = path.join(restoredDataDir, "manifest.json");
    if (!existsSync(restoredDatabase) || !existsSync(restoredManifest)) {
      reasons.push("restored_data_invalid");
    }
  }

  if (currentDataDir && path.resolve(currentDataDir) !== path.resolve(dataDir)) {
    reasons.push("runtime_data_dir_changed_since_prepare");
  }

  if (targetDataDir && path.resolve(targetDataDir) === path.resolve(dataDir)) {
    reasons.push("already_switched_to_target_data_dir");
  }

  const liveDatabaseUrl = databasePath ? `file:${databasePath}` : null;
  if (targetDatabaseUrl && liveDatabaseUrl && targetDatabaseUrl === liveDatabaseUrl) {
    reasons.push("database_url_already_matches_target");
  }

  if (typeof prePromoteBackup.snapshotId !== "string" || !prePromoteBackup.snapshotId) {
    reasons.push("missing_pre_promote_snapshot");
  }

  if (reasons.length === 0) {
    reporter.pass(
      "pending promote readiness",
      "pending-promote handoff looks ready for a controlled stop-update-restart",
      pendingPromotePath,
    );
  } else {
    reporter.warn(
      "pending promote readiness",
      `pending-promote handoff is not ready: ${reasons.join(", ")}`,
      pendingPromotePath,
    );
  }

  return {
    ready: reasons.length === 0,
    reasons,
    restoredDataDir,
    currentDataDir,
    targetDataDir,
    targetDatabaseUrl,
  };
}

function writeReport(report) {
  const reportPath = path.join(drillDir, "report.json");
  writeFileSync(reportPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    rootDir,
    dataDir,
    databasePath,
    ...report,
  }, null, 2)}\n`);
  reporter.pass("drill report", "archive drill report written", reportPath);
}
