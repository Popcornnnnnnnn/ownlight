import type { AdminMedia, Device, MaintenanceJob } from "./adminApi";

export function formatBytes(value: number): string {
  if (value < 1024) {
    return `${value} B`;
  }

  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }

  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) {
    return "-";
  }

  seconds = Math.round(seconds);
  if (seconds < 60) {
    return `${seconds}s`;
  }

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }

  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

export function jobSummary(job: MaintenanceJob): string {
  if (job.status === "running") {
    return `${job.type} · ${job.progress}%${job.stage ? ` · ${job.stage}` : ""}`;
  }

  if (job.errorCode) {
    return `${job.type} · ${job.errorCode}`;
  }

  return `${job.type} · ${job.status}`;
}

export function mediaSummary(media: AdminMedia[]): string {
  const active = media.filter((item) => !item.deletedAt);
  const images = active.filter((item) => item.kind === "image").length;
  const videos = active.filter((item) => item.kind === "video").length;
  const audio = active.filter((item) => item.kind === "audio").length;
  const parts = [
    images ? `${images} image${images === 1 ? "" : "s"}` : "",
    videos ? `${videos} video${videos === 1 ? "" : "s"}` : "",
    audio ? `${audio} audio` : "",
  ].filter(Boolean);

  return parts.length ? parts.join(", ") : "no media";
}

export function formatDate(value: string | null | undefined): string {
  if (!value) {
    return "-";
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export function shortId(value: string): string {
  return value.slice(0, 8);
}

export function deviceLabel(device: Device | null): string {
  if (!device) {
    return "-";
  }

  return `${device.name} (${shortId(device.id)})`;
}

export function deviceOptionLabel(device: Device): string {
  const state = device.revokedAt ? "revoked" : formatDate(device.lastSeenAt ?? device.createdAt);
  return `${device.name} · ${shortId(device.id)} · ${state}`;
}

export function lastPathSegment(value: string): string {
  return value.split("/").filter(Boolean).at(-1) ?? "";
}

export function startOfLocalDay(value: string): Date {
  return new Date(`${value}T00:00:00`);
}

export function nextLocalDay(value: string): Date {
  const date = startOfLocalDay(value);
  date.setDate(date.getDate() + 1);
  return date;
}
