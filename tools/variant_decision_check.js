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
    "  node tools/variant_decision_check.js --file <decision-template.json> [--json]",
    "  node tools/variant_decision_check.js --stdin [--json]",
    "",
    "Validates a filled variant decision template against docs/app-variants.json."
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

function parseInput() {
  try {
    return JSON.parse(readInput());
  } catch (error) {
    fail(`Decision template is not valid JSON: ${error.message}`);
  }
}

function isValuePresent(value) {
  if (value === null || value === undefined) {
    return false;
  }
  if (typeof value === "string") {
    return value.trim().length > 0;
  }
  if (Array.isArray(value)) {
    return true;
  }
  if (typeof value === "object") {
    return Object.keys(value).length > 0;
  }
  return true;
}

function expectedFieldsFor(variant, decision) {
  if (Array.isArray(decision.answerFields) && decision.answerFields.length > 0) {
    return decision.answerFields;
  }
  const catalogDecision = decisionCatalog[decision.id] || {};
  return answerFieldsForPlatform(catalogDecision.answerFields, variant.platform);
}

function validateDecisionTemplate(template) {
  const errors = [];
  const missingRequiredAnswers = [];
  const invalidAnswers = [];
  const unknownDecisions = [];
  const unknownAnswerFields = [];

  if (template.schemaVersion !== 1) {
    errors.push("schemaVersion must be 1.");
  }

  const variant = (registry.variants || []).find((candidate) => candidate.id === template.variantId);
  if (!variant) {
    errors.push(`Unknown variantId: ${template.variantId || ""}`);
    return { valid: false, errors, missingRequiredAnswers, invalidAnswers, unknownDecisions, unknownAnswerFields };
  }
  if (variant.status !== "planned") {
    errors.push(`Variant is already implemented: ${variant.id}`);
  }

  const checklist = Array.isArray(variant.decisionChecklist) ? variant.decisionChecklist : [];
  const expectedDecisionIds = new Set(checklist.map((decision) => decision.id));
  const decisions = template.decisions && typeof template.decisions === "object" && !Array.isArray(template.decisions)
    ? template.decisions
    : {};

  for (const decisionId of Object.keys(decisions)) {
    if (!expectedDecisionIds.has(decisionId)) {
      unknownDecisions.push(decisionId);
    }
  }

  for (const decision of checklist) {
    const submittedDecision = decisions[decision.id] || {};
    const answers = submittedDecision.answers && typeof submittedDecision.answers === "object" && !Array.isArray(submittedDecision.answers)
      ? submittedDecision.answers
      : {};
    const fields = expectedFieldsFor(variant, decision);
    const expectedAnswerIds = new Set(fields.map((field) => field.id));

    for (const answerId of Object.keys(answers)) {
      if (!expectedAnswerIds.has(answerId)) {
        unknownAnswerFields.push(`${decision.id}.${answerId}`);
      }
    }

    for (const field of fields) {
      const answerPath = `${decision.id}.${field.id}`;
      const value = answers[field.id];
      if (field.required === true && !isValuePresent(value)) {
        missingRequiredAnswers.push(answerPath);
      }
      if (Array.isArray(field.allowedValues) && isValuePresent(value) && !field.allowedValues.includes(value)) {
        invalidAnswers.push({
          field: answerPath,
          value,
          allowedValues: field.allowedValues
        });
      }
    }
  }

  const valid =
    errors.length === 0 &&
    missingRequiredAnswers.length === 0 &&
    invalidAnswers.length === 0 &&
    unknownDecisions.length === 0 &&
    unknownAnswerFields.length === 0;

  return {
    valid,
    variantId: variant.id,
    name: variant.name,
    platform: variant.platform,
    errors,
    missingRequiredAnswers,
    invalidAnswers,
    unknownDecisions,
    unknownAnswerFields
  };
}

function printText(report) {
  console.log(`${report.variantId || "unknown"} decision template: ${report.valid ? "valid" : "invalid"}`);
  if (report.errors && report.errors.length > 0) {
    console.log(`errors: ${report.errors.join("; ")}`);
  }
  if (report.missingRequiredAnswers.length > 0) {
    console.log(`missing required answers: ${report.missingRequiredAnswers.join(", ")}`);
  }
  if (report.invalidAnswers.length > 0) {
    console.log(`invalid answers: ${report.invalidAnswers.map((answer) => answer.field).join(", ")}`);
  }
  if (report.unknownDecisions.length > 0) {
    console.log(`unknown decisions: ${report.unknownDecisions.join(", ")}`);
  }
  if (report.unknownAnswerFields.length > 0) {
    console.log(`unknown answer fields: ${report.unknownAnswerFields.join(", ")}`);
  }
}

const report = validateDecisionTemplate(parseInput());
if (process.argv.includes("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  printText(report);
}

process.exit(report.valid ? 0 : 2);
