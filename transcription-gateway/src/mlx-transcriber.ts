import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { GatewayConfig, Transcriber, TranscriptionSegment } from "./types.js";
import { TranscriptionGatewayError } from "./types.js";

const execFileAsync = promisify(execFile);
const MAX_STDOUT_BYTES = 8 * 1024 * 1024;

interface LocalTranscriptionOutput {
  text?: unknown;
  language?: unknown;
  segments?: unknown;
}

export function createMlxWhisperTranscriber(config: GatewayConfig): Transcriber {
  return async (request) => {
    try {
      const { stdout } = await execFileAsync(
        config.pythonPath,
        [config.scriptPath, "--audio", request.filePath, "--model", request.model],
        {
          timeout: config.timeoutMs,
          maxBuffer: MAX_STDOUT_BYTES
        }
      );
      const parsed = parseLocalTranscriptionOutput(stdout);
      return {
        text: typeof parsed.text === "string" ? parsed.text.trim() : "",
        language: typeof parsed.language === "string" ? parsed.language : undefined,
        segments: parseSegments(parsed.segments),
        model: request.model
      };
    } catch (error) {
      if (error instanceof TranscriptionGatewayError) {
        throw error;
      }
      if (error instanceof Error && /timed out|timeout/i.test(error.message)) {
        throw new TranscriptionGatewayError("local_transcription_timeout", "Local transcription timed out.", 504);
      }
      throw new TranscriptionGatewayError("local_transcription_failed", "Local transcription failed.", 500);
    }
  };
}

function parseLocalTranscriptionOutput(stdout: string): LocalTranscriptionOutput {
  const jsonLine = stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{") && line.endsWith("}"))
    .at(-1);

  if (!jsonLine) {
    throw new TranscriptionGatewayError(
      "local_transcription_invalid_output",
      "Local transcription output was invalid.",
      502
    );
  }

  try {
    return JSON.parse(jsonLine) as LocalTranscriptionOutput;
  } catch {
    throw new TranscriptionGatewayError(
      "local_transcription_invalid_output",
      "Local transcription output was invalid.",
      502
    );
  }
}

function parseSegments(value: unknown): TranscriptionSegment[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((segment): TranscriptionSegment | undefined => {
      if (!segment || typeof segment !== "object") {
        return undefined;
      }
      const record = segment as Record<string, unknown>;
      const text = typeof record.text === "string" ? record.text.trim() : "";
      if (!text) {
        return undefined;
      }
      return {
        start: typeof record.start === "number" ? record.start : null,
        end: typeof record.end === "number" ? record.end : null,
        text
      };
    })
    .filter((segment): segment is TranscriptionSegment => Boolean(segment));
}
