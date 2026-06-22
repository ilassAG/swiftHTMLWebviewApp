#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { decisionChecklistForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const registryPath = path.join(root, "docs/app-variants.json");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const bridgeContract = JSON.parse(fs.readFileSync(path.join(root, "docs/bridge-contract.json"), "utf8"));

function usage() {
  return [
    "Usage:",
    "  node tools/variant_registry_plan.js --file <decision-template.json> [--json]",
    "  node tools/variant_registry_plan.js --stdin [--json]",
    "",
    "Validates a filled decision template and prints the registry update plan.",
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
  return fs.readFileSync(path.resolve(root, file), "utf8");
}

function validate(rawInput) {
  const result = spawnSync(
    process.execPath,
    ["tools/variant_decision_check.js", "--stdin", "--json"],
    {
      cwd: root,
      input: rawInput,
      encoding: "utf8"
    }
  );
  if (!result.stdout) {
    fail(result.stderr || "Decision check did not return JSON.");
  }
  return {
    status: result.status,
    report: JSON.parse(result.stdout)
  };
}

function normalizeGradleModule(value) {
  if (typeof value !== "string" || value.trim().length === 0) {
    return "";
  }
  const trimmed = value.trim();
  return trimmed.startsWith(":") ? trimmed : `:${trimmed.replace(/^android\//, "")}`;
}

function androidModulePath(gradleModule) {
  const normalized = normalizeGradleModule(gradleModule);
  return normalized ? normalized.slice(1).replaceAll(":", "/") : "";
}

function answersFor(template, decisionId) {
  const decision = template.decisions && template.decisions[decisionId];
  return decision && decision.answers && typeof decision.answers === "object" && !Array.isArray(decision.answers)
    ? decision.answers
    : {};
}

function compactObject(object) {
  return Object.fromEntries(
    Object.entries(object).filter(([, value]) => value !== null && value !== undefined && value !== "")
  );
}

function jsonPointerSegment(value) {
  return String(value).replaceAll("~", "~0").replaceAll("/", "~1");
}

function setOperationFor(variant, variantIndex, field, value) {
  return {
    op: Object.prototype.hasOwnProperty.call(variant, field) ? "replace" : "add",
    path: `/variants/${variantIndex}/${jsonPointerSegment(field)}`,
    value
  };
}

function decidedChecklistFor(variant, platform = variant.platform, variantId = variant.id) {
  const catalog = registry.plannedVariantDecisionCatalog || {};
  const decisionIds = Array.isArray(variant.requiredDecisionIds)
    ? variant.requiredDecisionIds
    : Object.keys(catalog);
  const shouldReuseChecklist = platform === variant.platform && Array.isArray(variant.decisionChecklist) && variant.decisionChecklist.length > 0;
  const checklist = shouldReuseChecklist
    ? variant.decisionChecklist
    : decisionChecklistForPlatform(catalog, decisionIds, platform, variantId);

  return checklist.map((decision) => ({
    ...decision,
    status: "decided"
  }));
}

function unavailableActionsFor(platform) {
  return (bridgeContract.actions || [])
    .filter((action) => action && action[platform] === "unavailable")
    .map((action) => action.name)
    .filter(Boolean)
    .sort();
}

function bridgeProfileFor(platform, submittedProfile, capabilities) {
  const submittedUnavailableActions = Array.isArray(submittedProfile.unavailableActions)
    ? submittedProfile.unavailableActions
    : [];
  const useSubmittedUnavailableActions =
    submittedProfile.contractPlatform === platform && submittedUnavailableActions.length > 0;
  const enabledOptionalModules = Array.isArray(submittedProfile.enabledOptionalModules)
    ? submittedProfile.enabledOptionalModules
    : Array.isArray(capabilities.optionalModules)
      ? capabilities.optionalModules
      : [];

  return {
    contractPlatform: platform,
    enabledOptionalModules,
    unavailableActions: useSubmittedUnavailableActions
      ? submittedUnavailableActions
      : unavailableActionsFor(platform)
  };
}

function testCoverageFor(verification) {
  if (!Array.isArray(verification.variantBoundaryTests)) {
    return undefined;
  }
  return verification.variantBoundaryTests;
}

function platformRegistryEntriesFor(variant, updatePlan) {
  if (variant.platform !== "cross-platform") {
    return [];
  }

  const entries = [];
  const requiredDecisionIds = Array.isArray(variant.requiredDecisionIds)
    ? variant.requiredDecisionIds
    : Object.keys(registry.plannedVariantDecisionCatalog || {});
  const requiredDecisions = Array.isArray(variant.requiredDecisions)
    ? variant.requiredDecisions
    : requiredDecisionIds.map((decisionId) => (registry.plannedVariantDecisionCatalog || {})[decisionId].description);

  const common = {
    status: "planned",
    name: variant.name,
    source: `derived from ${variant.id}`,
    sourceVariantId: variant.id,
    requiredDecisionIds,
    requiredDecisions
  };

  if (updatePlan.identity && updatePlan.identity.bundleIdentifier) {
    entries.push(compactObject({
      ...common,
      id: `${variant.id}-ios`,
      platform: "ios",
      xcodeProject: updatePlan.identity.xcodeProject,
      scheme: updatePlan.identity.scheme,
      bundleIdentifier: updatePlan.identity.bundleIdentifier,
      productName: updatePlan.identity.productName,
      displayName: updatePlan.identity.displayName,
      decisionChecklist: decidedChecklistFor(variant, "ios", variant.id),
      runtimeDefaults: updatePlan.runtimeDefaults,
      optionalModules: updatePlan.optionalModules,
      bridgeProfile: bridgeProfileFor("ios", updatePlan.bridgeProfile || {}, { optionalModules: updatePlan.optionalModules }),
      verification: updatePlan.verification && updatePlan.verification.iosBuildCommand && updatePlan.verification.iosTestCommand
        ? {
          build: updatePlan.verification.iosBuildCommand,
          test: updatePlan.verification.iosTestCommand
        }
        : undefined,
      testCoverage: testCoverageFor(updatePlan.verification || {})
    }));
  }

  if (updatePlan.identity && updatePlan.identity.gradleModule) {
    entries.push(compactObject({
      ...common,
      id: `${variant.id}-android`,
      platform: "android",
      gradleModule: updatePlan.identity.gradleModule,
      buildFile: updatePlan.identity.buildFile,
      manifest: updatePlan.identity.manifest,
      applicationId: updatePlan.identity.applicationId,
      namespace: updatePlan.identity.namespace,
      label: updatePlan.identity.label,
      decisionChecklist: decidedChecklistFor(variant, "android", androidModulePath(updatePlan.identity.gradleModule) || variant.id),
      runtimeDefaults: updatePlan.runtimeDefaults,
      optionalModules: updatePlan.optionalModules,
      bridgeProfile: bridgeProfileFor("android", updatePlan.bridgeProfile || {}, { optionalModules: updatePlan.optionalModules }),
      verification: updatePlan.verification && updatePlan.verification.androidBuildCommand && updatePlan.verification.androidTestCommand
        ? {
          build: updatePlan.verification.androidBuildCommand,
          test: updatePlan.verification.androidTestCommand
        }
        : undefined,
      testCoverage: testCoverageFor(updatePlan.verification || {})
    }));
  }

  return entries;
}

function registryPatchFor(variant, variantIndex, updatePlan, platformRegistryEntries) {
  if (variantIndex < 0) {
    return [];
  }

  const operations = [
    {
      op: "replace",
      path: `/variants/${variantIndex}/decisionChecklist`,
      value: decidedChecklistFor(variant)
    }
  ];

  if (platformRegistryEntries.length > 0) {
    operations.push(setOperationFor(
      variant,
      variantIndex,
      "derivedVariantIds",
      platformRegistryEntries.map((entry) => entry.id)
    ));
    for (const entry of platformRegistryEntries) {
      operations.push({
        op: "add",
        path: "/variants/-",
        value: entry
      });
    }
    return operations;
  }

  for (const [field, value] of Object.entries(updatePlan.identity || {})) {
    operations.push(setOperationFor(variant, variantIndex, field, value));
  }

  if (Object.keys(updatePlan.runtimeDefaults || {}).length > 0) {
    operations.push(setOperationFor(variant, variantIndex, "runtimeDefaults", updatePlan.runtimeDefaults));
  }
  if (Array.isArray(updatePlan.optionalModules)) {
    operations.push(setOperationFor(variant, variantIndex, "optionalModules", updatePlan.optionalModules));
  }
  if (Object.keys(updatePlan.bridgeProfile || {}).length > 0) {
    operations.push(setOperationFor(variant, variantIndex, "bridgeProfile", updatePlan.bridgeProfile));
  }

  if (variant.platform === "ios" && updatePlan.verification && updatePlan.verification.iosBuildCommand && updatePlan.verification.iosTestCommand) {
    operations.push(setOperationFor(variant, variantIndex, "verification", {
      build: updatePlan.verification.iosBuildCommand,
      test: updatePlan.verification.iosTestCommand
    }));
  } else if (variant.platform === "android" && updatePlan.verification && updatePlan.verification.androidBuildCommand && updatePlan.verification.androidTestCommand) {
    operations.push(setOperationFor(variant, variantIndex, "verification", {
      build: updatePlan.verification.androidBuildCommand,
      test: updatePlan.verification.androidTestCommand
    }));
  }

  return operations;
}

function registryPlanFor(template) {
  const variantIndex = (registry.variants || []).findIndex((candidate) => candidate.id === template.variantId);
  const variant = (registry.variants || [])[variantIndex] || {};
  const identity = answersFor(template, "identity");
  const branding = answersFor(template, "branding");
  const startup = answersFor(template, "startup-provisioning");
  const capabilities = answersFor(template, "native-capabilities");
  const bridgeProfile = answersFor(template, "bridge-profile");
  const verification = answersFor(template, "verification");
  const gradleModule = normalizeGradleModule(identity.gradleModule);
  const androidPath = androidModulePath(gradleModule);
  const targetArtifacts = [];

  if (androidPath) {
    targetArtifacts.push(`android/${androidPath}/build.gradle`);
    targetArtifacts.push(`android/${androidPath}/src/main/AndroidManifest.xml`);
    targetArtifacts.push(`android/${androidPath}/src/test/`);
  }
  if (identity.bundleIdentifier || identity.productName || identity.displayName) {
    targetArtifacts.push("ios project target or xcconfig");
    targetArtifacts.push("ios/swiftHTMLWebviewAppTests/");
  }
  targetArtifacts.push("docs/app-variants.json");

  const runtimeDefaults = compactObject({
    serverURL: startup.serverURL,
    startupMode: startup.startupMode,
    securityTokenPolicy: startup.securityTokenPolicy,
    highAvailability: startup.highAvailability,
    loadingImageName: branding.loadingImageName,
    recoveryShortMark: branding.recoveryShortMark,
    recoveryTitle: branding.recoveryTitle,
    recoveryBody: branding.recoveryBody,
    recoveryQRCodeDetectedMessage: branding.recoveryQRCodeDetectedMessage,
    recoveryInvalidQRMessage: branding.recoveryInvalidQRMessage
  });

  const verificationPlan = compactObject({
    iosBuildCommand: verification.iosBuildCommand,
    iosTestCommand: verification.iosTestCommand,
    androidBuildCommand: verification.androidBuildCommand,
    androidTestCommand: verification.androidTestCommand,
    variantBoundaryTests: verification.variantBoundaryTests
  });

  const unresolved = [];
  if (identity.iconSource || branding.iconSource) {
    unresolved.push("Icon source assets must still be copied into platform asset catalogs or Android resource folders.");
  }

  const registryUpdatePlan = {
    decisionChecklist: Object.keys(template.decisions || {}).map((decisionId) => ({
      id: decisionId,
      status: "decided"
    })),
    identity: compactObject({
      bundleIdentifier: identity.bundleIdentifier,
      productName: identity.productName,
      displayName: identity.displayName,
      gradleModule,
      buildFile: androidPath ? `android/${androidPath}/build.gradle` : undefined,
      manifest: androidPath ? `android/${androidPath}/src/main/AndroidManifest.xml` : undefined,
      applicationId: identity.applicationId,
      namespace: identity.namespace,
      label: identity.label,
      storeIdentity: identity.storeIdentity
    }),
    runtimeDefaults,
    optionalModules: Array.isArray(capabilities.optionalModules) ? capabilities.optionalModules : undefined,
    bridgeProfile: compactObject({
      contractPlatform: bridgeProfile.contractPlatform,
      enabledOptionalModules: bridgeProfile.enabledOptionalModules,
      unavailableActions: bridgeProfile.unavailableActions
    }),
    verification: verificationPlan
  };
  const platformRegistryEntries = platformRegistryEntriesFor(variant, registryUpdatePlan);
  if (variant.platform === "cross-platform" && platformRegistryEntries.length < 2) {
    unresolved.push("Cross-platform planned variants need enough iOS and Android identity answers to derive both platform registry entries.");
  }

  return {
    schemaVersion: 1,
    variantId: template.variantId,
    name: template.name,
    platform: template.platform,
    readyForRegistryPlanning: true,
    targetArtifacts: [...new Set(targetArtifacts)],
    registryUpdatePlan,
    platformRegistryEntries,
    registryPatch: {
      file: "docs/app-variants.json",
      operations: registryPatchFor(variant, variantIndex, registryUpdatePlan, platformRegistryEntries)
    },
    unresolved
  };
}

function printText(plan) {
  console.log(`${plan.variantId}: registry plan`);
  console.log(`ready for registry planning: ${plan.readyForRegistryPlanning ? "yes" : "no"}`);
  console.log(`target artifacts: ${plan.targetArtifacts.join(", ")}`);
  console.log(`decisions to mark decided: ${plan.registryUpdatePlan.decisionChecklist.map((decision) => decision.id).join(", ")}`);
  if (Object.keys(plan.registryUpdatePlan.identity).length > 0) {
    console.log(`identity fields: ${Object.keys(plan.registryUpdatePlan.identity).join(", ")}`);
  }
  if (Object.keys(plan.registryUpdatePlan.runtimeDefaults).length > 0) {
    console.log(`runtime defaults: ${Object.keys(plan.registryUpdatePlan.runtimeDefaults).join(", ")}`);
  }
  if (plan.registryPatch.operations.length > 0) {
    console.log(`registry patch operations: ${plan.registryPatch.operations.length}`);
  }
  if (plan.platformRegistryEntries.length > 0) {
    console.log(`platform registry entries: ${plan.platformRegistryEntries.map((entry) => entry.id).join(", ")}`);
  }
  if (plan.unresolved.length > 0) {
    console.log("unresolved:");
    for (const item of plan.unresolved) {
      console.log(`- ${item}`);
    }
  }
}

const rawInput = readInput();
const validation = validate(rawInput);
if (validation.status !== 0 || validation.report.valid !== true) {
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify({
      valid: false,
      decisionCheck: validation.report
    }, null, 2));
  } else {
    console.log("decision template is invalid; registry plan was not generated");
    if (validation.report.missingRequiredAnswers && validation.report.missingRequiredAnswers.length > 0) {
      console.log(`missing required answers: ${validation.report.missingRequiredAnswers.join(", ")}`);
    }
  }
  process.exit(2);
}

const template = JSON.parse(rawInput);
const plan = registryPlanFor(template);
if (process.argv.includes("--json")) {
  console.log(JSON.stringify(plan, null, 2));
} else {
  printText(plan);
}
