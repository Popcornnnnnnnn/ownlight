import { useEffect, useState } from "react";
import { Activity, Archive, Database, HardDrive, RefreshCw, ShieldCheck, Timer } from "lucide-react";

import {
  type ArchiveRepositoryState,
  type PendingPromoteReadiness,
  type ArchiveSnapshot,
  apiFetch,
  type MaintenanceJob,
  type PendingPromoteState,
} from "./adminApi";
import { formatDate, jobSummary, lastPathSegment, nextLocalDay, startOfLocalDay } from "./adminFormat";
import { Metric } from "./adminShared";

const CLEAR_STALE_PENDING_PROMOTE_CONFIRMATION = "CLEAR STALE PENDING PROMOTE";

function formatPendingPromoteReason(reason: string): string {
  switch (reason) {
    case "malformed_instructions":
      return "Instruction JSON is malformed.";
    case "missing_restored_data_dir":
      return "Restored data directory is missing from the handoff file.";
    case "restored_data_invalid":
      return "Restored data directory no longer passes verification.";
    case "runtime_data_dir_changed_since_prepare":
      return "Live data directory changed after this handoff was prepared.";
    case "already_switched_to_target_data_dir":
      return "Live data directory already matches the promote target.";
    case "database_url_already_matches_target":
      return "Live DATABASE_URL already matches the promote target.";
    default:
      return reason;
  }
}

export function ArchiveManager({ token }: { token: string }) {
  const [repository, setRepository] = useState<ArchiveRepositoryState | null>(null);
  const [repositoryPath, setRepositoryPath] = useState("");
  const [snapshots, setSnapshots] = useState<ArchiveSnapshot[]>([]);
  const [jobs, setJobs] = useState<MaintenanceJob[]>([]);
  const [pendingPromote, setPendingPromote] = useState<PendingPromoteState | null>(null);
  const [pendingPromoteReadiness, setPendingPromoteReadiness] = useState<PendingPromoteReadiness | null>(null);
  const [scheduleEnabled, setScheduleEnabled] = useState(false);
  const [scheduleTime, setScheduleTime] = useState("03:30");
  const [restoreSnapshotId, setRestoreSnapshotId] = useState("");
  const [restoreName, setRestoreName] = useState("");
  const [promotePath, setPromotePath] = useState("");
  const [promoteConfirmation, setPromoteConfirmation] = useState("");
  const [exportFrom, setExportFrom] = useState("");
  const [exportTo, setExportTo] = useState("");
  const [importPackagePath, setImportPackagePath] = useState("");
  const [importName, setImportName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState<string | null>(null);

  async function loadArchive() {
    setLoading(true);
    setError(null);

    try {
      const [
        repositoryResponse,
        snapshotsResponse,
        pendingPromoteResponse,
        pendingPromoteReadinessResponse,
        jobsResponse,
      ] = await Promise.all([
        apiFetch<{ repository: ArchiveRepositoryState }>("/api/v1/admin/archive/repository", token),
        apiFetch<{ snapshots: ArchiveSnapshot[] }>("/api/v1/admin/archive/snapshots", token).catch(() => ({
          snapshots: [],
        })),
        apiFetch<{ pendingPromote: PendingPromoteState | null }>(
          "/api/v1/admin/archive/pending-promote",
          token,
        ).catch(() => ({
          pendingPromote: null,
        })),
        apiFetch<{ readiness: PendingPromoteReadiness }>(
          "/api/v1/admin/archive/pending-promote/readiness",
          token,
        ).catch(() => ({
          readiness: null,
        })),
        apiFetch<{ jobs: MaintenanceJob[] }>("/api/v1/admin/maintenance/jobs?limit=12", token),
      ]);

      setRepository(repositoryResponse.repository);
      setRepositoryPath(repositoryResponse.repository.repositoryPath ?? "");
      setScheduleEnabled(repositoryResponse.repository.schedule.enabled);
      setScheduleTime(repositoryResponse.repository.schedule.timeOfDay);
      setSnapshots(snapshotsResponse.snapshots);
      setPendingPromote(pendingPromoteResponse.pendingPromote);
      setPendingPromoteReadiness(pendingPromoteReadinessResponse.readiness);
      setJobs(jobsResponse.jobs);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load archive state");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadArchive();
  }, []);

  async function runAction(name: string, action: () => Promise<string>) {
    setSubmitting(name);
    setError(null);
    setNotice(null);

    try {
      const message = await action();
      setNotice(message);
      await loadArchive();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Archive action failed");
    } finally {
      setSubmitting(null);
    }
  }

  async function saveRepository() {
    await runAction("repository", async () => {
      const response = await apiFetch<{ repository: ArchiveRepositoryState }>(
        "/api/v1/admin/archive/repository",
        token,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            repositoryPath,
          }),
        },
      );
      setRepository(response.repository);
      return "Backup repository path saved.";
    });
  }

  async function initializeRepository() {
    await runAction("init", async () => {
      await apiFetch("/api/v1/admin/archive/repository/init", token, {
        method: "POST",
      });
      return "Backup repository initialized.";
    });
  }

  async function saveSchedule() {
    await runAction("schedule", async () => {
      await apiFetch("/api/v1/admin/archive/schedule", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          enabled: scheduleEnabled,
          timeOfDay: scheduleTime,
        }),
      });
      return "Backup schedule updated.";
    });
  }

  async function startJob(kind: "backup" | "check") {
    await runAction(kind, async () => {
      await apiFetch(`/api/v1/admin/archive/jobs/${kind}`, token, {
        method: "POST",
      });
      return kind === "backup" ? "Backup job started." : "Repository check started.";
    });
  }

  async function startRestore(snapshotId: string) {
    await runAction("restore", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/restore", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          snapshotId,
          restoreName,
        }),
      });
      setRestoreSnapshotId(snapshotId);
      return "Restore job started. Watch recent jobs for the verified restore path.";
    });
  }

  async function startPromote() {
    await runAction("promote", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/promote", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          restoredDataDir: promotePath,
          confirmation: promoteConfirmation,
        }),
      });
      return "Promote preparation started. It will write restart instructions after verification and pre-promote backup.";
    });
  }

  async function startExport() {
    await runAction("export", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/export", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: exportFrom ? startOfLocalDay(exportFrom).toISOString() : undefined,
          to: exportTo ? nextLocalDay(exportTo).toISOString() : undefined,
        }),
      });
      return "Export job started. The package path will appear in Recent Jobs.";
    });
  }

  async function startImport() {
    await runAction("import", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/import", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          packagePath: importPackagePath,
          importName,
        }),
      });
      return "Import job started. It will create a new staged data directory and leave the current archive untouched.";
    });
  }

  async function clearStalePendingPromote() {
    await runAction("clear-stale-pending-promote", async () => {
      await apiFetch("/api/v1/admin/archive/pending-promote/clear", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          confirmation: CLEAR_STALE_PENDING_PROMOTE_CONFIRMATION,
        }),
      });
      return "Stale pending promote instructions cleared.";
    });
  }

  const runningJob = jobs.find((job) => job.status === "running");

  return (
    <section className="archive-manager">
      {error ? <div className="banner error">{error}</div> : null}
      {notice ? <div className="banner success">{notice}</div> : null}
      {loading ? <div className="banner">Loading archive state</div> : null}

      <section className="metric-grid">
        <Metric
          icon={<Archive size={20} />}
          label="Repository"
          value={repository?.configured ? "Configured" : "Not set"}
          detail={repository?.initialized ? "initialized" : "not initialized"}
        />
        <Metric
          icon={<HardDrive size={20} />}
          label="restic"
          value={repository?.resticAvailable ? "Available" : "Missing"}
          detail={repository?.resticVersion ?? "brew install restic"}
        />
        <Metric
          icon={<Timer size={20} />}
          label="Schedule"
          value={repository?.schedule.enabled ? repository.schedule.timeOfDay : "Off"}
          detail={repository?.schedule.nextRunAt ? `next ${formatDate(repository.schedule.nextRunAt)}` : "manual only"}
        />
        <Metric
          icon={<Activity size={20} />}
          label="Running job"
          value={runningJob ? runningJob.type : "None"}
          detail={runningJob ? `${runningJob.progress}% · ${runningJob.stage ?? "running"}` : `${jobs.length} recent jobs`}
        />
      </section>

      <section className="layout-grid archive-grid">
        <section className="panel wide">
          <div className="panel-heading">
            <h2>Backup Repository</h2>
            <Archive size={18} />
          </div>
          <p className="muted-text">
            Repository plus key file can restore your archive. This is a recovery tool for your own
            Mac, not a separate encrypted vault if someone has both files.
          </p>
          <div className="form-grid">
            <label>
              <span>Repository path</span>
              <input
                onChange={(event) => setRepositoryPath(event.target.value)}
                placeholder="/Users/you/Library/Mobile Documents/com~apple~CloudDocs/PrivateMomentsBackup"
                value={repositoryPath}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null || !repositoryPath.trim()}
              onClick={() => void saveRepository()}
              type="button"
            >
              Save path
            </button>
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Key file</dt>
              <dd>{repository?.keyFilePath ?? "-"}</dd>
            </div>
            <div>
              <dt>Updated</dt>
              <dd>{formatDate(repository?.updatedAt)}</dd>
            </div>
          </dl>
          <div className="toolbar-row">
            <button
              className="icon-button"
              disabled={submitting !== null || !repository?.configured}
              onClick={() => void initializeRepository()}
              type="button"
            >
              <Database size={17} />
              Initialize
            </button>
            <button
              className="primary-button"
              disabled={submitting !== null || !repository?.configured}
              onClick={() => void startJob("backup")}
              type="button"
            >
              <Archive size={17} />
              Backup now
            </button>
            <button
              className="icon-button"
              disabled={submitting !== null || !repository?.initialized}
              onClick={() => void startJob("check")}
              type="button"
            >
              <ShieldCheck size={17} />
              Check repository
            </button>
            <button className="icon-button" onClick={() => void loadArchive()} type="button">
              <RefreshCw size={17} />
              Refresh
            </button>
          </div>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Daily Backup</h2>
            <Timer size={18} />
          </div>
          <div className="form-grid compact-form">
            <label className="checkbox-label">
              <input
                checked={scheduleEnabled}
                onChange={(event) => setScheduleEnabled(event.target.checked)}
                type="checkbox"
              />
              <span>Enable daily backup</span>
            </label>
            <label>
              <span>Time</span>
              <input
                onChange={(event) => setScheduleTime(event.target.value)}
                type="time"
                value={scheduleTime}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null}
              onClick={() => void saveSchedule()}
              type="button"
            >
              Save schedule
            </button>
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Last run</dt>
              <dd>{formatDate(repository?.schedule.lastRunAt)}</dd>
            </div>
            <div>
              <dt>Next run</dt>
              <dd>{formatDate(repository?.schedule.nextRunAt)}</dd>
            </div>
          </dl>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Promote Restore</h2>
            <ShieldCheck size={18} />
          </div>
          <p className="muted-text">
            Restore first, then paste the verified restore path here. Promotion creates a
            pre-promote backup and writes restart instructions instead of replacing the live SQLite
            database in-process.
          </p>
          <div className="form-grid compact-form">
            <label>
              <span>Restored data directory</span>
              <input
                onChange={(event) => setPromotePath(event.target.value)}
                placeholder="/path/from/restore/job"
                value={promotePath}
              />
            </label>
            <label>
              <span>Confirmation</span>
              <input
                onChange={(event) => setPromoteConfirmation(event.target.value)}
                placeholder={promotePath ? `PROMOTE ${lastPathSegment(promotePath)}` : "PROMOTE <folder>"}
                value={promoteConfirmation}
              />
            </label>
            <button
              className="primary-button destructive"
              disabled={submitting !== null || !promotePath.trim() || !promoteConfirmation.trim()}
              onClick={() => void startPromote()}
              type="button"
            >
              Prepare promote
            </button>
          </div>
          {pendingPromote ? (
            <>
              <dl className="details-list compact">
                <div>
                  <dt>Status</dt>
                  <dd>
                    {pendingPromote.stale
                      ? pendingPromote.malformed
                        ? "Malformed and stale"
                        : "Stale instructions"
                      : "Pending restart handoff ready"}
                  </dd>
                </div>
                <div>
                  <dt>Created</dt>
                  <dd>{formatDate(pendingPromote.createdAt)}</dd>
                </div>
                <div>
                  <dt>Instruction file</dt>
                  <dd className="mono">{pendingPromote.instructionPath}</dd>
                </div>
                <div>
                  <dt>Restored data dir</dt>
                  <dd className="mono">{pendingPromote.restoredDataDir ?? "-"}</dd>
                </div>
                <div>
                  <dt>Current data dir</dt>
                  <dd className="mono">{pendingPromote.currentDataDir ?? "-"}</dd>
                </div>
                <div>
                  <dt>Pre-promote snapshot</dt>
                  <dd>{pendingPromote.prePromoteSnapshotId ?? "-"}</dd>
                </div>
              </dl>
              <dl className="details-list compact">
                <div>
                  <dt>PRIVATE_MOMENTS_DATA_DIR</dt>
                  <dd className="mono">{pendingPromote.requiredEnv.PRIVATE_MOMENTS_DATA_DIR ?? "-"}</dd>
                </div>
                <div>
                  <dt>DATABASE_URL</dt>
                  <dd className="mono">{pendingPromote.requiredEnv.DATABASE_URL ?? "-"}</dd>
                </div>
              </dl>
              {pendingPromote.staleReasons.length ? (
                <p className="danger-text">
                  Stale reasons: {pendingPromote.staleReasons.map(formatPendingPromoteReason).join(" ")}
                </p>
              ) : null}
              {pendingPromote.note ? (
                <p className={pendingPromote.malformed ? "danger-text" : "muted-text"}>
                  {pendingPromote.note}
                </p>
              ) : null}
              {pendingPromote.stale ? (
                <div className="toolbar-row">
                  <button
                    className="primary-button destructive"
                    disabled={submitting !== null}
                    onClick={() => void clearStalePendingPromote()}
                    type="button"
                  >
                    Clear stale instructions
                  </button>
                </div>
              ) : null}
              {pendingPromoteReadiness ? (
                <>
                  <dl className="details-list compact">
                    <div>
                      <dt>Readiness drill</dt>
                      <dd>{pendingPromoteReadiness.ready ? "Ready" : "Not ready"}</dd>
                    </div>
                    <div>
                      <dt>Checked</dt>
                      <dd>{formatDate(pendingPromoteReadiness.checkedAt)}</dd>
                    </div>
                    <div>
                      <dt>Summary</dt>
                      <dd>{pendingPromoteReadiness.summary}</dd>
                    </div>
                  </dl>
                  <div className="job-list">
                    {pendingPromoteReadiness.checks.map((check) => (
                      <div className="job-row" key={check.id}>
                        <div>
                          <strong>{check.label}</strong>
                          <span>{check.detail}</span>
                        </div>
                        <span className={check.status === "fail" ? "status-pill danger" : "status-pill"}>
                          {check.status}
                        </span>
                      </div>
                    ))}
                  </div>
                </>
              ) : null}
            </>
          ) : (
            <p className="muted-text">
              No pending promote instructions. After `Prepare promote`, Admin will show the
              restart-safe handoff truth here without requiring a filesystem lookup.
            </p>
          )}
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Snapshots</h2>
            <span className="status-pill">{snapshots.length}</span>
          </div>
          <div className="snapshot-list">
            {snapshots.map((snapshot) => (
              <div className="snapshot-row" key={snapshot.id}>
                <div>
                  <strong>{snapshot.shortId}</strong>
                  <span>{formatDate(snapshot.time)}</span>
                  <span>{snapshot.tags.length ? snapshot.tags.join(", ") : "private-moments"}</span>
                </div>
                <button
                  className="icon-button"
                  disabled={submitting !== null}
                  onClick={() => void startRestore(snapshot.id)}
                  type="button"
                >
                  Restore
                </button>
              </div>
            ))}
            {!snapshots.length ? <div className="empty-state">No snapshots yet</div> : null}
          </div>
          <label className="restore-name-label">
            <span>Restore label</span>
            <input
              onChange={(event) => setRestoreName(event.target.value)}
              placeholder="optional label"
              value={restoreName}
            />
          </label>
          {restoreSnapshotId ? (
            <p className="muted-text">Last selected snapshot: {restoreSnapshotId.slice(0, 12)}</p>
          ) : null}
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Exports</h2>
            <Archive size={18} />
          </div>
          <p className="muted-text">
            Export is migration-first: JSON is the source of truth, media files are included, and
            Markdown is only a preview. Import always stages into a new data directory.
          </p>
          <div className="form-grid export-form">
            <label>
              <span>From</span>
              <input
                onChange={(event) => setExportFrom(event.target.value)}
                type="date"
                value={exportFrom}
              />
            </label>
            <label>
              <span>To</span>
              <input
                onChange={(event) => setExportTo(event.target.value)}
                type="date"
                value={exportTo}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null}
              onClick={() => void startExport()}
              type="button"
            >
              Create export
            </button>
          </div>
          <div className="form-grid import-form">
            <label>
              <span>Package path</span>
              <input
                onChange={(event) => setImportPackagePath(event.target.value)}
                placeholder="/path/to/private-moments-export.tar.gz"
                value={importPackagePath}
              />
            </label>
            <label>
              <span>Import label</span>
              <input
                onChange={(event) => setImportName(event.target.value)}
                placeholder="optional label"
                value={importName}
              />
            </label>
            <button
              className="icon-button"
              disabled={submitting !== null || !importPackagePath.trim()}
              onClick={() => void startImport()}
              type="button"
            >
              Import package
            </button>
          </div>
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Recent Jobs</h2>
            <Activity size={18} />
          </div>
          <div className="job-list">
            {jobs.map((job) => (
              <div className="job-row" key={job.id}>
                <div>
                  <strong>{job.type}</strong>
                  <span>
                    {formatDate(job.createdAt)} · {job.stage ?? "queued"} · {job.progress}%
                  </span>
                  {job.artifactPath ? <span className="mono">{job.artifactPath}</span> : null}
                  {job.errorMessage ? <span className="danger-text">{job.errorMessage}</span> : null}
                </div>
                <span className={job.status === "failed" ? "status-pill danger" : "status-pill"}>
                  {job.status}
                </span>
              </div>
            ))}
            {!jobs.length ? <div className="empty-state">No maintenance jobs yet</div> : null}
          </div>
        </section>
      </section>
    </section>
  );
}
