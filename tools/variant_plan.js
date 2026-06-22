#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { decisionChecklistForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const registryPath = path.join(root, "docs/app-variants.json");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));

function usage() {
  return [
    "Usage:",
    "  node tools/variant_plan.js --id <variant-id> --name <display-name> --platform <ios|android|cross-platform>",
    "",
    "Prints a planned docs/app-variants.json entry with the standard decision checklist.",
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

const id = argValue("--id").trim();
const name = argValue("--name").trim();
const platform = argValue("--platform").trim();
const source = argValue("--source").trim() || "planned variant template";

if (!id || !/^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(id)) {
  fail("--id must be kebab-case with lowercase letters, numbers, and dashes.");
}

if (!name) {
  fail("--name is required.");
}

if (!["ios", "android", "cross-platform"].includes(platform)) {
  fail("--platform must be ios, android, or cross-platform.");
}

const existingIds = new Set((registry.variants || []).map((variant) => variant.id));
if (existingIds.has(id)) {
  fail(`Variant already exists: ${id}`);
}

const catalog = registry.plannedVariantDecisionCatalog || {};
const requiredDecisionIds = Object.keys(catalog);
if (requiredDecisionIds.length === 0) {
  fail("plannedVariantDecisionCatalog is empty.");
}

const plannedVariant = {
  id,
  status: "planned",
  platform,
  name,
  source,
  requiredDecisionIds,
  requiredDecisions: requiredDecisionIds.map((decisionId) => catalog[decisionId].description),
  decisionChecklist: decisionChecklistForPlatform(catalog, requiredDecisionIds, platform, id)
};

console.log(JSON.stringify(plannedVariant, null, 2));
