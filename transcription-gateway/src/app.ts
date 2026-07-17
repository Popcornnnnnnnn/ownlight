import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { createWriteStream } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { randomUUID } from "node:crypto";

import type { GatewayConfig, Transcriber } from "./types.js";
import { TranscriptionGatewayError } from "./types.js";

interface BuildGatewayAppOptions {
  config: GatewayConfig;
  transcribe: Transcriber;
}

interface UploadedFile {
  filePath: string;
  fileName: string;
  mimeType: string;
}

class SingleConcurrencyQueue {
  private tail: Promise<void> = Promise.resolve();

  run<T>(task: () => Promise<T>): Promise<T> {
    const result = this.tail.then(task, task);
    this.tail = result.then(
      () => undefined,
      () => undefined
    );
    return result;
  }
}

export function buildGatewayApp(options: BuildGatewayAppOptions): FastifyInstance {
  const { config, transcribe } = options;
  const queue = new SingleConcurrencyQueue();
  const app = Fastify({ logger: false });

  app.register(multipart, {
    limits: {
      files: 1,
      fields: 8,
      parts: 10,
      fileSize: config.maxFileBytes
    }
  });

  app.addHook("preHandler", async (request, reply) => {
    if (request.headers.authorization !== `Bearer ${config.token}`) {
      return reply.code(401).send({
        error: "unauthorized",
        message: "A valid bearer token is required."
      });
    }
  });

  app.get("/health", async () => ({
    ok: true,
    service: "private-moments-transcription-gateway",
    provider: "local-gateway",
    engine: "mlx-whisper",
    status: "ready",
    model: config.defaultModel,
    concurrency: 1
  }));

  app.get("/v1/models", async () => ({
    object: "list",
    data: [
      {
        id: config.defaultModel,
        object: "model",
        owned_by: "local-gateway"
      }
    ]
  }));

  app.post("/v1/audio/transcriptions", async (request, reply) => {
    let tmpDir: string | undefined;

    try {
      tmpDir = await mkdtemp(path.join(os.tmpdir(), "private-moments-transcription-"));
      const { uploadedFile, fields } = await readMultipartUpload(request, tmpDir);
      if (!uploadedFile) {
        return reply.code(400).send({
          error: "missing_file",
          message: "Multipart field `file` is required."
        });
      }

      const model = normalizeField(fields.model) || config.defaultModel;
      const language = normalizeField(fields.language);
      const result = await queue.run(() =>
        transcribe({
          ...uploadedFile,
          model,
          language
        })
      );
      const text = result.text.trim();
      if (!text) {
        return reply.code(422).send({
          error: "empty_transcript",
          message: "Local transcription returned no speech text."
        });
      }

      return {
        text,
        language: result.language,
        segments: result.segments ?? [],
        model: result.model ?? model,
        provider: "local-gateway"
      };
    } catch (error) {
      if (error instanceof TranscriptionGatewayError) {
        return reply.code(error.statusCode).send({
          error: error.code,
          message: error.message
        });
      }
      request.log.error({ error }, "Transcription gateway request failed");
      return reply.code(500).send({
        error: "transcription_failed",
        message: "Transcription failed."
      });
    } finally {
      if (tmpDir) {
        await rm(tmpDir, { recursive: true, force: true });
      }
    }
  });

  return app;
}

async function readMultipartUpload(
  request: FastifyRequest,
  tmpDir: string
): Promise<{ uploadedFile?: UploadedFile; fields: Record<string, string> }> {
  const fields: Record<string, string> = {};
  let uploadedFile: UploadedFile | undefined;

  for await (const part of request.parts()) {
    if (part.type === "file") {
      if (part.fieldname !== "file") {
        part.file.resume();
        continue;
      }
      if (uploadedFile) {
        throw new TranscriptionGatewayError("too_many_files", "Only one audio file can be uploaded.", 400);
      }
      const fileName = sanitizeFileName(part.filename || "audio-upload");
      const filePath = path.join(tmpDir, `${randomUUID()}-${fileName}`);
      await pipeline(part.file, createWriteStream(filePath));
      uploadedFile = {
        filePath,
        fileName,
        mimeType: part.mimetype || "application/octet-stream"
      };
    } else {
      const fieldValue = typeof part.value === "string" ? part.value : String(part.value ?? "");
      fields[part.fieldname] = fieldValue;
    }
  }

  return { uploadedFile, fields };
}

function sanitizeFileName(value: string): string {
  const baseName = path.basename(value).replace(/[^A-Za-z0-9._-]/g, "_");
  return baseName || "audio-upload";
}

function normalizeField(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}
