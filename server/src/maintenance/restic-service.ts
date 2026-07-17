import { spawn } from "node:child_process";
import type { Dirent } from "node:fs";
import { copyFile, mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import type { PrismaClient } from "@prisma/client";

import { SCHEMA_VERSION, SERVER_VERSION, type AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import type { DataPaths } from "../storage/data-dir.js";
import { safeRegularFileStatsInside } from "../storage/file-safety.js";
import { isPathInsideOrEqual } from "../storage/path-safety.js";
import { ArchiveConfigService, type ArchiveConfig } from "./archive-config.js";

export interface ResticRepositoryState {
  configured: boolean;
  repositoryPath: string | null;
  keyFilePath: string | null;
  resticAvailable: boolean;
  resticVersion: string | null;
  initialized: boolean;
  schedule: ArchiveConfig["schedule"];
  updatedAt: string | null;
}

export interface ResticSnapshot {
  id: string;
  shortId: string;
  time: string;
  hostname: string | null;
  paths: string[];
  tags: string[];
}

export interface RestoreVerification {
  ok: boolean;
  dataDir: string;
  databasePath: string;
  manifestPath: string;
  mediaDir: string;
  schemaVersion: number | null;
  mediaTotal: number;
  missingMediaFiles: number;
  issues: string[];
}

export interface PendingPromoteState {
  instructionPath: string;
  createdAt: string | null;
  restoredDataDir: string | null;
  currentDataDir: string | null;
  prePromoteSnapshotId: string | null;
  prePromoteSnapshotDir: string | null;
  requiredEnv: {
    PRIVATE_MOMENTS_DATA_DIR: string | null;
    DATABASE_URL: string | null;
  };
  note: string | null;
  malformed: boolean;
  stale: boolean;
  staleReasons: string[];
}

export interface PendingPromoteReadinessCheck {
  id: string;
  label: string;
  status: "pass" | "fail";
  detail: string;
}

export interface PendingPromoteReadiness {
  checkedAt: string;
  ready: boolean;
  summary: string;
  checks: PendingPromoteReadinessCheck[];
}

interface ResticCommandResult {
  stdout: string;
  stderr: string;
}

export class ResticService {
  private readonly archiveConfig: ArchiveConfigService;

  constructor(
    private readonly config: AppConfig,
    private readonly paths: DataPaths,
    private readonly prisma: PrismaClient,
    private readonly fileLogger: FileLogger,
  ) {
    this.archiveConfig = new ArchiveConfigService(paths);
  }

  async getRepositoryState(): Promise<ResticRepositoryState> {
    const [config, restic] = await Promise.all([
      this.archiveConfig.read(),
      this.detectRestic(),
    ]);

    return {
      configured: Boolean(config.repositoryPath && config.keyFilePath),
      repositoryPath: config.repositoryPath,
      keyFilePath: config.keyFilePath,
      resticAvailable: restic.available,
      resticVersion: restic.version,
      initialized: await this.isRepositoryInitialized(config),
      schedule: config.schedule,
      updatedAt: config.updatedAt,
    };
  }

  async configureRepository(repositoryPath: string): Promise<ResticRepositoryState> {
    await this.archiveConfig.configureRepository(repositoryPath);
    await this.archiveConfig.ensureKeyFile();
    return this.getRepositoryState();
  }

  async updateSchedule(input: { enabled: boolean; timeOfDay: string }): Promise<ResticRepositoryState> {
    await this.archiveConfig.updateSchedule(input);
    return this.getRepositoryState();
  }

  async initializeRepository(): Promise<ResticRepositoryState> {
    const config = await this.requireConfiguredRepository();
    await this.archiveConfig.ensureKeyFile();

    if (await this.isRepositoryInitialized(config)) {
      return this.getRepositoryState();
    }

    await this.runRestic(config, ["init"]);
    await this.fileLogger.info("archive.repository_initialized", {
      repositoryPath: config.repositoryPath,
    });
    return this.getRepositoryState();
  }

  async createBackup(jobId: string, source: "manual" | "schedule" | "pre-promote"): Promise<Record<string, unknown>> {
    const config = await this.requireConfiguredRepository();
    await this.ensureReady(config);
    if (!(await this.isRepositoryInitialized(config))) {
      await this.runRestic(config, ["init"]);
    }

    const snapshotDir = await this.createSnapshotSource(jobId, source);
    const snapshotRoot = path.dirname(snapshotDir);
    try {
      const result = await this.runRestic(config, [
        "backup",
        "snapshot",
        "--tag",
        "private-moments",
        "--tag",
        source,
        "--json",
      ], undefined, snapshotRoot);
      const snapshotId = parseSnapshotId(result.stdout);
      if (source === "schedule") {
        await this.archiveConfig.markScheduleRun(new Date());
      }

      await this.fileLogger.info("archive.backup_completed", {
        source,
        snapshotId,
      });

      return {
        source,
        snapshotId,
        snapshotDir,
      };
    } finally {
      await rm(snapshotRoot, { force: true, recursive: true });
    }
  }

  async listSnapshots(): Promise<ResticSnapshot[]> {
    const config = await this.requireConfiguredRepository();
    await this.ensureReady(config);
    if (!(await this.isRepositoryInitialized(config))) {
      return [];
    }

    const result = await this.runRestic(config, ["snapshots", "--json"]);
    const parsed = JSON.parse(result.stdout || "[]") as unknown;
    if (!Array.isArray(parsed)) {
      return [];
    }

    return parsed.map(normalizeSnapshot).filter((snapshot): snapshot is ResticSnapshot => snapshot !== null);
  }

  async checkRepository(): Promise<Record<string, unknown>> {
    const config = await this.requireConfiguredRepository();
    await this.ensureReady(config);
    await this.runRestic(config, ["check"]);
    return {
      checkedAt: new Date().toISOString(),
      repositoryPath: config.repositoryPath,
    };
  }

  async getPendingPromoteState(): Promise<PendingPromoteState | null> {
    const instructionPath = path.join(this.paths.archiveDir, "pending-promote.json");
    if (!(await exists(instructionPath))) {
      return null;
    }

    try {
      const parsed = JSON.parse(await readFile(instructionPath, "utf8")) as unknown;
      const raw = asRecord(parsed);
      const requiredEnv = asRecord(raw?.requiredEnv);
      const prePromoteBackup = asRecord(raw?.prePromoteBackup);
      const restoredDataDir = asOptionalString(raw?.restoredDataDir);
      const currentDataDir = asOptionalString(raw?.currentDataDir);
      const targetDataDir = asOptionalString(requiredEnv?.PRIVATE_MOMENTS_DATA_DIR);
      const targetDatabaseUrl = asOptionalString(requiredEnv?.DATABASE_URL);
      const staleReasons = await this.collectPendingPromoteStaleReasons({
        restoredDataDir,
        currentDataDir,
        targetDataDir,
        targetDatabaseUrl,
      });

      return {
        instructionPath,
        createdAt: asOptionalString(raw?.createdAt),
        restoredDataDir,
        currentDataDir,
        prePromoteSnapshotId: asOptionalString(prePromoteBackup?.snapshotId),
        prePromoteSnapshotDir: asOptionalString(prePromoteBackup?.snapshotDir),
        requiredEnv: {
          PRIVATE_MOMENTS_DATA_DIR: targetDataDir,
          DATABASE_URL: targetDatabaseUrl,
        },
        note: asOptionalString(raw?.note),
        malformed: false,
        stale: staleReasons.length > 0,
        staleReasons,
      };
    } catch (error) {
      return {
        instructionPath,
        createdAt: null,
        restoredDataDir: null,
        currentDataDir: null,
        prePromoteSnapshotId: null,
        prePromoteSnapshotDir: null,
        requiredEnv: {
          PRIVATE_MOMENTS_DATA_DIR: null,
          DATABASE_URL: null,
        },
        note:
          error instanceof Error
            ? `Failed to parse pending promote instructions: ${error.message}`
            : "Failed to parse pending promote instructions",
        malformed: true,
        stale: true,
        staleReasons: ["malformed_instructions"],
      };
    }
  }

  async clearPendingPromoteState(): Promise<boolean> {
    const instructionPath = path.join(this.paths.archiveDir, "pending-promote.json");
    if (!(await exists(instructionPath))) {
      return false;
    }

    await rm(instructionPath, { force: true });
    await this.fileLogger.info("archive.pending_promote_cleared", {
      instructionPath,
    });
    return true;
  }

  async runPendingPromoteReadinessDrill(): Promise<PendingPromoteReadiness> {
    const checkedAt = new Date().toISOString();
    const checks: PendingPromoteReadinessCheck[] = [];
    const pendingPromote = await this.getPendingPromoteState();

    if (!pendingPromote) {
      checks.push({
        id: "pending_promote_exists",
        label: "Pending promote handoff",
        status: "fail",
        detail: "No pending-promote.json is present.",
      });
      return {
        checkedAt,
        ready: false,
        summary: "No pending promote handoff to validate",
        checks,
      };
    }

    checks.push({
      id: "pending_promote_exists",
      label: "Pending promote handoff",
      status: "pass",
      detail: pendingPromote.instructionPath,
    });

    checks.push({
      id: "pending_promote_not_stale",
      label: "Handoff state",
      status: pendingPromote.stale ? "fail" : "pass",
      detail: pendingPromote.stale
        ? pendingPromote.staleReasons.join(", ")
        : "pending-promote.json is active and not stale",
    });

    checks.push({
      id: "pre_promote_backup_present",
      label: "Pre-promote backup",
      status: pendingPromote.prePromoteSnapshotId ? "pass" : "fail",
      detail: pendingPromote.prePromoteSnapshotId
        ? pendingPromote.prePromoteSnapshotId
        : "Missing pre-promote snapshot metadata",
    });

    if (pendingPromote.restoredDataDir) {
      const verification = await this.verifyRestoredDataDir(pendingPromote.restoredDataDir);
      checks.push({
        id: "restored_data_verification",
        label: "Restored data verification",
        status: verification.ok ? "pass" : "fail",
        detail: verification.ok
          ? `verified ${verification.dataDir}`
          : verification.issues.length > 0
            ? verification.issues.join(", ")
            : `${verification.missingMediaFiles} missing media file reference(s)`,
      });
    } else {
      checks.push({
        id: "restored_data_verification",
        label: "Restored data verification",
        status: "fail",
        detail: "restoredDataDir is missing from pending-promote.json",
      });
    }

    const expectedTargetDataDir = pendingPromote.restoredDataDir
      ? path.resolve(pendingPromote.restoredDataDir)
      : null;
    const expectedDatabaseUrl = expectedTargetDataDir
      ? `file:${path.join(expectedTargetDataDir, "app.sqlite")}`
      : null;
    const envMatches = Boolean(
      expectedTargetDataDir &&
        expectedDatabaseUrl &&
        pendingPromote.requiredEnv.PRIVATE_MOMENTS_DATA_DIR &&
        path.resolve(pendingPromote.requiredEnv.PRIVATE_MOMENTS_DATA_DIR) === expectedTargetDataDir &&
        pendingPromote.requiredEnv.DATABASE_URL === expectedDatabaseUrl,
    );
    checks.push({
      id: "target_env_matches_restore",
      label: "Restart env handoff",
      status: envMatches ? "pass" : "fail",
      detail: envMatches
        ? `${pendingPromote.requiredEnv.PRIVATE_MOMENTS_DATA_DIR} / ${pendingPromote.requiredEnv.DATABASE_URL}`
        : "requiredEnv does not match the restored data directory",
    });

    const ready = checks.every((check) => check.status === "pass");
    return {
      checkedAt,
      ready,
      summary: ready
        ? "Ready for a controlled stop-update-restart promote"
        : "Pending promote handoff is not ready for restart",
      checks,
    };
  }

  async restoreSnapshot(snapshotId: string, restoreName?: string): Promise<Record<string, unknown>> {
    const config = await this.requireConfiguredRepository();
    await this.ensureReady(config);
    const safeSnapshotId = sanitizeToken(snapshotId);
    if (!safeSnapshotId) {
      throw new Error("snapshotId is required");
    }

    const target = await this.restoreTargetPath(safeSnapshotId, restoreName);
    await mkdir(target, { recursive: true });
    await this.runRestic(config, ["restore", safeSnapshotId, "--target", target]);

    const restoredDataDir = await findRestoredDataDir(target);
    const verification = await this.verifyRestoredDataDir(restoredDataDir);
    await this.fileLogger.info("archive.restore_completed", {
      snapshotId: safeSnapshotId,
      restorePath: restoredDataDir,
      ok: verification.ok,
      missingMediaFiles: verification.missingMediaFiles,
    });

    return {
      snapshotId: safeSnapshotId,
      restorePath: restoredDataDir,
      verification,
    };
  }

  async verifyRestoredDataDir(dataDir: string): Promise<RestoreVerification> {
    const resolvedDataDir = path.resolve(dataDir);
    const databasePath = path.join(resolvedDataDir, "app.sqlite");
    const manifestPath = path.join(resolvedDataDir, "manifest.json");
    const mediaDir = path.join(resolvedDataDir, "media");
    const issues: string[] = [];
    let schemaVersion: number | null = null;
    let mediaTotal = 0;
    let missingMediaFiles = 0;

    if (!(await exists(databasePath))) {
      issues.push("missing_database");
    }
    if (!(await exists(manifestPath))) {
      issues.push("missing_manifest");
    }
    if (!(await exists(mediaDir))) {
      issues.push("missing_media_directory");
    }

    if (await exists(databasePath)) {
      try {
        await querySqliteJson(databasePath, "SELECT COUNT(*) AS count FROM server_changes;");
        schemaVersion = await readManifestSchemaVersion(manifestPath);
      } catch {
        issues.push("database_unreadable");
      }

      try {
        const mediaRows = await querySqliteJson(
          databasePath,
          "SELECT compressed_path, original_path, thumbnail_path FROM media WHERE deleted_at IS NULL;",
        );
        const checkInMediaRows = await querySqliteJson(
          databasePath,
          "SELECT compressed_path FROM checkin_media WHERE deleted_at IS NULL;",
        );
        mediaTotal = mediaRows.length;
        for (const row of mediaRows) {
          for (const key of ["compressed_path", "original_path", "thumbnail_path"] as const) {
            const relative = (row as Record<string, unknown>)[key];
            if (typeof relative !== "string" || relative.length === 0) {
              continue;
            }
            const absolute = path.join(resolvedDataDir, relative);
            if (!(await safeRegularFileStatsInside(resolvedDataDir, absolute))) {
              missingMediaFiles += 1;
            }
          }
        }
        mediaTotal += checkInMediaRows.length;
        for (const row of checkInMediaRows) {
          const relative = (row as Record<string, unknown>).compressed_path;
          if (typeof relative !== "string" || relative.length === 0) {
            continue;
          }
          const absolute = path.join(resolvedDataDir, relative);
          if (!(await safeRegularFileStatsInside(resolvedDataDir, absolute))) {
            missingMediaFiles += 1;
          }
        }
      } catch {
        issues.push("media_reference_check_failed");
      }
    }

    return {
      ok: issues.length === 0 && missingMediaFiles === 0,
      dataDir: resolvedDataDir,
      databasePath,
      manifestPath,
      mediaDir,
      schemaVersion,
      mediaTotal,
      missingMediaFiles,
      issues,
    };
  }

  async promoteRestore(jobId: string, restoredDataDir: string, confirmation: string): Promise<Record<string, unknown>> {
    const resolved = path.resolve(restoredDataDir);
    const required = `PROMOTE ${path.basename(resolved)}`;
    if (confirmation !== required) {
      throw new Error(`Confirmation must be exactly: ${required}`);
    }

    const verification = await this.verifyRestoredDataDir(resolved);
    if (!verification.ok) {
      throw new Error("Restore candidate did not pass verification");
    }

    const prePromoteBackup = await this.createBackup(jobId, "pre-promote");
    const instructionPath = path.join(this.paths.archiveDir, "pending-promote.json");
    const instructions = {
      createdAt: new Date().toISOString(),
      restoredDataDir: resolved,
      currentDataDir: this.paths.dataDir,
      prePromoteBackup,
      requiredEnv: {
        PRIVATE_MOMENTS_DATA_DIR: resolved,
        DATABASE_URL: `file:${path.join(resolved, "app.sqlite")}`,
      },
      note: "Stop the server, update server/.env with requiredEnv, then start the server again. Runtime database replacement is intentionally not performed while Prisma has an open SQLite connection.",
    };
    await writeFile(instructionPath, `${JSON.stringify(instructions, null, 2)}\n`, "utf8");

    return {
      pendingPromotePath: instructionPath,
      restoredDataDir: resolved,
      prePromoteBackup,
    };
  }

  private async collectPendingPromoteStaleReasons(input: {
    restoredDataDir: string | null;
    currentDataDir: string | null;
    targetDataDir: string | null;
    targetDatabaseUrl: string | null;
  }): Promise<string[]> {
    const reasons: string[] = [];

    if (!input.restoredDataDir) {
      reasons.push("missing_restored_data_dir");
    } else {
      const verification = await this.verifyRestoredDataDir(input.restoredDataDir);
      if (!verification.ok) {
        reasons.push("restored_data_invalid");
      }
    }

    const liveDataDir = path.resolve(this.paths.dataDir);
    if (input.currentDataDir && path.resolve(input.currentDataDir) !== liveDataDir) {
      reasons.push("runtime_data_dir_changed_since_prepare");
    }

    if (input.targetDataDir && path.resolve(input.targetDataDir) === liveDataDir) {
      reasons.push("already_switched_to_target_data_dir");
    }

    if (input.targetDatabaseUrl && input.targetDatabaseUrl === this.config.databaseUrl) {
      reasons.push("database_url_already_matches_target");
    }

    return [...new Set(reasons)];
  }

  private async createSnapshotSource(jobId: string, source: string): Promise<string> {
    const snapshotDir = path.join(
      this.paths.archiveStagingDir,
      `${Date.now()}-${sanitizeToken(jobId)}`,
      "snapshot",
    );
    await mkdir(snapshotDir, { recursive: true });

    const databaseSource = resolveSqlitePath(this.config.databaseUrl);
    const databaseTarget = path.join(snapshotDir, "app.sqlite");
    if (await exists(databaseSource)) {
      try {
        await backupSqlite(databaseSource, databaseTarget);
      } catch {
        await copyFile(databaseSource, databaseTarget);
      }
    } else if (await exists(this.paths.databasePath)) {
      await copyFile(this.paths.databasePath, databaseTarget);
    } else {
      throw new Error("SQLite database file does not exist");
    }

    await copyIfExists(this.paths.manifestPath, path.join(snapshotDir, "manifest.json"));
    await copyDirectoryIfExists(this.paths.mediaDir, path.join(snapshotDir, "media"));

    const backupManifest = {
      app: "PrivateMoments",
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      createdAt: new Date().toISOString(),
      source,
      dataDir: this.paths.dataDir,
      databaseSource,
    };
    await writeFile(
      path.join(snapshotDir, "backup-manifest.json"),
      `${JSON.stringify(backupManifest, null, 2)}\n`,
      "utf8",
    );

    return snapshotDir;
  }

  private async restoreTargetPath(snapshotId: string, restoreName?: string): Promise<string> {
    const safeName = sanitizeToken(restoreName ?? "");
    const base = `${new Date().toISOString().replace(/[:.]/g, "-")}-${snapshotId.slice(0, 12)}${safeName ? `-${safeName}` : ""}`;
    const target = path.join(this.paths.archiveRestoresDir, base);
    const resolved = path.resolve(target);
    if (!isPathInsideOrEqual(this.paths.archiveRestoresDir, resolved)) {
      throw new Error("Restore target path is invalid");
    }
    return resolved;
  }

  private async requireConfiguredRepository(): Promise<ArchiveConfig> {
    const config = await this.archiveConfig.read();
    if (!config.repositoryPath || !config.keyFilePath) {
      throw new Error("Backup repository is not configured");
    }
    return config;
  }

  private async ensureReady(config: ArchiveConfig): Promise<void> {
    const restic = await this.detectRestic();
    if (!restic.available) {
      throw new Error("restic is not installed. Install it on the Mac first, for example: brew install restic");
    }
    if (!config.keyFilePath || !(await exists(config.keyFilePath))) {
      await this.archiveConfig.ensureKeyFile();
    }
  }

  private async detectRestic(): Promise<{ available: boolean; version: string | null }> {
    try {
      const result = await runCommand("restic", ["version"], {}, 10_000);
      return {
        available: true,
        version: result.stdout.trim() || result.stderr.trim() || null,
      };
    } catch {
      return {
        available: false,
        version: null,
      };
    }
  }

  private async isRepositoryInitialized(config: ArchiveConfig): Promise<boolean> {
    if (!config.repositoryPath || !config.keyFilePath || !(await exists(config.keyFilePath))) {
      return false;
    }

    try {
      await this.runRestic(config, ["snapshots", "--json"], 15_000);
      return true;
    } catch {
      return false;
    }
  }

  private async runRestic(
    config: ArchiveConfig,
    args: string[],
    timeoutMs = 30 * 60 * 1000,
    cwd?: string,
  ): Promise<ResticCommandResult> {
    if (!config.repositoryPath || !config.keyFilePath) {
      throw new Error("Backup repository is not configured");
    }

    return runCommand(
      "restic",
      ["-r", config.repositoryPath, "--password-file", config.keyFilePath, ...args],
      {
        RESTIC_CACHE_DIR: path.join(this.paths.archiveDir, "restic-cache"),
      },
      timeoutMs,
      cwd,
    );
  }
}

async function runCommand(
  command: string,
  args: string[],
  env: Record<string, string>,
  timeoutMs: number,
  cwd?: string,
): Promise<ResticCommandResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: {
        ...process.env,
        ...env,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`${command} timed out`));
    }, timeoutMs);

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(stderr.trim() || `${command} exited with code ${code}`));
      }
    });
  });
}

function resolveSqlitePath(databaseUrl: string): string {
  const prefix = "file:";
  if (!databaseUrl.startsWith(prefix)) {
    throw new Error("Only SQLite file DATABASE_URL is supported for archive backup");
  }

  const filePath = databaseUrl.slice(prefix.length);
  return path.resolve(filePath);
}

async function backupSqlite(source: string, target: string): Promise<void> {
  await runCommand("sqlite3", [source, `.backup '${target.replaceAll("'", "''")}'`], {}, 120_000);
}

async function querySqliteJson(databasePath: string, sql: string): Promise<unknown[]> {
  const result = await runCommand("sqlite3", ["-json", databasePath, sql], {}, 120_000);
  return JSON.parse(result.stdout || "[]") as unknown[];
}

async function copyIfExists(source: string, target: string): Promise<void> {
  if (await exists(source)) {
    await copyFile(source, target);
  }
}

async function copyDirectoryIfExists(source: string, target: string): Promise<void> {
  if (!(await exists(source))) {
    return;
  }

  await mkdir(path.dirname(target), { recursive: true });
  await rm(target, { force: true, recursive: true });
  await copyFileOrDirectory(source, target);
}

async function copyFileOrDirectory(source: string, target: string): Promise<void> {
  const sourceStat = await stat(source);
  if (sourceStat.isDirectory()) {
    await mkdir(target, { recursive: true });
    const { cp } = await import("node:fs/promises");
    await cp(source, target, {
      recursive: true,
      filter: (item) => !item.includes(`${path.sep}temp${path.sep}`),
    });
  } else {
    await copyFile(source, target);
  }
}

async function exists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

async function findRestoredDataDir(target: string): Promise<string> {
  const candidates: string[] = [];
  await collectDataDirCandidates(target, candidates, 0);
  const preferred = candidates.find((candidate) => path.basename(candidate) === "snapshot");
  return preferred ?? candidates[0] ?? target;
}

async function collectDataDirCandidates(
  current: string,
  candidates: string[],
  depth: number,
): Promise<void> {
  if (depth > 8) {
    return;
  }

  if ((await exists(path.join(current, "app.sqlite"))) && (await exists(path.join(current, "manifest.json")))) {
    candidates.push(current);
    return;
  }

  let entries: Dirent[];
  try {
    entries = await readdir(current, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (entry.isDirectory()) {
      await collectDataDirCandidates(path.join(current, entry.name), candidates, depth + 1);
    }
  }
}

async function readManifestSchemaVersion(manifestPath: string): Promise<number | null> {
  try {
    const parsed = JSON.parse(await readFile(manifestPath, "utf8")) as { schemaVersion?: unknown };
    return typeof parsed.schemaVersion === "number" ? parsed.schemaVersion : null;
  } catch {
    return null;
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function asOptionalString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function parseSnapshotId(stdout: string): string | null {
  for (const line of stdout.split("\n")) {
    if (!line.trim()) {
      continue;
    }
    try {
      const parsed = JSON.parse(line) as { message_type?: string; snapshot_id?: string };
      if (parsed.message_type === "summary" && typeof parsed.snapshot_id === "string") {
        return parsed.snapshot_id;
      }
    } catch {
      // Ignore non-JSON restic output.
    }
  }
  return null;
}

function normalizeSnapshot(value: unknown): ResticSnapshot | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const raw = value as Record<string, unknown>;
  const id = typeof raw.id === "string" ? raw.id : null;
  const time = typeof raw.time === "string" ? raw.time : null;
  if (!id || !time) {
    return null;
  }

  return {
    id,
    shortId: id.slice(0, 8),
    time,
    hostname: typeof raw.hostname === "string" ? raw.hostname : null,
    paths: Array.isArray(raw.paths) ? raw.paths.filter((item): item is string => typeof item === "string") : [],
    tags: Array.isArray(raw.tags) ? raw.tags.filter((item): item is string => typeof item === "string") : [],
  };
}

function sanitizeToken(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 80);
}
