import assert from "node:assert/strict";
import test from "node:test";

import { selectReadyAudioSummaryAnchor } from "./media-audio-groups.js";

test("selectReadyAudioSummaryAnchor waits until all grouped audio uploads are present", () => {
  const uploadedAudio = [
    { id: "audio-2", sortOrder: 1 },
    { id: "audio-1", sortOrder: 0 },
  ];

  assert.equal(selectReadyAudioSummaryAnchor(uploadedAudio, 3), null);
});

test("selectReadyAudioSummaryAnchor returns the first audio item when the group is complete", () => {
  const uploadedAudio = [
    { id: "audio-2", sortOrder: 1 },
    { id: "audio-3", sortOrder: 2 },
    { id: "audio-1", sortOrder: 0 },
  ];

  assert.deepEqual(selectReadyAudioSummaryAnchor(uploadedAudio, 3), {
    mediaId: "audio-1",
    groupCount: 3,
  });
});
