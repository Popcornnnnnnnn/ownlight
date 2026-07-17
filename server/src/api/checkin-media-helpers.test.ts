import assert from "node:assert/strict";
import test from "node:test";

import type { MultipartFields } from "@fastify/multipart";

import {
  extensionForCheckInMediaMimeType,
  isAllowedCheckInMediaUpload,
  parseCheckInMediaUploadFields,
  relativeCheckInMediaPath,
} from "./checkin-media-helpers.js";

function fields(values: Record<string, string>): MultipartFields {
  return Object.fromEntries(
    Object.entries(values).map(([key, value]) => [key, { type: "field", fieldname: key, value }]),
  ) as unknown as MultipartFields;
}

test("parseCheckInMediaUploadFields accepts compressed image and audio uploads", () => {
  const imageParsed = parseCheckInMediaUploadFields(
    fields({
      mediaId: "media-1",
      entryId: "entry-1",
      variant: "compressed",
      kind: "image",
      mimeType: "image/jpeg",
      sortOrder: "2",
    }),
  );

  const audioParsed = parseCheckInMediaUploadFields(
    fields({
      mediaId: "media-2",
      entryId: "entry-2",
      variant: "compressed",
      kind: "audio",
      mimeType: "audio/mp4",
      durationSeconds: "93.5",
      sortOrder: "1",
    }),
  );

  assert.equal(imageParsed.ok, true);
  assert.equal(imageParsed.ok ? imageParsed.fields.variant : null, "compressed");
  assert.equal(imageParsed.ok ? imageParsed.fields.kind : null, "image");
  assert.equal(imageParsed.ok ? imageParsed.fields.sortOrder : null, 2);

  assert.equal(audioParsed.ok, true);
  assert.equal(audioParsed.ok ? audioParsed.fields.kind : null, "audio");
  assert.equal(audioParsed.ok ? audioParsed.fields.durationSeconds : null, 93.5);
  assert.equal(audioParsed.ok ? audioParsed.fields.sortOrder : null, 1);
});

test("parseCheckInMediaUploadFields rejects unsupported kinds, invalid duration, and non-compressed uploads", () => {
  assert.deepEqual(
    parseCheckInMediaUploadFields(
      fields({ mediaId: "../../escaped", entryId: "e", variant: "compressed" }),
    ),
    { ok: false, message: "mediaId contains unsupported characters" },
  );
  assert.deepEqual(
    parseCheckInMediaUploadFields(fields({ mediaId: "m", entryId: "e", variant: "thumbnail" })),
    {
      ok: false,
      message: "check-in media currently supports compressed uploads only",
    },
  );
  assert.deepEqual(
    parseCheckInMediaUploadFields(
      fields({ mediaId: "m", entryId: "e", variant: "compressed", kind: "video" }),
    ),
    { ok: false, message: "check-in media currently supports image or audio uploads only" },
  );
  assert.deepEqual(
    parseCheckInMediaUploadFields(
      fields({ mediaId: "m", entryId: "e", variant: "compressed", kind: "audio", durationSeconds: "999999" }),
    ),
    { ok: false, message: "durationSeconds is invalid" },
  );
});

test("check-in media path helpers keep photos out of ordinary post media paths", () => {
  assert.equal(
    relativeCheckInMediaPath("checkin-media-1", ".jpg"),
    "media/checkins/compressed/checkin-media-1.jpg",
  );
  assert.throws(
    () => relativeCheckInMediaPath("../../escaped", ".jpg"),
    /unsupported characters/,
  );
  assert.equal(extensionForCheckInMediaMimeType("image/png", "photo.bin"), ".png");
  assert.equal(extensionForCheckInMediaMimeType("audio/mp4", "audio.bin"), ".m4a");
  assert.equal(extensionForCheckInMediaMimeType("application/octet-stream", "photo.custom"), ".custom");
  assert.equal(extensionForCheckInMediaMimeType("application/octet-stream", "photo"), ".jpg");
  assert.equal(isAllowedCheckInMediaUpload("image/jpeg", "image"), true);
  assert.equal(isAllowedCheckInMediaUpload("audio/mp4", "audio"), true);
  assert.equal(isAllowedCheckInMediaUpload("audio/mp4", "image"), false);
});
