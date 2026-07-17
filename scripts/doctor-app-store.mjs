#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { commandExists, commandOutput, makeReporter, parseArgs, rootDir } from "./lib/doctor-common.mjs";

const appInfoPlistPath = path.join(rootDir, "ios", "PrivateMoments", "Info.plist");
const privacyManifestPath = path.join(rootDir, "ios", "PrivateMoments", "PrivacyInfo.xcprivacy");
const appEntitlementsPath = path.join(rootDir, "ios", "PrivateMoments", "PrivateMoments.entitlements");
const shareEntitlementsPath = path.join(rootDir, "ios", "ShareExtension", "ShareExtension.entitlements");
const publicXcconfigPath = path.join(rootDir, "ios", "Config", "Public.xcconfig");
const localXcconfigPath = path.join(rootDir, "ios", "Config", "Local.xcconfig");
const projectYamlPath = path.join(rootDir, "ios", "project.yml");
const uatGatesPath = path.join(rootDir, "docs", "UAT-GATES.md");

const knownSdkNames = new Set([
  "@amplitude/analytics-browser",
  "@bugsnag/js",
  "@datadog/browser-rum",
  "@datadog/mobile-react-native",
  "@firebase/analytics",
  "@firebase/app",
  "@react-native-firebase/analytics",
  "@react-native-firebase/app",
  "@segment/analytics-next",
  "@sentry/browser",
  "@sentry/react",
  "@sentry/react-native",
  "@sentry/vue",
  "appcenter",
  "appcenter-analytics",
  "appcenter-crashes",
  "amplitude-js",
  "bugsnag",
  "crashlytics",
  "datadog",
  "firebase",
  "firebase-admin",
  "mixpanel",
  "newrelic",
  "posthog-js",
  "sentry",
]);

const iosImportSdkPatterns = [
  /^\s*import\s+Firebase\b/m,
  /^\s*import\s+FirebaseAnalytics\b/m,
  /^\s*import\s+FirebaseCrashlytics\b/m,
  /^\s*import\s+Sentry\b/m,
  /^\s*import\s+Amplitude\b/m,
  /^\s*import\s+Mixpanel\b/m,
  /^\s*import\s+PostHog\b/m,
];

const diskSpaceApiPatterns = [
  "volumeAvailableCapacity",
  "volumeAvailableCapacityForImportantUsage",
  "volumeAvailableCapacityForOpportunisticUsage",
  "systemFreeSize",
  "statfs(",
  "attributesOfFileSystem",
];

const userGrantedMetadataPatterns = [
  "creationDateKey",
  "fileSizeKey",
  "totalFileAllocatedSizeKey",
  "totalFileSizeKey",
  "attributesOfItem",
];

export function parseXcconfig(content) {
  const values = {};
  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("//") || line.startsWith("#include")) {
      continue;
    }

    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) {
      continue;
    }

    const key = match[1];
    const value = match[2].replace(/\s+\/\/.*$/, "").trim();
    values[key] = value;
  }
  return values;
}

export function normalizeXcconfigUrl(value) {
  return String(value ?? "")
    .trim()
    .replaceAll(":/$()/", "://")
    .replaceAll(":/${}/", "://");
}

export function shouldTreatAsHttpsUrl(value) {
  const normalized = normalizeXcconfigUrl(value);
  if (!normalized || normalized.includes("$(")) {
    return false;
  }
  try {
    const url = new URL(normalized);
    return url.protocol === "https:" && Boolean(url.hostname);
  } catch {
    return false;
  }
}

export function dependencyMatchesKnownSdk(name) {
  const normalized = String(name).toLowerCase();
  if (knownSdkNames.has(normalized)) {
    return true;
  }
  if (normalized.startsWith("@sentry/") || normalized.startsWith("@react-native-firebase/")) {
    return true;
  }
  return false;
}

export function collectPackageManifests({ root = rootDir, files } = {}) {
  const candidates = files ?? listFiles(root);
  return candidates
    .filter((filePath) => path.basename(filePath) === "package.json")
    .filter((filePath) => {
      const relative = path.relative(root, filePath);
      const parts = relative.split(path.sep);
      if (parts.some((part) => part === "node_modules" || part === "build" || part === "dist")) {
        return false;
      }
      return !relative.startsWith(".git/");
    })
    .sort((lhs, rhs) => {
      const lhsDepth = path.relative(root, lhs).split(path.sep).length;
      const rhsDepth = path.relative(root, rhs).split(path.sep).length;
      return lhsDepth - rhsDepth || lhs.localeCompare(rhs);
    });
}

export function hasRequiredReason(manifest, category, reason) {
  const entries = manifest?.NSPrivacyAccessedAPITypes;
  if (!Array.isArray(entries)) {
    return false;
  }
  return entries.some((entry) => {
    if (entry?.NSPrivacyAccessedAPIType !== category) {
      return false;
    }
    return Array.isArray(entry.NSPrivacyAccessedAPITypeReasons)
      && entry.NSPrivacyAccessedAPITypeReasons.includes(reason);
  });
}

export function parseUatGates(markdown) {
  return markdown
    .split("\n")
    .filter((line) => /^\|\s*UAT-[A-Z0-9-]+/.test(line))
    .map((line) => {
      const cells = line
        .split("|")
        .slice(1, -1)
        .map((cell) => cell.trim());
      return {
        id: cells[0] ?? "",
        status: (cells[1] ?? "").toLowerCase(),
        area: cells[2] ?? "",
        requiredEvidence: cells[3] ?? "",
      };
    });
}

export function readPlistValue(plist, keys) {
  let current = plist;
  for (const key of keys) {
    if (current == null || typeof current !== "object" || !(key in current)) {
      return undefined;
    }
    current = current[key];
  }
  return current;
}

async function main() {
  const args = parseArgs();
  const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_APP_STORE_STRICT === "1";
  const reporter = makeReporter({ strict });

  checkUatGates(reporter);
  checkInfoPlist(reporter);
  checkPrivacyManifest(reporter);
  checkEntitlements(reporter);
  checkBuildSettings(reporter);
  checkSdkDrift(reporter);
  checkRequiredReasonDrift(reporter);

  reporter.printAndExit();
}

function checkUatGates(reporter) {
  if (!existsSync(uatGatesPath)) {
    reporter.fail("UAT gates", "docs/UAT-GATES.md is missing");
    return;
  }

  const gates = parseUatGates(readFileSync(uatGatesPath, "utf8"));
  if (gates.length === 0) {
    reporter.fail("UAT gates", "no UAT gate rows found");
    return;
  }

  const open = gates.filter((gate) => gate.status !== "closed");
  if (open.length === 0) {
    reporter.pass("UAT gates", `${gates.length} total gates are closed`);
  } else {
    reporter.fail("UAT gates", `${open.length} open UAT gate(s) remain`, open.map((gate) => gate.id).join(", "));
  }
}

function checkInfoPlist(reporter) {
  const plist = readPlist(appInfoPlistPath, reporter, "Info.plist");
  if (!plist) {
    return;
  }

  const requiredStrings = [
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSLocalNetworkUsageDescription",
  ];
  const missing = requiredStrings.filter((key) => !nonPlaceholderString(plist[key]));
  if (missing.length === 0) {
    reporter.pass("Info.plist purpose strings", "required user-facing permission strings are present");
  } else {
    reporter.fail("Info.plist purpose strings", "missing or placeholder permission strings", missing.join(", "));
  }

  const atsArbitraryLoads = readPlistValue(plist, ["NSAppTransportSecurity", "NSAllowsArbitraryLoads"]);
  if (atsArbitraryLoads === false || atsArbitraryLoads === 0) {
    reporter.pass("App Transport Security", "NSAllowsArbitraryLoads is disabled");
  } else {
    reporter.fail("App Transport Security", "NSAllowsArbitraryLoads must stay disabled for App Store builds");
  }

  const usesNonExemptEncryption = plist.ITSAppUsesNonExemptEncryption;
  if (usesNonExemptEncryption === false || usesNonExemptEncryption === 0) {
    reporter.pass("export compliance plist", "ITSAppUsesNonExemptEncryption is false for the current Apple-OS-only encryption posture");
  } else {
    reporter.warn(
      "export compliance plist",
      "ITSAppUsesNonExemptEncryption is not false; App Store Connect will ask export compliance questions for each uploaded build",
    );
  }

  const backgroundModes = plist.UIBackgroundModes;
  if (Array.isArray(backgroundModes) && backgroundModes.includes("audio")) {
    reporter.fail(
      "background audio mode",
      "UIBackgroundModes must not include audio for the v1 foreground-only voice moment workflow; App Review rejected build 1.0 (2) under guideline 2.5.4",
    );
  } else {
    reporter.pass(
      "background audio mode",
      "UIBackgroundModes does not declare audio; v1 voice moments record and play in the foreground only",
    );
  }
}

function checkPrivacyManifest(reporter) {
  const manifest = readPlist(privacyManifestPath, reporter, "PrivacyInfo.xcprivacy");
  if (!manifest) {
    return;
  }

  if (manifest.NSPrivacyTracking === false || manifest.NSPrivacyTracking === 0) {
    reporter.pass("privacy tracking", "NSPrivacyTracking is false");
  } else {
    reporter.fail("privacy tracking", "NSPrivacyTracking must be false unless ATT/tracking is intentionally added");
  }

  if (Array.isArray(manifest.NSPrivacyTrackingDomains) && manifest.NSPrivacyTrackingDomains.length === 0) {
    reporter.pass("privacy tracking domains", "no tracking domains declared");
  } else {
    reporter.fail("privacy tracking domains", "tracking domains are declared", JSON.stringify(manifest.NSPrivacyTrackingDomains ?? null));
  }

  if (Array.isArray(manifest.NSPrivacyCollectedDataTypes) && manifest.NSPrivacyCollectedDataTypes.length === 0) {
    reporter.pass("privacy collected data", "NSPrivacyCollectedDataTypes is empty for the current no-developer-collection posture");
  } else {
    reporter.warn("privacy collected data", "NSPrivacyCollectedDataTypes is not empty; App Privacy Label must match", JSON.stringify(manifest.NSPrivacyCollectedDataTypes ?? null));
  }

  const missingReasons = [];
  if (!hasRequiredReason(manifest, "NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1")) {
    missingReasons.push("FileTimestamp C617.1");
  }
  if (!hasRequiredReason(manifest, "NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1")) {
    missingReasons.push("UserDefaults CA92.1");
  }
  if (missingReasons.length === 0) {
    reporter.pass("required reason APIs", "FileTimestamp C617.1 and UserDefaults CA92.1 are declared");
  } else {
    reporter.fail("required reason APIs", "expected required reason declarations are missing", missingReasons.join(", "));
  }
}

function checkEntitlements(reporter) {
  const appEntitlements = readPlist(appEntitlementsPath, reporter, "PrivateMoments.entitlements");
  const shareEntitlements = readPlist(shareEntitlementsPath, reporter, "ShareExtension.entitlements");
  if (!appEntitlements || !shareEntitlements) {
    return;
  }

  const services = appEntitlements["com.apple.developer.icloud-services"];
  const containers = appEntitlements["com.apple.developer.icloud-container-identifiers"];
  const groups = appEntitlements["com.apple.security.application-groups"];
  if (Array.isArray(services) && services.includes("CloudKit") && Array.isArray(containers) && containers.length === 1) {
    reporter.pass("main app iCloud entitlement", "main app has CloudKit service and one container identifier");
  } else {
    reporter.fail("main app iCloud entitlement", "main app CloudKit entitlement is incomplete");
  }
  if (Array.isArray(groups) && groups.length === 1) {
    reporter.pass("main app group entitlement", "main app has one App Group");
  } else {
    reporter.fail("main app group entitlement", "main app App Group entitlement is missing or ambiguous");
  }

  const shareCloudKeys = Object.keys(shareEntitlements).filter((key) => key.includes("icloud"));
  const shareGroups = shareEntitlements["com.apple.security.application-groups"];
  if (Array.isArray(shareGroups) && shareGroups.length === 1 && shareCloudKeys.length === 0) {
    reporter.pass("share extension entitlement", "Share Extension has App Group only and no CloudKit entitlement");
  } else {
    reporter.fail(
      "share extension entitlement",
      "Share Extension should stay thin with App Group only",
      `groups=${JSON.stringify(shareGroups ?? null)} cloudKeys=${shareCloudKeys.join(", ")}`,
    );
  }
}

function checkBuildSettings(reporter) {
  const publicConfig = readXcconfig(publicXcconfigPath);
  if (!publicConfig) {
    reporter.fail("public build settings", "ios/Config/Public.xcconfig is missing");
    return;
  }

  if ((publicConfig.PRIVATE_MOMENTS_FALLBACK_SERVER_URL ?? "") === "") {
    reporter.pass("public fallback server", "tracked public fallback Server URL is empty");
  } else {
    reporter.fail("public fallback server", "tracked public fallback Server URL must be empty for App Store posture");
  }

  const projectYaml = existsSync(projectYamlPath) ? readFileSync(projectYamlPath, "utf8") : "";
  if (/PRIVATE_MOMENTS_FALLBACK_SERVER_URL:\s*""/.test(projectYaml)) {
    reporter.pass("project fallback server", "project.yml default fallback Server URL is empty");
  } else {
    reporter.fail("project fallback server", "project.yml must keep the default fallback Server URL empty");
  }

  const localConfig = readXcconfig(localXcconfigPath);
  if (!localConfig) {
    reporter.warn("local archive URLs", "ios/Config/Local.xcconfig is missing; final archive must provide HTTPS privacy/support URLs");
    return;
  }

  const supportUrl = localConfig.PRIVATE_MOMENTS_SUPPORT_URL;
  const privacyUrls = [
    localConfig.PRIVATE_MOMENTS_PRIVACY_POLICY_URL,
    localConfig.PRIVATE_MOMENTS_PRIVACY_POLICY_URL_ZH_HANS,
    localConfig.PRIVATE_MOMENTS_PRIVACY_POLICY_URL_EN,
  ];
  const invalidUrls = [
    ["support", supportUrl],
    ["privacy", privacyUrls[0]],
    ["privacy zh-Hans", privacyUrls[1]],
    ["privacy en", privacyUrls[2]],
  ].filter(([, value]) => !shouldTreatAsHttpsUrl(value));

  if (invalidUrls.length === 0) {
    reporter.pass("local archive URLs", "local Privacy/Support URL overrides are HTTPS-compatible");
  } else {
    reporter.warn("local archive URLs", "final archive Privacy/Support URL overrides need HTTPS values", invalidUrls.map(([name]) => name).join(", "));
  }

  const localFallback = normalizeXcconfigUrl(localConfig.PRIVATE_MOMENTS_FALLBACK_SERVER_URL);
  if (!localFallback) {
    reporter.pass("local fallback server", "local fallback Server URL override is empty");
  } else {
    reporter.warn(
      "local fallback server",
      "local owner config has a fallback Server URL; clear it before App Store archive unless the privacy label/review notes intentionally cover developer-hosted service",
      redactUrl(localFallback),
    );
  }
}

function checkSdkDrift(reporter) {
  const manifests = collectPackageManifests();
  const flagged = [];
  for (const manifestPath of manifests) {
    const parsed = JSON.parse(readFileSync(manifestPath, "utf8"));
    const dependencySections = [
      parsed.dependencies ?? {},
      parsed.devDependencies ?? {},
      parsed.peerDependencies ?? {},
      parsed.optionalDependencies ?? {},
    ];
    for (const dependencies of dependencySections) {
      for (const name of Object.keys(dependencies)) {
        if (dependencyMatchesKnownSdk(name)) {
          flagged.push(`${path.relative(rootDir, manifestPath)}:${name}`);
        }
      }
    }
  }

  const iosFiles = listFiles(path.join(rootDir, "ios")).filter((filePath) => /\.(swift|m|mm|h)$/.test(filePath));
  const importHits = [];
  for (const filePath of iosFiles) {
    const content = readFileSync(filePath, "utf8");
    if (iosImportSdkPatterns.some((pattern) => pattern.test(content))) {
      importHits.push(path.relative(rootDir, filePath));
    }
  }

  if (flagged.length === 0 && importHits.length === 0) {
    reporter.pass("third-party SDK drift", "no known analytics/crash/ad/tracking SDK dependencies or iOS imports found");
  } else {
    reporter.fail(
      "third-party SDK drift",
      "known analytics/crash/ad/tracking SDK references found; update privacy manifest/App Privacy Label before archive",
      [...flagged, ...importHits].join(", "),
    );
  }
}

function checkRequiredReasonDrift(reporter) {
  const iosFiles = listFiles(path.join(rootDir, "ios"))
    .filter((filePath) => /\.(swift|m|mm|h)$/.test(filePath))
    .filter((filePath) => !filePath.includes(`${path.sep}build${path.sep}`) && !filePath.includes(`${path.sep}DerivedData${path.sep}`));

  const diskHits = grepPatterns(iosFiles, diskSpaceApiPatterns);
  if (diskHits.length === 0) {
    reporter.pass("disk-space required API drift", "no iOS disk-space required API references found");
  } else {
    reporter.fail("disk-space required API drift", "disk-space required API references found; update PrivacyInfo.xcprivacy", diskHits.join(" | "));
  }

  const shareAndImportFiles = iosFiles.filter((filePath) => {
    const relative = path.relative(rootDir, filePath);
    return relative.startsWith(path.join("ios", "ShareExtension"))
      || relative.includes("Share")
      || relative.includes("Import")
      || relative.includes("File");
  });
  const metadataHits = grepPatterns(shareAndImportFiles, userGrantedMetadataPatterns);
  if (metadataHits.length === 0) {
    reporter.pass("user-granted file metadata drift", "no obvious external import timestamp/size metadata reads found before app-container copy");
  } else {
    reporter.warn(
      "user-granted file metadata drift",
      "file metadata APIs appear in share/import code; confirm all reads are app-container files or add FileTimestamp 3B52.1 if needed",
      metadataHits.slice(0, 8).join(" | "),
    );
  }
}

function readXcconfig(filePath) {
  if (!existsSync(filePath)) {
    return null;
  }
  return parseXcconfig(readFileSync(filePath, "utf8"));
}

function readPlist(filePath, reporter, label) {
  if (!existsSync(filePath)) {
    reporter.fail(label, `${path.relative(rootDir, filePath)} is missing`);
    return null;
  }
  if (!commandExists("plutil")) {
    reporter.fail(label, "plutil is unavailable");
    return null;
  }

  const result = commandOutput("plutil", ["-convert", "json", "-o", "-", filePath], { timeoutMs: 10_000 });
  if (!result.ok) {
    reporter.fail(label, `failed to parse ${path.relative(rootDir, filePath)}`, result.stderr.trim());
    return null;
  }

  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    reporter.fail(label, `invalid JSON emitted by plutil for ${path.relative(rootDir, filePath)}`, error.message);
    return null;
  }
}

function nonPlaceholderString(value) {
  return typeof value === "string" && value.trim() && !value.includes("$(");
}

function listFiles(start) {
  if (!existsSync(start)) {
    return [];
  }
  const output = [];
  const ignoredDirs = new Set([
    ".git",
    ".tmp",
    "node_modules",
    "DerivedData",
    "build",
    "build-device-release",
    "dist",
    ".venv",
  ]);
  const stack = [start];
  while (stack.length > 0) {
    const current = stack.pop();
    const stat = statSync(current);
    if (stat.isDirectory()) {
      if (ignoredDirs.has(path.basename(current))) {
        continue;
      }
      for (const child of readdirSync(current)) {
        stack.push(path.join(current, child));
      }
    } else if (stat.isFile()) {
      output.push(current);
    }
  }
  return output;
}

function grepPatterns(files, patterns) {
  const hits = [];
  for (const filePath of files) {
    const content = readFileSync(filePath, "utf8");
    for (const pattern of patterns) {
      const index = content.indexOf(pattern);
      if (index === -1) {
        continue;
      }
      const line = content.slice(0, index).split("\n").length;
      hits.push(`${path.relative(rootDir, filePath)}:${line}:${pattern}`);
    }
  }
  return hits;
}

function redactUrl(value) {
  try {
    const url = new URL(value);
    return `${url.protocol}//${url.hostname}`;
  } catch {
    return "<configured>";
  }
}

if (path.resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  await main();
}
