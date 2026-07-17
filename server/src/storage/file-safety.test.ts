import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { safeRegularFileStatsInside } from "./file-safety.js";

test("safeRegularFileStatsInside accepts regular files inside the parent", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "private-moments-file-safety-"));
  try {
    const filePath = path.join(root, "media", "compressed", "m1.jpg");
    await mkdir(path.dirname(filePath), { recursive: true });
    await writeFile(filePath, "ok", "utf8");

    const stats = await safeRegularFileStatsInside(root, filePath);
    assert.equal(stats?.isFile(), true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("safeRegularFileStatsInside rejects symlinks that point outside the parent", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "private-moments-file-safety-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "private-moments-file-safety-outside-"));
  try {
    const outsideFile = path.join(outside, "secret.txt");
    const linkPath = path.join(root, "secret-link.txt");
    await writeFile(outsideFile, "secret", "utf8");
    await symlink(outsideFile, linkPath);

    assert.equal(await safeRegularFileStatsInside(root, linkPath), null);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
