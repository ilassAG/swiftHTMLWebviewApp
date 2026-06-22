#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const allowlistPath = path.join(root, "docs/private-product-footprint-allowlist.json");

function usage() {
  return [
    "Usage:",
    "  node tools/private_product_footprint_audit.js [--json]",
    "",
    "Scans the open-source wrapper for product-specific private product footprint.",
    "Known legacy parity anchors are allowed only in docs/private-product-footprint-allowlist.json."
  ].join("\n");
}

function fail(message) {
  console.error(message);
  console.error("");
  console.error(usage());
  process.exit(1);
}

function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`Could not read ${path.relative(root, file)}: ${error.message}`);
  }
}

function escapeRegex(value) {
  return String(value).replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
}

function globToRegex(glob) {
  let source = "";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    if (char === "*" && glob[index + 1] === "*") {
      source += ".*";
      index += 1;
    } else if (char === "*") {
      source += "[^/]*";
    } else {
      source += escapeRegex(char);
    }
  }
  return new RegExp(`^${source}$`);
}

function normalizePath(file) {
  return file.split(path.sep).join("/");
}

function isAllowedPath(relativePath, patterns) {
  return patterns.some((pattern) => globToRegex(pattern).test(relativePath));
}

function isBinary(buffer) {
  const scanLength = Math.min(buffer.length, 4096);
  for (let index = 0; index < scanLength; index += 1) {
    if (buffer[index] === 0) {
      return true;
    }
  }
  return false;
}

function collectFiles(dir, ignoredPathPatterns, files = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const absolutePath = path.join(dir, entry.name);
    const relativePath = normalizePath(path.relative(root, absolutePath));
    if (isAllowedPath(relativePath, ignoredPathPatterns)) {
      continue;
    }
    if (entry.isDirectory()) {
      collectFiles(absolutePath, ignoredPathPatterns, files);
    } else if (entry.isFile()) {
      files.push({ absolutePath, relativePath });
    }
  }
  return files;
}

function lineAndColumn(text, index) {
  const before = text.slice(0, index);
  const lines = before.split("\n");
  return {
    line: lines.length,
    column: lines[lines.length - 1].length + 1
  };
}

function findMatches(text, regexSource) {
  const regex = new RegExp(regexSource, "g");
  const matches = [];
  let match;
  while ((match = regex.exec(text)) !== null) {
    const value = match[0];
    const position = lineAndColumn(text, match.index);
    matches.push({
      value,
      line: position.line,
      column: position.column
    });
    if (value.length === 0) {
      regex.lastIndex += 1;
    }
  }
  return matches;
}

const allowlist = readJSON(allowlistPath);
if (allowlist.schemaVersion !== 1) {
  fail("docs/private-product-footprint-allowlist.json must use schemaVersion 1.");
}

const ignoredPaths = Array.isArray(allowlist.ignoredPaths) ? allowlist.ignoredPaths : [];
const files = collectFiles(root, ignoredPaths);
const violations = [];
const allowedMatches = [];
const blockedMatches = [];

for (const file of files) {
  const buffer = fs.readFileSync(file.absolutePath);
  if (isBinary(buffer)) {
    continue;
  }
  const text = buffer.toString("utf8");

  for (const pattern of allowlist.blockedPatterns || []) {
    for (const match of findMatches(text, pattern.regex)) {
      const item = {
        patternId: pattern.id,
        path: file.relativePath,
        line: match.line,
        column: match.column,
        value: match.value,
        reason: pattern.reason
      };
      blockedMatches.push(item);
      violations.push(item);
    }
  }

  for (const pattern of allowlist.allowedPatterns || []) {
    const matches = findMatches(text, pattern.regex);
    if (matches.length === 0) {
      continue;
    }
    const allowed = isAllowedPath(file.relativePath, pattern.allowedPaths || []);
    for (const match of matches) {
      const item = {
        patternId: pattern.id,
        path: file.relativePath,
        line: match.line,
        column: match.column,
        value: match.value,
        reason: pattern.reason
      };
      if (allowed) {
        allowedMatches.push(item);
      } else {
        violations.push(item);
      }
    }
  }
}

const result = {
  valid: violations.length === 0,
  scannedFiles: files.length,
  allowedMatches: allowedMatches.length,
  blockedMatches: blockedMatches.length,
  violations
};

if (process.argv.includes("--json")) {
  console.log(`${JSON.stringify(result, null, 2)}\n`);
} else if (result.valid) {
  console.log(`private product footprint audit passed (${allowedMatches.length} allowed legacy matches).`);
} else {
  console.error("private product footprint audit failed:");
  for (const violation of violations) {
    console.error(`- ${violation.path}:${violation.line}:${violation.column} ${violation.patternId}: ${violation.value}`);
  }
}

process.exit(result.valid ? 0 : 2);
