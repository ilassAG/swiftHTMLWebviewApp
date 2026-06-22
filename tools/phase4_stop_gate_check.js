#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const REQUIRED_FILES = [
  "README.md",
  "VARIANT_WORKSPACE.json",
  "variant-decision-template.json",
  "variant-scaffold-plan.json",
  "commands.json",
  "MIGRATION_STOP_GATE.json",
  "PHASE4_DECISION_RECORD_TEMPLATE.md",
  "PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md",
  "review-next-steps.sh"
];

const REQUIRED_EVIDENCE_IDS = [
  "target-repository",
  "manifest-ownership",
  "asset-ownership",
  "agents-guidance",
  "ci-commands",
  "parity-tests",
  "hardware-owner",
  "wrapper-removal-window"
];

const ALLOWED_EVIDENCE_STATUSES = new Set([
  "required",
  "satisfied-by-input",
  "generated-for-review",
  "required-before-wrapper-sanitizing"
]);

function usage() {
  return [
    "Usage:",
    "  node path/to/swiftHTMLWebviewApp/tools/phase4_stop_gate_check.js --generated <native/generated> [--decision-record <native/phase4-migration-decision.md>] [--require-filled-decision-record] [--json]",
    "",
    "Validates the generated Phase 4 stop-gate handoff before private product logic moves.",
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

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function readJSON(file, errors) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    errors.push(`${file}: ${error.message}`);
    return null;
  }
}

function isPathInside(parent, child) {
  const relative = path.relative(parent, child);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function assert(condition, errors, message) {
  if (!condition) {
    errors.push(message);
  }
}

function markdownTableCells(line) {
  return String(line)
    .split("|")
    .slice(1, -1)
    .map((cell) => cell.trim());
}

function evidenceRowFor(content, evidenceId) {
  return content
    .split("\n")
    .find((line) => new RegExp(`^\\|\\s*${evidenceId}\\s*\\|`).test(line));
}

function validateGeneratedWorkspace(generatedDir) {
  const errors = [];
  const warnings = [];
  const generatedPath = path.resolve(process.cwd(), generatedDir);

  assert(fs.existsSync(generatedPath), errors, `generated directory does not exist: ${generatedPath}`);
  if (!fs.existsSync(generatedPath)) {
    return { valid: false, errors, warnings, generatedPath };
  }

  for (const file of REQUIRED_FILES) {
    assert(fs.existsSync(path.join(generatedPath, file)), errors, `missing generated file: ${file}`);
  }

  const workspace = readJSON(path.join(generatedPath, "VARIANT_WORKSPACE.json"), errors);
  const gate = readJSON(path.join(generatedPath, "MIGRATION_STOP_GATE.json"), errors);
  const commands = readJSON(path.join(generatedPath, "commands.json"), errors);

  if (workspace) {
    assert(workspace.schemaVersion === 1, errors, "VARIANT_WORKSPACE.json schemaVersion must be 1.");
    assert(workspace.outputs && workspace.outputs.migrationStopGate === "MIGRATION_STOP_GATE.json", errors, "VARIANT_WORKSPACE.json must reference MIGRATION_STOP_GATE.json.");
    assert(workspace.outputs && workspace.outputs.phase4DecisionRecordTemplate === "PHASE4_DECISION_RECORD_TEMPLATE.md", errors, "VARIANT_WORKSPACE.json must reference PHASE4_DECISION_RECORD_TEMPLATE.md.");
    assert(workspace.status && String(workspace.status.migrationStop || "").includes("Do not move existing private product logic"), errors, "VARIANT_WORKSPACE.json must record the migration stop.");
  }

  if (gate) {
    assert(gate.schemaVersion === 1, errors, "MIGRATION_STOP_GATE.json schemaVersion must be 1.");
    assert(gate.phase4Authorized === false, errors, "MIGRATION_STOP_GATE.json must keep phase4Authorized false until reviewed.");
    assert(isNonEmptyString(gate.variantId), errors, "MIGRATION_STOP_GATE.json must include variantId.");
    assert(String(gate.stopPoint || "").includes("Do not move existing private product logic"), errors, "MIGRATION_STOP_GATE.json must include the explicit stop point.");
    const evidence = Array.isArray(gate.requiredEvidence) ? gate.requiredEvidence : [];
    const evidenceIds = evidence.map((item) => item && item.id);
    assert(JSON.stringify(evidenceIds) === JSON.stringify(REQUIRED_EVIDENCE_IDS), errors, `MIGRATION_STOP_GATE.json evidence IDs must be ${REQUIRED_EVIDENCE_IDS.join(", ")}.`);
    for (const item of evidence) {
      assert(ALLOWED_EVIDENCE_STATUSES.has(item.status), errors, `MIGRATION_STOP_GATE.json evidence ${item.id} has unsupported status ${item.status}.`);
      assert(isNonEmptyString(item.evidence), errors, `MIGRATION_STOP_GATE.json evidence ${item.id} must describe required evidence.`);
    }
    assert(Array.isArray(gate.nextDiscussion) && gate.nextDiscussion.length >= 3, errors, "MIGRATION_STOP_GATE.json must include nextDiscussion prompts.");
  }

  if (workspace && gate) {
    assert(workspace.variantId === gate.variantId, errors, "VARIANT_WORKSPACE.json and MIGRATION_STOP_GATE.json variantId must match.");
    assert(JSON.stringify(workspace.platforms || []) === JSON.stringify(gate.platforms || []), errors, "VARIANT_WORKSPACE.json and MIGRATION_STOP_GATE.json platforms must match.");
  }

  if (workspace && commands) {
    for (const platform of workspace.platforms || []) {
      assert(commands[platform] && isNonEmptyString(commands[platform].build), errors, `commands.json must include ${platform}.build.`);
      assert(commands[platform] && isNonEmptyString(commands[platform].test), errors, `commands.json must include ${platform}.test.`);
    }
  }

  const decisionTemplate = fs.existsSync(path.join(generatedPath, "PHASE4_DECISION_RECORD_TEMPLATE.md"))
    ? fs.readFileSync(path.join(generatedPath, "PHASE4_DECISION_RECORD_TEMPLATE.md"), "utf8")
    : "";
  if (decisionTemplate) {
    assert(decisionTemplate.includes("Target Repository Decision"), errors, "PHASE4_DECISION_RECORD_TEMPLATE.md must include Target Repository Decision.");
    assert(decisionTemplate.includes("Evidence Checklist"), errors, "PHASE4_DECISION_RECORD_TEMPLATE.md must include Evidence Checklist.");
    assert(decisionTemplate.includes("No existing private product logic"), errors, "PHASE4_DECISION_RECORD_TEMPLATE.md must include the no-move stop wording.");
  }

  return { valid: errors.length === 0, errors, warnings, generatedPath };
}

function validateDecisionRecord(generatedPath, decisionRecordArg, requireFilled) {
  const errors = [];
  const warnings = [];
  if (!decisionRecordArg) {
    warnings.push("No --decision-record supplied; generated stop-gate is valid but Phase 4 evidence has not been checked.");
    return { valid: true, errors, warnings };
  }

  const decisionRecordPath = path.resolve(process.cwd(), decisionRecordArg);
  assert(fs.existsSync(decisionRecordPath), errors, `decision record does not exist: ${decisionRecordPath}`);
  assert(!isPathInside(generatedPath, decisionRecordPath), errors, "decision record must be copied outside native/generated before evidence is filled in.");
  if (!fs.existsSync(decisionRecordPath)) {
    return { valid: false, errors, warnings, decisionRecordPath };
  }

  const content = fs.readFileSync(decisionRecordPath, "utf8");
  for (const marker of ["Target Repository Decision", "Evidence Checklist", "Generated Commands To Wire Into CI", "Approval"]) {
    assert(content.includes(marker), errors, `decision record must include ${marker}.`);
  }
  if (requireFilled) {
    for (const evidenceId of REQUIRED_EVIDENCE_IDS) {
      const row = evidenceRowFor(content, evidenceId);
      assert(Boolean(row), errors, `decision record must include evidence row for ${evidenceId}.`);
      if (row) {
        const cells = markdownTableCells(row);
        assert(cells.length >= 5, errors, `decision record evidence row for ${evidenceId} must keep all table columns.`);
        assert(isNonEmptyString(cells[3]), errors, `decision record evidence row for ${evidenceId} must include an evidence location.`);
        assert(isNonEmptyString(cells[4]), errors, `decision record evidence row for ${evidenceId} must include owner/date.`);
      }
    }
    assert(!/\bTBD\b/.test(content), errors, "decision record still contains TBD placeholders.");
  }
  return { valid: errors.length === 0, errors, warnings, decisionRecordPath };
}

const generatedArg = argValue("--generated").trim();
if (!generatedArg) {
  console.error("--generated is required.");
  console.error("");
  console.error(usage());
  process.exit(1);
}

const generatedReport = validateGeneratedWorkspace(generatedArg);
const decisionReport = validateDecisionRecord(
  generatedReport.generatedPath,
  argValue("--decision-record").trim(),
  process.argv.includes("--require-filled-decision-record")
);
const errors = [...generatedReport.errors, ...decisionReport.errors];
const warnings = [...generatedReport.warnings, ...decisionReport.warnings];
const report = {
  valid: errors.length === 0,
  errors,
  warnings,
  generatedPath: generatedReport.generatedPath,
  decisionRecordPath: decisionReport.decisionRecordPath
};

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`phase4 stop gate: ${report.valid ? "valid" : "invalid"}`);
  if (errors.length > 0) {
    console.log(`errors: ${errors.join("; ")}`);
  }
  if (warnings.length > 0) {
    console.log(`warnings: ${warnings.join("; ")}`);
  }
}

process.exit(report.valid ? 0 : 2);
