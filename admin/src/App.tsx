import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  Eye,
  HardDrive,
  LogOut,
  RefreshCw,
  Search,
  Server,
  ShieldCheck,
  Smartphone,
  Star,
  Trash2,
  Video,
  X,
} from "lucide-react";

import {
  DEVICE_ID_KEY,
  TOKEN_KEY,
  adminDeviceKey,
  apiFetch,
  type AdminMedia,
  type AdminPost,
  type AdminStatus,
  type AdminTab,
  type CleanPreview,
  type DeletedFilter,
  type Device,
  type LogEntry,
  type LoginResponse,
  type MaintenanceJob,
  type MaintenanceStateResponse,
  type PostsResponse,
} from "./adminApi";
import { ArchiveManager } from "./ArchiveManager";
import {
  deviceLabel,
  deviceOptionLabel,
  formatBytes,
  formatDate,
  formatDuration,
  jobSummary,
  mediaSummary,
  shortId,
} from "./adminFormat";
import { AuthenticatedImage, ImageLightbox, mediaIcon, Metric } from "./adminShared";

export function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY));
  const [deviceId, setDeviceId] = useState(() => sessionStorage.getItem(DEVICE_ID_KEY));

  function handleLogin(response: LoginResponse) {
    sessionStorage.setItem(TOKEN_KEY, response.deviceToken);
    sessionStorage.setItem(DEVICE_ID_KEY, response.deviceId);
    setToken(response.deviceToken);
    setDeviceId(response.deviceId);
  }

  function handleLogout() {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(DEVICE_ID_KEY);
    setToken(null);
    setDeviceId(null);
  }

  if (!token) {
    return <LoginScreen onLogin={handleLogin} />;
  }

  return <Dashboard currentDeviceId={deviceId} token={token} onLogout={handleLogout} />;
}

function LoginScreen({ onLogin }: { onLogin: (response: LoginResponse) => void }) {
  const [password, setPassword] = useState("");
  const [deviceName, setDeviceName] = useState("Mac Admin Browser");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const response = await apiFetch<LoginResponse>("/api/v1/auth/login", null, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          password,
          deviceName,
          deviceKey: adminDeviceKey(),
          platform: "web",
        }),
      });

      onLogin(response);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Login failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="login-shell">
      <form className="login-panel" onSubmit={submit}>
        <div>
          <p className="eyebrow">Private Moments</p>
          <h1>Mac Admin</h1>
        </div>
        <label>
          <span>Password</span>
          <input
            autoComplete="current-password"
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            value={password}
          />
        </label>
        <label>
          <span>Device name</span>
          <input
            autoComplete="off"
            onChange={(event) => setDeviceName(event.target.value)}
            type="text"
            value={deviceName}
          />
        </label>
        {error ? <p className="error-text">{error}</p> : null}
        <button className="primary-button" disabled={submitting} type="submit">
          <ShieldCheck size={18} />
          {submitting ? "Signing in" : "Sign in"}
        </button>
      </form>
    </main>
  );
}

function Dashboard({
  currentDeviceId,
  token,
  onLogout,
}: {
  currentDeviceId: string | null;
  token: string;
  onLogout: () => void;
}) {
  const [activeTab, setActiveTab] = useState<AdminTab>("archive");
  const [status, setStatus] = useState<AdminStatus | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [maintenanceState, setMaintenanceState] = useState<MaintenanceStateResponse | null>(null);
  const [maintenanceJobs, setMaintenanceJobs] = useState<MaintenanceJob[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [cleanPreview, setCleanPreview] = useState<CleanPreview | null>(null);
  const [cleanConfirmation, setCleanConfirmation] = useState("");
  const [cleanSubmitting, setCleanSubmitting] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);

    try {
      const [statusResponse, devicesResponse, logsResponse, maintenanceResponse, jobsResponse] = await Promise.all([
        apiFetch<AdminStatus>("/api/v1/admin/status", token),
        apiFetch<{ devices: Device[] }>("/api/v1/devices", token),
        apiFetch<{ logs: LogEntry[] }>("/api/v1/admin/logs?limit=20", token),
        apiFetch<MaintenanceStateResponse>("/api/v1/admin/maintenance/state", token),
        apiFetch<{ jobs: MaintenanceJob[] }>("/api/v1/admin/maintenance/jobs?limit=5", token),
      ]);

      setStatus(statusResponse);
      setDevices(devicesResponse.devices);
      setLogs(logsResponse.logs);
      setMaintenanceState(maintenanceResponse);
      setMaintenanceJobs(jobsResponse.jobs);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load dashboard");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function revokeDevice(id: string) {
    await apiFetch(`/api/v1/devices/${id}`, token, {
      method: "DELETE",
    });
    await load();
  }

  async function openCleanDevice(deviceId: string) {
    setError(null);
    setNotice(null);

    try {
      const preview = await apiFetch<CleanPreview>(
        `/api/v1/admin/devices/${deviceId}/clean-posts/preview`,
        token,
      );
      setCleanPreview(preview);
      setCleanConfirmation("");
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load clean preview");
    }
  }

  async function confirmCleanDevice() {
    if (!cleanPreview || cleanConfirmation !== cleanPreview.device.name) {
      return;
    }

    setCleanSubmitting(true);
    setError(null);
    setNotice(null);

    try {
      const result = await apiFetch<{ deletedPosts: number; deletedMediaFiles: number }>(
        `/api/v1/admin/devices/${cleanPreview.device.id}/clean-posts`,
        token,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            confirmDeviceName: cleanConfirmation,
          }),
        },
      );

      setNotice(
        `Cleaned ${result.deletedPosts} posts and ${result.deletedMediaFiles} media files from ${cleanPreview.device.name}.`,
      );
      setCleanPreview(null);
      setCleanConfirmation("");
      await load();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to clean device posts");
    } finally {
      setCleanSubmitting(false);
    }
  }

  const activeDevices = useMemo(
    () => devices.filter((device) => !device.revokedAt),
    [devices],
  );

  return (
    <main className="dashboard-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Private Moments</p>
          <h1>Mac Admin</h1>
        </div>
        <div className="topbar-actions">
          <button className="icon-button" onClick={() => void load()} type="button">
            <RefreshCw size={18} />
            Refresh
          </button>
          <button className="icon-button subtle" onClick={onLogout} type="button">
            <LogOut size={18} />
            Sign out
          </button>
        </div>
      </header>

      <nav className="tabbar" aria-label="Admin sections">
        <button
          className={activeTab === "archive" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("archive")}
          type="button"
        >
          Archive
        </button>
        <button
          className={activeTab === "overview" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("overview")}
          type="button"
        >
          Overview
        </button>
      </nav>

      {error ? <div className="banner error">{error}</div> : null}
      {notice ? <div className="banner success">{notice}</div> : null}
      {loading ? <div className="banner">Loading</div> : null}

      {activeTab === "overview" ? (
        <Overview
          activeDevices={activeDevices}
          currentDeviceId={currentDeviceId}
          devices={devices}
          logs={logs}
          maintenanceJobs={maintenanceJobs}
          maintenanceState={maintenanceState}
          onCleanDevice={openCleanDevice}
          onRevokeDevice={revokeDevice}
          status={status}
        />
      ) : (
        <ArchiveManager token={token} />
      )}

      {cleanPreview ? (
        <CleanDeviceDialog
          confirmation={cleanConfirmation}
          onCancel={() => {
            setCleanPreview(null);
            setCleanConfirmation("");
          }}
          onChangeConfirmation={setCleanConfirmation}
          onConfirm={() => void confirmCleanDevice()}
          preview={cleanPreview}
          submitting={cleanSubmitting}
        />
      ) : null}
    </main>
  );
}

function Overview({
  activeDevices,
  currentDeviceId,
  devices,
  logs,
  maintenanceJobs,
  maintenanceState,
  onCleanDevice,
  onRevokeDevice,
  status,
}: {
  activeDevices: Device[];
  currentDeviceId: string | null;
  devices: Device[];
  logs: LogEntry[];
  maintenanceJobs: MaintenanceJob[];
  maintenanceState: MaintenanceStateResponse | null;
  onCleanDevice: (deviceId: string) => void;
  onRevokeDevice: (deviceId: string) => void;
  status: AdminStatus | null;
}) {
  const runningJob = maintenanceState?.runningJob ?? maintenanceJobs.find((job) => job.status === "running");
  const latestFailedJob = maintenanceJobs.find((job) => job.status === "failed");

  return (
    <>
      <section className="metric-grid">
        <Metric
          icon={<Server size={20} />}
          label="Server"
          value={status ? `v${status.serverVersion}` : "-"}
          detail={status ? `schema ${status.schemaVersion}` : ""}
        />
        <Metric
          icon={<Activity size={20} />}
          label="Maintenance"
          value={maintenanceState?.maintenance.active ? "Active" : "Idle"}
          detail={runningJob ? `${runningJob.type} · ${runningJob.progress}%` : "no running job"}
        />
        <Metric
          icon={<HardDrive size={20} />}
          label="Storage"
          value={status ? formatBytes(status.storage.totalBytes) : "-"}
          detail={
            status?.storage.availableBytes !== undefined && status.storage.availableBytes !== null
              ? `${formatBytes(status.storage.availableBytes)} available`
              : "runtime data"
          }
        />
        <Metric
          icon={<Smartphone size={20} />}
          label="Devices"
          value={String(status?.counts.activeDevices ?? activeDevices.length)}
          detail={`${status?.counts.revokedDevices ?? 0} revoked`}
        />
      </section>

      <section className="layout-grid">
        <section className="panel wide">
          <div className="panel-heading">
            <h2>Service</h2>
            <Activity size={18} />
          </div>
          <dl className="details-list">
            <div>
              <dt>Data directory</dt>
              <dd>{status?.dataDir ?? "-"}</dd>
            </div>
            <div>
              <dt>Uptime</dt>
              <dd>{status ? formatDuration(status.uptimeSeconds) : "-"}</dd>
            </div>
            <div>
              <dt>Storage</dt>
              <dd>{status ? formatBytes(status.storage.totalBytes) : "-"}</dd>
            </div>
            <div>
              <dt>Available disk</dt>
              <dd>
                {status?.storage.availableBytes !== undefined && status.storage.availableBytes !== null
                  ? formatBytes(status.storage.availableBytes)
                  : "-"}
              </dd>
            </div>
          </dl>
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Jobs</h2>
            <Activity size={18} />
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Maintenance mode</dt>
              <dd>{maintenanceState?.maintenance.active ? "Active" : "Idle"}</dd>
            </div>
            <div>
              <dt>Running job</dt>
              <dd>{runningJob ? jobSummary(runningJob) : "None"}</dd>
            </div>
            <div>
              <dt>Recent failed job</dt>
              <dd>{latestFailedJob ? jobSummary(latestFailedJob) : "None"}</dd>
            </div>
            <div>
              <dt>Recent jobs</dt>
              <dd>{maintenanceJobs.length}</dd>
            </div>
          </dl>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Devices</h2>
            <Smartphone size={18} />
          </div>
          <div className="device-list">
            {devices.map((device) => (
              <div className="device-row" key={device.id}>
                <div>
                  <strong>{device.name}</strong>
                  <span>
                    {device.platform} · {formatDate(device.lastSeenAt ?? device.createdAt)}
                  </span>
                  <span className="mono">{shortId(device.id)}</span>
                </div>
                <div className="row-actions">
                  <button
                    className="icon-button danger-outline"
                    onClick={() => onCleanDevice(device.id)}
                    title="Permanently clean posts created by this device"
                    type="button"
                  >
                    <Trash2 size={15} />
                    Clean posts
                  </button>
                  {device.revokedAt ? (
                    <span className="status-pill muted">Revoked</span>
                  ) : (
                    <button
                      className="danger-button"
                      disabled={device.id === currentDeviceId}
                      onClick={() => onRevokeDevice(device.id)}
                      title={device.id === currentDeviceId ? "Current device" : "Revoke device"}
                      type="button"
                    >
                      <Trash2 size={16} />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Recent Logs</h2>
            <Activity size={18} />
          </div>
          <div className="log-list">
            {logs.map((log, index) => (
              <div className="log-row" key={`${log.time ?? "log"}-${index}`}>
                <span className={`level ${String(log.level ?? "info")}`}>
                  {String(log.level ?? "info")}
                </span>
                <div>
                  <strong>{String(log.event ?? "log")}</strong>
                  <span>{formatDate(log.time)}</span>
                </div>
              </div>
            ))}
          </div>
        </section>
      </section>
    </>
  );
}

function PostsManager({
  devices,
  onChanged,
  reloadSignal,
  token,
}: {
  devices: Device[];
  onChanged: () => void;
  reloadSignal: number;
  token: string;
}) {
  const [posts, setPosts] = useState<AdminPost[]>([]);
  const [selectedPost, setSelectedPost] = useState<AdminPost | null>(null);
  const [deletedFilter, setDeletedFilter] = useState<DeletedFilter>("active");
  const [deviceId, setDeviceId] = useState("");
  const [searchText, setSearchText] = useState("");
  const [appliedSearch, setAppliedSearch] = useState("");
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lightboxMedia, setLightboxMedia] = useState<AdminMedia | null>(null);

  async function loadPosts(reset: boolean) {
    setLoading(true);
    setError(null);

    try {
      const params = new URLSearchParams({
        deleted: deletedFilter,
        limit: appliedSearch ? "100" : "50",
      });

      if (deviceId) {
        params.set("deviceId", deviceId);
      }

      if (appliedSearch) {
        params.set("q", appliedSearch);
      } else if (!reset && nextCursor) {
        params.set("cursor", nextCursor);
      }

      const response = await apiFetch<PostsResponse>(`/api/v1/admin/posts?${params}`, token);
      setPosts((current) => (reset ? response.posts : [...current, ...response.posts]));
      setNextCursor(response.nextCursor);

      if (reset) {
        setSelectedPost(null);
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load posts");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPosts(true);
  }, [deletedFilter, deviceId, appliedSearch, reloadSignal]);

  async function selectPost(postId: string) {
    setError(null);

    try {
      const response = await apiFetch<{ post: AdminPost }>(
        `/api/v1/admin/posts/${postId}`,
        token,
      );
      setSelectedPost(response.post);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load post");
    }
  }

  async function softDeleteSelectedPost() {
    if (!selectedPost) {
      return;
    }

    const confirmed = window.confirm("Soft delete this post and sync the deletion to iPhone?");
    if (!confirmed) {
      return;
    }

    setError(null);

    try {
      const response = await apiFetch<{ post: AdminPost | null }>(
        `/api/v1/admin/posts/${selectedPost.id}`,
        token,
        {
          method: "DELETE",
        },
      );
      setSelectedPost(response.post);
      await loadPosts(true);
      onChanged();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to delete post");
    }
  }

  function submitSearch(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAppliedSearch(searchText.trim());
  }

  function clearSearch() {
    setSearchText("");
    setAppliedSearch("");
  }

  return (
    <section className="posts-manager">
      <div className="panel posts-toolbar">
        <form className="filter-bar" onSubmit={submitSearch}>
          <label>
            <span>Device</span>
            <select onChange={(event) => setDeviceId(event.target.value)} value={deviceId}>
              <option value="">All devices</option>
              {devices.map((device) => (
                <option key={device.id} value={device.id}>
                  {deviceOptionLabel(device)}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span>Deleted</span>
            <select
              onChange={(event) => setDeletedFilter(event.target.value as DeletedFilter)}
              value={deletedFilter}
            >
              <option value="active">Active</option>
              <option value="deleted">Soft deleted</option>
              <option value="all">All</option>
            </select>
          </label>
          <label className="search-label">
            <span>Search</span>
            <div className="search-box">
              <input
                onChange={(event) => setSearchText(event.target.value)}
                placeholder="Search text"
                type="search"
                value={searchText}
              />
              {appliedSearch ? (
                <button className="inline-icon-button" onClick={clearSearch} type="button">
                  <X size={16} />
                </button>
              ) : null}
            </div>
          </label>
          <button className="primary-button" type="submit">
            <Search size={17} />
            Search
          </button>
        </form>
      </div>

      {error ? <div className="banner error">{error}</div> : null}

      <div className="posts-layout">
        <section className="panel posts-list-panel">
          <div className="panel-heading">
            <h2>Posts</h2>
            <span className="status-pill">{posts.length}</span>
          </div>
          <div className="post-list">
            {posts.map((post) => (
              <button
                className={selectedPost?.id === post.id ? "post-row active" : "post-row"}
                key={post.id}
                onClick={() => void selectPost(post.id)}
                type="button"
              >
                <div>
                  <strong>{post.text.trim() || "Image-only moment"}</strong>
                  <span>
                    {formatDate(post.occurredAt)} · {mediaSummary(post.media)}
                  </span>
                  <span>
                    {post.createdByDevice?.name ?? "Unknown device"} · v{post.serverVersion}
                  </span>
                </div>
                <div className="post-row-status">
                  {post.isFavorite ? <Star className="favorite-icon" fill="currentColor" size={15} /> : null}
                  <span className={post.deletedAt ? "status-pill danger" : "status-pill"}>
                    {post.deletedAt ? "deleted" : "active"}
                  </span>
                </div>
              </button>
            ))}
          </div>
          {!appliedSearch && nextCursor ? (
            <button
              className="icon-button load-more-button"
              disabled={loading}
              onClick={() => void loadPosts(false)}
              type="button"
            >
              <RefreshCw size={17} />
              {loading ? "Loading" : "Load more"}
            </button>
          ) : null}
          {loading && !posts.length ? <div className="empty-state">Loading posts</div> : null}
          {!loading && !posts.length ? <div className="empty-state">No posts found</div> : null}
        </section>

        <PostDetailDrawer
          onDelete={() => void softDeleteSelectedPost()}
          onOpenImage={setLightboxMedia}
          post={selectedPost}
          token={token}
        />
      </div>

      {lightboxMedia ? (
        <ImageLightbox
          media={lightboxMedia}
          onClose={() => setLightboxMedia(null)}
          token={token}
        />
      ) : null}
    </section>
  );
}

function PostDetailDrawer({
  onDelete,
  onOpenImage,
  post,
  token,
}: {
  onDelete: () => void;
  onOpenImage: (media: AdminMedia) => void;
  post: AdminPost | null;
  token: string;
}) {
  if (!post) {
    return (
      <aside className="panel post-detail empty-detail">
        <Eye size={22} />
        <p>Select a post to inspect its content, media, devices, and sync metadata.</p>
      </aside>
    );
  }

  const visibleMedia = post.media.filter(
    (media) =>
      !media.deletedAt &&
      (media.kind === "image" || media.kind === "video") &&
      (media.thumbnailUrl || media.compressedUrl),
  );

  return (
    <aside className="panel post-detail">
      <div className="panel-heading">
        <h2>Post Detail</h2>
        <div className="post-row-status">
          {post.isFavorite ? <Star className="favorite-icon" fill="currentColor" size={15} /> : null}
          <span className={post.deletedAt ? "status-pill danger" : "status-pill"}>
            {post.deletedAt ? "deleted" : "active"}
          </span>
        </div>
      </div>

      <div className="post-body-text">{post.text.trim() || "Image-only moment"}</div>

      {visibleMedia.length ? (
        <div className="admin-media-grid">
          {visibleMedia.map((media) => (
            <button
              className="admin-media-thumb"
              disabled={media.kind !== "image"}
              key={media.id}
              onClick={() => onOpenImage(media)}
              type="button"
            >
              <AuthenticatedImage
                alt={`${media.kind} media`}
                className="admin-media-image"
                src={media.thumbnailUrl ?? media.compressedUrl}
                token={token}
              />
              {media.kind === "video" ? (
                <span className="admin-media-badge">
                  <Video size={14} />
                  {formatDuration(media.durationSeconds)}
                </span>
              ) : null}
            </button>
          ))}
        </div>
      ) : null}

      {post.media.some((media) => media.transcriptionText) ? (
        <div className="transcript-list">
          {post.media
            .filter((media) => media.transcriptionText)
            .map((media) => (
              <div className="transcript-block" key={`${media.id}-transcript`}>
                <span>{media.kind} transcript</span>
                <p>{media.transcriptionText}</p>
              </div>
            ))}
        </div>
      ) : null}

      <dl className="details-list compact">
        <div>
          <dt>Occurred</dt>
          <dd>{formatDate(post.occurredAt)}</dd>
        </div>
        <div>
          <dt>Created</dt>
          <dd>{formatDate(post.createdAt)}</dd>
        </div>
        <div>
          <dt>Updated</dt>
          <dd>{formatDate(post.updatedAt)}</dd>
        </div>
        <div>
          <dt>Deleted</dt>
          <dd>{formatDate(post.deletedAt)}</dd>
        </div>
        <div>
          <dt>Created by</dt>
          <dd>{deviceLabel(post.createdByDevice)}</dd>
        </div>
        <div>
          <dt>Updated by</dt>
          <dd>{deviceLabel(post.updatedByDevice)}</dd>
        </div>
        <div>
          <dt>Server version</dt>
          <dd>{post.serverVersion}</dd>
        </div>
        <div>
          <dt>Post id</dt>
          <dd className="mono">{post.id}</dd>
        </div>
      </dl>

      <section className="media-meta">
        <h3>Media</h3>
        {post.media.length ? (
          post.media.map((media) => (
            <div className="media-meta-row" key={media.id}>
              <div>
                <strong>
                  {media.kind} · #{media.sortOrder}
                </strong>
                <span>
                  {media.status}
                  {media.deletedAt ? ` · deleted ${formatDate(media.deletedAt)}` : ""}
                </span>
                <span>
                  {formatBytes(media.compressedSizeBytes ?? 0)}
                  {media.mimeType ? ` · ${media.mimeType}` : ""}
                  {media.durationSeconds ? ` · ${formatDuration(media.durationSeconds)}` : ""}
                  {media.checksum ? ` · ${media.checksum.slice(0, 12)}` : ""}
                </span>
              </div>
              {mediaIcon(media.kind)}
            </div>
          ))
        ) : (
          <p className="muted-text">No media</p>
        )}
      </section>

      {!post.deletedAt ? (
        <button className="primary-button destructive-wide" onClick={onDelete} type="button">
          <Trash2 size={17} />
          Soft delete post
        </button>
      ) : null}
    </aside>
  );
}

function CleanDeviceDialog({
  confirmation,
  onCancel,
  onChangeConfirmation,
  onConfirm,
  preview,
  submitting,
}: {
  confirmation: string;
  onCancel: () => void;
  onChangeConfirmation: (value: string) => void;
  onConfirm: () => void;
  preview: CleanPreview;
  submitting: boolean;
}) {
  const canConfirm = confirmation === preview.device.name && !submitting;

  return (
    <div className="modal-backdrop" role="presentation">
      <section aria-modal="true" className="modal-panel" role="dialog">
        <div>
          <p className="eyebrow danger-text">Danger zone</p>
          <h2>Clean posts from device</h2>
        </div>
        <p>
          This will permanently delete {preview.candidateCount} posts created by{" "}
          <strong>{preview.device.name}</strong>. iPhone devices will receive deletion events on
          next sync.
        </p>
        <label>
          <span>Type device name to confirm</span>
          <input
            autoComplete="off"
            onChange={(event) => onChangeConfirmation(event.target.value)}
            value={confirmation}
          />
        </label>
        <div className="modal-actions">
          <button className="icon-button subtle" disabled={submitting} onClick={onCancel} type="button">
            Cancel
          </button>
          <button
            className="primary-button destructive"
            disabled={!canConfirm}
            onClick={onConfirm}
            type="button"
          >
            <Trash2 size={17} />
            {submitting ? "Cleaning" : "Clean posts"}
          </button>
        </div>
      </section>
    </div>
  );
}
