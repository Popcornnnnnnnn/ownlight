import type { Stats } from "node:fs";
import { lstat, realpath } from "node:fs/promises";
import path from "node:path";

import { isPathInsideOrEqual } from "./path-safety.js";

export async function safeRegularFileStatsInside(
  parentDirectory: string,
  filePath: string,
): Promise<Stats | null> {
  const resolvedParent = await realpath(parentDirectory).catch(() => path.resolve(parentDirectory));
  const resolvedFile = path.resolve(filePath);
  if (!isPathInsideOrEqual(path.resolve(parentDirectory), resolvedFile)) {
    return null;
  }

  try {
    const stats = await lstat(resolvedFile);
    if (!stats.isFile() || stats.nlink > 1) {
      return null;
    }

    const realFile = await realpath(resolvedFile);
    if (!isPathInsideOrEqual(resolvedParent, realFile)) {
      return null;
    }

    return stats;
  } catch {
    return null;
  }
}
