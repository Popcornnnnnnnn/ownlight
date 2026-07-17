ALTER TABLE "devices" ADD COLUMN "admin_enabled" BOOLEAN NOT NULL DEFAULT false;

UPDATE "devices"
SET "admin_enabled" = true
WHERE "platform" IN ('mac', 'web');
