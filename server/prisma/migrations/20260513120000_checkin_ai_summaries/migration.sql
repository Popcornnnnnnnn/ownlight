ALTER TABLE "checkin_media" ADD COLUMN "duration_seconds" REAL;

CREATE TABLE "checkin_ai_summaries" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "entry_id" TEXT NOT NULL,
    "media_id" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "format" TEXT,
    "language" TEXT,
    "overview" TEXT,
    "key_points_json" TEXT NOT NULL DEFAULT '[]',
    "sections_json" TEXT NOT NULL DEFAULT '[]',
    "summary_text" TEXT,
    "document_title" TEXT,
    "one_liner" TEXT,
    "document_blocks_json" TEXT NOT NULL DEFAULT '[]',
    "input_transcript_hash" TEXT,
    "input_transcript_length" INTEGER,
    "input_duration_seconds" REAL,
    "prompt_version" TEXT NOT NULL,
    "provider" TEXT,
    "model" TEXT,
    "error_code" TEXT,
    "error_message" TEXT,
    "requested_by_device_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    CONSTRAINT "checkin_ai_summaries_entry_id_fkey"
      FOREIGN KEY ("entry_id") REFERENCES "checkin_entries" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "checkin_ai_summaries_media_id_fkey"
      FOREIGN KEY ("media_id") REFERENCES "checkin_media" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "checkin_ai_summaries_requested_by_device_id_fkey"
      FOREIGN KEY ("requested_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "checkin_ai_summaries_media_id_key" ON "checkin_ai_summaries"("media_id");
CREATE INDEX "checkin_ai_summaries_entry_id_idx" ON "checkin_ai_summaries"("entry_id");
CREATE INDEX "checkin_ai_summaries_status_idx" ON "checkin_ai_summaries"("status");
CREATE INDEX "checkin_ai_summaries_deleted_at_idx" ON "checkin_ai_summaries"("deleted_at");
