#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { answerFieldsForPlatform, targetArtifactsForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const registryPath = path.join(root, "docs/app-variants.json");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const decisionCatalog = registry.plannedVariantDecisionCatalog || {};

function usage() {
  return [
    "Usage:",
    "  node tools/variant_readiness.js [--id <variant-id>] [--json] [--require-ready]",
    "",
    "Prints implemented variants and planned-variant decision blockers.",
    "--require-ready exits with code 2 when a selected planned variant still has blocking decisions."
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

function identityFor(variant) {
  if (variant.platform === "ios") {
    return [variant.bundleIdentifier, variant.productName, variant.displayName]
      .filter(Boolean)
      .join(" / ");
  }
  if (variant.platform === "android") {
    return [variant.gradleModule, variant.applicationId, variant.label]
      .filter(Boolean)
      .join(" / ");
  }
  return variant.platform;
}

function targetArtifactsFor(decisionId, platform, variantId) {
  const decision = decisionCatalog[decisionId] || {};
  return targetArtifactsForPlatform(decision.targetArtifacts, platform, variantId);
}

function answerFieldsFor(decisionId, platform) {
  const decision = decisionCatalog[decisionId] || {};
  return answerFieldsForPlatform(decision.answerFields, platform);
}

function unique(values) {
  return [...new Set(values)];
}

function readinessFor(variant) {
  const checklist = Array.isArray(variant.decisionChecklist) ? variant.decisionChecklist : [];
  const missingDecisions = checklist
    .filter((decision) => decision.status !== "decided")
    .map((decision) => ({
      id: decision.id,
      status: decision.status || "needed",
      question: decision.question,
      targetArtifacts: targetArtifactsFor(decision.id, variant.platform, variant.id),
      answerFields: Array.isArray(decision.answerFields) && decision.answerFields.length > 0
        ? decision.answerFields
        : answerFieldsFor(decision.id, variant.platform)
    }));
  const implemented = variant.status === "implemented";
  const blocked = !implemented && missingDecisions.length > 0;
  const blockingTargetArtifacts = unique(
    missingDecisions.flatMap((decision) => decision.targetArtifacts || [])
  );

  return {
    id: variant.id,
    name: variant.name,
    status: variant.status,
    platform: variant.platform,
    identity: identityFor(variant),
    releaseChannel: variant.releaseChannel || null,
    implemented,
    verification: variant.verification || null,
    missingDecisions,
    blockingDecisionIds: missingDecisions.map((decision) => decision.id),
    blockingTargetArtifacts,
    nextDecision: missingDecisions[0] || null,
    blocked,
    readyForImplementation: implemented || missingDecisions.length === 0
  };
}

function printText(readiness) {
  const implemented = readiness.filter((variant) => variant.implemented);
  const planned = readiness.filter((variant) => !variant.implemented);

  if (implemented.length > 0) {
    console.log("Implemented variants:");
    for (const variant of implemented) {
      console.log(`- ${variant.id}: ${variant.name} (${variant.platform})`);
      console.log(`  identity: ${variant.identity}`);
      if (variant.verification) {
        console.log(`  build: ${variant.verification.build}`);
        console.log(`  test: ${variant.verification.test}`);
      }
    }
  }

  if (implemented.length > 0 && planned.length > 0) {
    console.log("");
  }

  if (planned.length > 0) {
    console.log("Planned variants:");
    for (const variant of planned) {
      console.log(`- ${variant.id}: ${variant.name} (${variant.platform})`);
      if (variant.missingDecisions.length === 0) {
        console.log("  readiness: ready for implementation decisions");
        console.log("  missing decisions: none recorded");
        continue;
      }
      console.log(`  readiness: blocked (${variant.missingDecisions.length} decision${variant.missingDecisions.length === 1 ? "" : "s"} needed)`);
      if (variant.nextDecision) {
        console.log(`  next decision: ${variant.nextDecision.id}`);
      }
      console.log("  missing decisions:");
      for (const decision of variant.missingDecisions) {
        console.log(`  - ${decision.id}: ${decision.question}`);
        if (decision.targetArtifacts && decision.targetArtifacts.length > 0) {
          console.log(`    target artifacts: ${decision.targetArtifacts.join(", ")}`);
        }
        if (decision.answerFields && decision.answerFields.length > 0) {
          console.log(`    answer fields: ${decision.answerFields.map((field) => field.id).join(", ")}`);
        }
      }
    }
  }
}

const requestedId = argValue("--id").trim();
const requireReady = process.argv.includes("--require-ready");
let selectedVariants = registry.variants || [];
if (requestedId) {
  selectedVariants = selectedVariants.filter((variant) => variant.id === requestedId);
  if (selectedVariants.length === 0) {
    fail(`Unknown variant: ${requestedId}`);
  }
}

const readiness = selectedVariants.map(readinessFor);
if (process.argv.includes("--json")) {
  console.log(JSON.stringify(readiness, null, 2));
} else {
  printText(readiness);
}

if (requireReady) {
  const blocked = readiness.filter((variant) => variant.blocked);
  if (blocked.length > 0) {
    for (const variant of blocked) {
      console.error(
        `${variant.id} is not ready: missing ${variant.blockingDecisionIds.join(", ")}`
      );
    }
    process.exit(2);
  }
}
