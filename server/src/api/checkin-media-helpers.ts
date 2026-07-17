import path from "node:path";

import type { MultipartFields } from "@fastify/multipart";

import { parseMediaVariant } from "./media-helpers.js";
import {
  getMultipartInteger,
  getMultipartString,
  isSafePathToken,
} from "./upload-helpers.js";
import { getMultipartFloat } from "./media-upload-fields.js";

export interface CheckInMediaUploadFields {
  mediaId: string;
  entryId: string;
  variant: "compressed";
  kind: "image" | "audio";
  mimeType: string | null;
  durationSeconds: number | null;
  sortOrder: number;
}

export type CheckInMediaUploadFieldsResult =
  | { ok: true; fields: CheckInMediaUploadFields }
  | { ok: false; message: string };

export function parseCheckInMediaUploadFields(
  fields: MultipartFields,
): CheckInMediaUploadFieldsResult {
  const mediaId = getMultipartString(fields, "mediaId");
  const entryId = getMultipartString(fields, "entryId");
  const variant = getMultipartString(fields, "variant");
  const kind = getMultipartString(fields, "kind") ?? "image";
  const mimeType = getMultipartString(fields, "mimeType");
  const durationSeconds = getMultipartFloat(fields, "durationSeconds");
  const sortOrder = getMultipartInteger(fields, "sortOrder") ?? 0;

  if (!mediaId || !entryId || !variant) {
    return { ok: false, message: "mediaId, entryId, and variant are required" };
  }

  if (!isSafePathToken(mediaId)) {
    return { ok: false, message: "mediaId contains unsupported characters" };
  }

  if (parseMediaVariant(variant) !== "compressed") {
    return {
      ok: false,
      message: "check-in media currently supports compressed uploads only",
    };
  }

  if (kind !== "image" && kind !== "audio") {
    return { ok: false, message: "check-in media currently supports image or audio uploads only" };
  }

  if (durationSeconds !== null && (durationSeconds < 0 || durationSeconds > 24 * 60 * 60)) {
    return { ok: false, message: "durationSeconds is invalid" };
  }

  return {
    ok: true,
    fields: {
      mediaId,
      entryId,
      variant: "compressed",
      kind,
      mimeType,
      durationSeconds,
      sortOrder,
    },
  };
}

export function relativeCheckInMediaPath(mediaId: string, extension: string): string {
  if (!isSafePathToken(mediaId)) {
    throw new Error("mediaId contains unsupported characters");
  }

  return path.join("media", "checkins", "compressed", `${mediaId}${extension}`);
}

export function extensionForCheckInMediaMimeType(mimetype: string, filename: string): string {
  if (mimetype === "image/jpeg") {
    return ".jpg";
  }

  if (mimetype === "image/png") {
    return ".png";
  }

  if (mimetype === "image/heic") {
    return ".heic";
  }

  if (mimetype === "image/webp") {
    return ".webp";
  }

  if (mimetype === "audio/mp4" || mimetype === "audio/x-m4a" || mimetype === "audio/m4a") {
    return ".m4a";
  }

  if (mimetype === "audio/aac") {
    return ".aac";
  }

  const extension = path.extname(filename).toLowerCase();
  return extension.length > 0 && extension.length <= 10 ? extension : ".jpg";
}

export function isAllowedCheckInMediaUpload(mimetype: string, kind: CheckInMediaUploadFields["kind"]): boolean {
  if (kind === "image") {
    return mimetype.startsWith("image/");
  }

  return mimetype.startsWith("audio/");
}
