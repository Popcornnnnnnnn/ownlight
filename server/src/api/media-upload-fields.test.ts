import assert from "node:assert/strict";
import test from "node:test";

import type { MultipartFields } from "@fastify/multipart";

import {
  extensionForMediaMimeType,
  isAllowedMediaUpload,
  parseMediaUploadFields,
  relativeMediaPath,
} from "./media-upload-fields.js";

function fields(values: Record<string, string>): MultipartFields {
  return Object.fromEntries(
    Object.entries(values).map(([key, value]) => [key, { type: "field", fieldname: key, value }]),
  ) as unknown as MultipartFields;
}

test("parseMediaUploadFields parses full audio/video/image metadata safely", () => {
  const parsed = parseMediaUploadFields(
    fields({
      mediaId: "media-1",
      postId: "post-1",
      variant: "compressed",
      kind: "audio",
      mimeType: "audio/mp4",
      durationSeconds: "12.5",
      transcriptionText: "short transcript",
      width: "0",
      height: "0",
      originalPreserved: "true",
      sortOrder: "3",
      aiLanguage: "zh",
      audioGroupCount: "4",
    }),
  );

  assert.equal(parsed.ok, true);
  assert.equal(parsed.ok ? parsed.fields.kind : null, "audio");
  assert.equal(parsed.ok ? parsed.fields.durationSeconds : null, 12.5);
  assert.equal(parsed.ok ? parsed.fields.originalPreserved : null, true);
  assert.equal(parsed.ok ? parsed.fields.aiLanguage : null, "zh");
  assert.equal(parsed.ok ? parsed.fields.audioGroupCount : null, 4);
});

test("parseMediaUploadFields rejects unsupported variants, kinds, and huge transcripts", () => {
  assert.deepEqual(
    parseMediaUploadFields(
      fields({ mediaId: "../escaped", postId: "p", variant: "compressed" }),
    ),
    { ok: false, message: "mediaId contains unsupported characters" },
  );
  assert.deepEqual(
    parseMediaUploadFields(fields({ mediaId: "m", postId: "p", variant: "preview" })),
    { ok: false, message: "variant must be one of: compressed, original, thumbnail" },
  );
  const documentParsed = parseMediaUploadFields(
    fields({ mediaId: "m", postId: "p", variant: "compressed", kind: "document" }),
  );
  assert.equal(documentParsed.ok, true);
  assert.equal(documentParsed.ok ? documentParsed.fields.kind : null, "document");
  assert.deepEqual(
    parseMediaUploadFields(
      fields({
        mediaId: "m",
        postId: "p",
        variant: "compressed",
        transcriptionText: "x".repeat(100_001),
      }),
    ),
    { ok: false, message: "transcriptionText cannot exceed 100000 characters" },
  );
  assert.deepEqual(
    parseMediaUploadFields(
      fields({ mediaId: "m", postId: "p", variant: "compressed", audioGroupCount: "10" }),
    ),
    { ok: false, message: "audioGroupCount must be between 1 and 9" },
  );
});

test("media upload path and mime helpers preserve media pipeline boundaries", () => {
  assert.equal(relativeMediaPath("compressed", "m1", ".jpg"), "media/compressed/m1.jpg");
  assert.equal(relativeMediaPath("original", "m1", ".heic"), "media/originals/m1.heic");
  assert.equal(relativeMediaPath("thumbnail", "m1", ".jpg"), "media/thumbnails/m1.jpg");
  assert.throws(
    () => relativeMediaPath("compressed", "../../../escaped", ".jpg"),
    /unsupported characters/,
  );
  assert.equal(extensionForMediaMimeType("audio/x-m4a", "ignored.bin"), ".m4a");
  assert.equal(extensionForMediaMimeType("application/pdf", "ignored.bin"), ".pdf");
  assert.equal(extensionForMediaMimeType("application/octet-stream", "clip.custom"), ".custom");
  assert.equal(isAllowedMediaUpload("image/jpeg", "image", "compressed"), true);
  assert.equal(isAllowedMediaUpload("video/mp4", "image", "compressed"), false);
  assert.equal(isAllowedMediaUpload("application/octet-stream", "video", "compressed"), true);
  assert.equal(isAllowedMediaUpload("application/pdf", "document", "compressed"), true);
  assert.equal(isAllowedMediaUpload("application/octet-stream", "document", "compressed"), false);
  assert.equal(isAllowedMediaUpload("video/mp4", "video", "thumbnail"), false);
});
