#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");

function usage() {
  return [
    "Usage:",
    "  node path/to/swiftHTMLWebviewApp/tools/generate_variant_workspace.js --variant <native/variant.json> --output <native/generated> [--dry-run] [--force] [--json]",
    "",
    "Validates a private product variant manifest and writes a deterministic generated handoff workspace.",
    "The command does not edit the wrapper source tree or private product source files outside --output."
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

function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`Could not read JSON from ${file}: ${error.message}`);
  }
}

function runNode(args, input) {
  const result = spawnSync(process.execPath, args, {
    cwd: root,
    input,
    encoding: "utf8"
  });
  if (!result.stdout) {
    fail(result.stderr || `${args.join(" ")} did not return JSON.`);
  }
  return {
    status: result.status,
    json: JSON.parse(result.stdout)
  };
}

function normalizeForJSON(value) {
  if (Array.isArray(value)) {
    return value.map(normalizeForJSON);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, normalizeForJSON(value[key])])
    );
  }
  return value;
}

function stableJSONString(value) {
  return `${JSON.stringify(normalizeForJSON(value), null, 2)}\n`;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function isPathInside(parent, child) {
  const relative = path.relative(parent, child);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function assertSafeOutputPath(outputPath) {
  if (outputPath === root || !isPathInside(path.dirname(outputPath), outputPath)) {
    fail("--output must point to a generated directory, not the wrapper root.");
  }
  const normalized = path.normalize(outputPath);
  if (normalized === path.parse(normalized).root || normalized === os.homedir()) {
    fail("--output must not be a filesystem root or home directory.");
  }
}

function writeFileIfSafe(file, content, force, written, conflicts) {
  if (fs.existsSync(file)) {
    const existing = fs.readFileSync(file, "utf8");
    if (existing === content) {
      return;
    }
    if (!force) {
      conflicts.push(file);
      return;
    }
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  written.push(file);
}

function collectCommands(scaffoldPlan) {
  const commands = {};
  for (const scaffold of scaffoldPlan.platformScaffolds || []) {
    commands[scaffold.platform] = scaffold.commands || {};
  }
  return commands;
}

function pascalCase(value) {
  const text = String(value || "")
    .replace(/^:/, "")
    .split(/[^a-zA-Z0-9]+/)
    .filter(Boolean)
    .map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`)
    .join("");
  return text || "Variant";
}

function androidModulePath(gradleModule) {
  return String(gradleModule || "")
    .replace(/^:/, "")
    .replaceAll(":", "/");
}

function androidScaffoldForManifest(manifest) {
  const modulePath = androidModulePath(manifest.android.gradleModule);
  const enabledOptionalModules = manifest.bridgeProfile && manifest.bridgeProfile.android
    ? manifest.bridgeProfile.android.enabledOptionalModules || []
    : manifest.features.optionalModules || [];
  const sourceTemplate = "android/app";

  return {
    id: `${manifest.id}-android`,
    platform: "android",
    sourceTemplate,
    registryEntry: {
      id: `${manifest.id}-android`,
      status: "planned",
      platform: "android",
      name: manifest.name,
      source: `private manifest ${manifest.id}`,
      gradleModule: manifest.android.gradleModule,
      buildFile: `android/${modulePath}/build.gradle`,
      manifest: `android/${modulePath}/src/main/AndroidManifest.xml`,
      applicationId: manifest.android.applicationId,
      namespace: manifest.android.namespace,
      label: manifest.android.label,
      runtimeDefaults: manifest.startup,
      optionalModules: manifest.features.optionalModules,
      bridgeProfile: {
        contractPlatform: "android",
        enabledOptionalModules,
        unavailableActions: manifest.bridgeProfile && manifest.bridgeProfile.android
          ? manifest.bridgeProfile.android.unavailableActions || []
          : []
      },
      verification: manifest.verification
        ? {
          build: manifest.verification.androidBuildCommand,
          test: manifest.verification.androidTestCommand
        }
        : undefined
    },
    files: [
      {
        action: "update",
        path: "android/settings.gradle",
        purpose: `Add include '${manifest.android.gradleModule}'.`
      },
      {
        action: "create",
        path: `android/${modulePath}/build.gradle`,
        sourceTemplate: `${sourceTemplate}/build.gradle`,
        purpose: "Create an Android application module with the chosen namespace, applicationId, optional modules, and shared wrapper source sets."
      },
      {
        action: "create",
        path: `android/${modulePath}/src/main/AndroidManifest.xml`,
        sourceTemplate: `${sourceTemplate}/src/main/AndroidManifest.xml`,
        purpose: "Set app label, launcher activity, runtime defaults, recovery metadata, permissions, and feature requirements for this variant."
      },
      {
        action: "create-or-copy",
        path: `android/${modulePath}/src/main/res/`,
        sourceTemplate: `${sourceTemplate}/src/main/res/`,
        purpose: "Provide app name, icon, splash/loading image, styles, and Android resources from the private manifest/assets."
      },
      {
        action: "create",
        path: `android/${modulePath}/src/test/java/com/ilass/swifthtmlwebviewapp/${pascalCase(manifest.id)}AndroidVariantTest.java`,
        purpose: "Add variant-boundary tests for identity, manifest defaults, optional modules, and bridge capability profile."
      }
    ],
    commands: {
      build: manifest.verification && manifest.verification.androidBuildCommand
        ? manifest.verification.androidBuildCommand
        : `cd android && ./gradlew ${manifest.android.gradleModule}:assembleDebug`,
      test: manifest.verification && manifest.verification.androidTestCommand
        ? manifest.verification.androidTestCommand
        : `cd android && ./gradlew ${manifest.android.gradleModule}:testDebugUnitTest`
    },
    assetInputs: [
      manifest.branding.iconSource,
      manifest.branding.loadingImageSource
    ]
  };
}

function iosScaffoldForManifest(manifest) {
  const enabledOptionalModules = manifest.bridgeProfile && manifest.bridgeProfile.ios
    ? manifest.bridgeProfile.ios.enabledOptionalModules || []
    : manifest.features.optionalModules || [];

  return {
    id: `${manifest.id}-ios`,
    platform: "ios",
    registryEntry: {
      id: `${manifest.id}-ios`,
      status: "planned",
      platform: "ios",
      name: manifest.name,
      source: `private manifest ${manifest.id}`,
      bundleIdentifier: manifest.ios.bundleIdentifier,
      productName: manifest.ios.productName,
      displayName: manifest.ios.displayName,
      scheme: manifest.ios.scheme,
      runtimeDefaults: manifest.startup,
      optionalModules: manifest.features.optionalModules,
      bridgeProfile: {
        contractPlatform: "ios",
        enabledOptionalModules,
        unavailableActions: manifest.bridgeProfile && manifest.bridgeProfile.ios
          ? manifest.bridgeProfile.ios.unavailableActions || []
          : []
      },
      verification: manifest.verification
        ? {
          build: manifest.verification.iosBuildCommand,
          test: manifest.verification.iosTestCommand
        }
        : undefined
    },
    files: [
      {
        action: "update",
        path: "ios/swiftHTMLWebviewApp.xcodeproj/project.pbxproj",
        purpose: "Create or configure the iOS app target, bundle identifier, product name, display name, scheme, and build settings."
      },
      {
        action: "create",
        path: `ios/Variants/${manifest.id}/`,
        purpose: "Add variant-specific config, icon/loading asset references, startup defaults, and recovery copy."
      },
      {
        action: "create-or-copy",
        path: "ios/swiftHTMLWebviewApp/Assets.xcassets/",
        purpose: "Provide app icon and loading image assets from the private manifest/assets."
      },
      {
        action: "create",
        path: `ios/swiftHTMLWebviewAppTests/${pascalCase(manifest.id)}IosVariantTests.swift`,
        purpose: "Add variant-boundary tests for identity, defaults, optional modules, and bridge capability profile."
      }
    ],
    commands: {
      build: manifest.verification && manifest.verification.iosBuildCommand
        ? manifest.verification.iosBuildCommand
        : "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme <variant-scheme> -destination 'generic/platform=iOS Simulator' build",
      test: manifest.verification && manifest.verification.iosTestCommand
        ? manifest.verification.iosTestCommand
        : "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme <variant-scheme> -destination 'platform=iOS Simulator,name=iPhone 17' test"
    },
    assetInputs: [
      manifest.branding.iconSource,
      manifest.branding.loadingImageSource
    ]
  };
}

function scaffoldPlanForManifest(manifest) {
  const platformScaffolds = [];
  if ((manifest.platforms || []).includes("ios")) {
    platformScaffolds.push(iosScaffoldForManifest(manifest));
  }
  if ((manifest.platforms || []).includes("android")) {
    platformScaffolds.push(androidScaffoldForManifest(manifest));
  }
  return {
    schemaVersion: 1,
    valid: true,
    variantId: manifest.id,
    name: manifest.name,
    platform: manifest.platforms.length === 1 ? manifest.platforms[0] : "cross-platform",
    readyForScaffold: platformScaffolds.length > 0,
    platformScaffolds,
    unresolved: [
      "This generated workspace is a handoff plan. It does not move existing private product logic into private product repositories.",
      "Create or update real platform files only after the target private product repositories and paths are agreed.",
      "private-product-owned source overrides are required for product-selected optional modules such as Stripe Terminal Tap to Pay."
    ]
  };
}

function readmeFor(workspace) {
  const wrapperRoot = shellQuote(workspace.wrapper.root);
  const lines = [
    `# Generated Native Workspace: ${workspace.name}`,
    "",
    "This directory is generated from a private product `native/variant.json` manifest.",
    "Do not edit generated files by hand. Change the manifest, override files, or the upstream wrapper tooling instead.",
    "",
    "## Inputs",
    "",
    `- Variant ID: \`${workspace.variantId}\``,
    `- Wrapper version: \`${workspace.wrapperVersion}\``,
    `- Source manifest: \`${workspace.sourceManifest}\``,
    "",
    "## Generated Files",
    "",
    "- `VARIANT_WORKSPACE.json`: normalized handoff summary",
    "- `variant-decision-template.json`: decision-template shape consumed by variant planning tools",
    "- `variant-scaffold-plan.json`: registry and platform scaffold artifact plan",
    "- `commands.json`: build/test commands grouped by platform",
    "- `MIGRATION_STOP_GATE.json`: Phase 4 prerequisites that must be reviewed before product data moves",
    "- `PHASE4_DECISION_RECORD_TEMPLATE.md`: copyable private product decision record template",
    "- `PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md`: suggested private product `AGENTS.md` native-wrapper section",
    "",
    "## Next Step",
    "",
    "From the private product repository, validate this generated handoff with:",
    "",
    "```sh",
    `WRAPPER_ROOT=${wrapperRoot}`,
    "node \"$WRAPPER_ROOT/tools/phase4_stop_gate_check.js\" \\",
    "  --generated native/generated",
    "```",
    "",
    "Review this generated handoff before creating or updating real iOS/Android platform files.",
    "Use `MIGRATION_STOP_GATE.json` as the review checklist.",
    "Copy `PHASE4_DECISION_RECORD_TEMPLATE.md` to a private-product-owned path such as `native/phase4-migration-decision.md` before recording approvals or evidence.",
    "The migration plan intentionally stops before moving existing private product logic into private product repositories without a project-specific decision."
  ];
  return `${lines.join("\n")}\n`;
}

function migrationStopGateFor(manifest, scaffoldPlan) {
  return {
    schemaVersion: 1,
    variantId: manifest.id,
    name: manifest.name,
    phase4Authorized: false,
    stopPoint: "Do not move existing private product logic, assets, identity, URLs, signing, or store metadata until every required evidence item is reviewed.",
    platforms: manifest.platforms,
    generatedScaffoldIds: (scaffoldPlan.platformScaffolds || []).map((scaffold) => scaffold.id),
    requiredEvidence: [
      {
        id: "target-repository",
        status: "required",
        evidence: "Exact private product repository URL/path and native/ directory target are agreed."
      },
      {
        id: "manifest-ownership",
        status: "satisfied-by-input",
        evidence: "Private native/variant.json validated and owns identity, startup, branding, and feature choices."
      },
      {
        id: "asset-ownership",
        status: "required",
        evidence: "Icon and loading/splash source files exist under native/assets/ in the private product repository."
      },
      {
        id: "agents-guidance",
        status: "generated-for-review",
        evidence: "PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md reviewed and merged into the private product AGENTS.md."
      },
      {
        id: "ci-commands",
        status: "generated-for-review",
        evidence: "commands.json build/test commands are wired into private product CI."
      },
      {
        id: "parity-tests",
        status: "required",
        evidence: "private product variant-boundary tests prove identity, startup defaults, optional modules, and unavailable actions."
      },
      {
        id: "hardware-owner",
        status: "required",
        evidence: "Manual/device smoke owner is assigned for camera, NFC, Bluetooth, printing, or Tap to Pay where enabled."
      },
      {
        id: "wrapper-removal-window",
        status: "required-before-wrapper-sanitizing",
        evidence: "Replacement private product build/test parity is green before product-specific wrapper entries are removed."
      }
    ],
    nextDiscussion: [
      "Which exact private product repository owns this native integration?",
      "Which paths under native/ are authoritative for manifest, assets, overrides, and generated output?",
      "Which CI job proves build/test parity before the open-source wrapper is sanitized?",
      "Which hardware smoke tests remain manual and who owns them?"
    ]
  };
}

function manifestLooksLikePrivateProductNativeManifest(manifestPath) {
  return path.basename(manifestPath) === "variant.json" && path.basename(path.dirname(manifestPath)) === "native";
}

function privateProductRootForManifest(manifestPath) {
  if (manifestLooksLikePrivateProductNativeManifest(manifestPath)) {
    return path.dirname(path.dirname(manifestPath));
  }
  return process.cwd();
}

function requiredAssetPathsForManifest(manifest) {
  return [
    manifest.branding && manifest.branding.iconSource,
    manifest.branding && manifest.branding.loadingImageSource
  ].filter(Boolean);
}

function assertRequiredAssetsExist(manifestPath, manifest) {
  if (!manifestLooksLikePrivateProductNativeManifest(manifestPath)) {
    return;
  }
  const privateProductRoot = privateProductRootForManifest(manifestPath);
  const missing = requiredAssetPathsForManifest(manifest)
    .map((assetPath) => ({
      assetPath,
      absolutePath: path.resolve(privateProductRoot, assetPath)
    }))
    .filter((asset) => !fs.existsSync(asset.absolutePath));
  if (missing.length > 0) {
    fail([
      "private product asset files referenced by native/variant.json are missing:",
      ...missing.map((asset) => `- ${asset.assetPath} (${asset.absolutePath})`)
    ].join("\n"));
  }
}

function workspaceFor(manifestPath, manifest, decisionTemplate, scaffoldPlan) {
  return {
    schemaVersion: 1,
    generatedBy: "tools/generate_variant_workspace.js",
    variantId: manifest.id,
    name: manifest.name,
    wrapperVersion: manifest.wrapperVersion,
    releaseChannel: manifest.releaseChannel,
    sourceManifest: path.relative(process.cwd(), manifestPath) || path.basename(manifestPath),
    platforms: manifest.platforms,
    wrapper: {
      root,
      version: manifest.wrapperVersion
    },
    status: {
      validManifest: true,
      readyForScaffoldPlanning: scaffoldPlan.readyForScaffold === true,
      migrationStop: "Do not move existing private product logic into private product repositories until the migration target repos and paths are explicitly agreed."
    },
    outputs: {
      decisionTemplate: "variant-decision-template.json",
      scaffoldPlan: "variant-scaffold-plan.json",
      commands: "commands.json",
      migrationStopGate: "MIGRATION_STOP_GATE.json",
      phase4DecisionRecordTemplate: "PHASE4_DECISION_RECORD_TEMPLATE.md",
      privateProductAgentsNativeSection: "PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md"
    }
  };
}

function agentsNativeSectionFor(workspace, scaffoldPlan) {
  const commands = collectCommands(scaffoldPlan);
  const wrapperRoot = shellQuote(workspace.wrapper.root);
  const commandLines = [];
  for (const platform of Object.keys(commands).sort()) {
    const platformCommands = commands[platform] || {};
    for (const kind of Object.keys(platformCommands).sort()) {
      commandLines.push(`- ${platform} ${kind}: \`${platformCommands[kind]}\``);
    }
  }

  return [
    "## Native Wrapper Integration",
    "",
    `This repository owns the app-specific native variant data for ${workspace.name}.`,
    "",
    "Owned files and directories:",
    "",
    "- `native/variant.json`",
    "- `native/wrapper-version.txt`",
    "- `native/assets/`",
    "- `native/ios/overrides/`",
    "- `native/android/overrides/`",
    "",
    "Do not edit files under `native/generated/` by hand. They are generated from",
    "`native/variant.json`, override files, and the pinned wrapper version.",
    "",
    "Product-specific native identity, startup URLs, icons, splash/loading assets,",
    "signing references, store metadata, and release-channel decisions belong in",
    "this repository, not in the open-source wrapper repository.",
    "",
    "Do not commit secrets, signing keys, provisioning profiles, Stripe keys, or",
    "private API tokens. Store only references to CI variables, Keychain entries,",
    "or secure vault paths.",
    "",
    "After changing native variant data, run:",
    "",
    "```sh",
    `WRAPPER_ROOT=${wrapperRoot}`,
    "node \"$WRAPPER_ROOT/tools/variant_manifest_check.js\" \\",
    "  --file native/variant.json",
    "node \"$WRAPPER_ROOT/tools/generate_variant_workspace.js\" \\",
    "  --variant native/variant.json \\",
    "  --output native/generated",
    "node \"$WRAPPER_ROOT/tools/phase4_stop_gate_check.js\" \\",
    "  --generated native/generated",
    "```",
    "",
    "Then run the generated build/test commands from `native/generated/commands.json`:",
    "",
    ...(commandLines.length > 0 ? commandLines : ["- No platform commands were generated."]),
    "",
    "Before moving existing private product logic or assets, review",
    "`native/generated/MIGRATION_STOP_GATE.json`, copy",
    "`native/generated/PHASE4_DECISION_RECORD_TEMPLATE.md` to a private-product-owned path,",
    "and capture the required repository, CI, parity-test, and hardware-smoke",
    "evidence there.",
    "",
    "Stop before moving existing private product logic or assets until the target repo",
    "paths and migration sequence are explicitly agreed."
  ].join("\n") + "\n";
}

function phase4DecisionRecordTemplateFor(workspace, scaffoldPlan, migrationStopGate) {
  const commands = collectCommands(scaffoldPlan);
  const commandLines = [];
  for (const platform of Object.keys(commands).sort()) {
    const platformCommands = commands[platform] || {};
    for (const kind of Object.keys(platformCommands).sort()) {
      commandLines.push(`- ${platform} ${kind}: \`${platformCommands[kind]}\``);
    }
  }

  const platformRows = (workspace.platforms || [])
    .map((platform) => `| ${platform} | TBD | TBD | TBD | TBD |`)
    .join("\n");
  const evidenceRows = (migrationStopGate.requiredEvidence || [])
    .map((item) => `| ${item.id} | ${item.status} | ${item.evidence} | TBD | TBD |`)
    .join("\n");

  return [
    `# Phase 4 Migration Decision Record: ${workspace.name}`,
    "",
    "Copy this generated template to a private-product-owned path such as",
    "`native/phase4-migration-decision.md` before filling it in.",
    "",
    "Do not edit `native/generated/` by hand. Regenerate generated files from",
    "`native/variant.json` and the pinned wrapper version.",
    "",
    "## Variant",
    "",
    `- Variant ID: \`${workspace.variantId}\``,
    `- Wrapper version: \`${workspace.wrapperVersion}\``,
    `- Source manifest: \`${workspace.sourceManifest}\``,
    `- Generated stop gate: \`${workspace.outputs.migrationStopGate}\``,
    "",
    "## Target Repository Decision",
    "",
    "| Platform | Target repository | Native root | Generated output policy | CI job |",
    "| --- | --- | --- | --- | --- |",
    platformRows || "| TBD | TBD | TBD | TBD | TBD |",
    "",
    "## Evidence Checklist",
    "",
    "| Gate item | Generated status | Required evidence | Evidence location | Owner/date |",
    "| --- | --- | --- | --- | --- |",
    evidenceRows,
    "",
    "## Generated Commands To Wire Into CI",
    "",
    ...(commandLines.length > 0 ? commandLines : ["- No platform commands were generated."]),
    "",
    "## Manual Or Device Smoke Tests",
    "",
    "| Capability | Required? | Owner | Evidence location |",
    "| --- | --- | --- | --- |",
    "| Camera / barcode / document scan | TBD | TBD | TBD |",
    "| NFC | TBD | TBD | TBD |",
    "| Bluetooth / beacons | TBD | TBD | TBD |",
    "| Printing | TBD | TBD | TBD |",
    "| Tap to Pay | TBD | TBD | TBD |",
    "",
    "## Approval",
    "",
    "- Target repositories and native paths agreed: TBD",
    "- CI parity evidence reviewed: TBD",
    "- Hardware smoke ownership assigned: TBD",
    "- Wrapper cleanup window approved: TBD",
    "",
    "No existing private product logic, assets, identity, URLs, signing, or store",
    "metadata should move until this record is filled in and reviewed."
  ].join("\n") + "\n";
}

function generatedFilesFor(workspace, decisionTemplate, scaffoldPlan) {
  const migrationStopGate = migrationStopGateFor(
    {
      id: workspace.variantId,
      name: workspace.name,
      platforms: workspace.platforms
    },
    scaffoldPlan
  );
  return {
    "README.md": readmeFor(workspace),
    "VARIANT_WORKSPACE.json": stableJSONString(workspace),
    "variant-decision-template.json": stableJSONString(decisionTemplate),
    "variant-scaffold-plan.json": stableJSONString(scaffoldPlan),
    "commands.json": stableJSONString(collectCommands(scaffoldPlan)),
    "MIGRATION_STOP_GATE.json": stableJSONString(migrationStopGate),
    "PHASE4_DECISION_RECORD_TEMPLATE.md": phase4DecisionRecordTemplateFor(workspace, scaffoldPlan, migrationStopGate),
    "PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md": agentsNativeSectionFor(workspace, scaffoldPlan),
    "review-next-steps.sh": [
      "#!/usr/bin/env sh",
      "set -eu",
      "echo 'Review generated workspace artifacts:'",
      "echo '  VARIANT_WORKSPACE.json'",
      "echo '  variant-decision-template.json'",
      "echo '  variant-scaffold-plan.json'",
      "echo '  commands.json'",
      "echo '  MIGRATION_STOP_GATE.json'",
      "echo '  PHASE4_DECISION_RECORD_TEMPLATE.md'",
      "echo '  PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md'",
      "echo 'Copy PHASE4_DECISION_RECORD_TEMPLATE.md to a private-product-owned path before recording approvals.'",
      "echo 'Stop before moving private product logic into private product repositories without explicit migration approval.'",
      ""
    ].join("\n")
  };
}

const variantArg = argValue("--variant").trim();
const outputArg = argValue("--output").trim();
const dryRun = process.argv.includes("--dry-run");
const force = process.argv.includes("--force");

if (!variantArg || !outputArg) {
  fail("--variant and --output are required.");
}

const manifestPath = path.resolve(process.cwd(), variantArg);
const outputPath = path.resolve(process.cwd(), outputArg);
assertSafeOutputPath(outputPath);

const manifest = readJSON(manifestPath);
const manifestRaw = JSON.stringify(manifest);
const manifestCheck = runNode(["tools/variant_manifest_check.js", "--stdin", "--json"], manifestRaw);
if (manifestCheck.status !== 0 || manifestCheck.json.valid !== true) {
  if (process.argv.includes("--json")) {
    console.log(stableJSONString({
      valid: false,
      manifestCheck: manifestCheck.json
    }));
  } else {
    console.log("variant manifest is invalid; generated workspace was not written");
    if (Array.isArray(manifestCheck.json.errors) && manifestCheck.json.errors.length > 0) {
      console.log(`errors: ${manifestCheck.json.errors.join("; ")}`);
    }
  }
  process.exit(2);
}
assertRequiredAssetsExist(manifestPath, manifest);

const decisionTemplate = manifestCheck.json.decisionTemplate;
const scaffoldPlan = scaffoldPlanForManifest(manifest);
const workspace = workspaceFor(manifestPath, manifest, decisionTemplate, scaffoldPlan);
const files = generatedFilesFor(workspace, decisionTemplate, scaffoldPlan);
const plannedFiles = Object.keys(files).map((relativePath) => path.join(outputPath, relativePath));
const written = [];
const conflicts = [];

if (!dryRun) {
  for (const [relativePath, content] of Object.entries(files)) {
    writeFileIfSafe(path.join(outputPath, relativePath), content, force, written, conflicts);
  }
  if (conflicts.length > 0) {
    console.error("Refusing to overwrite generated files with different content. Re-run with --force after review:");
    for (const file of conflicts) {
      console.error(`- ${file}`);
    }
    process.exit(3);
  }
}

const result = {
  valid: true,
  dryRun,
  output: outputPath,
  plannedFiles,
  generatedFiles: plannedFiles,
  commands: collectCommands(scaffoldPlan),
  workspace
};

if (process.argv.includes("--json")) {
  console.log(stableJSONString(result));
} else {
  console.log(`${manifest.id}: generated workspace ${dryRun ? "plan" : "written"}`);
  console.log(`output: ${outputPath}`);
  console.log(`files: ${plannedFiles.map((file) => path.relative(process.cwd(), file)).join(", ")}`);
  if (!dryRun && written.length > 0) {
    console.log(`written: ${written.map((file) => path.relative(process.cwd(), file)).join(", ")}`);
  }
  console.log(`review: ${shellQuote(path.join(outputPath, "README.md"))}`);
}
