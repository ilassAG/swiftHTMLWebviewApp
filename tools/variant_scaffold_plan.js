#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { answerFieldsForPlatform, targetArtifactsForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const registryPath = path.join(root, "docs/app-variants.json");
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const decisionCatalog = registry.plannedVariantDecisionCatalog || {};

function usage() {
  return [
    "Usage:",
    "  node tools/variant_scaffold_plan.js --id <variant-id> [--json]",
    "  node tools/variant_scaffold_plan.js --file <decision-template.json> [--json]",
    "  node tools/variant_scaffold_plan.js --stdin [--json]",
    "",
    "Prints the concrete decision, input-field, and target-file plan for a planned app variant.",
    "With --file or --stdin, validates a filled decision template and prints the platform scaffold artifact plan.",
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

function unique(values) {
  return [...new Set(values)];
}

function readDecisionInput() {
  if (process.argv.includes("--stdin")) {
    return fs.readFileSync(0, "utf8");
  }
  const file = argValue("--file").trim();
  if (!file) {
    return "";
  }
  return fs.readFileSync(path.resolve(root, file), "utf8");
}

function registryPlanFor(rawInput) {
  const result = spawnSync(
    process.execPath,
    ["tools/variant_registry_plan.js", "--stdin", "--json"],
    {
      cwd: root,
      input: rawInput,
      encoding: "utf8"
    }
  );
  if (!result.stdout) {
    fail(result.stderr || "Variant registry plan did not return JSON.");
  }
  return {
    status: result.status,
    plan: JSON.parse(result.stdout)
  };
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

function testClassNameFor(entry) {
  return `${pascalCase(entry.id)}VariantTest`;
}

function androidSourceTemplateFor(entry) {
  return "android/app";
}

function androidScaffoldFor(entry) {
  const modulePath = androidModulePath(entry.gradleModule);
  const sourceTemplate = androidSourceTemplateFor(entry);
  const testClassName = testClassNameFor(entry);

  return {
    id: entry.id,
    platform: "android",
    registryEntry: entry,
    sourceTemplate,
    files: [
      {
        action: "update",
        path: "android/settings.gradle",
        purpose: `Add include '${entry.gradleModule}'.`
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
        purpose: "Set the app label, launcher activity, runtime defaults, recovery metadata, permissions, and feature requirements for this variant."
      },
      {
        action: "create-or-copy",
        path: `android/${modulePath}/src/main/res/`,
        sourceTemplate: `${sourceTemplate}/src/main/res/`,
        purpose: "Provide variant app name, icon, splash/loading image, styles, and Android resources."
      },
      {
        action: "create",
        path: `android/${modulePath}/src/test/java/com/ilass/swifthtmlwebviewapp/${testClassName}.java`,
        purpose: "Add variant-boundary tests for identity, manifest defaults, optional modules, and bridge capability profile."
      }
    ],
    commands: {
      build: entry.verification && entry.verification.build
        ? entry.verification.build
        : `cd android && ./gradlew ${entry.gradleModule}:assembleDebug`,
      test: entry.verification && entry.verification.test
        ? entry.verification.test
        : `cd android && ./gradlew ${entry.gradleModule}:testDebugUnitTest`
    },
    blockers: [
      "Copy or generate final launcher icons and loading assets before treating the module as implemented.",
      "Provide private-product-owned source overrides for product-selected optional modules such as Stripe Terminal Tap to Pay.",
      "Run the generated variant-boundary tests and register them in docs/app-variants.json testCoverage."
    ]
  };
}

function iosScaffoldFor(entry) {
  const variantDirectory = `ios/Variants/${entry.sourceVariantId || entry.id}/`;
  const testClassName = `${pascalCase(entry.id)}VariantTests.swift`;

  return {
    id: entry.id,
    platform: "ios",
    registryEntry: entry,
    files: [
      {
        action: "update",
        path: "ios/swiftHTMLWebviewApp.xcodeproj/project.pbxproj",
        purpose: "Create or configure the iOS app target, bundle identifier, product name, display name, and build settings for this variant."
      },
      {
        action: "create",
        path: variantDirectory,
        purpose: "Add variant-specific config, icon/loading asset references, startup defaults, and recovery copy."
      },
      {
        action: "create-or-copy",
        path: "ios/swiftHTMLWebviewApp/Assets.xcassets/",
        purpose: "Provide final app icon and loading image assets for the variant target."
      },
      {
        action: "create",
        path: `ios/swiftHTMLWebviewAppTests/${testClassName}`,
        purpose: "Add variant-boundary tests for identity, defaults, optional modules, and bridge capability profile."
      }
    ],
    commands: {
      build: entry.verification && entry.verification.build
        ? entry.verification.build
        : "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme <variant-scheme> -destination 'generic/platform=iOS Simulator' build",
      test: entry.verification && entry.verification.test
        ? entry.verification.test
        : "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme <variant-scheme> -destination 'platform=iOS Simulator,name=iPhone 17' test"
    },
    blockers: [
      "Create a real Xcode target or xcconfig-backed scheme before treating the iOS variant as implemented.",
      "Copy or generate final app icon and loading assets before App Store or device validation."
    ]
  };
}

function platformEntryFromRegistryPlan(plan) {
  const updatePlan = plan.registryUpdatePlan || {};
  const identity = updatePlan.identity || {};
  const base = {
    id: plan.variantId,
    name: plan.name,
    platform: plan.platform,
    runtimeDefaults: updatePlan.runtimeDefaults,
    optionalModules: updatePlan.optionalModules,
    bridgeProfile: updatePlan.bridgeProfile
  };

  if (plan.platform === "ios") {
    return {
      ...base,
      bundleIdentifier: identity.bundleIdentifier,
      productName: identity.productName,
      displayName: identity.displayName,
      verification: updatePlan.verification && updatePlan.verification.iosBuildCommand && updatePlan.verification.iosTestCommand
        ? {
          build: updatePlan.verification.iosBuildCommand,
          test: updatePlan.verification.iosTestCommand
        }
        : undefined
    };
  }

  if (plan.platform === "android") {
    return {
      ...base,
      gradleModule: identity.gradleModule,
      buildFile: identity.buildFile,
      manifest: identity.manifest,
      applicationId: identity.applicationId,
      namespace: identity.namespace,
      label: identity.label,
      verification: updatePlan.verification && updatePlan.verification.androidBuildCommand && updatePlan.verification.androidTestCommand
        ? {
          build: updatePlan.verification.androidBuildCommand,
          test: updatePlan.verification.androidTestCommand
        }
        : undefined
    };
  }

  return null;
}

function platformScaffoldFor(entry) {
  if (entry.platform === "android") {
    return androidScaffoldFor(entry);
  }
  if (entry.platform === "ios") {
    return iosScaffoldFor(entry);
  }
  return null;
}

function scaffoldPlanForDecisionTemplate(rawInput) {
  const registryResult = registryPlanFor(rawInput);
  if (registryResult.status !== 0 || registryResult.plan.readyForRegistryPlanning !== true) {
    return {
      schemaVersion: 1,
      valid: false,
      decisionCheck: registryResult.plan.decisionCheck || registryResult.plan
    };
  }

  const registryPlan = registryResult.plan;
  const platformEntries = Array.isArray(registryPlan.platformRegistryEntries) && registryPlan.platformRegistryEntries.length > 0
    ? registryPlan.platformRegistryEntries
    : [platformEntryFromRegistryPlan(registryPlan)].filter(Boolean);
  const platformScaffolds = platformEntries
    .map(platformScaffoldFor)
    .filter(Boolean);

  return {
    schemaVersion: 1,
    valid: true,
    variantId: registryPlan.variantId,
    name: registryPlan.name,
    platform: registryPlan.platform,
    readyForScaffold: platformScaffolds.length > 0,
    registryPatch: registryPlan.registryPatch,
    platformScaffolds,
    unresolved: registryPlan.unresolved || []
  };
}

function plannedDecisionSteps(variant) {
  const checklist = Array.isArray(variant.decisionChecklist) ? variant.decisionChecklist : [];
  return checklist.map((decision) => {
    const catalogDecision = decisionCatalog[decision.id] || {};
    const targetArtifacts = Array.isArray(decision.targetArtifacts) && decision.targetArtifacts.length > 0
      ? decision.targetArtifacts
      : targetArtifactsForPlatform(catalogDecision.targetArtifacts, variant.platform, variant.id);
    const answerFields = Array.isArray(decision.answerFields) && decision.answerFields.length > 0
      ? decision.answerFields
      : answerFieldsForPlatform(catalogDecision.answerFields, variant.platform);

    return {
      id: decision.id,
      status: decision.status || "needed",
      question: decision.question || catalogDecision.question || "",
      answerFields,
      targetArtifacts,
      ready: decision.status === "decided",
      nextAction: decision.status === "decided"
        ? "Keep this decision synchronized with its target artifacts."
        : "Collect these answer fields before editing the target artifacts."
    };
  });
}

function scaffoldPlanFor(variant) {
  const steps = variant.status === "planned" ? plannedDecisionSteps(variant) : [];
  const blockingSteps = steps.filter((step) => !step.ready);
  return {
    id: variant.id,
    name: variant.name,
    status: variant.status,
    platform: variant.platform,
    readyForScaffold: variant.status === "planned" && blockingSteps.length === 0,
    alreadyImplemented: variant.status === "implemented",
    blockingDecisionIds: blockingSteps.map((step) => step.id),
    targetArtifacts: unique(steps.flatMap((step) => step.targetArtifacts || [])),
    steps
  };
}

function printText(plan) {
  console.log(`${plan.id}: ${plan.name} (${plan.platform})`);
  if (plan.alreadyImplemented) {
    console.log("status: already implemented");
    return;
  }
  console.log(`ready for scaffold: ${plan.readyForScaffold ? "yes" : "no"}`);
  if (plan.blockingDecisionIds.length > 0) {
    console.log(`blocking decisions: ${plan.blockingDecisionIds.join(", ")}`);
  }
  for (const step of plan.steps) {
    console.log("");
    console.log(`- ${step.id}: ${step.status}`);
    if (step.question) {
      console.log(`  question: ${step.question}`);
    }
    if (step.answerFields.length > 0) {
      console.log(`  answer fields: ${step.answerFields.map((field) => field.id).join(", ")}`);
    }
    if (step.targetArtifacts.length > 0) {
      console.log(`  target artifacts: ${step.targetArtifacts.join(", ")}`);
    }
    console.log(`  next action: ${step.nextAction}`);
  }
}

function printDecisionScaffoldText(plan) {
  if (plan.valid === false) {
    console.log("decision template is invalid; scaffold plan was not generated");
    const missing = plan.decisionCheck && plan.decisionCheck.missingRequiredAnswers;
    if (Array.isArray(missing) && missing.length > 0) {
      console.log(`missing required answers: ${missing.join(", ")}`);
    }
    return;
  }

  console.log(`${plan.variantId}: scaffold artifact plan`);
  console.log(`ready for scaffold: ${plan.readyForScaffold ? "yes" : "no"}`);
  if (plan.registryPatch && Array.isArray(plan.registryPatch.operations)) {
    console.log(`registry patch operations: ${plan.registryPatch.operations.length}`);
  }
  for (const scaffold of plan.platformScaffolds) {
    console.log("");
    console.log(`- ${scaffold.id}: ${scaffold.platform}`);
    if (scaffold.sourceTemplate) {
      console.log(`  source template: ${scaffold.sourceTemplate}`);
    }
    console.log(`  files: ${scaffold.files.map((file) => file.path).join(", ")}`);
    console.log(`  build: ${scaffold.commands.build}`);
    console.log(`  test: ${scaffold.commands.test}`);
  }
  if (plan.unresolved.length > 0) {
    console.log("");
    console.log("unresolved:");
    for (const item of plan.unresolved) {
      console.log(`- ${item}`);
    }
  }
}

const requestedId = argValue("--id").trim();
const decisionInput = readDecisionInput();
if (!requestedId && !decisionInput) {
  fail("--id is required.");
}

if (decisionInput) {
  const plan = scaffoldPlanForDecisionTemplate(decisionInput);
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(plan, null, 2));
  } else {
    printDecisionScaffoldText(plan);
  }
  process.exit(plan.valid === false ? 2 : 0);
}

const variant = (registry.variants || []).find((candidate) => candidate.id === requestedId);
if (!variant) {
  fail(`Unknown variant: ${requestedId}`);
}

const plan = scaffoldPlanFor(variant);
if (process.argv.includes("--json")) {
  console.log(JSON.stringify(plan, null, 2));
} else {
  printText(plan);
}
