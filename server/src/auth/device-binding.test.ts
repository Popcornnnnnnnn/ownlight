import assert from "node:assert/strict";
import test from "node:test";

import { upsertLoginDevice } from "./device-binding.js";

const baseInput = {
  userId: "user-1",
  deviceName: "Personal iPhone",
  deviceKey: "stable-device-key",
  platform: "ios",
  adminEnabled: false,
  tokenHash: "token-hash",
};

test("upsertLoginDevice rebinds an existing device by stable deviceKey", async () => {
  let updateInput: unknown = null;
  const prisma = {
    device: {
      findUnique: async () => ({ id: "device-by-key" }),
      update: async (input: unknown) => {
        updateInput = input;
        return { id: "device-by-key", name: baseInput.deviceName, platform: "ios", adminEnabled: false };
      },
    },
  };

  const device = await upsertLoginDevice(prisma as never, baseInput);

  assert.equal(device.id, "device-by-key");
  assert.equal(device.wasCreated, false);
  assert.deepEqual((updateInput as { where: { id: string } }).where, { id: "device-by-key" });
  assert.equal((updateInput as { data: { revokedAt: null } }).data.revokedAt, null);
  assert.equal((updateInput as { data: { adminEnabled: boolean } }).data.adminEnabled, false);
});

test("upsertLoginDevice upgrades a legacy same-name device to the stable deviceKey", async () => {
  let findFirstInput: unknown = null;
  let updateInput: unknown = null;
  const prisma = {
    device: {
      findUnique: async () => null,
      findFirst: async (input: unknown) => {
        findFirstInput = input;
        return { id: "legacy-device" };
      },
      update: async (input: unknown) => {
        updateInput = input;
        return { id: "legacy-device", name: baseInput.deviceName, platform: "ios", adminEnabled: false };
      },
    },
  };

  const device = await upsertLoginDevice(prisma as never, baseInput);

  assert.equal(device.id, "legacy-device");
  assert.equal(device.wasCreated, false);
  assert.equal((findFirstInput as { where: { deviceKey: null } }).where.deviceKey, null);
  assert.equal((updateInput as { data: { deviceKey: string } }).data.deviceKey, baseInput.deviceKey);
  assert.equal((updateInput as { data: { adminEnabled: boolean } }).data.adminEnabled, false);
});

test("upsertLoginDevice creates a new row when no binding candidate exists", async () => {
  let createInput: unknown = null;
  const prisma = {
    device: {
      findUnique: async () => null,
      findFirst: async () => null,
      create: async (input: unknown) => {
        createInput = input;
        return { id: "new-device", name: baseInput.deviceName, platform: "ios", adminEnabled: false };
      },
    },
  };

  const device = await upsertLoginDevice(prisma as never, baseInput);

  assert.equal(device.id, "new-device");
  assert.equal(device.wasCreated, true);
  assert.equal((createInput as { data: { deviceKey: string } }).data.deviceKey, baseInput.deviceKey);
  assert.equal((createInput as { data: { adminEnabled: boolean } }).data.adminEnabled, false);
});
