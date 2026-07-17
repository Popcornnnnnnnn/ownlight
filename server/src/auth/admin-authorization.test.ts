import assert from "node:assert/strict";
import test from "node:test";

import { adminEnabledForPlatform, isAdminDevice } from "./admin-authorization.js";

test("adminEnabledForPlatform grants admin capability only to Mac and web logins", () => {
  assert.equal(adminEnabledForPlatform("mac"), true);
  assert.equal(adminEnabledForPlatform("web"), true);
  assert.equal(adminEnabledForPlatform("ios"), false);
});

test("isAdminDevice checks persisted capability rather than platform text", () => {
  assert.equal(isAdminDevice({ adminEnabled: true }), true);
  assert.equal(isAdminDevice({ adminEnabled: false }), false);
});
