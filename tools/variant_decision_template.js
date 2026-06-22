#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { answerFieldsForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const registryPath = path.join(root, "docs/app-variants.json");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const decisionCatalog = registry.plannedVariantDecisionCatalog || {};

function usage() {
  return [
    "Usage:",
    "  node tools/variant_decision_template.js --id <variant-id>",
    "",
    "Prints a fillable JSON decision template for a planned app variant.",
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

function emptyValueFor(field) {
  if (Array.isArray(field.allowedValues) && field.allowedValues.length > 0) {
    return field.allowedValues[0];
  }
  return null;
}

function answerFieldsFor(variant, decision) {
  if (Array.isArray(decision.answerFields) && decision.answerFields.length > 0) {
    return decision.answerFields;
  }
  const catalogDecision = decisionCatalog[decision.id] || {};
  return answerFieldsForPlatform(catalogDecision.answerFields, variant.platform);
}

function decisionTemplateFor(variant) {
  const checklist = Array.isArray(variant.decisionChecklist) ? variant.decisionChecklist : [];
  const decisions = {};
  for (const decision of checklist) {
    const fields = answerFieldsFor(variant, decision);
    const answers = {};
    const fieldMetadata = {};
    for (const field of fields) {
      answers[field.id] = emptyValueFor(field);
      fieldMetadata[field.id] = {
        label: field.label,
        required: field.required === true,
        platforms: Array.isArray(field.platforms) ? field.platforms : undefined,
        allowedValues: Array.isArray(field.allowedValues) ? field.allowedValues : undefined
      };
    }
    decisions[decision.id] = {
      status: decision.status || "needed",
      question: decision.question || (decisionCatalog[decision.id] || {}).question || "",
      answers,
      fields: fieldMetadata
    };
  }
  return {
    schemaVersion: 1,
    variantId: variant.id,
    name: variant.name,
    platform: variant.platform,
    instructions: "Fill answers for every required field, then update docs/app-variants.json and platform artifacts through the normal scaffold workflow.",
    decisions
  };
}

const requestedId = argValue("--id").trim();
if (!requestedId) {
  fail("--id is required.");
}

const variant = (registry.variants || []).find((candidate) => candidate.id === requestedId);
if (!variant) {
  fail(`Unknown variant: ${requestedId}`);
}
if (variant.status !== "planned") {
  fail(`Variant is already implemented: ${requestedId}`);
}

console.log(JSON.stringify(decisionTemplateFor(variant), null, 2));
