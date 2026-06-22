#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const bridgeContract = JSON.parse(fs.readFileSync(path.join(root, "docs/bridge-contract.json"), "utf8"));
const variants = JSON.parse(fs.readFileSync(path.join(root, "docs/app-variants.json"), "utf8"));

const allowedPlatforms = new Set(["ios", "android"]);
const allowedReleaseChannels = new Set(["development", "staging", "production"]);
const allowedStartupModes = new Set(["fixed-url", "local-bundled", "qr-provisioned", "high-availability"]);
const allowedSecurityTokenPolicies = new Set(["none", "ci-secret", "qr-provisioned", "ci-secret-or-qr-provisioned", "runtime-only"]);
const bridgeActions = new Set((bridgeContract.actions || []).map((action) => action.name));
const bridgeActionByName = new Map((bridgeContract.actions || []).map((action) => [action.name, action]));
const optionalModuleCatalog = variants.optionalModuleCatalog || {};
const optionalModuleIds = new Set(Object.keys(optionalModuleCatalog));

function usage() {
  return [
    "Usage:",
    "  node path/to/swiftHTMLWebviewApp/tools/variant_manifest_check.js --file <native/variant.json> [--json] [--decision-template]",
    "  node path/to/swiftHTMLWebviewApp/tools/variant_manifest_check.js --stdin [--json] [--decision-template]",
    "",
    "Validates a private product native/variant.json manifest.",
    "The command does not edit files."
  ].join("\n");
}

function argValue(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) {
    return "";
  }
  return process.argv[index + 1];
}

function fail(message) {
  console.error(message);
  console.error("");
  console.error(usage());
  process.exit(1);
}

function readInput() {
  if (process.argv.includes("--stdin")) {
    return fs.readFileSync(0, "utf8");
  }
  const file = argValue("--file").trim();
  if (!file) {
    fail("--file or --stdin is required.");
  }
  return fs.readFileSync(path.resolve(process.cwd(), file), "utf8");
}

function parseManifest() {
  try {
    return JSON.parse(readInput());
  } catch (error) {
    fail(`Variant manifest is not valid JSON: ${error.message}`);
  }
}

function isObject(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function addRequiredString(errors, object, pathName) {
  const parts = pathName.split(".");
  const field = parts[parts.length - 1];
  if (!isNonEmptyString(object && object[field])) {
    errors.push(`${pathName} is required.`);
  }
}

function uniqueStrings(values) {
  if (!Array.isArray(values)) {
    return [];
  }
  return values.filter(isNonEmptyString);
}

function hasDuplicates(values) {
  return new Set(values).size !== values.length;
}

function isKebabCase(value) {
  return /^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(value);
}

function isReverseDNS(value) {
  return /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/.test(value);
}

function isGradleModule(value) {
  return /^:[a-z0-9][a-z0-9-]*(?::[a-z0-9][a-z0-9-]*)*$/.test(value);
}

function isRelativePath(value) {
  if (!isNonEmptyString(value)) {
    return false;
  }
  return !path.isAbsolute(value) && !value.split(/[\\/]/).includes("..");
}

function isNativeAssetPath(value) {
  return isRelativePath(value) && /^native\/assets\/[^/].+/i.test(value.replaceAll("\\", "/"));
}

function parseURL(value) {
  try {
    return new URL(value);
  } catch (_) {
    return null;
  }
}

function looksLikeSecret(value) {
  if (!isNonEmptyString(value)) {
    return false;
  }
  if (/change-me-before-production/i.test(value)) {
    return true;
  }
  return /(sk_live|sk_test|pk_live|rk_live|secret|token=|api[_-]?key=|bearer\s+)/i.test(value);
}

function checkUnknownKeys(errors, object, allowedKeys, pathName) {
  for (const key of Object.keys(object || {})) {
    if (!allowedKeys.includes(key)) {
      errors.push(`${pathName}.${key} is not supported by this manifest schema.`);
    }
  }
}

function validatePlatformSection(report, manifest, platform) {
  if (platform === "ios") {
    if (!isObject(manifest.ios)) {
      report.errors.push("ios section is required because platforms contains ios.");
      return;
    }
    checkUnknownKeys(report.errors, manifest.ios, ["bundleIdentifier", "productName", "displayName", "scheme"], "ios");
    addRequiredString(report.errors, manifest.ios, "ios.bundleIdentifier");
    addRequiredString(report.errors, manifest.ios, "ios.productName");
    addRequiredString(report.errors, manifest.ios, "ios.displayName");
    if (isNonEmptyString(manifest.ios.bundleIdentifier) && !isReverseDNS(manifest.ios.bundleIdentifier)) {
      report.errors.push("ios.bundleIdentifier must use reverse-DNS notation.");
    }
  }

  if (platform === "android") {
    if (!isObject(manifest.android)) {
      report.errors.push("android section is required because platforms contains android.");
      return;
    }
    checkUnknownKeys(report.errors, manifest.android, ["gradleModule", "applicationId", "namespace", "label"], "android");
    addRequiredString(report.errors, manifest.android, "android.gradleModule");
    addRequiredString(report.errors, manifest.android, "android.applicationId");
    addRequiredString(report.errors, manifest.android, "android.namespace");
    addRequiredString(report.errors, manifest.android, "android.label");
    if (isNonEmptyString(manifest.android.gradleModule) && !isGradleModule(manifest.android.gradleModule)) {
      report.errors.push("android.gradleModule must look like :my-app or :group:my-app.");
    }
    for (const field of ["applicationId", "namespace"]) {
      if (isNonEmptyString(manifest.android[field]) && !isReverseDNS(manifest.android[field])) {
        report.errors.push(`android.${field} must use reverse-DNS notation.`);
      }
    }
  }
}

function validateStartup(report, startup) {
  if (!isObject(startup)) {
    report.errors.push("startup section is required.");
    return;
  }
  checkUnknownKeys(report.errors, startup, ["mode", "serverURL", "securityTokenPolicy", "highAvailability"], "startup");
  addRequiredString(report.errors, startup, "startup.mode");
  addRequiredString(report.errors, startup, "startup.serverURL");
  addRequiredString(report.errors, startup, "startup.securityTokenPolicy");
  if (isNonEmptyString(startup.mode) && !allowedStartupModes.has(startup.mode)) {
    report.errors.push(`startup.mode must be one of ${[...allowedStartupModes].join(", ")}.`);
  }
  if (isNonEmptyString(startup.securityTokenPolicy) && !allowedSecurityTokenPolicies.has(startup.securityTokenPolicy)) {
    report.errors.push(`startup.securityTokenPolicy must be one of ${[...allowedSecurityTokenPolicies].join(", ")}.`);
  }
  if (isNonEmptyString(startup.serverURL)) {
    const url = parseURL(startup.serverURL);
    if (!url && !["local-bundled", "qr-provisioned"].includes(startup.mode)) {
      report.errors.push("startup.serverURL must be a valid URL unless startup.mode is local-bundled or qr-provisioned.");
    }
    if (url && !["http:", "https:", "file:"].includes(url.protocol)) {
      report.errors.push("startup.serverURL must use http, https, or file protocol.");
    }
    if (looksLikeSecret(startup.serverURL)) {
      report.errors.push("startup.serverURL must not contain embedded tokens, API keys, or secrets.");
    }
  }
  if (looksLikeSecret(startup.securityTokenPolicy)) {
    report.errors.push("startup.securityTokenPolicy must describe a policy, not contain a raw token.");
  }
}

function validateBranding(report, branding) {
  if (!isObject(branding)) {
    report.errors.push("branding section is required.");
    return;
  }
  checkUnknownKeys(
    report.errors,
    branding,
    [
      "iconSource",
      "loadingImageSource",
      "loadingImageName",
      "recoveryShortMark",
      "recoveryTitle",
      "recoveryBody",
      "recoveryQRCodeDetectedMessage",
      "recoveryInvalidQRMessage"
    ],
    "branding"
  );
  for (const field of [
    "iconSource",
    "loadingImageSource",
    "loadingImageName",
    "recoveryShortMark",
    "recoveryTitle",
    "recoveryBody",
    "recoveryQRCodeDetectedMessage",
    "recoveryInvalidQRMessage"
  ]) {
    addRequiredString(report.errors, branding, `branding.${field}`);
  }
  if (isNonEmptyString(branding.iconSource) && !isNativeAssetPath(branding.iconSource)) {
    report.errors.push("branding.iconSource must be a relative path under native/assets/.");
  }
  if (isNonEmptyString(branding.loadingImageSource) && !isNativeAssetPath(branding.loadingImageSource)) {
    report.errors.push("branding.loadingImageSource must be a relative path under native/assets/.");
  }
  if (isNonEmptyString(branding.loadingImageName) && !/^[A-Za-z0-9_-]+$/.test(branding.loadingImageName)) {
    report.errors.push("branding.loadingImageName must be an asset name, not a path.");
  }
}

function validateFeatures(report, features, platforms) {
  if (!isObject(features)) {
    report.errors.push("features section is required.");
    return;
  }
  checkUnknownKeys(report.errors, features, ["requiredCapabilities", "optionalModules", "excludedCapabilities"], "features");

  for (const field of ["requiredCapabilities", "optionalModules", "excludedCapabilities"]) {
    if (!Array.isArray(features[field])) {
      report.errors.push(`features.${field} must be an array.`);
    } else if (hasDuplicates(features[field])) {
      report.errors.push(`features.${field} must not contain duplicates.`);
    }
  }

  for (const action of uniqueStrings(features.requiredCapabilities)) {
    const contractAction = bridgeActionByName.get(action);
    if (!contractAction) {
      report.errors.push(`features.requiredCapabilities contains unknown bridge action: ${action}`);
      continue;
    }
    for (const platform of platforms.filter((candidate) => allowedPlatforms.has(candidate))) {
      if (contractAction[platform] === "unavailable") {
        report.errors.push(`features.requiredCapabilities.${action} is unavailable on ${platform}.`);
      }
      if (contractAction[platform] === "optional") {
        const enabledOptionalModules = uniqueStrings(features.optionalModules);
        const coveredByModule = enabledOptionalModules.some((moduleId) => {
          const module = optionalModuleCatalog[moduleId];
          return module && Array.isArray(module.actions) && module.actions.includes(action);
        });
        if (!coveredByModule) {
          report.errors.push(`features.requiredCapabilities.${action} requires an optional module on ${platform}.`);
        }
      }
    }
  }
  for (const action of uniqueStrings(features.excludedCapabilities)) {
    if (!bridgeActions.has(action)) {
      report.errors.push(`features.excludedCapabilities contains unknown bridge action: ${action}`);
    }
  }
  for (const action of uniqueStrings(features.requiredCapabilities)) {
    if (uniqueStrings(features.excludedCapabilities).includes(action)) {
      report.errors.push(`features.${action} cannot be both required and excluded.`);
    }
  }
  for (const moduleId of uniqueStrings(features.optionalModules)) {
    const module = optionalModuleCatalog[moduleId];
    if (!module) {
      report.errors.push(`features.optionalModules contains unknown optional module: ${moduleId}`);
      continue;
    }
    const modulePlatforms = Array.isArray(module.platforms) ? module.platforms : [];
    if (!platforms.every((platform) => modulePlatforms.includes(platform))) {
      report.errors.push(`features.optionalModules.${moduleId} does not support selected platforms: ${platforms.join(", ")}`);
    }
  }
}

function unavailableActionsFor(platform) {
  return (bridgeContract.actions || [])
    .filter((action) => action && action[platform] === "unavailable")
    .map((action) => action.name)
    .sort();
}

function validateBridgeProfile(report, bridgeProfile, platforms, features) {
  if (bridgeProfile === undefined) {
    report.warnings.push("bridgeProfile is missing; unavailable actions will be derived from docs/bridge-contract.json.");
    return;
  }
  if (!isObject(bridgeProfile)) {
    report.errors.push("bridgeProfile must be an object when present.");
    return;
  }
  checkUnknownKeys(report.errors, bridgeProfile, ["ios", "android"], "bridgeProfile");
  for (const platform of platforms.filter((candidate) => allowedPlatforms.has(candidate))) {
    const profile = bridgeProfile[platform];
    if (!isObject(profile)) {
      report.errors.push(`bridgeProfile.${platform} is required because platforms contains ${platform}.`);
      continue;
    }
    checkUnknownKeys(report.errors, profile, ["enabledOptionalModules", "unavailableActions"], `bridgeProfile.${platform}`);
    if (!Array.isArray(profile.enabledOptionalModules)) {
      report.errors.push(`bridgeProfile.${platform}.enabledOptionalModules must be an array.`);
    }
    if (!Array.isArray(profile.unavailableActions)) {
      report.errors.push(`bridgeProfile.${platform}.unavailableActions must be an array.`);
    }
    if (hasDuplicates(profile.enabledOptionalModules || [])) {
      report.errors.push(`bridgeProfile.${platform}.enabledOptionalModules must not contain duplicates.`);
    }
    if (hasDuplicates(profile.unavailableActions || [])) {
      report.errors.push(`bridgeProfile.${platform}.unavailableActions must not contain duplicates.`);
    }
    const enabledOptionalModules = uniqueStrings(profile.enabledOptionalModules);
    for (const moduleId of enabledOptionalModules) {
      if (!optionalModuleIds.has(moduleId)) {
        report.errors.push(`bridgeProfile.${platform}.enabledOptionalModules contains unknown optional module: ${moduleId}`);
      }
    }
    const featureModules = uniqueStrings(features && features.optionalModules);
    if (enabledOptionalModules.sort().join("\n") !== featureModules.sort().join("\n")) {
      report.errors.push(`bridgeProfile.${platform}.enabledOptionalModules must match features.optionalModules.`);
    }
    const expectedUnavailable = unavailableActionsFor(platform);
    const actualUnavailable = uniqueStrings(profile.unavailableActions);
    const missing = expectedUnavailable.filter((action) => !actualUnavailable.includes(action));
    const extra = actualUnavailable.filter((action) => !expectedUnavailable.includes(action));
    if (missing.length > 0 || extra.length > 0) {
      report.errors.push(
        `bridgeProfile.${platform}.unavailableActions must match bridge contract unavailable actions (missing: ${missing.join(", ") || "-"}; extra: ${extra.join(", ") || "-"}).`
      );
    }
  }
  for (const platform of ["ios", "android"]) {
    if (!platforms.includes(platform) && bridgeProfile[platform] !== undefined) {
      report.warnings.push(`bridgeProfile.${platform} is ignored because platforms does not contain ${platform}.`);
    }
  }
}

function validateVerification(report, verification, platforms) {
  if (verification === undefined) {
    report.errors.push("verification section is required.");
    return;
  }
  if (!isObject(verification)) {
    report.errors.push("verification must be an object when present.");
    return;
  }
  checkUnknownKeys(
    report.errors,
    verification,
    ["iosBuildCommand", "iosTestCommand", "androidBuildCommand", "androidTestCommand", "variantBoundaryTests"],
    "verification"
  );
  if (platforms.includes("ios")) {
    addRequiredString(report.errors, verification, "verification.iosBuildCommand");
    addRequiredString(report.errors, verification, "verification.iosTestCommand");
  }
  if (platforms.includes("android")) {
    addRequiredString(report.errors, verification, "verification.androidBuildCommand");
    addRequiredString(report.errors, verification, "verification.androidTestCommand");
  }
  if (!Array.isArray(verification.variantBoundaryTests) || verification.variantBoundaryTests.length === 0) {
    report.errors.push("verification.variantBoundaryTests must contain at least one test marker.");
    return;
  }
  verification.variantBoundaryTests.forEach((test, index) => {
    if (!isObject(test)) {
      report.errors.push(`verification.variantBoundaryTests[${index}] must be an object.`);
      return;
    }
    checkUnknownKeys(report.errors, test, ["file", "contains"], `verification.variantBoundaryTests[${index}]`);
    addRequiredString(report.errors, test, `verification.variantBoundaryTests[${index}].file`);
    addRequiredString(report.errors, test, `verification.variantBoundaryTests[${index}].contains`);
  });
}

function validateRequiredTopLevelSections(report, manifest) {
  for (const section of ["startup", "branding", "features", "bridgeProfile", "verification"]) {
    if (manifest[section] === undefined) {
      report.errors.push(`${section} section is required.`);
    }
  }
}

function validateManifest(manifest) {
  const report = {
    valid: false,
    errors: [],
    warnings: [],
    decisionTemplate: null
  };

  if (!isObject(manifest)) {
    report.errors.push("manifest must be a JSON object.");
    return report;
  }

  checkUnknownKeys(
    report.errors,
    manifest,
    ["schemaVersion", "id", "name", "wrapperVersion", "releaseChannel", "platforms", "ios", "android", "startup", "branding", "features", "bridgeProfile", "verification", "store"],
    "manifest"
  );

  if (manifest.schemaVersion !== 1) {
    report.errors.push("schemaVersion must be 1.");
  }
  addRequiredString(report.errors, manifest, "id");
  addRequiredString(report.errors, manifest, "name");
  addRequiredString(report.errors, manifest, "wrapperVersion");
  addRequiredString(report.errors, manifest, "releaseChannel");
  validateRequiredTopLevelSections(report, manifest);
  if (isNonEmptyString(manifest.id) && !isKebabCase(manifest.id)) {
    report.errors.push("id must be kebab-case with lowercase letters, numbers, and dashes.");
  }
  if (isNonEmptyString(manifest.releaseChannel) && !allowedReleaseChannels.has(manifest.releaseChannel)) {
    report.errors.push(`releaseChannel must be one of ${[...allowedReleaseChannels].join(", ")}.`);
  }
  if (!Array.isArray(manifest.platforms) || manifest.platforms.length === 0) {
    report.errors.push("platforms must contain at least one platform.");
  }

  const platforms = uniqueStrings(manifest.platforms);
  if (hasDuplicates(platforms)) {
    report.errors.push("platforms must not contain duplicates.");
  }
  for (const platform of platforms) {
    if (!allowedPlatforms.has(platform)) {
      report.errors.push(`platforms contains unknown platform: ${platform}`);
    }
  }

  for (const platform of platforms.filter((platform) => allowedPlatforms.has(platform))) {
    validatePlatformSection(report, manifest, platform);
  }
  validateStartup(report, manifest.startup);
  validateBranding(report, manifest.branding);
  validateFeatures(report, manifest.features, platforms);
  validateBridgeProfile(report, manifest.bridgeProfile, platforms, manifest.features);
  validateVerification(report, manifest.verification, platforms);
  validateReleaseChannel(report, manifest, platforms);

  if (!platforms.includes("ios") && manifest.ios !== undefined) {
    report.warnings.push("ios section is ignored because platforms does not contain ios.");
  }
  if (!platforms.includes("android") && manifest.android !== undefined) {
    report.warnings.push("android section is ignored because platforms does not contain android.");
  }

  report.valid = report.errors.length === 0;
  if (report.valid) {
    report.decisionTemplate = decisionTemplateForManifest(manifest, platforms);
  }
  return report;
}

function validateReleaseChannel(report, manifest, platforms) {
  if (manifest.releaseChannel !== "production") {
    return;
  }
  const startupURL = manifest.startup && manifest.startup.serverURL;
  const url = parseURL(startupURL);
  if (url && url.protocol !== "https:") {
    report.errors.push("production startup.serverURL must use https.");
  }
  if (isNonEmptyString(startupURL) && /(example\.invalid|localhost|127\.0\.0\.1|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/i.test(startupURL)) {
    report.errors.push("production startup.serverURL must not point to example, localhost, or private LAN addresses.");
  }
  if (/example|demo/i.test(manifest.name || "")) {
    report.errors.push("production name must not look like an example/demo placeholder.");
  }
  if (platforms.includes("ios") && /example|invalid/i.test((manifest.ios && manifest.ios.bundleIdentifier) || "")) {
    report.errors.push("production ios.bundleIdentifier must not use example/invalid placeholder domains.");
  }
  if (platforms.includes("android") && /example|invalid/i.test((manifest.android && manifest.android.applicationId) || "")) {
    report.errors.push("production android.applicationId must not use example/invalid placeholder domains.");
  }
}

function answerMapFor(manifest) {
  return {
    identity: {
      bundleIdentifier: manifest.ios && manifest.ios.bundleIdentifier,
      productName: manifest.ios && manifest.ios.productName,
      displayName: manifest.ios && manifest.ios.displayName,
      gradleModule: manifest.android && manifest.android.gradleModule,
      applicationId: manifest.android && manifest.android.applicationId,
      namespace: manifest.android && manifest.android.namespace,
      label: manifest.android && manifest.android.label,
      storeIdentity: manifest.store && manifest.store.identity
    },
    branding: {
      iconSource: manifest.branding.iconSource,
      loadingImageName: manifest.branding.loadingImageName,
      loadingImageSource: manifest.branding.loadingImageSource,
      recoveryShortMark: manifest.branding.recoveryShortMark,
      recoveryTitle: manifest.branding.recoveryTitle,
      recoveryBody: manifest.branding.recoveryBody,
      recoveryQRCodeDetectedMessage: manifest.branding.recoveryQRCodeDetectedMessage,
      recoveryInvalidQRMessage: manifest.branding.recoveryInvalidQRMessage
    },
    "startup-provisioning": {
      startupMode: manifest.startup.mode,
      serverURL: manifest.startup.serverURL,
      securityTokenPolicy: manifest.startup.securityTokenPolicy,
      highAvailability: manifest.startup.highAvailability
    },
    "native-capabilities": {
      requiredCapabilities: manifest.features.requiredCapabilities,
      optionalModules: manifest.features.optionalModules,
      excludedCapabilities: manifest.features.excludedCapabilities
    },
    "bridge-profile": {
      contractPlatform: manifest.platforms.length === 1 ? manifest.platforms[0] : "ios",
      enabledOptionalModules: manifest.bridgeProfile && manifest.bridgeProfile.ios
        ? manifest.bridgeProfile.ios.enabledOptionalModules
        : manifest.features.optionalModules,
      unavailableActions: manifest.bridgeProfile && manifest.bridgeProfile.ios
        ? manifest.bridgeProfile.ios.unavailableActions
        : unavailableActionsFor("ios"),
      platformProfiles: Object.fromEntries(
        manifest.platforms.map((platform) => [
          platform,
          {
            contractPlatform: platform,
            enabledOptionalModules: manifest.bridgeProfile && manifest.bridgeProfile[platform]
              ? manifest.bridgeProfile[platform].enabledOptionalModules
              : manifest.features.optionalModules,
            unavailableActions: manifest.bridgeProfile && manifest.bridgeProfile[platform]
              ? manifest.bridgeProfile[platform].unavailableActions
              : unavailableActionsFor(platform)
          }
        ])
      )
    },
    verification: {
      iosBuildCommand: manifest.verification && manifest.verification.iosBuildCommand,
      iosTestCommand: manifest.verification && manifest.verification.iosTestCommand,
      androidBuildCommand: manifest.verification && manifest.verification.androidBuildCommand,
      androidTestCommand: manifest.verification && manifest.verification.androidTestCommand,
      variantBoundaryTests: manifest.verification && manifest.verification.variantBoundaryTests
    }
  };
}

function compactAnswers(answers) {
  return Object.fromEntries(
    Object.entries(answers).filter(([, value]) => value !== undefined)
  );
}

function decisionTemplateForManifest(manifest, platforms) {
  const answers = answerMapFor(manifest);
  const platform = platforms.length === 1 ? platforms[0] : "cross-platform";
  return {
    schemaVersion: 1,
    variantId: manifest.id,
    name: manifest.name,
    platform,
    instructions: "Generated from a private product native/variant.json manifest. Review before applying registry or scaffold changes.",
    decisions: Object.fromEntries(
      Object.entries(answers).map(([decisionId, decisionAnswers]) => [
        decisionId,
        {
          status: "decided",
          answers: compactAnswers(decisionAnswers)
        }
      ])
    )
  };
}

function printText(report) {
  console.log(`variant manifest: ${report.valid ? "valid" : "invalid"}`);
  if (report.errors.length > 0) {
    console.log(`errors: ${report.errors.join("; ")}`);
  }
  if (report.warnings.length > 0) {
    console.log(`warnings: ${report.warnings.join("; ")}`);
  }
}

const report = validateManifest(parseManifest());
if (process.argv.includes("--decision-template")) {
  if (!report.valid) {
    if (process.argv.includes("--json")) {
      console.log(JSON.stringify(report, null, 2));
    } else {
      printText(report);
    }
    process.exit(2);
  }
  console.log(JSON.stringify(report.decisionTemplate, null, 2));
} else if (process.argv.includes("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  printText(report);
}

process.exit(report.valid ? 0 : 2);
