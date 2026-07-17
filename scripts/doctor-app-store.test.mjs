import assert from "node:assert/strict";
import { test } from "node:test";

import {
  collectPackageManifests,
  dependencyMatchesKnownSdk,
  hasRequiredReason,
  normalizeXcconfigUrl,
  parseUatGates,
  parseXcconfig,
  readPlistValue,
  shouldTreatAsHttpsUrl,
} from "./doctor-app-store.mjs";

test("parseXcconfig keeps empty build settings explicit", () => {
  const parsed = parseXcconfig(`
    PRIVATE_MOMENTS_FALLBACK_SERVER_URL =
    PRIVATE_MOMENTS_SUPPORT_URL = https://private-moments.example/support
    // PRIVATE_MOMENTS_PRIVACY_POLICY_URL = ignored
  `);

  assert.equal(parsed.PRIVATE_MOMENTS_FALLBACK_SERVER_URL, "");
  assert.equal(parsed.PRIVATE_MOMENTS_SUPPORT_URL, "https://private-moments.example/support");
  assert.equal(parsed.PRIVATE_MOMENTS_PRIVACY_POLICY_URL, undefined);
});

test("dependencyMatchesKnownSdk catches analytics and crash packages only by dependency name", () => {
  assert.equal(dependencyMatchesKnownSdk("firebase"), true);
  assert.equal(dependencyMatchesKnownSdk("@sentry/react"), true);
  assert.equal(dependencyMatchesKnownSdk("@segment/analytics-next"), true);
  assert.equal(dependencyMatchesKnownSdk("fastify"), false);
  assert.equal(dependencyMatchesKnownSdk("typescript"), false);
});

test("shouldTreatAsHttpsUrl accepts only public https URLs", () => {
  assert.equal(shouldTreatAsHttpsUrl("https://private-moments.example/privacy"), true);
  assert.equal(normalizeXcconfigUrl("https:/$()/private-moments.example/privacy"), "https://private-moments.example/privacy");
  assert.equal(shouldTreatAsHttpsUrl("https:/$()/private-moments.example/privacy"), true);
  assert.equal(shouldTreatAsHttpsUrl("http://private-moments.example/privacy"), false);
  assert.equal(shouldTreatAsHttpsUrl(""), false);
  assert.equal(shouldTreatAsHttpsUrl("$(PRIVATE_MOMENTS_SUPPORT_URL)"), false);
});

test("hasRequiredReason finds a declared privacy manifest reason", () => {
  const manifest = {
    NSPrivacyAccessedAPITypes: [
      {
        NSPrivacyAccessedAPIType: "NSPrivacyAccessedAPICategoryFileTimestamp",
        NSPrivacyAccessedAPITypeReasons: ["C617.1"],
      },
    ],
  };

  assert.equal(hasRequiredReason(manifest, "NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"), true);
  assert.equal(hasRequiredReason(manifest, "NSPrivacyAccessedAPICategoryFileTimestamp", "3B52.1"), false);
  assert.equal(hasRequiredReason(manifest, "NSPrivacyAccessedAPICategoryDiskSpace", "E174.1"), false);
});

test("parseUatGates counts open and closed release gates", () => {
  const gates = parseUatGates(`
| Gate | Status | Area | Required evidence |
| --- | --- | --- | --- |
| UAT-ONE | Closed | Timeline | Done |
| UAT-TWO | Open | CloudKit | Needs user check |
  `);

  assert.equal(gates.length, 2);
  assert.deepEqual(gates.map((gate) => gate.status), ["closed", "open"]);
});

test("readPlistValue reads nested plist-style objects safely", () => {
  const plist = {
    NSAppTransportSecurity: {
      NSAllowsArbitraryLoads: false,
    },
    ITSAppUsesNonExemptEncryption: false,
  };

  assert.equal(readPlistValue(plist, ["NSAppTransportSecurity", "NSAllowsArbitraryLoads"]), false);
  assert.equal(readPlistValue(plist, ["ITSAppUsesNonExemptEncryption"]), false);
  assert.equal(readPlistValue(plist, ["NSAppTransportSecurity", "Missing"]), undefined);
});

test("collectPackageManifests ignores dependency folders", () => {
  const manifests = collectPackageManifests({
    root: "/repo",
    files: [
      "/repo/package.json",
      "/repo/admin/package.json",
      "/repo/node_modules/package.json",
      "/repo/admin/node_modules/package.json",
      "/repo/ios/build/package.json",
    ],
  });

  assert.deepEqual(manifests, ["/repo/package.json", "/repo/admin/package.json"]);
});
