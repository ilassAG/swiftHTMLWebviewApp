#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execSync, spawnSync } = require("child_process");
const { answerFieldsForPlatform, targetArtifactsForPlatform } = require("./variant_artifacts");

const root = path.resolve(__dirname, "..");
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
const readJSON = (relativePath) => JSON.parse(read(relativePath));

let failures = 0;

function fail(message) {
  failures += 1;
  console.error(`FAIL ${message}`);
}

function pass(message) {
  console.log(`OK   ${message}`);
}

function assert(condition, message) {
  if (condition) {
    pass(message);
  } else {
    fail(message);
  }
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function contains(file, text) {
  return read(file).includes(text);
}

function fileExists(relativePath) {
  return fs.existsSync(path.join(root, relativePath));
}

function normalizeStringArray(values) {
  return Array.isArray(values) ? values.filter(isNonEmptyString) : [];
}

function normalizeOptionalModuleIds(modules) {
  if (!Array.isArray(modules)) {
    return [];
  }
  return modules
    .map((module) => {
      if (typeof module === "string") {
        return module;
      }
      return module && module.id;
    })
    .filter(isNonEmptyString);
}

function assertSetEquals(actualValues, expectedValues, message) {
  const actual = new Set(normalizeStringArray(actualValues));
  const expected = new Set(normalizeStringArray(expectedValues));
  const missing = [...expected].filter((value) => !actual.has(value)).sort();
  const extra = [...actual].filter((value) => !expected.has(value)).sort();
  assert(
    missing.length === 0 && extra.length === 0,
    `${message}${missing.length || extra.length ? ` (missing: ${missing.join(", ") || "-"}; extra: ${extra.join(", ") || "-"})` : ""}`
  );
}

function isHTTPSURL(value) {
  if (!isNonEmptyString(value)) {
    return false;
  }
  try {
    return new URL(value).protocol === "https:";
  } catch (_) {
    return false;
  }
}

function extractBlockAfter(source, startMarker) {
  const start = source.indexOf(startMarker);
  if (start < 0) {
    return "";
  }
  const openBrace = source.indexOf("{", start);
  if (openBrace < 0) {
    return "";
  }
  let depth = 0;
  let closeBrace = source.length;
  for (let index = openBrace; index < source.length; index += 1) {
    if (source[index] === "{") {
      depth += 1;
    } else if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) {
        closeBrace = index;
        break;
      }
    }
  }
  return source.slice(openBrace, closeBrace);
}

function extractSwitchCaseActions(source, startMarker) {
  const switchBody = extractBlockAfter(source, startMarker);
  const actions = new Set();
  const caseRegex = /case\s+([^:\n]+):/g;
  let match;
  while ((match = caseRegex.exec(switchBody)) !== null) {
    const labels = match[1].match(/"([^"]+)"/g) || [];
    for (const label of labels) {
      actions.add(label.slice(1, -1));
    }
  }
  return actions;
}

function extractJavaStringSetValues(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) {
    return new Set();
  }
  const openParen = source.indexOf("(", start);
  if (openParen < 0) {
    return new Set();
  }
  let depth = 0;
  let closeParen = source.length;
  for (let index = openParen; index < source.length; index += 1) {
    if (source[index] === "(") {
      depth += 1;
    } else if (source[index] === ")") {
      depth -= 1;
      if (depth === 0) {
        closeParen = index;
        break;
      }
    }
  }
  const body = source.slice(openParen, closeParen);
  const values = new Set();
  const stringRegex = /"([^"]+)"/g;
  let match;
  while ((match = stringRegex.exec(body)) !== null) {
    values.add(match[1]);
  }
  return values;
}

function extractJavaActionCatalogActions(source) {
  return new Set([
    ...extractJavaStringSetValues(source, "static final Set<String> PUBLIC_ACTIONS"),
    ...extractJavaStringSetValues(source, "static final Set<String> INTERNAL_ACTIONS")
  ]);
}

function extractJSSetValues(source, setName) {
  const marker = `const ${setName} = new Set([`;
  const start = source.indexOf(marker);
  if (start < 0) {
    return new Set();
  }
  const end = source.indexOf("]);", start);
  if (end < 0) {
    return new Set();
  }
  const setBody = source.slice(start, end);
  const values = new Set();
  const stringRegex = /"([^"]+)"/g;
  let match;
  while ((match = stringRegex.exec(setBody)) !== null) {
    values.add(match[1]);
  }
  return values;
}

function extractSwiftRouterActions(source) {
  const routerBody = extractBlockAfter(source, "private func makeBridgeRouter() -> BridgeRouter");
  const actions = new Set();
  let match;
  const onRegex = /\.on\("([^"]+)"/g;
  while ((match = onRegex.exec(routerBody)) !== null) {
    actions.add(match[1]);
  }
  const onAllRegex = /\.onAll\(\[([^\]]+)\]/g;
  while ((match = onAllRegex.exec(routerBody)) !== null) {
    const labels = match[1].match(/"([^"]+)"/g) || [];
    for (const label of labels) {
      actions.add(label.slice(1, -1));
    }
  }
  return actions;
}

function extractSwiftStringSetValues(source, marker) {
  const start = source.indexOf(marker);
  if (start < 0) {
    return new Set();
  }
  const openBracket = source.indexOf("[", start);
  if (openBracket < 0) {
    return new Set();
  }
  let depth = 0;
  let closeBracket = source.length;
  for (let index = openBracket; index < source.length; index += 1) {
    if (source[index] === "[") {
      depth += 1;
    } else if (source[index] === "]") {
      depth -= 1;
      if (depth === 0) {
        closeBracket = index;
        break;
      }
    }
  }
  const body = source.slice(openBracket, closeBracket);
  const values = new Set();
  const stringRegex = /"([^"]+)"/g;
  let match;
  while ((match = stringRegex.exec(body)) !== null) {
    values.add(match[1]);
  }
  return values;
}

function extractSwiftActionCatalogActions(source) {
  return new Set([
    ...extractSwiftStringSetValues(source, "static let publicActions"),
    ...extractSwiftStringSetValues(source, "static let internalActions")
  ]);
}

function assertNoUndocumentedNativeActions(nativeActions, contractActionNames, allowedInternalActions, platform) {
  const undocumented = [...nativeActions].filter(
    (action) => !contractActionNames.has(action) && !allowedInternalActions.has(action)
  );
  assert(undocumented.length === 0, `${platform} native dispatch has no undocumented public actions${undocumented.length ? `: ${undocumented.join(", ")}` : ""}`);
}

function extractAndroidManifestLabel(manifestPath) {
  const manifest = read(manifestPath);
  const match = manifest.match(/android:label="([^"]+)"/);
  return match ? match[1] : "";
}

function extractAndroidStringValue(stringsPath, key) {
  const strings = read(stringsPath);
  const match = strings.match(new RegExp(`<string\\s+name="${key}">([^<]+)</string>`));
  return match ? match[1] : "";
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function extractAndroidMetaDataValue(manifestPath, name) {
  const manifest = read(manifestPath);
  const match = manifest.match(
    new RegExp(
      `<meta-data\\s+[^>]*android:name="${escapeRegExp(name)}"[^>]*android:value="([^"]+)"[^>]*/>`,
      "m"
    )
  );
  return match ? match[1] : "";
}

function extractSettingsBundleDefault(key) {
  const settings = read("ios/swiftHTMLWebviewApp/Settings.bundle/Root.plist");
  const match = settings.match(
    new RegExp(
      `<key>Key</key>\\s*<string>${escapeRegExp(key)}</string>[\\s\\S]*?<key>DefaultValue</key>\\s*(?:<string>([^<]*)</string>|<integer>([^<]*)</integer>|<(true|false)/>)`
    )
  );
  if (!match) {
    return undefined;
  }
  if (match[1] !== undefined) {
    return match[1];
  }
  if (match[2] !== undefined) {
    return Number(match[2]);
  }
  return match[3] === "true";
}

function instantiateFixturePayload(payload, actionName) {
  return JSON.parse(JSON.stringify(payload).replaceAll("<action>", actionName));
}

function validateFixturePayload(payload, profile, expectedAction, expectedSuccess, messagePrefix) {
  assert(payload && typeof payload === "object" && !Array.isArray(payload), `${messagePrefix} payload is an object`);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return;
  }
  assert(payload.action === expectedAction, `${messagePrefix} echoes action`);
  assert(payload.success === expectedSuccess, `${messagePrefix} success flag is ${expectedSuccess}`);
  for (const field of profile.requiredEchoFields || []) {
    assert(Object.prototype.hasOwnProperty.call(payload, field), `${messagePrefix} includes required field ${field}`);
  }
  if (expectedSuccess === false) {
    assert(isNonEmptyString(payload[profile.errorField]), `${messagePrefix} includes error field ${profile.errorField}`);
  }
}

function validateContract() {
  const contract = readJSON("docs/bridge-contract.json");
  const fixtures = readJSON("docs/bridge-response-fixtures.json");
  const iosDispatch = read("ios/swiftHTMLWebviewApp/ContentView.swift");
  const iosActionCatalog = read("ios/swiftHTMLWebviewApp/Models/BridgeActionCatalog.swift");
  const androidActionCatalog = read("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalog.java");
  const iosDemoScript = read("ios/swiftHTMLWebviewApp/HTML/script.js");
  const androidDemoScript = read("android/app/src/main/assets/script.js");
  const nativeBridgeDocs = read("docs/native-bridge.md");
  const iosNativeActions = extractSwiftActionCatalogActions(iosActionCatalog);
  const androidNativeActions = extractJavaActionCatalogActions(androidActionCatalog);
  const iosDemoLiveEvents = extractJSSetValues(iosDemoScript, "liveEventActions");
  const androidDemoLiveEvents = extractJSSetValues(androidDemoScript, "liveEventActions");
  const validStatuses = new Set(["implemented", "unavailable", "optional", "planned"]);

  assert(contract.schemaVersion === 1, "bridge contract schemaVersion is 1");
  assert(Array.isArray(contract.responseShape.requiredEchoFields), "bridge contract declares required echo fields");
  assert(contract.responseShape.requiredEchoFields.includes("action"), "bridge contract responses echo action");
  assert(contract.responseShape.errorField === "error", "bridge contract error field is error");
  assert(
    contract.responseProfiles &&
      typeof contract.responseProfiles === "object" &&
      !Array.isArray(contract.responseProfiles),
    "bridge contract declares response profiles"
  );
  assert(fixtures.schemaVersion === 1, "bridge response fixtures schemaVersion is 1");
  assert(
    fixtures.profileFixtures &&
      typeof fixtures.profileFixtures === "object" &&
      !Array.isArray(fixtures.profileFixtures),
    "bridge response fixtures declare profile fixtures"
  );
  const responseProfileNames = Object.keys(contract.responseProfiles || {});
  const fixtureProfileNames = Object.keys(fixtures.profileFixtures || {});
  assertSetEquals(fixtureProfileNames, responseProfileNames, "bridge response fixtures cover response profiles");
  for (const [profileName, profile] of Object.entries(contract.responseProfiles || {})) {
    assert(isNonEmptyString(profileName), `${profileName} response profile has name`);
    assert(isNonEmptyString(profile.delivery), `${profileName} response profile has delivery`);
    assert(isNonEmptyString(profile.resultCount), `${profileName} response profile has result count`);
    assert(Array.isArray(profile.requiredEchoFields), `${profileName} response profile declares required echo fields`);
    if (Array.isArray(profile.requiredEchoFields)) {
      assert(profile.requiredEchoFields.includes("action"), `${profileName} response profile echoes action`);
    }
    assert(profile.errorField === contract.responseShape.errorField, `${profileName} response profile uses contract error field`);
    const fixture = fixtures.profileFixtures[profileName];
    assert(Boolean(fixture), `${profileName} response profile has fixture`);
    if (fixture) {
      validateFixturePayload(
        instantiateFixturePayload(fixture.success, "<action>"),
        profile,
        "<action>",
        true,
        `${profileName} success fixture`
      );
      validateFixturePayload(
        instantiateFixturePayload(fixture.error, "<action>"),
        profile,
        "<action>",
        false,
        `${profileName} error fixture`
      );
    }
  }
  assert(
    contract.emittedEvents &&
      typeof contract.emittedEvents === "object" &&
      !Array.isArray(contract.emittedEvents),
    "bridge contract declares emitted event catalog"
  );
  const emittedEventNames = new Set(Object.keys(contract.emittedEvents || {}));
  assert(emittedEventNames.size > 0, "bridge contract emitted event catalog is not empty");
  for (const [eventName, event] of Object.entries(contract.emittedEvents || {})) {
    assert(isNonEmptyString(eventName), `${eventName} emitted event has name`);
    assert(isNonEmptyString(event.source), `${eventName} emitted event has source`);
    assert(isNonEmptyString(event.delivery), `${eventName} emitted event has delivery`);
    assert(Array.isArray(event.requiredFields), `${eventName} emitted event declares required fields`);
    if (Array.isArray(event.requiredFields)) {
      assert(event.requiredFields.includes("action"), `${eventName} emitted event echoes action`);
    }
  }
  assert(Array.isArray(contract.actions) && contract.actions.length > 0, "bridge contract has actions");

  const names = contract.actions.map((action) => action.name);
  const contractActionNames = new Set(names);
  const actionsByName = new Map(contract.actions.map((action) => [action.name, action]));
  assert(new Set(names).size === names.length, "bridge contract action names are unique");
  assert(
    contract.legacyCompatibility &&
      typeof contract.legacyCompatibility === "object" &&
      !Array.isArray(contract.legacyCompatibility),
    "bridge contract declares legacy compatibility exceptions"
  );
  const legacyCompatibilityActions = contract.legacyCompatibility && contract.legacyCompatibility.actions;
  assert(
    legacyCompatibilityActions &&
      typeof legacyCompatibilityActions === "object" &&
      !Array.isArray(legacyCompatibilityActions),
    "bridge contract legacy compatibility lists actions"
  );
  for (const [actionName, legacy] of Object.entries(legacyCompatibilityActions || {})) {
    assert(contractActionNames.has(actionName), `${actionName} legacy compatibility action exists in contract`);
    assert(Array.isArray(legacy.platforms) && legacy.platforms.length > 0, `${actionName} legacy compatibility lists platforms`);
    if (Array.isArray(legacy.platforms)) {
      for (const platform of legacy.platforms) {
        assert(["ios", "android"].includes(platform), `${actionName} legacy compatibility platform is valid: ${platform}`);
      }
    }
    assert(
      Array.isArray(legacy.omitsRecommendedFields) && legacy.omitsRecommendedFields.length > 0,
      `${actionName} legacy compatibility lists omitted recommended fields`
    );
    if (Array.isArray(legacy.omitsRecommendedFields)) {
      for (const field of legacy.omitsRecommendedFields) {
        assert(
          contract.responseShape.recommendedEchoFields.includes(field),
          `${actionName} legacy compatibility only omits recommended field: ${field}`
        );
      }
    }
    assert(isNonEmptyString(legacy.reason), `${actionName} legacy compatibility records reason`);
    assert(Array.isArray(legacy.tests) && legacy.tests.length > 0, `${actionName} legacy compatibility records tests`);
    if (Array.isArray(legacy.tests)) {
      for (const testPath of legacy.tests) {
        assert(fileExists(testPath), `${actionName} legacy compatibility test exists: ${testPath}`);
      }
    }
  }
  for (const eventName of emittedEventNames) {
    assert(!contractActionNames.has(eventName), `${eventName} emitted event is not also a public command action`);
  }
  for (const eventName of iosDemoLiveEvents) {
    assert(emittedEventNames.has(eventName), `iOS demo live event is in emitted event catalog: ${eventName}`);
  }
  for (const eventName of androidDemoLiveEvents) {
    assert(emittedEventNames.has(eventName), `Android demo live event is in emitted event catalog: ${eventName}`);
  }
  assert(iosNativeActions.size > 0, "iOS bridge router actions can be extracted");
  assert(androidNativeActions.size > 0, "Android bridge action catalog actions can be extracted");
  assertNoUndocumentedNativeActions(iosNativeActions, contractActionNames, new Set(["idleActivity"]), "iOS");
  assertNoUndocumentedNativeActions(androidNativeActions, contractActionNames, new Set(["idleActivity"]), "Android");
  assert(nativeBridgeDocs.includes("arGuidedMeasurementUpdateStats"), "native bridge docs list arGuidedMeasurementUpdateStats");
  assert(nativeBridgeDocs.includes("- `reload`"), "native bridge docs list reload as a public action");

  for (const action of contract.actions) {
    assert(isNonEmptyString(action.name), `action ${action.name} has a name`);
    assert(validStatuses.has(action.ios), `${action.name} has valid iOS status`);
    assert(validStatuses.has(action.android), `${action.name} has valid Android status`);
    assert(isNonEmptyString(action.responseProfile), `${action.name} declares response profile`);
    assert(Boolean(contract.responseProfiles[action.responseProfile]), `${action.name} response profile exists`);
    const fixture = fixtures.profileFixtures[action.responseProfile];
    if (fixture && contract.responseProfiles[action.responseProfile]) {
      validateFixturePayload(
        instantiateFixturePayload(fixture.success, action.name),
        contract.responseProfiles[action.responseProfile],
        action.name,
        true,
        `${action.name} success response fixture`
      );
      validateFixturePayload(
        instantiateFixturePayload(fixture.error, action.name),
        contract.responseProfiles[action.responseProfile],
        action.name,
        false,
        `${action.name} error response fixture`
      );
    }
    assert(action.emits === undefined || Array.isArray(action.emits), `${action.name} emits is absent or an array`);
    if (Array.isArray(action.emits)) {
      assert(new Set(action.emits).size === action.emits.length, `${action.name} emits unique events`);
      for (const eventName of action.emits) {
        assert(emittedEventNames.has(eventName), `${action.name} emits cataloged event ${eventName}`);
      }
    }

    if (action.aliasOf) {
      const target = actionsByName.get(action.aliasOf);
      assert(Boolean(target), `${action.name} alias target exists`);
      if (target) {
        assert(action.ios === target.ios, `${action.name} alias iOS status matches ${action.aliasOf}`);
        assert(action.android === target.android, `${action.name} alias Android status matches ${action.aliasOf}`);
        assert(action.responseProfile === target.responseProfile, `${action.name} alias response profile matches ${action.aliasOf}`);
      }
    }

    if (action.ios !== "planned") {
      assert(iosNativeActions.has(action.name), `iOS dispatch references ${action.name}`);
    }

    if (action.android !== "planned") {
      assert(androidNativeActions.has(action.name), `Android action catalog references ${action.name}`);
    }
  }

  const secureActionNames = contract.secureDocumentActions.actions || [];
  assert(
    Array.isArray(secureActionNames) &&
      contract.secureDocumentActions.status === "planned",
    "secure document bridge actions remain explicitly planned"
  );
  assert(secureActionNames.length > 0, "secure document bridge lists planned actions");
  assert(new Set(secureActionNames).size === secureActionNames.length, "secure document bridge actions are unique");
  for (const action of secureActionNames) {
    assert(action.startsWith("secure"), `${action} is namespaced as a secure action`);
    assert(!contractActionNames.has(action), `${action} is not mixed into the non-secure bridge contract`);
    assert(!iosNativeActions.has(action), `${action} is not registered in iOS native dispatch while planned`);
    assert(!androidNativeActions.has(action), `${action} is not registered in Android action catalog while planned`);
    assert(!iosDemoScript.includes(action), `${action} is not exposed in iOS demo script while planned`);
    assert(!androidDemoScript.includes(action), `${action} is not exposed in Android demo script while planned`);
  }
}

function validateVariants() {
  const variants = readJSON("docs/app-variants.json");
  const contract = readJSON("docs/bridge-contract.json");
  const androidDocs = read("docs/android.md");
  const contractActionsByName = new Map(contract.actions.map((action) => [action.name, action]));
  const validPlatforms = new Set(["ios", "android"]);
  const validDecisionStatuses = new Set(["needed", "decided"]);
  const plannedDecisionArtifactFields = {
    identity: [
      "xcodeProject",
      "scheme",
      "bundleIdentifier",
      "productName",
      "displayName",
      "gradleModule",
      "buildFile",
      "manifest",
      "applicationId",
      "namespace",
      "label",
      "labelResource"
    ],
    branding: ["displayName", "label", "labelResource"],
    "startup-provisioning": ["runtimeDefaults"],
    "native-capabilities": ["optionalModules"],
    "bridge-profile": ["bridgeProfile"],
    verification: ["verification", "testCoverage"]
  };

  assert(variants.schemaVersion === 1, "variant registry schemaVersion is 1");
  assert(Array.isArray(variants.variants) && variants.variants.length > 0, "variant registry has variants");

  const ids = variants.variants.map((variant) => variant.id);
  assert(new Set(ids).size === ids.length, "variant registry ids are unique");
  assert(fileExists("tools/variant_readiness.js"), "variant readiness CLI exists");
  const readinessJSON = JSON.parse(execSync("node tools/variant_readiness.js --json", { cwd: root, encoding: "utf8" }));
  assert(Array.isArray(readinessJSON), "variant readiness CLI returns JSON array");
  assertSetEquals(readinessJSON.map((variant) => variant.id), ids, "variant readiness CLI lists registry variants");
  const privateDemoAppReadiness = JSON.parse(
    execSync("node tools/variant_readiness.js --id private-demo-app --json", { cwd: root, encoding: "utf8" })
  );
  const privateDemoApp = privateDemoAppReadiness[0] || {};
  assert(privateDemoAppReadiness.length === 1, "variant readiness CLI filters by variant id");
  assert(privateDemoApp.id === "private-demo-app", "variant readiness CLI returns requested planned variant");
  assert(privateDemoApp.blocked === true, "variant readiness marks PrivateDemoApp as blocked by decisions");
  assert(privateDemoApp.readyForImplementation === false, "variant readiness keeps PrivateDemoApp out of implementation-ready state");
  assert((privateDemoApp.blockingDecisionIds || []).includes("identity"), "variant readiness lists PrivateDemoApp identity blocker");
  assert((privateDemoApp.blockingDecisionIds || []).includes("verification"), "variant readiness lists PrivateDemoApp verification blocker");
  assert(
    (privateDemoApp.blockingTargetArtifacts || []).includes("docs/app-variants.json"),
    "variant readiness lists PrivateDemoApp blocking registry artifact"
  );
  assert(
    (privateDemoApp.blockingTargetArtifacts || []).includes("tools/validate_contracts.js"),
    "variant readiness lists PrivateDemoApp blocking validator artifact"
  );
  assert(Boolean(privateDemoApp.nextDecision), "variant readiness exposes next PrivateDemoApp decision");
  assert(
    Array.isArray(privateDemoApp.nextDecision && privateDemoApp.nextDecision.targetArtifacts) &&
      privateDemoApp.nextDecision.targetArtifacts.includes("docs/app-variants.json"),
    "variant readiness exposes next decision target artifacts"
  );
  assert(
    Array.isArray(privateDemoApp.nextDecision && privateDemoApp.nextDecision.answerFields) &&
      privateDemoApp.nextDecision.answerFields.some((field) => field.id === "bundleIdentifier") &&
      privateDemoApp.nextDecision.answerFields.some((field) => field.id === "applicationId"),
    "variant readiness exposes platform-relevant next decision answer fields"
  );
  const readinessGate = spawnSync(
    process.execPath,
    ["tools/variant_readiness.js", "--id", "private-demo-app", "--require-ready"],
    { cwd: root, encoding: "utf8" }
  );
  assert(readinessGate.status === 2, "variant readiness CLI fails require-ready for blocked planned variants");
  assert(readinessGate.stderr.includes("private-demo-app"), "variant readiness require-ready failure names blocked variant");
  assert(fileExists("tools/variant_plan.js"), "variant plan CLI exists");
  assert(fileExists("tools/variant_artifacts.js"), "variant artifact helper exists");
  assert(fileExists("tools/variant_scaffold_plan.js"), "variant scaffold plan CLI exists");
  assert(fileExists("tools/variant_decision_template.js"), "variant decision template CLI exists");
  assert(fileExists("tools/variant_decision_check.js"), "variant decision check CLI exists");
  assert(fileExists("tools/variant_registry_plan.js"), "variant registry plan CLI exists");
  assert(fileExists("docs/private-product-migration-inventory.md"), "private product migration inventory exists");
  assert(fileExists("docs/private-product-footprint-allowlist.json"), "private product footprint allowlist exists");
  assert(fileExists("docs/private-product-native-integration-template.md"), "private product native integration template exists");
  assert(fileExists("docs/variant-manifest.schema.json"), "private variant manifest schema exists");
  assert(fileExists("docs/variant-manifest.example.json"), "sanitized private variant manifest example exists");
  assert(fileExists("tools/private_product_footprint_audit.js"), "private product footprint audit CLI exists");
  assert(fileExists("tools/variant_manifest_check.js"), "private variant manifest check CLI exists");
  assert(fileExists("tools/generate_variant_workspace.js"), "generated variant workspace CLI exists");
  const privateProductFootprintAudit = spawnSync(
    process.execPath,
    ["tools/private_product_footprint_audit.js", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(privateProductFootprintAudit.status === 0, "private product footprint audit passes");
  const privateProductFootprintReport = JSON.parse(privateProductFootprintAudit.stdout);
  assert(
    privateProductFootprintReport.valid === true &&
      privateProductFootprintReport.blockedMatches === 0 &&
      privateProductFootprintReport.violations.length === 0,
    "private product footprint audit reports no new product-footprint violations"
  );

  const plannedDecisionCatalog = variants.plannedVariantDecisionCatalog || {};
  assert(
    plannedDecisionCatalog &&
      typeof plannedDecisionCatalog === "object" &&
      !Array.isArray(plannedDecisionCatalog),
    "variant registry has planned variant decision catalog"
  );
  const plannedDecisionIds = new Set(Object.keys(plannedDecisionCatalog));
  assert(plannedDecisionIds.size > 0, "planned variant decision catalog is not empty");
  for (const [decisionId, decision] of Object.entries(plannedDecisionCatalog)) {
    assert(isNonEmptyString(decisionId), `${decisionId} planned decision has id`);
    assert(isNonEmptyString(decision.description), `${decisionId} planned decision has description`);
    assert(isNonEmptyString(decision.question), `${decisionId} planned decision has intake question`);
    assert(Array.isArray(decision.targetArtifacts) && decision.targetArtifacts.length > 0, `${decisionId} planned decision lists target artifacts`);
    if (Array.isArray(decision.targetArtifacts)) {
      assert(decision.targetArtifacts.every(isNonEmptyString), `${decisionId} planned decision target artifacts are non-empty`);
    }
    assert(Array.isArray(decision.answerFields) && decision.answerFields.length > 0, `${decisionId} planned decision lists answer fields`);
    if (Array.isArray(decision.answerFields)) {
      const answerFieldIds = decision.answerFields.map((field) => field && field.id).filter(isNonEmptyString);
      assert(new Set(answerFieldIds).size === answerFieldIds.length, `${decisionId} planned decision answer field ids are unique`);
      for (const field of decision.answerFields) {
        assert(field && typeof field === "object" && !Array.isArray(field), `${decisionId} planned decision answer field is an object`);
        assert(isNonEmptyString(field.id), `${decisionId} planned decision answer field has id`);
        assert(isNonEmptyString(field.label), `${decisionId} planned decision answer field ${field.id} has label`);
        assert(typeof field.required === "boolean", `${decisionId} planned decision answer field ${field.id} declares required flag`);
        if (Array.isArray(field.platforms)) {
          assert(field.platforms.every((platform) => ["ios", "android"].includes(platform)), `${decisionId} planned decision answer field ${field.id} uses known platforms`);
        }
        if (Array.isArray(field.allowedValues)) {
          assert(field.allowedValues.every(isNonEmptyString), `${decisionId} planned decision answer field ${field.id} allowed values are non-empty`);
        }
      }
    }
  }
  const plannedTemplate = JSON.parse(
    execSync('node tools/variant_plan.js --id private-product-template --name "Private Product" --platform android', { cwd: root, encoding: "utf8" })
  );
  assert(plannedTemplate.id === "private-product-template", "variant plan CLI uses requested id");
  assert(plannedTemplate.name === "Private Product", "variant plan CLI uses requested name");
  assert(plannedTemplate.platform === "android", "variant plan CLI uses requested platform");
  assert(plannedTemplate.status === "planned", "variant plan CLI emits planned status");
  assertSetEquals(plannedTemplate.requiredDecisionIds, [...plannedDecisionIds], "variant plan CLI uses planned decision ids");
  assertSetEquals(
    plannedTemplate.requiredDecisions,
    plannedTemplate.requiredDecisionIds.map((decisionId) => plannedDecisionCatalog[decisionId].description),
    "variant plan CLI required decisions use catalog descriptions"
  );
  assertSetEquals(
    (plannedTemplate.decisionChecklist || []).map((decision) => decision.id),
    [...plannedDecisionIds],
    "variant plan CLI checklist covers planned decision ids"
  );
  for (const decision of plannedTemplate.decisionChecklist || []) {
    assert(
      Array.isArray(decision.targetArtifacts) && decision.targetArtifacts.length > 0,
      `variant plan CLI includes target artifacts for ${decision.id}`
    );
    assert(
      Array.isArray(decision.answerFields) && decision.answerFields.length > 0,
      `variant plan CLI includes answer fields for ${decision.id}`
    );
  }
  const plannedAndroidIdentityArtifacts = (plannedTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .targetArtifacts;
  assert(plannedAndroidIdentityArtifacts.includes("android/private-product-template/build.gradle"), "variant plan CLI keeps concrete Android build artifact for Android variants");
  assert(plannedAndroidIdentityArtifacts.includes("android/settings.gradle"), "variant plan CLI keeps Android settings artifact for Android variants");
  assert(plannedAndroidIdentityArtifacts.every((artifact) => !artifact.includes("<variant>")), "variant plan CLI resolves Android variant artifact placeholders");
  assert(!plannedAndroidIdentityArtifacts.includes("ios project target or xcconfig"), "variant plan CLI omits iOS identity artifact for Android variants");
  const plannedAndroidIdentityFields = (plannedTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .answerFields;
  assert(plannedAndroidIdentityFields.some((field) => field.id === "applicationId"), "variant plan CLI keeps Android identity answer fields for Android variants");
  assert(!plannedAndroidIdentityFields.some((field) => field.id === "bundleIdentifier"), "variant plan CLI omits iOS identity answer fields for Android variants");
  const plannedIOSTemplate = JSON.parse(
    execSync('node tools/variant_plan.js --id ios-private-product-template --name "Private Product" --platform ios', { cwd: root, encoding: "utf8" })
  );
  const plannedIOSIdentityArtifacts = (plannedIOSTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .targetArtifacts;
  assert(plannedIOSIdentityArtifacts.includes("ios project target or xcconfig"), "variant plan CLI keeps iOS identity artifact for iOS variants");
  assert(plannedIOSTemplate.decisionChecklist.flatMap((decision) => decision.targetArtifacts || []).every((artifact) => !artifact.includes("<variant>")), "variant plan CLI resolves iOS variant artifact placeholders");
  assert(!plannedIOSIdentityArtifacts.includes("android/ios-private-product-template/build.gradle"), "variant plan CLI omits Android build artifact for iOS variants");
  assert(!plannedIOSIdentityArtifacts.includes("android/settings.gradle"), "variant plan CLI omits Android settings artifact for iOS variants");
  const plannedIOSIdentityFields = (plannedIOSTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .answerFields;
  assert(plannedIOSIdentityFields.some((field) => field.id === "bundleIdentifier"), "variant plan CLI keeps iOS identity answer fields for iOS variants");
  assert(!plannedIOSIdentityFields.some((field) => field.id === "applicationId"), "variant plan CLI omits Android identity answer fields for iOS variants");
  const plannedCrossPlatformTemplate = JSON.parse(
    execSync('node tools/variant_plan.js --id cross-private-product-template --name "Private Product" --platform cross-platform', { cwd: root, encoding: "utf8" })
  );
  const plannedCrossPlatformIdentityArtifacts = (plannedCrossPlatformTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .targetArtifacts;
  assert(plannedCrossPlatformIdentityArtifacts.includes("ios project target or xcconfig"), "variant plan CLI keeps iOS identity artifact for cross-platform variants");
  assert(plannedCrossPlatformIdentityArtifacts.includes("android/cross-private-product-template/build.gradle"), "variant plan CLI keeps concrete Android build artifact for cross-platform variants");
  assert(plannedCrossPlatformTemplate.decisionChecklist.flatMap((decision) => decision.targetArtifacts || []).every((artifact) => !artifact.includes("<variant>")), "variant plan CLI resolves cross-platform variant artifact placeholders");
  const plannedCrossPlatformIdentityFields = (plannedCrossPlatformTemplate.decisionChecklist || [])
    .find((decision) => decision.id === "identity")
    .answerFields;
  assert(plannedCrossPlatformIdentityFields.some((field) => field.id === "bundleIdentifier"), "variant plan CLI keeps iOS identity answer fields for cross-platform variants");
  assert(plannedCrossPlatformIdentityFields.some((field) => field.id === "applicationId"), "variant plan CLI keeps Android identity answer fields for cross-platform variants");

  const privateVariantSchema = readJSON("docs/variant-manifest.schema.json");
  assert(privateVariantSchema.title && privateVariantSchema.properties, "private variant manifest schema declares a JSON schema shape");
  const exampleManifestCheck = spawnSync(
    process.execPath,
    ["tools/variant_manifest_check.js", "--file", "docs/variant-manifest.example.json", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(exampleManifestCheck.status === 0, "private variant manifest check accepts sanitized example manifest");
  const exampleManifestReport = JSON.parse(exampleManifestCheck.stdout);
  assert(exampleManifestReport.valid === true, "private variant manifest check marks sanitized example valid");
  const unavailableActionsFor = (platform) => (contract.actions || [])
    .filter((action) => action && action[platform] === "unavailable")
    .map((action) => action.name)
    .sort();
  const filledPrivatePrivateDemoAppManifest = {
    schemaVersion: 1,
    id: "private-demo-app",
    name: "PrivateDemoApp",
    wrapperVersion: "v1.0.0",
    releaseChannel: "development",
    platforms: ["ios", "android"],
    ios: {
      bundleIdentifier: "invalid.example.privatedemoapp",
      productName: "Private Demo App",
      displayName: "Private Demo App"
    },
    android: {
      gradleModule: ":private-demo-app",
      applicationId: "invalid.example.privatedemoapp",
      namespace: "invalid.example.privatedemoapp",
      label: "Private Demo App"
    },
    startup: {
      mode: "fixed-url",
      serverURL: "https://example.invalid/private-demo-app/",
      securityTokenPolicy: "qr-provisioned"
    },
    branding: {
      iconSource: "native/assets/icon.png",
      loadingImageSource: "native/assets/splash.png",
      loadingImageName: "splash",
      recoveryShortMark: "PD",
      recoveryTitle: "Private Demo App",
      recoveryBody: "Server nicht erreichbar. Bitte QR-Code erneut scannen.",
      recoveryQRCodeDetectedMessage: "QR-Code erkannt. Verbindung wird geprueft...",
      recoveryInvalidQRMessage: "Der QR-Code enthaelt keine gueltige Server-URL."
    },
    features: {
      requiredCapabilities: ["scanBarcode"],
      optionalModules: [],
      excludedCapabilities: []
    },
    bridgeProfile: {
      ios: {
        enabledOptionalModules: [],
        unavailableActions: unavailableActionsFor("ios")
      },
      android: {
        enabledOptionalModules: [],
        unavailableActions: unavailableActionsFor("android")
      }
    },
    verification: {
      iosBuildCommand: "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme PrivateDemoApp -destination 'generic/platform=iOS Simulator' build",
      iosTestCommand: "xcodebuild -project ios/swiftHTMLWebviewApp.xcodeproj -scheme PrivateDemoApp -destination 'platform=iOS Simulator,name=iPhone 17' test",
      androidBuildCommand: "cd android && ./gradlew :private-demo-app:assembleDebug",
      androidTestCommand: "cd android && ./gradlew :private-demo-app:testDebugUnitTest",
      variantBoundaryTests: [
        {
          file: "native/generated/tests/PrivateDemoAppVariantTest",
          contains: "identity matches manifest"
        }
      ]
    }
  };
  const filledManifestCheck = spawnSync(
    process.execPath,
    ["tools/variant_manifest_check.js", "--stdin", "--json"],
    { cwd: root, input: JSON.stringify(filledPrivatePrivateDemoAppManifest), encoding: "utf8" }
  );
  assert(filledManifestCheck.status === 0, "private variant manifest check accepts filled PrivateDemoApp manifest");
  const filledManifestReport = JSON.parse(filledManifestCheck.stdout);
  assert(
    filledManifestReport.valid === true &&
      filledManifestReport.decisionTemplate &&
      filledManifestReport.decisionTemplate.variantId === "private-demo-app",
    "private variant manifest check emits a decision template for planned variants"
  );
  const bridgeProfileAnswers = filledManifestReport.decisionTemplate.decisions["bridge-profile"].answers;
  assert(
    bridgeProfileAnswers.platformProfiles &&
      bridgeProfileAnswers.platformProfiles.ios &&
      bridgeProfileAnswers.platformProfiles.android &&
      bridgeProfileAnswers.platformProfiles.android.contractPlatform === "android" &&
      Array.isArray(bridgeProfileAnswers.platformProfiles.android.unavailableActions) &&
      bridgeProfileAnswers.platformProfiles.android.unavailableActions.includes("roomPlanScanStart"),
    "private variant manifest decision template preserves cross-platform bridge profiles"
  );
  const missingVerificationManifest = { ...filledPrivatePrivateDemoAppManifest };
  delete missingVerificationManifest.verification;
  const missingVerificationCheck = spawnSync(
    process.execPath,
    ["tools/variant_manifest_check.js", "--stdin", "--json"],
    { cwd: root, input: JSON.stringify(missingVerificationManifest), encoding: "utf8" }
  );
  assert(missingVerificationCheck.status === 2, "private variant manifest check rejects missing verification section");
  const missingVerificationReport = JSON.parse(missingVerificationCheck.stdout);
  assert(
    missingVerificationReport.errors.some((error) => error.includes("verification section is required")),
    "private variant manifest check reports missing verification as an error"
  );
  const manifestDecisionCheck = spawnSync(
    process.execPath,
    ["tools/variant_decision_check.js", "--stdin", "--json"],
    { cwd: root, input: JSON.stringify(filledManifestReport.decisionTemplate), encoding: "utf8" }
  );
  assert(manifestDecisionCheck.status === 0, "private variant manifest decision template passes existing decision checker");
  const invalidPrivateManifest = {
    ...filledPrivatePrivateDemoAppManifest,
    releaseChannel: "production",
    startup: {
      mode: "fixed-url",
      serverURL: "http://192.168.1.10/mobile/?token=secret",
      securityTokenPolicy: "raw-token-secret"
    },
    features: {
      requiredCapabilities: ["roomPlanScanStart", "tapToPayCollect"],
      optionalModules: [],
      excludedCapabilities: ["roomPlanScanStart"]
    },
    bridgeProfile: {
      android: {
        enabledOptionalModules: [],
        unavailableActions: []
      }
    }
  };
  const invalidManifestCheck = spawnSync(
    process.execPath,
    ["tools/variant_manifest_check.js", "--stdin", "--json"],
    { cwd: root, input: JSON.stringify(invalidPrivateManifest), encoding: "utf8" }
  );
  assert(invalidManifestCheck.status === 2, "private variant manifest check rejects unsafe or inconsistent manifests");
  const invalidManifestReport = JSON.parse(invalidManifestCheck.stdout);
  assert(
    invalidManifestReport.errors.some((error) => error.includes("roomPlanScanStart is unavailable on android")) &&
      invalidManifestReport.errors.some((error) => error.includes("startup.serverURL must not contain embedded tokens")),
    "private variant manifest check reports contract and secret-policy errors"
  );
  const invalidReverseDNSManifest = {
    ...filledPrivatePrivateDemoAppManifest,
    ios: {
      ...filledPrivatePrivateDemoAppManifest.ios,
      bundleIdentifier: "invalid.example.bad-name"
    },
    android: {
      ...filledPrivatePrivateDemoAppManifest.android,
      applicationId: "invalid.example.1bad",
      namespace: "invalid.example.bad-name"
    }
  };
  const invalidReverseDNSCheck = spawnSync(
    process.execPath,
    ["tools/variant_manifest_check.js", "--stdin", "--json"],
    { cwd: root, input: JSON.stringify(invalidReverseDNSManifest), encoding: "utf8" }
  );
  assert(invalidReverseDNSCheck.status === 2, "private variant manifest check rejects reverse-DNS identifiers that drift from schema rules");
  const privateProductDir = fs.mkdtempSync(path.join(os.tmpdir(), "swift-html-private-product-"));
  fs.mkdirSync(path.join(privateProductDir, "native", "assets"), { recursive: true });
  fs.writeFileSync(path.join(privateProductDir, "native", "variant.json"), JSON.stringify(filledPrivatePrivateDemoAppManifest, null, 2));
  fs.writeFileSync(path.join(privateProductDir, "native", "assets", "icon.png"), "placeholder icon");
  fs.writeFileSync(path.join(privateProductDir, "native", "assets", "splash.png"), "placeholder splash");
  const cwdManifestCheck = spawnSync(
    process.execPath,
    [path.join(root, "tools/variant_manifest_check.js"), "--file", "native/variant.json", "--json"],
    { cwd: privateProductDir, encoding: "utf8" }
  );
  assert(cwdManifestCheck.status === 0, "private variant manifest check resolves --file relative to the private product working directory");
  const privateProductGeneratedDir = path.join(privateProductDir, "native", "generated");
  const privateProductWorkspaceWrite = spawnSync(
    process.execPath,
    [path.join(root, "tools/generate_variant_workspace.js"), "--variant", "native/variant.json", "--output", privateProductGeneratedDir, "--json"],
    { cwd: privateProductDir, encoding: "utf8" }
  );
  assert(privateProductWorkspaceWrite.status === 0, "generated variant workspace accepts private product native assets referenced by native/variant.json");
  fs.unlinkSync(path.join(privateProductDir, "native", "assets", "icon.png"));
  const missingAssetWorkspaceWrite = spawnSync(
    process.execPath,
    [path.join(root, "tools/generate_variant_workspace.js"), "--variant", "native/variant.json", "--output", path.join(privateProductDir, "native", "generated-missing-asset"), "--json"],
    { cwd: privateProductDir, encoding: "utf8" }
  );
  assert(missingAssetWorkspaceWrite.status === 1, "generated variant workspace rejects missing private product native assets");
  const generatedWorkspaceDir = fs.mkdtempSync(path.join(os.tmpdir(), "swift-html-generated-workspace-"));
  const generatedWorkspaceDryRun = spawnSync(
    process.execPath,
    [
      "tools/generate_variant_workspace.js",
      "--variant",
      "docs/variant-manifest.example.json",
      "--output",
      generatedWorkspaceDir,
      "--dry-run",
      "--json"
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(generatedWorkspaceDryRun.status === 0, "generated variant workspace CLI supports dry-run planning");
  const generatedWorkspaceDryRunReport = JSON.parse(generatedWorkspaceDryRun.stdout);
  assert(
    generatedWorkspaceDryRunReport.valid === true &&
      generatedWorkspaceDryRunReport.dryRun === true &&
      (generatedWorkspaceDryRunReport.plannedFiles || []).some((file) => file.endsWith("VARIANT_WORKSPACE.json")),
    "generated variant workspace dry-run reports deterministic handoff files"
  );
  const generatedWorkspaceWrite = spawnSync(
    process.execPath,
    [
      "tools/generate_variant_workspace.js",
      "--variant",
      "docs/variant-manifest.example.json",
      "--output",
      generatedWorkspaceDir,
      "--json"
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(generatedWorkspaceWrite.status === 0, "generated variant workspace CLI writes handoff files");
  const generatedWorkspaceFiles = [
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
  for (const file of generatedWorkspaceFiles) {
    assert(fs.existsSync(path.join(generatedWorkspaceDir, file)), `generated variant workspace writes ${file}`);
  }
  const generatedWorkspaceSummary = JSON.parse(fs.readFileSync(path.join(generatedWorkspaceDir, "VARIANT_WORKSPACE.json"), "utf8"));
  assert(
    generatedWorkspaceSummary.variantId === "demo-wrapper" &&
      generatedWorkspaceSummary.status.migrationStop.includes("Do not move existing private product logic") &&
      generatedWorkspaceSummary.outputs.migrationStopGate === "MIGRATION_STOP_GATE.json",
    "generated variant workspace records migration stop before private product repository moves"
  );
  assert(
    generatedWorkspaceSummary.outputs.phase4DecisionRecordTemplate === "PHASE4_DECISION_RECORD_TEMPLATE.md",
    "generated variant workspace records copyable Phase 4 decision record template"
  );
  const migrationStopGate = JSON.parse(fs.readFileSync(path.join(generatedWorkspaceDir, "MIGRATION_STOP_GATE.json"), "utf8"));
  const requiredStopGateEvidenceIds = [
    "target-repository",
    "manifest-ownership",
    "asset-ownership",
    "agents-guidance",
    "ci-commands",
    "parity-tests",
    "hardware-owner",
    "wrapper-removal-window"
  ];
  const actualStopGateEvidenceIds = (migrationStopGate.requiredEvidence || []).map((item) => item.id);
  assert(
    migrationStopGate.variantId === "demo-wrapper" &&
      migrationStopGate.phase4Authorized === false &&
      migrationStopGate.stopPoint.includes("Do not move existing private product logic") &&
      JSON.stringify(actualStopGateEvidenceIds) === JSON.stringify(requiredStopGateEvidenceIds) &&
      migrationStopGate.requiredEvidence.every((item) => ["required", "satisfied-by-input", "generated-for-review", "required-before-wrapper-sanitizing"].includes(item.status)) &&
      migrationStopGate.nextDiscussion.length >= 3,
    "generated variant workspace writes explicit Phase 4 stop-gate evidence checklist"
  );
  const phase4DecisionRecordTemplate = fs.readFileSync(path.join(generatedWorkspaceDir, "PHASE4_DECISION_RECORD_TEMPLATE.md"), "utf8");
  assert(
    phase4DecisionRecordTemplate.includes("Copy this generated template to a private-product-owned path") &&
      phase4DecisionRecordTemplate.includes("Target Repository Decision") &&
      phase4DecisionRecordTemplate.includes("Evidence Checklist") &&
      phase4DecisionRecordTemplate.includes("No existing private product logic"),
    "generated variant workspace writes a copyable Phase 4 decision record template"
  );
  const phase4StopGateCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(phase4StopGateCheck.status === 0, "Phase 4 stop-gate checker accepts generated handoff workspace");
  const copiedDecisionRecord = path.join(os.tmpdir(), `phase4-migration-decision-${Date.now()}.md`);
  fs.copyFileSync(path.join(generatedWorkspaceDir, "PHASE4_DECISION_RECORD_TEMPLATE.md"), copiedDecisionRecord);
  const phase4StopGateWithDecisionRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", copiedDecisionRecord, "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(phase4StopGateWithDecisionRecordCheck.status === 0, "Phase 4 stop-gate checker accepts copied private product decision record");
  const unfilledDecisionRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", copiedDecisionRecord, "--require-filled-decision-record", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(unfilledDecisionRecordCheck.status === 2, "Phase 4 stop-gate checker rejects unfilled decision records when final evidence is required");
  const filledDecisionRecord = path.join(os.tmpdir(), `phase4-migration-decision-filled-${Date.now()}.md`);
  fs.writeFileSync(filledDecisionRecord, phase4DecisionRecordTemplate.replace(/\bTBD\b/g, "recorded"));
  const filledDecisionRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", filledDecisionRecord, "--require-filled-decision-record", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(filledDecisionRecordCheck.status === 0, "Phase 4 stop-gate checker accepts filled decision records with all evidence IDs");
  const missingEvidenceDecisionRecord = path.join(os.tmpdir(), `phase4-migration-decision-missing-evidence-${Date.now()}.md`);
  fs.writeFileSync(
    missingEvidenceDecisionRecord,
    phase4DecisionRecordTemplate
      .replace(/\bTBD\b/g, "recorded")
      .split("\n")
      .filter((line) => !line.includes("| hardware-owner |"))
      .join("\n")
  );
  const missingEvidenceDecisionRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", missingEvidenceDecisionRecord, "--require-filled-decision-record", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(missingEvidenceDecisionRecordCheck.status === 2, "Phase 4 stop-gate checker rejects filled decision records missing evidence rows");
  const blankEvidenceLocationRecord = path.join(os.tmpdir(), `phase4-migration-decision-blank-evidence-location-${Date.now()}.md`);
  fs.writeFileSync(
    blankEvidenceLocationRecord,
    phase4DecisionRecordTemplate
      .replace(/\bTBD\b/g, "recorded")
      .replace(/\| target-repository \| required \| Exact private product repository URL\/path and native\/ directory target are agreed\. \| recorded \| recorded \|/, "| target-repository | required | Exact private product repository URL/path and native/ directory target are agreed. |  | recorded |")
  );
  const blankEvidenceLocationRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", blankEvidenceLocationRecord, "--require-filled-decision-record", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(blankEvidenceLocationRecordCheck.status === 2, "Phase 4 stop-gate checker rejects decision records with blank evidence locations");
  const blankOwnerRecord = path.join(os.tmpdir(), `phase4-migration-decision-blank-owner-${Date.now()}.md`);
  fs.writeFileSync(
    blankOwnerRecord,
    phase4DecisionRecordTemplate
      .replace(/\bTBD\b/g, "recorded")
      .replace(/\| hardware-owner \| required \| Manual\/device smoke owner is assigned for camera, NFC, Bluetooth, printing, or Tap to Pay where enabled\. \| recorded \| recorded \|/, "| hardware-owner | required | Manual/device smoke owner is assigned for camera, NFC, Bluetooth, printing, or Tap to Pay where enabled. | recorded |  |")
  );
  const blankOwnerRecordCheck = spawnSync(
    process.execPath,
    ["tools/phase4_stop_gate_check.js", "--generated", generatedWorkspaceDir, "--decision-record", blankOwnerRecord, "--require-filled-decision-record", "--json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(blankOwnerRecordCheck.status === 2, "Phase 4 stop-gate checker rejects decision records with blank owners");
  const privateProductAgentsSection = fs.readFileSync(path.join(generatedWorkspaceDir, "PRIVATE_PRODUCT_AGENTS_NATIVE_SECTION.md"), "utf8");
  assert(
    privateProductAgentsSection.includes("This repository owns the app-specific native variant data") &&
      privateProductAgentsSection.includes("Do not edit files under `native/generated/` by hand") &&
      privateProductAgentsSection.includes("not in the open-source wrapper repository") &&
      privateProductAgentsSection.includes("MIGRATION_STOP_GATE.json") &&
      privateProductAgentsSection.includes("WRAPPER_ROOT="),
    "generated variant workspace writes private product AGENTS.md native-wrapper guidance"
  );
  const generatedWorkspaceBefore = fs.readFileSync(path.join(generatedWorkspaceDir, "VARIANT_WORKSPACE.json"), "utf8");
  const generatedWorkspaceRepeat = spawnSync(
    process.execPath,
    [
      "tools/generate_variant_workspace.js",
      "--variant",
      "docs/variant-manifest.example.json",
      "--output",
      generatedWorkspaceDir,
      "--json"
    ],
    { cwd: root, encoding: "utf8" }
  );
  const generatedWorkspaceAfter = fs.readFileSync(path.join(generatedWorkspaceDir, "VARIANT_WORKSPACE.json"), "utf8");
  assert(
    generatedWorkspaceRepeat.status === 0 && generatedWorkspaceBefore === generatedWorkspaceAfter,
    "generated variant workspace can be regenerated without changing existing matching files"
  );
  fs.appendFileSync(path.join(generatedWorkspaceDir, "README.md"), "\nmanual edit\n");
  const generatedWorkspaceConflict = spawnSync(
    process.execPath,
    [
      "tools/generate_variant_workspace.js",
      "--variant",
      "docs/variant-manifest.example.json",
      "--output",
      generatedWorkspaceDir,
      "--json"
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(generatedWorkspaceConflict.status === 3, "generated variant workspace refuses to overwrite changed generated files without force");

  const privateDemoAppScaffoldPlan = JSON.parse(
    execSync("node tools/variant_scaffold_plan.js --id private-demo-app --json", { cwd: root, encoding: "utf8" })
  );
  assert(privateDemoAppScaffoldPlan.id === "private-demo-app", "variant scaffold plan CLI returns requested variant");
  assert(privateDemoAppScaffoldPlan.readyForScaffold === false, "variant scaffold plan blocks PrivateDemoApp until decisions are decided");
  assert((privateDemoAppScaffoldPlan.blockingDecisionIds || []).includes("identity"), "variant scaffold plan lists identity blocker");
  assert(
    (privateDemoAppScaffoldPlan.targetArtifacts || []).includes("android/private-demo-app/build.gradle"),
    "variant scaffold plan lists concrete Android target artifacts"
  );
  const scaffoldIdentityStep = (privateDemoAppScaffoldPlan.steps || []).find((step) => step.id === "identity") || {};
  assert(
    Array.isArray(scaffoldIdentityStep.answerFields) &&
      scaffoldIdentityStep.answerFields.some((field) => field.id === "bundleIdentifier") &&
      scaffoldIdentityStep.answerFields.some((field) => field.id === "applicationId"),
    "variant scaffold plan lists cross-platform identity answer fields"
  );
  const privateDemoAppDecisionTemplate = JSON.parse(
    execSync("node tools/variant_decision_template.js --id private-demo-app", { cwd: root, encoding: "utf8" })
  );
  assert(privateDemoAppDecisionTemplate.schemaVersion === 1, "variant decision template has schema version");
  assert(privateDemoAppDecisionTemplate.variantId === "private-demo-app", "variant decision template returns requested variant");
  assert(Boolean(privateDemoAppDecisionTemplate.decisions.identity), "variant decision template includes identity decision");
  assert(
    privateDemoAppDecisionTemplate.decisions.identity.answers.bundleIdentifier === null &&
      privateDemoAppDecisionTemplate.decisions.identity.answers.applicationId === null,
    "variant decision template initializes cross-platform identity answer slots"
  );
  assert(
    Array.isArray(privateDemoAppDecisionTemplate.decisions["startup-provisioning"].fields.startupMode.allowedValues) &&
      privateDemoAppDecisionTemplate.decisions["startup-provisioning"].answers.startupMode === "fixed-url",
    "variant decision template carries allowed values and defaults to the first allowed value"
  );
  const blankDecisionCheck = spawnSync(
    "/bin/zsh",
    ["-lc", "node tools/variant_decision_template.js --id private-demo-app | node tools/variant_decision_check.js --stdin --json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(blankDecisionCheck.status === 2, "variant decision check rejects incomplete decision templates");
  const blankDecisionReport = JSON.parse(blankDecisionCheck.stdout);
  assert(blankDecisionReport.valid === false, "variant decision check marks incomplete template invalid");
  assert(
    (blankDecisionReport.missingRequiredAnswers || []).includes("identity.bundleIdentifier") &&
      (blankDecisionReport.missingRequiredAnswers || []).includes("identity.applicationId"),
    "variant decision check reports missing cross-platform identity answers"
  );
  const filledDecisionCheck = spawnSync(
    "/bin/zsh",
    [
      "-lc",
      [
        "node tools/variant_decision_template.js --id private-demo-app |",
        "node -e 'let input=\"\"; process.stdin.on(\"data\", chunk => input += chunk); process.stdin.on(\"end\", () => { const template = JSON.parse(input); for (const decision of Object.values(template.decisions)) { for (const key of Object.keys(decision.answers)) { if (decision.answers[key] === null) decision.answers[key] = key.endsWith(\"Modules\") || key.endsWith(\"Actions\") || key.endsWith(\"Tests\") || key === \"requiredCapabilities\" || key === \"excludedCapabilities\" ? [] : `filled-${key}`; } } process.stdout.write(JSON.stringify(template)); });' |",
        "node tools/variant_decision_check.js --stdin --json"
      ].join(" ")
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(filledDecisionCheck.status === 0, "variant decision check accepts filled decision templates");
  const filledDecisionReport = JSON.parse(filledDecisionCheck.stdout);
  assert(filledDecisionReport.valid === true, "variant decision check marks filled template valid");
  const invalidRegistryPlan = spawnSync(
    "/bin/zsh",
    ["-lc", "node tools/variant_decision_template.js --id private-demo-app | node tools/variant_registry_plan.js --stdin --json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(invalidRegistryPlan.status === 2, "variant registry plan rejects incomplete decision templates");
  const invalidRegistryPlanReport = JSON.parse(invalidRegistryPlan.stdout);
  assert(invalidRegistryPlanReport.valid === false, "variant registry plan returns invalid decision check report");
  const filledRegistryPlan = spawnSync(
    "/bin/zsh",
    [
      "-lc",
      [
        "node tools/variant_decision_template.js --id private-demo-app |",
        "node -e 'let input=\"\"; process.stdin.on(\"data\", chunk => input += chunk); process.stdin.on(\"end\", () => { const template = JSON.parse(input); for (const decision of Object.values(template.decisions)) { for (const key of Object.keys(decision.answers)) { if (decision.answers[key] === null) decision.answers[key] = key.endsWith(\"Modules\") || key.endsWith(\"Actions\") || key.endsWith(\"Tests\") || key === \"requiredCapabilities\" || key === \"excludedCapabilities\" ? [] : `filled-${key}`; } } template.decisions.identity.answers.gradleModule = \"private-demo-app\"; process.stdout.write(JSON.stringify(template)); });' |",
        "node tools/variant_registry_plan.js --stdin --json"
      ].join(" ")
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(filledRegistryPlan.status === 0, "variant registry plan accepts filled decision templates");
  const filledRegistryPlanReport = JSON.parse(filledRegistryPlan.stdout);
  assert(filledRegistryPlanReport.readyForRegistryPlanning === true, "variant registry plan marks filled template ready for registry planning");
  assert(
    filledRegistryPlanReport.registryUpdatePlan.identity.gradleModule === ":private-demo-app" &&
      filledRegistryPlanReport.registryUpdatePlan.identity.buildFile === "android/private-demo-app/build.gradle",
    "variant registry plan derives Android module registry fields"
  );
  assert(filledRegistryPlanReport.registryPatch.file === "docs/app-variants.json", "variant registry plan targets app variant registry");
  assert(
    (filledRegistryPlanReport.registryPatch.operations || []).some((operation) => operation.path.endsWith("/decisionChecklist") && operation.op === "replace"),
    "variant registry plan includes decision checklist patch"
  );
  assert(
    Array.isArray(filledRegistryPlanReport.platformRegistryEntries) &&
      filledRegistryPlanReport.platformRegistryEntries.some((entry) => entry.id === "private-demo-app-ios" && entry.platform === "ios") &&
      filledRegistryPlanReport.platformRegistryEntries.some((entry) => entry.id === "private-demo-app-android" && entry.platform === "android"),
    "variant registry plan derives platform-specific registry entries from cross-platform decisions"
  );
  assert(
    (filledRegistryPlanReport.registryPatch.operations || []).some((operation) => operation.op === "add" && operation.path === "/variants/-" && operation.value.id === "private-demo-app-ios") &&
      (filledRegistryPlanReport.registryPatch.operations || []).some((operation) => operation.op === "add" && operation.path === "/variants/-" && operation.value.id === "private-demo-app-android"),
    "variant registry plan includes platform registry add operations"
  );
  assert(
    (filledRegistryPlanReport.registryPatch.operations || []).some((operation) => operation.path.endsWith("/derivedVariantIds")),
    "variant registry plan records derived platform variant ids on the source variant"
  );
  const derivedIOSRegistryEntry = filledRegistryPlanReport.platformRegistryEntries.find((entry) => entry.id === "private-demo-app-ios") || {};
  const derivedAndroidRegistryEntry = filledRegistryPlanReport.platformRegistryEntries.find((entry) => entry.id === "private-demo-app-android") || {};
  assert(
    derivedIOSRegistryEntry.bridgeProfile &&
      derivedIOSRegistryEntry.bridgeProfile.contractPlatform === "ios" &&
      (derivedIOSRegistryEntry.bridgeProfile.unavailableActions || []).includes("printerPrint"),
    "variant registry plan derives iOS bridge profile from the bridge contract"
  );
  assert(
    derivedAndroidRegistryEntry.bridgeProfile &&
      derivedAndroidRegistryEntry.bridgeProfile.contractPlatform === "android" &&
      (derivedAndroidRegistryEntry.bridgeProfile.unavailableActions || []).includes("roomPlanScanStart") &&
      !(derivedAndroidRegistryEntry.bridgeProfile.unavailableActions || []).includes("printerPrint"),
    "variant registry plan derives Android bridge profile from the bridge contract"
  );
  assert(
    derivedAndroidRegistryEntry.gradleModule === ":private-demo-app" &&
      derivedAndroidRegistryEntry.buildFile === "android/private-demo-app/build.gradle",
    "variant registry plan derives Android module registry fields on the platform entry"
  );
  assert(
    (derivedAndroidRegistryEntry.decisionChecklist || [])
      .flatMap((decision) => decision.targetArtifacts || [])
      .includes("android/private-demo-app/build.gradle"),
    "variant registry plan keeps Android platform-entry target artifacts aligned with the Gradle module path"
  );
  assert(
    !(derivedAndroidRegistryEntry.decisionChecklist || [])
      .flatMap((decision) => decision.targetArtifacts || [])
      .some((artifact) => artifact.includes("ios")),
    "variant registry plan filters iOS artifacts out of Android platform-entry decisions"
  );
  assert(
    !(derivedIOSRegistryEntry.decisionChecklist || [])
      .flatMap((decision) => decision.targetArtifacts || [])
      .some((artifact) => artifact.includes("android/")),
    "variant registry plan filters Android artifacts out of iOS platform-entry decisions"
  );
  const invalidScaffoldPlan = spawnSync(
    "/bin/zsh",
    ["-lc", "node tools/variant_decision_template.js --id private-demo-app | node tools/variant_scaffold_plan.js --stdin --json"],
    { cwd: root, encoding: "utf8" }
  );
  assert(invalidScaffoldPlan.status === 2, "variant scaffold plan rejects incomplete decision templates");
  const invalidScaffoldPlanReport = JSON.parse(invalidScaffoldPlan.stdout);
  assert(invalidScaffoldPlanReport.valid === false, "variant scaffold plan returns invalid decision check report");
  const filledScaffoldPlan = spawnSync(
    "/bin/zsh",
    [
      "-lc",
      [
        "node tools/variant_decision_template.js --id private-demo-app |",
        "node -e 'let input=\"\"; process.stdin.on(\"data\", chunk => input += chunk); process.stdin.on(\"end\", () => { const template = JSON.parse(input); for (const decision of Object.values(template.decisions)) { for (const key of Object.keys(decision.answers)) { if (decision.answers[key] === null) decision.answers[key] = key.endsWith(\"Modules\") || key.endsWith(\"Actions\") || key.endsWith(\"Tests\") || key === \"requiredCapabilities\" || key === \"excludedCapabilities\" ? [] : `filled-${key}`; } } template.decisions.identity.answers.gradleModule = \"private-demo-app\"; process.stdout.write(JSON.stringify(template)); });' |",
        "node tools/variant_scaffold_plan.js --stdin --json"
      ].join(" ")
    ],
    { cwd: root, encoding: "utf8" }
  );
  assert(filledScaffoldPlan.status === 0, "variant scaffold plan accepts filled decision templates");
  const filledScaffoldPlanReport = JSON.parse(filledScaffoldPlan.stdout);
  assert(filledScaffoldPlanReport.valid === true, "variant scaffold plan marks filled template valid");
  assert(filledScaffoldPlanReport.readyForScaffold === true, "variant scaffold plan marks filled template ready for scaffold planning");
  const androidScaffold = (filledScaffoldPlanReport.platformScaffolds || []).find((scaffold) => scaffold.id === "private-demo-app-android") || {};
  const iosScaffold = (filledScaffoldPlanReport.platformScaffolds || []).find((scaffold) => scaffold.id === "private-demo-app-ios") || {};
  assert(
    androidScaffold.platform === "android" &&
      androidScaffold.sourceTemplate === "android/app" &&
      (androidScaffold.files || []).some((file) => file.path === "android/settings.gradle") &&
      (androidScaffold.files || []).some((file) => file.path === "android/private-demo-app/build.gradle") &&
      (androidScaffold.files || []).some((file) => file.path === "android/private-demo-app/src/main/AndroidManifest.xml") &&
      (androidScaffold.files || []).some((file) => file.path.endsWith("PrivateDemoAppAndroidVariantTest.java")),
    "variant scaffold plan derives Android module, manifest, settings, and variant test artifacts"
  );
  assert(
    iosScaffold.platform === "ios" &&
      (iosScaffold.files || []).some((file) => file.path === "ios/swiftHTMLWebviewApp.xcodeproj/project.pbxproj") &&
      (iosScaffold.files || []).some((file) => file.path === "ios/Variants/private-demo-app/") &&
      (iosScaffold.files || []).some((file) => file.path.endsWith("PrivateDemoAppIosVariantTests.swift")),
    "variant scaffold plan derives iOS target, variant config, and variant test artifacts"
  );

  const optionalModuleCatalog = variants.optionalModuleCatalog || {};
  assert(
    optionalModuleCatalog &&
      typeof optionalModuleCatalog === "object" &&
      !Array.isArray(optionalModuleCatalog),
    "variant registry has optional module catalog"
  );
  for (const [moduleId, module] of Object.entries(optionalModuleCatalog)) {
    assert(isNonEmptyString(moduleId), `${moduleId} optional module has id`);
    assert(Array.isArray(module.platforms) && module.platforms.length > 0, `${moduleId} optional module lists platforms`);
    if (Array.isArray(module.platforms)) {
      for (const platform of module.platforms) {
        assert(validPlatforms.has(platform), `${moduleId} optional module platform is valid: ${platform}`);
      }
    }
    assert(Array.isArray(module.actions) && module.actions.length > 0, `${moduleId} optional module lists bridge actions`);
    if (Array.isArray(module.actions)) {
      assert(new Set(module.actions).size === module.actions.length, `${moduleId} optional module actions are unique`);
      for (const actionName of module.actions) {
        const action = contractActionsByName.get(actionName);
        assert(Boolean(action), `${moduleId} optional module action exists in bridge contract: ${actionName}`);
        if (action && Array.isArray(module.platforms)) {
          for (const platform of module.platforms) {
            assert(action[platform] === "optional", `${moduleId} optional module action is optional on ${platform}: ${actionName}`);
          }
        }
      }
    }
  }

  const implemented = variants.variants.filter((variant) => variant.status === "implemented");
  assert(implemented.length >= 2, "variant registry lists current implemented apps");
  assert(!androidDocs.includes("com.ilass.swifthtmlwebviewapp/.MainActivity"), "Android docs do not use stale launch package");

  for (const variant of variants.variants) {
    assert(isNonEmptyString(variant.id), `variant ${variant.name} has id`);
    assert(isNonEmptyString(variant.name), `${variant.id} has name`);
    assert(["implemented", "planned"].includes(variant.status), `${variant.id} has valid status`);
    assert(["ios", "android", "cross-platform"].includes(variant.platform), `${variant.id} has valid platform`);

    if (variant.status !== "implemented") {
      assert(Array.isArray(variant.requiredDecisions) && variant.requiredDecisions.length > 0, `${variant.id} planned variant records required decisions`);
      if (Array.isArray(variant.requiredDecisions)) {
        assert(variant.requiredDecisions.every(isNonEmptyString), `${variant.id} planned variant decisions are non-empty`);
        assertSetEquals(
          variant.requiredDecisions,
          (variant.requiredDecisionIds || []).map((decisionId) => (plannedDecisionCatalog[decisionId] || {}).description),
          `${variant.id} planned variant required decisions match catalog descriptions`
        );
      }
      assert(Array.isArray(variant.requiredDecisionIds) && variant.requiredDecisionIds.length > 0, `${variant.id} planned variant records structured decision ids`);
      if (Array.isArray(variant.requiredDecisionIds)) {
        assert(new Set(variant.requiredDecisionIds).size === variant.requiredDecisionIds.length, `${variant.id} structured decision ids are unique`);
        for (const decisionId of variant.requiredDecisionIds) {
          assert(plannedDecisionIds.has(decisionId), `${variant.id} structured decision id exists in catalog: ${decisionId}`);
        }
      }
      assert(Array.isArray(variant.decisionChecklist) && variant.decisionChecklist.length > 0, `${variant.id} planned variant records decision checklist`);
      if (Array.isArray(variant.decisionChecklist)) {
        const checklistIds = variant.decisionChecklist.map((decision) => decision.id).filter(isNonEmptyString);
        assert(new Set(checklistIds).size === checklistIds.length, `${variant.id} decision checklist ids are unique`);
        assertSetEquals(checklistIds, variant.requiredDecisionIds || [], `${variant.id} decision checklist covers required decision ids`);
        for (const decision of variant.decisionChecklist) {
          assert(isNonEmptyString(decision.id), `${variant.id} decision checklist item has id`);
          assert(plannedDecisionIds.has(decision.id), `${variant.id} decision checklist id exists in catalog: ${decision.id}`);
          assert(validDecisionStatuses.has(decision.status), `${variant.id} decision ${decision.id} has valid status`);
          assert(isNonEmptyString(decision.question), `${variant.id} decision ${decision.id} records an intake question`);
          if (plannedDecisionCatalog[decision.id]) {
            assert(
              decision.question === plannedDecisionCatalog[decision.id].question,
              `${variant.id} decision ${decision.id} question matches catalog`
            );
          }
          assert(
            Array.isArray(decision.targetArtifacts) && decision.targetArtifacts.length > 0,
            `${variant.id} decision ${decision.id} records target artifacts`
          );
          if (Array.isArray(decision.targetArtifacts) && plannedDecisionCatalog[decision.id]) {
            assertSetEquals(
              decision.targetArtifacts,
              targetArtifactsForPlatform(plannedDecisionCatalog[decision.id].targetArtifacts || [], variant.platform, variant.id),
              `${variant.id} decision ${decision.id} target artifacts match platform-filtered catalog`
            );
            assert(
              decision.targetArtifacts.every((artifact) => !artifact.includes("<variant>")),
              `${variant.id} decision ${decision.id} resolves variant artifact placeholders`
            );
          }
          if (plannedDecisionCatalog[decision.id]) {
            const expectedAnswerFields = answerFieldsForPlatform(plannedDecisionCatalog[decision.id].answerFields || [], variant.platform);
            const actualAnswerFields = Array.isArray(decision.answerFields) && decision.answerFields.length > 0
              ? decision.answerFields
              : expectedAnswerFields;
            assert(
              actualAnswerFields.length > 0,
              `${variant.id} decision ${decision.id} has platform-relevant answer fields`
            );
            assertSetEquals(
              actualAnswerFields.map((field) => field.id),
              expectedAnswerFields.map((field) => field.id),
              `${variant.id} decision ${decision.id} answer fields match platform-filtered catalog`
            );
          }
          if (decision.status === "needed") {
            for (const field of plannedDecisionArtifactFields[decision.id] || []) {
              assert(
                variant[field] === undefined,
                `${variant.id} leaves ${field} absent while ${decision.id} decision is needed`
              );
            }
          }
        }
      }
      if (variant.id === "private-demo-app") {
        assert((variant.requiredDecisionIds || []).includes("identity"), `${variant.id} requires bundle/application identifiers`);
        assert((variant.requiredDecisionIds || []).includes("branding"), `${variant.id} requires display labels`);
        assert((variant.requiredDecisionIds || []).includes("startup-provisioning"), `${variant.id} requires startup URL or QR provisioning decision`);
        assert((variant.requiredDecisionIds || []).includes("native-capabilities"), `${variant.id} requires native capability decisions`);
        assert((variant.requiredDecisionIds || []).includes("bridge-profile"), `${variant.id} requires bridge profile decision`);
        assert((variant.requiredDecisionIds || []).includes("verification"), `${variant.id} requires verification decision`);
      }
      continue;
    }

    assert(Boolean(variant.verification), `${variant.id} records verification commands`);
    assert(["development", "staging", "production"].includes(variant.releaseChannel), `${variant.id} has valid release channel`);
    if (variant.releaseChannel === "production" && variant.runtimeDefaults) {
      if (variant.runtimeDefaults.serverURL) {
        assert(isHTTPSURL(variant.runtimeDefaults.serverURL), `${variant.id} production server URL is HTTPS`);
      }
      if (variant.runtimeDefaults.securityToken) {
        assert(variant.runtimeDefaults.securityToken !== "change-me-before-production", `${variant.id} production security token is not placeholder`);
      }
    }
    assert(isNonEmptyString(variant.verification && variant.verification.build), `${variant.id} records build command`);
    assert(isNonEmptyString(variant.verification && variant.verification.test), `${variant.id} records test command`);
    assert(Boolean(variant.bridgeProfile), `${variant.id} records bridge capability profile`);
    if (variant.bridgeProfile) {
      assert(variant.bridgeProfile.contractPlatform === variant.platform, `${variant.id} bridge profile uses variant platform`);
      const expectedUnavailableActions = contract.actions
        .filter((action) => action[variant.platform] === "unavailable")
        .map((action) => action.name);
      assertSetEquals(
        variant.bridgeProfile.unavailableActions,
        expectedUnavailableActions,
        `${variant.id} unavailable bridge actions match platform contract`
      );

      const enabledOptionalModules = normalizeStringArray(variant.bridgeProfile.enabledOptionalModules);
      assertSetEquals(
        normalizeOptionalModuleIds(variant.optionalModules),
        enabledOptionalModules,
        `${variant.id} optionalModules mirrors bridge profile`
      );
      for (const moduleId of enabledOptionalModules) {
        const module = optionalModuleCatalog[moduleId];
        assert(Boolean(module), `${variant.id} enabled optional module exists in catalog: ${moduleId}`);
        if (module && Array.isArray(module.platforms)) {
          assert(module.platforms.includes(variant.platform), `${variant.id} enabled optional module supports ${variant.platform}: ${moduleId}`);
        }
      }
    }
    assert(Array.isArray(variant.testCoverage) && variant.testCoverage.length > 0, `${variant.id} records variant boundary test coverage`);
    if (Array.isArray(variant.testCoverage)) {
      for (const coverage of variant.testCoverage) {
        assert(isNonEmptyString(coverage.file), `${variant.id} test coverage entry has file`);
        assert(isNonEmptyString(coverage.contains), `${variant.id} test coverage entry has marker`);
        if (isNonEmptyString(coverage.file)) {
          assert(fileExists(coverage.file), `${variant.id} test coverage file exists: ${coverage.file}`);
          if (fileExists(coverage.file) && isNonEmptyString(coverage.contains)) {
            assert(contains(coverage.file, coverage.contains), `${variant.id} test coverage marker exists: ${coverage.contains}`);
          }
        }
      }
    }

    if (variant.platform === "ios") {
      const project = read("ios/swiftHTMLWebviewApp.xcodeproj/project.pbxproj");
      const info = read("ios/Info.plist");
      const contentView = read("ios/swiftHTMLWebviewApp/ContentView.swift");
      const appVariant = read("ios/swiftHTMLWebviewApp/Models/AppVariant.swift");
      const appSettings = read("ios/swiftHTMLWebviewApp/Models/AppSettings.swift");
      const bridgeActionCatalog = read("ios/swiftHTMLWebviewApp/Models/BridgeActionCatalog.swift");
      const bridgeDispatcher = read("ios/swiftHTMLWebviewApp/Models/BridgeDispatcher.swift");
      const bridgeRouter = read("ios/swiftHTMLWebviewApp/Models/BridgeRouter.swift");
      const bridgeResponse = read("ios/swiftHTMLWebviewApp/Models/BridgeResponse.swift");
      const bridgeScriptBuilder = read("ios/swiftHTMLWebviewApp/Models/BridgeScriptBuilder.swift");
      const webViewErrorPayload = read("ios/swiftHTMLWebviewApp/Models/WebViewErrorPayload.swift");
      const nativeCommandPayload = fileExists("ios/swiftHTMLWebviewApp/Models/NativeCommandPayload.swift")
        ? read("ios/swiftHTMLWebviewApp/Models/NativeCommandPayload.swift")
        : "";
      const tapToPayBridge = read("ios/swiftHTMLWebviewApp/TapToPayBridge.swift");
      const tapToPayPayload = read("ios/swiftHTMLWebviewApp/Models/TapToPayPayload.swift");
      const captureRequest = read("ios/swiftHTMLWebviewApp/Models/CaptureRequest.swift");
      const captureResponseBuilder = read("ios/swiftHTMLWebviewApp/Models/CaptureResponseBuilder.swift");
      const barcodeResponseBuilder = read("ios/swiftHTMLWebviewApp/Models/BarcodeResponseBuilder.swift");
      const continuousScannerResponseBuilder = read("ios/swiftHTMLWebviewApp/Models/ContinuousScannerResponseBuilder.swift");
      const continuousScannerEventBuilder = read("ios/swiftHTMLWebviewApp/Models/ContinuousScannerEventBuilder.swift");
      const arPositionBridge = read("ios/swiftHTMLWebviewApp/Models/ARPositionBridge.swift");
      const arPositionPayload = read("ios/swiftHTMLWebviewApp/Models/ARPositionPayload.swift");
      const arGuidedMeasurementBridge = read("ios/swiftHTMLWebviewApp/Models/ARGuidedMeasurementBridge.swift");
      const arGuidedMeasurementPayload = read("ios/swiftHTMLWebviewApp/Models/ARGuidedMeasurementPayload.swift");
      const roomPlanBridge = read("ios/swiftHTMLWebviewApp/Models/RoomPlanBridge.swift");
      const roomPlanPayload = read("ios/swiftHTMLWebviewApp/Models/RoomPlanPayload.swift");
      const arOverlayBridge = read("ios/swiftHTMLWebviewApp/Models/AROverlayBridge.swift");
      const arOverlayPayload = read("ios/swiftHTMLWebviewApp/Models/AROverlayPayload.swift");
      const deviceBridge = read("ios/swiftHTMLWebviewApp/Models/DeviceBridge.swift");
      const deviceBridgePayload = read("ios/swiftHTMLWebviewApp/Models/DeviceBridgePayload.swift");
      const beaconBridge = read("ios/swiftHTMLWebviewApp/Models/BeaconBridge.swift");
      const beaconAdvertiserBridge = read("ios/swiftHTMLWebviewApp/Models/BeaconAdvertiserBridge.swift");
      const beaconPayload = read("ios/swiftHTMLWebviewApp/Models/BeaconPayload.swift");
      const idleTimerBridge = read("ios/swiftHTMLWebviewApp/Models/IdleTimerBridge.swift");
      const idleTimerPayload = read("ios/swiftHTMLWebviewApp/Models/IdleTimerPayload.swift");
      const notificationBridge = read("ios/swiftHTMLWebviewApp/Models/NotificationBridge.swift");
      const notificationPayload = read("ios/swiftHTMLWebviewApp/Models/NotificationPayload.swift");
      const screenStreamBridge = read("ios/swiftHTMLWebviewApp/Models/ScreenStreamBridge.swift");
      const screenStreamPayload = read("ios/swiftHTMLWebviewApp/Models/ScreenStreamPayload.swift");
      const configPairingBridge = read("ios/swiftHTMLWebviewApp/Models/ConfigPairingBridge.swift");
      const configPairingPayload = read("ios/swiftHTMLWebviewApp/Models/ConfigPairingPayload.swift");
      const nfcTagReaderBridge = read("ios/swiftHTMLWebviewApp/Models/NFCTagReaderBridge.swift");
      const nfcPayload = read("ios/swiftHTMLWebviewApp/Models/NFCPayload.swift");
      const sensorBridge = read("ios/swiftHTMLWebviewApp/Models/SensorBridge.swift");
      const sensorPayload = read("ios/swiftHTMLWebviewApp/Models/SensorPayload.swift");
      const locationBridge = read("ios/swiftHTMLWebviewApp/Models/LocationBridge.swift");
      const locationPayload = read("ios/swiftHTMLWebviewApp/Models/LocationPayload.swift");
      const orientationController = read("ios/swiftHTMLWebviewApp/Models/OrientationController.swift");
      const orientationPayload = read("ios/swiftHTMLWebviewApp/Models/OrientationPayload.swift");
      const printerBridge = read("ios/swiftHTMLWebviewApp/Models/PrinterBridge.swift");
      const printerPayload = read("ios/swiftHTMLWebviewApp/Models/PrinterPayload.swift");
      const settingsBridge = read("ios/swiftHTMLWebviewApp/Models/SettingsBridge.swift");
      const startupURLResolver = read("ios/swiftHTMLWebviewApp/Models/StartupURLResolver.swift");
      const startupReachabilityPolicy = read("ios/swiftHTMLWebviewApp/Models/StartupReachabilityPolicy.swift");
      const startupLoadState = read("ios/swiftHTMLWebviewApp/Models/StartupLoadState.swift");
      const startupLoadCoordinator = read("ios/swiftHTMLWebviewApp/Models/StartupLoadCoordinator.swift");
      const recoveryConfigParser = read("ios/swiftHTMLWebviewApp/Models/RecoveryConfigParser.swift");
      const recoveryPageBuilder = read("ios/swiftHTMLWebviewApp/Models/RecoveryPageBuilder.swift");
      const webViewStore = read("ios/swiftHTMLWebviewApp/Models/WebViewStore.swift");
      assert(project.includes(`PRODUCT_BUNDLE_IDENTIFIER = ${variant.bundleIdentifier};`), `${variant.id} bundle identifier matches`);
      assert(project.includes(`PRODUCT_NAME = ${variant.productName};`), `${variant.id} product name matches`);
      const pbxDisplayName = String(variant.displayName).match(/^[A-Za-z0-9_.-]+$/)
        ? variant.displayName
        : `"${String(variant.displayName).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
      assert(project.includes(`INFOPLIST_KEY_CFBundleDisplayName = ${pbxDisplayName};`), `${variant.id} display name matches`);
      assert(info.includes("<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>"), `${variant.id} Info.plist uses build bundle identifier`);
      assert(info.includes("<string>$(PRODUCT_NAME)</string>"), `${variant.id} Info.plist uses build product name`);
      assert(project.includes("swiftHTMLWebviewAppTests"), `${variant.id} has an iOS test target`);

      if (variant.runtimeDefaults) {
        assert(appVariant.includes(`id: "${variant.id}"`), `${variant.id} AppVariant id matches`);
        assert(appVariant.includes(`bundleIdentifier: "${variant.bundleIdentifier}"`), `${variant.id} AppVariant bundle identifier matches`);
        assert(appVariant.includes(`productName: "${variant.productName}"`), `${variant.id} AppVariant product name matches`);
        assert(appVariant.includes(`displayName: "${variant.displayName}"`), `${variant.id} AppVariant display name matches`);
        assert(appVariant.includes(`serverURL: "${variant.runtimeDefaults.serverURL}"`), `${variant.id} AppVariant server URL matches`);
        assert(appVariant.includes(`securityToken: "${variant.runtimeDefaults.securityToken}"`), `${variant.id} AppVariant security token default matches`);
        assert(appVariant.includes(`highAvailabilityTimeoutSeconds: ${variant.runtimeDefaults.highAvailabilityTimeoutSeconds}`), `${variant.id} AppVariant HA timeout matches`);
        assert(appVariant.includes(`beaconUUID: "${variant.runtimeDefaults.beaconUUID}"`), `${variant.id} AppVariant beacon UUID matches`);
        assert(appVariant.includes(`loadingImageName: "${variant.runtimeDefaults.loadingImageName}"`), `${variant.id} AppVariant loading image matches`);
        assert(appVariant.includes(`appIconName: "${variant.runtimeDefaults.appIconName}"`), `${variant.id} AppVariant app icon matches`);
        assert(appVariant.includes(`recoveryShortMark: "${variant.runtimeDefaults.recoveryShortMark}"`), `${variant.id} AppVariant recovery mark matches`);
        assert(appVariant.includes(`recoveryTitle: "${variant.runtimeDefaults.recoveryTitle}"`), `${variant.id} AppVariant recovery title matches`);
        assert(appVariant.includes(`recoveryBody: "${variant.runtimeDefaults.recoveryBody}"`), `${variant.id} AppVariant recovery body matches`);
        assert(appVariant.includes(`recoveryQRCodeDetectedMessage: "${variant.runtimeDefaults.recoveryQRCodeDetectedMessage}"`), `${variant.id} AppVariant recovery QR detected message matches`);
        assert(appVariant.includes(`recoveryInvalidQRMessage: "${variant.runtimeDefaults.recoveryInvalidQRMessage}"`), `${variant.id} AppVariant recovery invalid QR message matches`);
        assert(appSettings.includes("var loadingImageName: String"), `${variant.id} AppSettings exposes loading image`);
        assert(contentView.includes("Image(AppSettings.shared.loadingImageName)"), `${variant.id} loading image is variant-driven in ContentView`);
        assert(!contentView.includes(`Image("${variant.runtimeDefaults.loadingImageName}")`), `${variant.id} loading image literal stays out of ContentView`);
        assert(appSettings.includes("var recoveryShortMark: String"), `${variant.id} AppSettings exposes recovery mark`);
        assert(appSettings.includes("var recoveryTitle: String"), `${variant.id} AppSettings exposes recovery title`);
        assert(appSettings.includes("var recoveryBody: String"), `${variant.id} AppSettings exposes recovery body`);
        assert(appSettings.includes("var recoveryQRCodeDetectedMessage: String"), `${variant.id} AppSettings exposes recovery QR detected message`);
        assert(appSettings.includes("var recoveryInvalidQRMessage: String"), `${variant.id} AppSettings exposes recovery invalid QR message`);
        assert(webViewStore.includes("AppSettings.shared.recoveryShortMark"), `${variant.id} recovery mark is variant-driven in WebViewStore`);
        assert(webViewStore.includes("AppSettings.shared.recoveryTitle"), `${variant.id} recovery title is variant-driven in WebViewStore`);
        assert(webViewStore.includes("AppSettings.shared.recoveryBody"), `${variant.id} recovery body is variant-driven in WebViewStore`);
        assert(webViewStore.includes("AppSettings.shared.recoveryQRCodeDetectedMessage"), `${variant.id} recovery QR detected message is variant-driven in WebViewStore`);
        assert(contentView.includes("AppSettings.shared.recoveryInvalidQRMessage"), `${variant.id} recovery invalid QR message is variant-driven in ContentView`);
        assert(!webViewStore.includes("<div class=\"logo\">Wi</div>"), `${variant.id} recovery mark stays out of shared WebViewStore HTML`);
        assert(!webViewStore.includes(variant.runtimeDefaults.recoveryBody), `${variant.id} recovery body literal stays out of WebViewStore`);
        assert(!webViewStore.includes(variant.runtimeDefaults.recoveryQRCodeDetectedMessage), `${variant.id} recovery QR detected literal stays out of WebViewStore`);
        assert(!contentView.includes(variant.runtimeDefaults.recoveryInvalidQRMessage), `${variant.id} recovery invalid QR literal stays out of ContentView`);
        assert(recoveryPageBuilder.includes("enum RecoveryPageBuilder"), `${variant.id} has RecoveryPageBuilder`);
        assert(recoveryPageBuilder.includes("static func html"), `${variant.id} RecoveryPageBuilder builds recovery HTML`);
        assert(recoveryPageBuilder.includes("escapedJavaScriptString"), `${variant.id} RecoveryPageBuilder owns JS escaping`);
        assert(webViewStore.includes("RecoveryPageBuilder.html"), `${variant.id} WebViewStore delegates recovery page HTML`);
        assert(!webViewStore.includes("private func escapedHTML"), `${variant.id} recovery HTML escaping stays out of WebViewStore`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryPageBuilderTests.swift", "testHTMLUsesVariantBrandingAndEscapesText"), `${variant.id} tests iOS recovery page branding and escaping`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryPageBuilderTests.swift", "testHTMLKeepsRecoveryBridgeActions"), `${variant.id} tests iOS recovery page bridge actions`);
        assert(bridgeResponse.includes("enum BridgeResponse"), `${variant.id} has BridgeResponse helper`);
        assert(bridgeResponse.includes("static func base"), `${variant.id} BridgeResponse has base response`);
        assert(bridgeResponse.includes("static func error"), `${variant.id} BridgeResponse has error response`);
        assert(bridgeResponse.includes("static func unavailable"), `${variant.id} BridgeResponse has unavailable response`);
        assert(captureRequest.includes("struct DocumentCaptureRequest"), `${variant.id} has DocumentCaptureRequest`);
        assert(captureRequest.includes("struct PhotoCaptureRequest"), `${variant.id} has PhotoCaptureRequest`);
        assert(captureRequest.includes("struct BarcodeCaptureRequest"), `${variant.id} has BarcodeCaptureRequest`);
        assert(captureRequest.includes("static func imageFormat"), `${variant.id} capture request owns document image format selection`);
        assert(captureRequest.includes("func imageFormat(backgroundRemoved:"), `${variant.id} capture request owns photo image format selection`);
        assert(captureResponseBuilder.includes("enum DocumentCaptureResponseBuilder"), `${variant.id} has DocumentCaptureResponseBuilder`);
        assert(captureResponseBuilder.includes("enum PhotoCaptureResponseBuilder"), `${variant.id} has PhotoCaptureResponseBuilder`);
        assert(captureResponseBuilder.includes("pdfData"), `${variant.id} document capture builder uses pdfData`);
        assert(captureResponseBuilder.includes("imageData"), `${variant.id} photo capture builder uses imageData`);
        assert(contentView.includes("DocumentCaptureRequest(currentRequest)"), `${variant.id} ContentView delegates document capture request parsing`);
        assert(contentView.includes("PhotoCaptureRequest(currentRequest)"), `${variant.id} ContentView delegates photo capture request parsing`);
        assert(contentView.includes("BarcodeCaptureRequest(currentRequest)"), `${variant.id} ContentView delegates barcode capture request parsing`);
        assert(!contentView.includes(`currentRequest?["ocr"]`), `${variant.id} document OCR request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["outputType"]`), `${variant.id} capture output type parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["camera"]`), `${variant.id} photo camera request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["removeBackground"]`), `${variant.id} background removal request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["cropTransparent"]`), `${variant.id} background crop request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["background"]`), `${variant.id} background mode request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["backgroundColor"]`), `${variant.id} background color request parsing stays out of ContentView`);
        assert(!contentView.includes(`currentRequest?["types"]`), `${variant.id} barcode type request parsing stays out of ContentView`);
        assert(contentView.includes("DocumentCaptureResponseBuilder.pdfResponse"), `${variant.id} ContentView delegates document PDF payloads`);
        assert(contentView.includes("DocumentCaptureResponseBuilder.imageResponse"), `${variant.id} ContentView delegates document image payloads`);
        assert(contentView.includes("PhotoCaptureResponseBuilder.response"), `${variant.id} ContentView delegates photo payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/CaptureRequestTests.swift", "testDocumentRequestNormalizesJpegAliases"), `${variant.id} tests iOS document capture request parsing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/CaptureRequestTests.swift", "testPhotoRequestForcesPngForTransparentBackgroundRemoval"), `${variant.id} tests iOS photo capture format policy`);
        assert(contains("ios/swiftHTMLWebviewAppTests/CaptureRequestTests.swift", "testBarcodeRequestDefaultsActionAndKeepsRequestedTypes"), `${variant.id} tests iOS barcode capture request parsing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/CaptureResponseBuilderTests.swift", "testDocumentPdfResponseUsesPdfDataField"), `${variant.id} capture response builder tests PDF payload field`);
        assert(contains("ios/swiftHTMLWebviewAppTests/CaptureResponseBuilderTests.swift", "testPhotoResponseIncludesBackgroundRemovalMetadata"), `${variant.id} capture response builder tests photo metadata`);
        assert(barcodeResponseBuilder.includes("enum BarcodeResponseBuilder"), `${variant.id} has BarcodeResponseBuilder`);
        assert(barcodeResponseBuilder.includes("static func response"), `${variant.id} barcode response builder builds success payloads`);
        assert(barcodeResponseBuilder.includes("static func configChangedResponse"), `${variant.id} barcode response builder builds config-change payloads`);
        assert(barcodeResponseBuilder.includes("recoveryInvalidResponse"), `${variant.id} barcode response builder builds recovery errors`);
        assert(contentView.includes("BarcodeResponseBuilder.response"), `${variant.id} ContentView delegates barcode success payloads`);
        assert(contentView.includes("BarcodeResponseBuilder.configChangedResponse"), `${variant.id} ContentView delegates barcode config-change payloads`);
        assert(contentView.includes("AppSettings.shared.configurationSnapshot()"), `${variant.id} barcode config-change payload includes current settings snapshot`);
        assert(recoveryConfigParser.includes("BarcodeResponseBuilder.recoveryInvalidResponse"), `${variant.id} RecoveryBarcodeHandler delegates barcode recovery error payloads`);
        assert(!contentView.includes("BarcodeResponseBuilder.recoveryInvalidResponse"), `${variant.id} barcode recovery error payloads stay out of ContentView`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BarcodeResponseBuilderTests.swift", "testBarcodeResponseUsesLegacyScannerFields"), `${variant.id} barcode response builder tests legacy payload field`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BarcodeResponseBuilderTests.swift", "testConfigChangedResponseAcknowledgesScannerRequestBeforeReload"), `${variant.id} barcode response builder tests config-change acknowledgement`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BarcodeResponseBuilderTests.swift", "testRecoveryInvalidResponseUsesStructuredErrorShape"), `${variant.id} barcode response builder tests recovery error shape`);
        assert(continuousScannerResponseBuilder.includes("enum ContinuousScannerResponseBuilder"), `${variant.id} has ContinuousScannerResponseBuilder`);
        assert(continuousScannerResponseBuilder.includes("static func config"), `${variant.id} continuous scanner builder normalizes config`);
        assert(continuousScannerResponseBuilder.includes("static func startResponse"), `${variant.id} continuous scanner builder builds start responses`);
        assert(continuousScannerResponseBuilder.includes("static func stopResponse"), `${variant.id} continuous scanner builder builds stop responses`);
        assert(continuousScannerResponseBuilder.includes("static func previewRect"), `${variant.id} continuous scanner builder normalizes preview rectangles`);
        assert(contentView.includes("ContinuousScannerResponseBuilder.config"), `${variant.id} ContentView delegates continuous scanner config normalization`);
        assert(contentView.includes("ContinuousScannerResponseBuilder.startResponse"), `${variant.id} ContentView delegates continuous scanner start payloads`);
        assert(contentView.includes("ContinuousScannerResponseBuilder.stopResponse"), `${variant.id} ContentView delegates continuous scanner stop payloads`);
        assert(contentView.includes("ContinuousScannerResponseBuilder.previewUpdateResponse"), `${variant.id} ContentView delegates continuous scanner preview payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ContinuousScannerResponseBuilderTests.swift", "testLoginScanDefaultsToLoginModeAndFrontCamera"), `${variant.id} tests iOS continuous scanner login defaults`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ContinuousScannerResponseBuilderTests.swift", "testScannerFrameKeepsMinimumSizeInsideViewport"), `${variant.id} tests iOS continuous scanner frame bounds`);
        assert(continuousScannerEventBuilder.includes("enum ContinuousScannerEventBuilder"), `${variant.id} has ContinuousScannerEventBuilder`);
        assert(continuousScannerEventBuilder.includes('"barcodeData"'), `${variant.id} ContinuousScannerEventBuilder builds data scanner events`);
        assert(continuousScannerEventBuilder.includes('"barcodeLogin"'), `${variant.id} ContinuousScannerEventBuilder builds login scanner events`);
        assert(contains("ios/swiftHTMLWebviewApp/ScannerViews/ContinuousBarcodeScannerView.swift", "ContinuousScannerEventBuilder.event"), `${variant.id} scanner view delegates continuous scanner event payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ContinuousScannerEventBuilderTests.swift", "testDataEventUsesBarcodeDataAndSourceAction"), `${variant.id} tests iOS continuous scanner data events`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ContinuousScannerEventBuilderTests.swift", "testLoginEventUsesBarcodeLogin"), `${variant.id} tests iOS continuous scanner login events`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ContinuousScannerEventBuilderTests.swift", "testContinuousScanStartUsesExplicitModeForEventAction"), `${variant.id} tests iOS continuousScanStart mode-selected event action`);
        assert(arPositionPayload.includes("enum ARPositionPayload"), `${variant.id} has ARPositionPayload`);
        assert(arPositionPayload.includes("import Foundation"), `${variant.id} ARPositionPayload imports Foundation`);
        assert(!arPositionPayload.includes("import ARKit"), `${variant.id} ARPositionPayload stays independent from ARKit`);
        assert(!arPositionPayload.includes("import AVFoundation"), `${variant.id} ARPositionPayload stays independent from camera APIs`);
        assert(arPositionPayload.includes("static func intervalMs"), `${variant.id} ARPositionPayload owns interval normalization`);
        assert(arPositionPayload.includes("static func startResponse"), `${variant.id} ARPositionPayload owns start responses`);
        assert(arPositionPayload.includes("static func positionEvent"), `${variant.id} ARPositionPayload owns arPosition events`);
        assert(arPositionPayload.includes("static func interruptionEvent"), `${variant.id} ARPositionPayload owns interruption events`);
        assert(arPositionPayload.includes("BridgeResponse.base"), `${variant.id} ARPositionPayload uses shared bridge base response`);
        assert(arPositionBridge.includes("ARPositionPayload.intervalMs"), `${variant.id} ARPositionBridge delegates interval normalization`);
        assert(arPositionBridge.includes("ARPositionPayload.startResponse"), `${variant.id} ARPositionBridge delegates start responses`);
        assert(arPositionBridge.includes("ARPositionPayload.positionEvent"), `${variant.id} ARPositionBridge delegates position events`);
        assert(arPositionBridge.includes("ARPositionPayload.interruptionEvent"), `${variant.id} ARPositionBridge delegates interruption events`);
        assert(arPositionBridge.includes("ARPositionPayload.errorResponse"), `${variant.id} ARPositionBridge delegates error responses`);
        assert(!arPositionBridge.includes("private func baseResponse"), `${variant.id} AR position base response stays out of ARPositionBridge`);
        assert(!arPositionBridge.includes("private func errorResponse"), `${variant.id} AR position error response stays out of ARPositionBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ARPositionPayloadTests.swift", "testPositionEventUsesCatalogedPayloadShape"), `${variant.id} tests iOS AR position event shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ARPositionPayloadTests.swift", "testIntervalDefaultsRoundsAndClamps"), `${variant.id} tests iOS AR position interval normalization`);
        assert(arGuidedMeasurementPayload.includes("enum ARGuidedMeasurementPayload"), `${variant.id} has ARGuidedMeasurementPayload`);
        assert(arGuidedMeasurementPayload.includes("import Foundation"), `${variant.id} ARGuidedMeasurementPayload imports Foundation`);
        assert(!arGuidedMeasurementPayload.includes("import ARKit"), `${variant.id} ARGuidedMeasurementPayload stays independent from ARKit`);
        assert(!arGuidedMeasurementPayload.includes("import AVFoundation"), `${variant.id} ARGuidedMeasurementPayload stays independent from camera APIs`);
        assert(!arGuidedMeasurementPayload.includes("import SceneKit"), `${variant.id} ARGuidedMeasurementPayload stays independent from SceneKit`);
        assert(!arGuidedMeasurementPayload.includes("import SwiftUI"), `${variant.id} ARGuidedMeasurementPayload stays independent from SwiftUI`);
        assert(!arGuidedMeasurementPayload.includes("import UIKit"), `${variant.id} ARGuidedMeasurementPayload stays independent from UIKit`);
        assert(arGuidedMeasurementPayload.includes("struct FrameSnapshot"), `${variant.id} ARGuidedMeasurementPayload has ARKit-free frame snapshot`);
        assert(arGuidedMeasurementPayload.includes("static func intervalMs"), `${variant.id} ARGuidedMeasurementPayload owns interval normalization`);
        assert(arGuidedMeasurementPayload.includes("static func worldMapAvailable"), `${variant.id} ARGuidedMeasurementPayload owns world-map availability`);
        assert(arGuidedMeasurementPayload.includes("static func startAnchor"), `${variant.id} ARGuidedMeasurementPayload owns start-anchor normalization`);
        assert(arGuidedMeasurementPayload.includes("static func mergedAnchors"), `${variant.id} ARGuidedMeasurementPayload owns anchor merging`);
        assert(arGuidedMeasurementPayload.includes("static func readyResponse"), `${variant.id} ARGuidedMeasurementPayload owns guided ready responses`);
        assert(arGuidedMeasurementPayload.includes("static func pendingPermissionResponse"), `${variant.id} ARGuidedMeasurementPayload owns guided pending responses`);
        assert(arGuidedMeasurementPayload.includes("static func acknowledgementResponse"), `${variant.id} ARGuidedMeasurementPayload owns guided acknowledgements`);
        assert(arGuidedMeasurementPayload.includes("static func errorResponse"), `${variant.id} ARGuidedMeasurementPayload owns guided errors`);
        assert(arGuidedMeasurementPayload.includes("static func relocalizationEvent"), `${variant.id} ARGuidedMeasurementPayload owns guided relocalization events`);
        assert(arGuidedMeasurementPayload.includes("static func positionEvent"), `${variant.id} ARGuidedMeasurementPayload owns guided position events`);
        assert(arGuidedMeasurementPayload.includes("static func startAnchorConfirmedEvent"), `${variant.id} ARGuidedMeasurementPayload owns guided start confirmation events`);
        assert(arGuidedMeasurementPayload.includes("static func anchorCapturedEvent"), `${variant.id} ARGuidedMeasurementPayload owns guided anchor capture events`);
        assert(arGuidedMeasurementPayload.includes("BridgeResponse.base"), `${variant.id} ARGuidedMeasurementPayload uses shared bridge base response`);
        assert(arGuidedMeasurementPayload.includes("BridgeResponse.error"), `${variant.id} ARGuidedMeasurementPayload uses shared bridge error response`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.intervalMs"), `${variant.id} ARGuidedMeasurementBridge delegates interval normalization`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.pendingPermissionResponse"), `${variant.id} ARGuidedMeasurementBridge delegates pending permission responses`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.readyResponse"), `${variant.id} ARGuidedMeasurementBridge delegates ready responses`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.acknowledgementResponse"), `${variant.id} ARGuidedMeasurementBridge delegates acknowledgements`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.errorResponse"), `${variant.id} ARGuidedMeasurementBridge delegates error responses`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.relocalizationEvent"), `${variant.id} ARGuidedMeasurementBridge delegates relocalization events`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.positionEvent"), `${variant.id} ARGuidedMeasurementBridge delegates position events`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.startAnchorConfirmedEvent"), `${variant.id} ARGuidedMeasurementBridge delegates start confirmation events`);
        assert(arGuidedMeasurementBridge.includes("ARGuidedMeasurementPayload.anchorCapturedEvent"), `${variant.id} ARGuidedMeasurementBridge delegates anchor capture events`);
        assert(!arGuidedMeasurementBridge.includes("private func baseResponse"), `${variant.id} AR guided base response stays out of ARGuidedMeasurementBridge`);
        assert(!arGuidedMeasurementBridge.includes("private func errorResponse"), `${variant.id} AR guided error response stays out of ARGuidedMeasurementBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ARGuidedMeasurementPayloadTests.swift", "testIntervalWorldMapAndAnchorRequestsNormalizeWithoutARKit"), `${variant.id} tests iOS guided AR request normalization`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ARGuidedMeasurementPayloadTests.swift", "testPositionAndRelocalizationEventsUseCatalogedPayloadShape"), `${variant.id} tests iOS guided AR position and relocalization events`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ARGuidedMeasurementPayloadTests.swift", "testAnchorEventsWrapPositionPayloads"), `${variant.id} tests iOS guided AR anchor events`);
        assert(roomPlanPayload.includes("enum RoomPlanPayload"), `${variant.id} has RoomPlanPayload`);
        assert(roomPlanPayload.includes("import Foundation"), `${variant.id} RoomPlanPayload imports Foundation`);
        assert(!roomPlanPayload.includes("import RoomPlan"), `${variant.id} RoomPlanPayload stays independent from RoomPlan`);
        assert(!roomPlanPayload.includes("import ARKit"), `${variant.id} RoomPlanPayload stays independent from ARKit`);
        assert(roomPlanPayload.includes("static func startResponse"), `${variant.id} RoomPlanPayload owns start responses`);
        assert(roomPlanPayload.includes("static func stopProcessingResponse"), `${variant.id} RoomPlanPayload owns stop-processing responses`);
        assert(roomPlanPayload.includes("static func stateEvent"), `${variant.id} RoomPlanPayload owns state events`);
        assert(roomPlanPayload.includes("static func resultEvent"), `${variant.id} RoomPlanPayload owns scan result events`);
        assert(roomPlanPayload.includes("static func exportResponse"), `${variant.id} RoomPlanPayload owns export responses`);
        assert(roomPlanPayload.includes("BridgeResponse.base"), `${variant.id} RoomPlanPayload uses shared bridge base response`);
        assert(roomPlanBridge.includes("RoomPlanPayload.startResponse"), `${variant.id} RoomPlanBridge delegates start responses`);
        assert(roomPlanBridge.includes("RoomPlanPayload.stopProcessingResponse"), `${variant.id} RoomPlanBridge delegates stop-processing responses`);
        assert(roomPlanBridge.includes("RoomPlanPayload.exportResponse"), `${variant.id} RoomPlanBridge delegates export responses`);
        assert(roomPlanBridge.includes("RoomPlanPayload.stateEvent"), `${variant.id} RoomPlanBridge delegates state events`);
        assert(roomPlanBridge.includes("RoomPlanPayload.resultEvent"), `${variant.id} RoomPlanBridge delegates result events`);
        assert(roomPlanBridge.includes("RoomPlanPayload.errorResponse"), `${variant.id} RoomPlanBridge delegates error responses`);
        assert(!roomPlanBridge.includes("private func baseResponse"), `${variant.id} RoomPlan base response stays out of RoomPlanBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RoomPlanPayloadTests.swift", "testResultEventUsesCatalogedPayloadShapeAndWorldMapFallback"), `${variant.id} tests iOS RoomPlan result payload shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RoomPlanPayloadTests.swift", "testStartStopAndStateResponsesUseCommonShape"), `${variant.id} tests iOS RoomPlan start/stop/state payload shape`);
        assert(arOverlayPayload.includes("enum AROverlayPayload"), `${variant.id} has AROverlayPayload`);
        assert(arOverlayPayload.includes("struct AROverlayScene"), `${variant.id} AROverlayPayload owns overlay scene normalization`);
        assert(arOverlayPayload.includes("import UIKit"), `${variant.id} AROverlayPayload imports UIKit for display colors`);
        assert(arOverlayPayload.includes("import simd"), `${variant.id} AROverlayPayload imports simd for scene positions`);
        assert(!arOverlayPayload.includes("import ARKit"), `${variant.id} AROverlayPayload stays independent from ARKit`);
        assert(!arOverlayPayload.includes("import AVFoundation"), `${variant.id} AROverlayPayload stays independent from camera APIs`);
        assert(!arOverlayPayload.includes("import SceneKit"), `${variant.id} AROverlayPayload stays independent from SceneKit`);
        assert(arOverlayPayload.includes("static func requestAction"), `${variant.id} AROverlayPayload owns action alias preservation`);
        assert(arOverlayPayload.includes("static func readyResponse"), `${variant.id} AROverlayPayload owns overlay ready responses`);
        assert(arOverlayPayload.includes("static func pendingPermissionResponse"), `${variant.id} AROverlayPayload owns pending permission responses`);
        assert(arOverlayPayload.includes("static func relocalizationEvent"), `${variant.id} AROverlayPayload owns relocalization events`);
        assert(arOverlayPayload.includes("static func itemSelectedEvent"), `${variant.id} AROverlayPayload owns item selection events`);
        assert(arOverlayPayload.includes("BridgeResponse.base"), `${variant.id} AROverlayPayload uses shared bridge base response`);
        assert(arOverlayBridge.includes("AROverlayPayload.requestAction"), `${variant.id} AROverlayBridge delegates action alias preservation`);
        assert(arOverlayBridge.includes("AROverlayPayload.pendingPermissionResponse"), `${variant.id} AROverlayBridge delegates pending permission responses`);
        assert(arOverlayBridge.includes("AROverlayPayload.readyResponse"), `${variant.id} AROverlayBridge delegates ready responses`);
        assert(arOverlayBridge.includes("AROverlayPayload.closeResponse"), `${variant.id} AROverlayBridge delegates close responses`);
        assert(arOverlayBridge.includes("AROverlayPayload.relocalizationEvent"), `${variant.id} AROverlayBridge delegates relocalization events`);
        assert(arOverlayBridge.includes("AROverlayPayload.itemSelectedEvent"), `${variant.id} AROverlayBridge delegates item selection events`);
        assert(arOverlayBridge.includes("AROverlayPayload.errorResponse"), `${variant.id} AROverlayBridge delegates error responses`);
        assert(!arOverlayBridge.includes("private func baseResponse"), `${variant.id} AR overlay base response stays out of AROverlayBridge`);
        assert(!arOverlayBridge.includes("fileprivate struct AROverlayScene"), `${variant.id} AR overlay scene model stays out of AROverlayBridge`);
        assert(!arOverlayBridge.includes("fileprivate struct AROverlayItem"), `${variant.id} AR overlay item model stays out of AROverlayBridge`);
        assert(!arOverlayBridge.includes("fileprivate struct AROverlayLine"), `${variant.id} AR overlay line model stays out of AROverlayBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/AROverlayPayloadTests.swift", "testFloorPlanAndDemoOverlayCreateSceneItemsAndLines"), `${variant.id} tests iOS AR overlay scene normalization`);
        assert(contains("ios/swiftHTMLWebviewAppTests/AROverlayPayloadTests.swift", "testOpenCloseResponsesPreserveDefaultAndAliasActions"), `${variant.id} tests iOS AR overlay action alias payloads`);
        assert(deviceBridgePayload.includes("enum DeviceBridgePayload"), `${variant.id} has DeviceBridgePayload`);
        assert(deviceBridgePayload.includes("static func capabilities"), `${variant.id} DeviceBridgePayload owns capability payloads`);
        assert(deviceBridgePayload.includes("static func wifiConfigureRequest"), `${variant.id} DeviceBridgePayload owns Wi-Fi request normalization`);
        assert(deviceBridgePayload.includes("static func wifiInfo"), `${variant.id} DeviceBridgePayload owns Wi-Fi info payloads`);
        assert(deviceBridgePayload.includes("static func soundRequest"), `${variant.id} DeviceBridgePayload owns sound request normalization`);
        assert(deviceBridge.includes("DeviceBridgePayload.capabilities"), `${variant.id} DeviceBridge delegates capability payloads`);
        assert(deviceBridge.includes("DeviceBridgePayload.wifiConfigureRequest"), `${variant.id} DeviceBridge delegates Wi-Fi request normalization`);
        assert(deviceBridge.includes("DeviceBridgePayload.wifiStatusResponse"), `${variant.id} DeviceBridge delegates Wi-Fi status payloads`);
        assert(deviceBridge.includes("DeviceBridgePayload.wifiConfigureResponse"), `${variant.id} DeviceBridge delegates Wi-Fi configure payloads`);
        assert(deviceBridge.includes("DeviceBridgePayload.soundRequest"), `${variant.id} DeviceBridge delegates sound request normalization`);
        assert(deviceBridge.includes("DeviceBridgePayload.soundResponse"), `${variant.id} DeviceBridge delegates sound responses`);
        assert(!deviceBridge.includes("\"deviceInfoGet\": true"), `${variant.id} device capability literals stay out of DeviceBridge`);
        assert(!deviceBridge.includes("private static func hotspotSecurityTypeName"), `${variant.id} Wi-Fi security naming stays out of DeviceBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/DeviceBridgePayloadTests.swift", "testCapabilitiesReflectInjectedRuntimeSupport"), `${variant.id} tests iOS device capability payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/DeviceBridgePayloadTests.swift", "testWifiResponsesAndErrorsUseContractShape"), `${variant.id} tests iOS Wi-Fi payload and error shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/DeviceBridgePayloadTests.swift", "testSoundRequestClampsAndResponseEchoesNormalizedValues"), `${variant.id} tests iOS sound request normalization`);
        assert(beaconPayload.includes("enum BeaconPayload"), `${variant.id} has BeaconPayload`);
        assert(beaconPayload.includes("import Foundation"), `${variant.id} BeaconPayload imports Foundation`);
        assert(!beaconPayload.includes("import CoreLocation"), `${variant.id} BeaconPayload stays independent from CoreLocation`);
        assert(!beaconPayload.includes("import CoreBluetooth"), `${variant.id} BeaconPayload stays independent from CoreBluetooth`);
        assert(beaconPayload.includes("struct AdvertiseConfig"), `${variant.id} BeaconPayload owns advertise config model`);
        assert(beaconPayload.includes("static func rangingStartResponse"), `${variant.id} BeaconPayload owns ranging start responses`);
        assert(beaconPayload.includes("static func rangingEvent"), `${variant.id} BeaconPayload owns ranging events`);
        assert(beaconPayload.includes("static func advertiseConfig"), `${variant.id} BeaconPayload owns advertiser request normalization`);
        assert(beaconPayload.includes("static func advertiseStateEvent"), `${variant.id} BeaconPayload owns advertiser state events`);
        assert(beaconPayload.includes("BridgeResponse.base"), `${variant.id} BeaconPayload uses shared bridge base response`);
        assert(beaconBridge.includes("BeaconPayload.rangingUUID"), `${variant.id} BeaconBridge delegates ranging UUID normalization`);
        assert(beaconBridge.includes("BeaconPayload.rangingStartResponse"), `${variant.id} BeaconBridge delegates ranging start responses`);
        assert(beaconBridge.includes("BeaconPayload.rangingEvent"), `${variant.id} BeaconBridge delegates ranging events`);
        assert(beaconBridge.includes("BeaconPayload.errorEvent"), `${variant.id} BeaconBridge delegates ranging error events`);
        assert(beaconAdvertiserBridge.includes("BeaconPayload.advertiseConfig"), `${variant.id} BeaconAdvertiserBridge delegates advertiser config normalization`);
        assert(beaconAdvertiserBridge.includes("BeaconPayload.advertiseStartResponse"), `${variant.id} BeaconAdvertiserBridge delegates advertiser start responses`);
        assert(beaconAdvertiserBridge.includes("BeaconPayload.advertiseStateEvent"), `${variant.id} BeaconAdvertiserBridge delegates advertiser state events`);
        assert(!beaconBridge.includes("private func baseResponse"), `${variant.id} beacon ranging base response stays out of BeaconBridge`);
        assert(!beaconAdvertiserBridge.includes("private func baseResponse"), `${variant.id} beacon advertiser base response stays out of BeaconAdvertiserBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BeaconPayloadTests.swift", "testBeaconEventUsesCatalogedPayloadShape"), `${variant.id} tests iOS beacon event shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BeaconPayloadTests.swift", "testAdvertiseConfigAcceptsAliasesDefaultsAndRejectsInvalidValues"), `${variant.id} tests iOS beacon advertiser config normalization`);
        assert(idleTimerPayload.includes("enum IdleTimerPayload"), `${variant.id} has IdleTimerPayload`);
        assert(idleTimerPayload.includes("static func startRequest"), `${variant.id} IdleTimerPayload owns idle timer request normalization`);
        assert(idleTimerPayload.includes("static func startResponse"), `${variant.id} IdleTimerPayload owns idle timer start responses`);
        assert(idleTimerPayload.includes("static func event"), `${variant.id} IdleTimerPayload owns idle timer event payloads`);
        assert(idleTimerBridge.includes("IdleTimerPayload.startRequest"), `${variant.id} IdleTimerBridge delegates idle timer request normalization`);
        assert(idleTimerBridge.includes("IdleTimerPayload.startResponse"), `${variant.id} IdleTimerBridge delegates idle timer start responses`);
        assert(idleTimerBridge.includes("IdleTimerPayload.stopResponse"), `${variant.id} IdleTimerBridge delegates idle timer stop responses`);
        assert(idleTimerBridge.includes("IdleTimerPayload.resetResponse"), `${variant.id} IdleTimerBridge delegates idle timer reset responses`);
        assert(idleTimerBridge.includes("IdleTimerPayload.event"), `${variant.id} IdleTimerBridge delegates idle timer event payloads`);
        assert(!idleTimerBridge.includes("private func baseResponse"), `${variant.id} idle timer base response stays out of IdleTimerBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/IdleTimerPayloadTests.swift", "testStartRequestClampsTimeoutAndInterval"), `${variant.id} tests iOS idle timer request normalization`);
        assert(contains("ios/swiftHTMLWebviewAppTests/IdleTimerPayloadTests.swift", "testTickAndTimeoutEventsUseCatalogedPayloadShape"), `${variant.id} tests iOS idle timer event payloads`);
        assert(notificationPayload.includes("enum NotificationPayload"), `${variant.id} has NotificationPayload`);
        assert(notificationPayload.includes("static func permissionResponse"), `${variant.id} NotificationPayload owns permission response envelopes`);
        assert(notificationPayload.includes("static func permissionError"), `${variant.id} NotificationPayload owns permission errors`);
        assert(notificationPayload.includes("static func notificationRequest"), `${variant.id} NotificationPayload owns notification request normalization`);
        assert(notificationPayload.includes("static func ids"), `${variant.id} NotificationPayload owns notification cancel ID normalization`);
        assert(notificationPayload.includes("static func eventPayload"), `${variant.id} NotificationPayload owns notification event envelopes`);
        assert(notificationBridge.includes("NotificationPayload.permissionResponse"), `${variant.id} NotificationBridge delegates permission response payloads`);
        assert(notificationBridge.includes("NotificationPayload.notificationRequest"), `${variant.id} NotificationBridge delegates notification request payloads`);
        assert(notificationBridge.includes("NotificationPayload.cancelResponse"), `${variant.id} NotificationBridge delegates cancel response payloads`);
        assert(notificationBridge.includes("NotificationPayload.eventPayload"), `${variant.id} NotificationBridge delegates notification event payloads`);
        assert(!notificationBridge.includes("private func baseResponse"), `${variant.id} notification base response stays out of NotificationBridge`);
        assert(!notificationBridge.includes("private func notificationIDs"), `${variant.id} notification ID parsing stays out of NotificationBridge`);
        assert(!notificationBridge.includes("private func jsonUserInfo"), `${variant.id} notification data filtering stays out of NotificationBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NotificationPayloadTests.swift", "testNotificationPayloadNormalizesFallbacksAndData"), `${variant.id} tests iOS notification payload defaults`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NotificationPayloadTests.swift", "testEventsAndScheduleResponsesWrapNotificationPayloads"), `${variant.id} tests iOS notification event envelopes`);
        assert(screenStreamPayload.includes("enum ScreenStreamPayload"), `${variant.id} has ScreenStreamPayload`);
        assert(screenStreamPayload.includes("static func streamRequest"), `${variant.id} ScreenStreamPayload owns stream request normalization`);
        assert(screenStreamPayload.includes("static func startAck"), `${variant.id} ScreenStreamPayload owns stream start acknowledgements`);
        assert(screenStreamPayload.includes("static func stopAck"), `${variant.id} ScreenStreamPayload owns stream stop acknowledgements`);
        assert(screenStreamPayload.includes("static func meta"), `${variant.id} ScreenStreamPayload owns stream metadata payloads`);
        assert(screenStreamPayload.includes("static func stats"), `${variant.id} ScreenStreamPayload owns stream stats events`);
        assert(screenStreamBridge.includes("ScreenStreamPayload.streamRequest"), `${variant.id} ScreenStreamBridge delegates stream request normalization`);
        assert(screenStreamBridge.includes("ScreenStreamPayload.startAck"), `${variant.id} ScreenStreamBridge delegates stream start acknowledgements`);
        assert(screenStreamBridge.includes("ScreenStreamPayload.stopAck"), `${variant.id} ScreenStreamBridge delegates stream stop acknowledgements`);
        assert(screenStreamBridge.includes("ScreenStreamPayload.meta"), `${variant.id} ScreenStreamBridge delegates stream metadata payloads`);
        assert(screenStreamBridge.includes("ScreenStreamPayload.stats"), `${variant.id} ScreenStreamBridge delegates stream stats events`);
        assert(!screenStreamBridge.includes("private func baseResponse"), `${variant.id} screen stream base response stays out of ScreenStreamBridge`);
        assert(!screenStreamBridge.includes("private func baseEvent"), `${variant.id} screen stream base event stays out of ScreenStreamBridge`);
        assert(!screenStreamBridge.includes("private func errorResponse"), `${variant.id} screen stream error response stays out of ScreenStreamBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ScreenStreamPayloadTests.swift", "testStreamRequestNormalizesAliasesAndClampsValues"), `${variant.id} tests iOS screen stream request normalization`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ScreenStreamPayloadTests.swift", "testMetaEventsAndStatsUseCatalogedEventShapes"), `${variant.id} tests iOS screen stream event shapes`);
        assert(configPairingPayload.includes("enum ConfigPairingPayload"), `${variant.id} has ConfigPairingPayload`);
        assert(configPairingPayload.includes("import Foundation"), `${variant.id} ConfigPairingPayload imports Foundation`);
        assert(!configPairingPayload.includes("import CoreBluetooth"), `${variant.id} ConfigPairingPayload stays independent from CoreBluetooth`);
        assert(!configPairingPayload.includes("import UIKit"), `${variant.id} ConfigPairingPayload stays independent from UIKit`);
        assert(!configPairingPayload.includes("import SwiftUI"), `${variant.id} ConfigPairingPayload stays independent from SwiftUI`);
        assert(!configPairingPayload.includes("import Security"), `${variant.id} ConfigPairingPayload stays independent from Security`);
        assert(!configPairingPayload.includes("import CoreImage"), `${variant.id} ConfigPairingPayload stays independent from QR image APIs`);
        assert(configPairingPayload.includes("static let serviceUUID"), `${variant.id} ConfigPairingPayload owns service UUID`);
        assert(configPairingPayload.includes("static let commandUUID"), `${variant.id} ConfigPairingPayload owns command UUID`);
        assert(configPairingPayload.includes("static let responseUUID"), `${variant.id} ConfigPairingPayload owns response UUID`);
        assert(configPairingPayload.includes("struct PairingTarget"), `${variant.id} ConfigPairingPayload owns target parsing`);
        assert(configPairingPayload.includes("struct ChunkAccumulator"), `${variant.id} ConfigPairingPayload owns chunk reassembly state`);
        assert(configPairingPayload.includes("static func pairingPayload"), `${variant.id} ConfigPairingPayload owns pairing QR payloads`);
        assert(configPairingPayload.includes("static func command"), `${variant.id} ConfigPairingPayload owns command construction`);
        assert(configPairingPayload.includes("static func responsePayload"), `${variant.id} ConfigPairingPayload owns response envelopes`);
        assert(configPairingPayload.includes("static func errorPayload"), `${variant.id} ConfigPairingPayload owns error envelopes`);
        assert(configPairingPayload.includes("static func eventPayload"), `${variant.id} ConfigPairingPayload owns event envelopes`);
        assert(configPairingPayload.includes("static func chunkPayloads"), `${variant.id} ConfigPairingPayload owns chunk splitting`);
        assert(configPairingPayload.includes("static func chunkData"), `${variant.id} ConfigPairingPayload owns chunk decoding`);
        assert(configPairingPayload.includes("BridgeResponse.base"), `${variant.id} ConfigPairingPayload uses shared bridge base response`);
        assert(configPairingPayload.includes("BridgeResponse.error"), `${variant.id} ConfigPairingPayload uses shared bridge error response`);
        assert(configPairingBridge.includes("ConfigPairingPayload.pairingPayload"), `${variant.id} ConfigPairingBridge delegates pairing QR payloads`);
        assert(configPairingBridge.includes("ConfigPairingPayload.showResponse"), `${variant.id} ConfigPairingBridge delegates show responses`);
        assert(configPairingBridge.includes("ConfigPairingPayload.acknowledgementResponse"), `${variant.id} ConfigPairingBridge delegates acknowledgements`);
        assert(configPairingBridge.includes("ConfigPairingPayload.connectResponse"), `${variant.id} ConfigPairingBridge delegates connect responses`);
        assert(configPairingBridge.includes("ConfigPairingPayload.command"), `${variant.id} ConfigPairingBridge delegates command construction`);
        assert(configPairingBridge.includes("ConfigPairingPayload.sendResponse"), `${variant.id} ConfigPairingBridge delegates send responses`);
        assert(configPairingBridge.includes("ConfigPairingPayload.chunkPayloads"), `${variant.id} ConfigPairingBridge delegates chunk splitting`);
        assert(configPairingBridge.includes("ConfigPairingPayload.chunkData"), `${variant.id} ConfigPairingBridge delegates chunk decoding`);
        assert(!configPairingBridge.includes("private struct PairingTarget"), `${variant.id} pairing target parsing stays out of ConfigPairingBridge`);
        assert(!configPairingBridge.includes("private struct ConfigChunkAccumulator"), `${variant.id} chunk accumulator stays out of ConfigPairingBridge`);
        assert(!configPairingBridge.includes("private func pairingPayload"), `${variant.id} pairing payload construction stays out of ConfigPairingBridge`);
        assert(!configPairingBridge.includes("private func baseResponse"), `${variant.id} config pairing base response stays out of ConfigPairingBridge`);
        assert(!configPairingBridge.includes("private func errorResponse"), `${variant.id} config pairing error response stays out of ConfigPairingBridge`);
        assert(!configPairingBridge.includes("private func stringOrGenerated"), `${variant.id} generated request ID fallback stays out of ConfigPairingBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ConfigPairingPayloadTests.swift", "testPairingPayloadRoundTripsIdentityFields"), `${variant.id} tests iOS config pairing payload roundtrip`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ConfigPairingPayloadTests.swift", "testPairingTargetParseSupportsLegacyAliasesDuplicatesAndRejectsInvalidPayloads"), `${variant.id} tests iOS config pairing target parsing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ConfigPairingPayloadTests.swift", "testCommandUsesDefaultsAliasesAndTrimming"), `${variant.id} tests iOS config pairing command construction`);
        assert(contains("ios/swiftHTMLWebviewAppTests/ConfigPairingPayloadTests.swift", "testChunkAccumulatorReassemblesOutOfOrderPayloads"), `${variant.id} tests iOS config pairing chunk reassembly`);
        assert(nfcPayload.includes("enum NFCPayload"), `${variant.id} has NFCPayload`);
        assert(nfcPayload.includes("import Foundation"), `${variant.id} NFCPayload imports Foundation`);
        assert(!nfcPayload.includes("import CoreNFC"), `${variant.id} NFCPayload stays independent from CoreNFC`);
        assert(nfcPayload.includes("struct RecordInput"), `${variant.id} NFCPayload has CoreNFC-free record input`);
        assert(nfcPayload.includes("static func tagPayload"), `${variant.id} NFCPayload owns tag payloads`);
        assert(nfcPayload.includes("static func ndefPayload"), `${variant.id} NFCPayload owns NDEF payloads`);
        assert(nfcPayload.includes("static func recordPayload"), `${variant.id} NFCPayload owns record payloads`);
        assert(nfcPayload.includes("static func decodeTextRecord"), `${variant.id} NFCPayload owns text record decoding`);
        assert(nfcPayload.includes("static func decodeURIRecord"), `${variant.id} NFCPayload owns URI record decoding`);
        assert(nfcPayload.includes("BridgeResponse.base"), `${variant.id} NFCPayload uses shared base response shape`);
        assert(nfcTagReaderBridge.includes("NFCPayload.tagPayload"), `${variant.id} NFCTagReaderBridge delegates tag payloads`);
        assert(nfcTagReaderBridge.includes("NFCPayload.ndefPayload"), `${variant.id} NFCTagReaderBridge delegates NDEF payloads`);
        assert(nfcTagReaderBridge.includes("NFCPayload.errorResponse"), `${variant.id} NFCTagReaderBridge delegates error response shape`);
        assert(nfcTagReaderBridge.includes("NFCPayload.RecordInput"), `${variant.id} NFCTagReaderBridge adapts CoreNFC records only`);
        assert(!nfcTagReaderBridge.includes("private func decodeTextRecord"), `${variant.id} NFC text decoding stays out of NFCTagReaderBridge`);
        assert(!nfcTagReaderBridge.includes("private func decodeURIRecord"), `${variant.id} NFC URI decoding stays out of NFCTagReaderBridge`);
        assert(!nfcTagReaderBridge.includes("private func uriPrefix"), `${variant.id} NFC URI prefix table stays out of NFCTagReaderBridge`);
        assert(!nfcTagReaderBridge.includes("private func baseResponse"), `${variant.id} NFC base response stays out of NFCTagReaderBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NFCPayloadTests.swift", "testTextRecordDecodesLanguageAndUtf8Text"), `${variant.id} tests iOS NFC text record decoding`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NFCPayloadTests.swift", "testInvalidTextAndUnknownTypeNameFormatAreStable"), `${variant.id} tests iOS NFC invalid text and unknown TNF fallback`);
        assert(sensorPayload.includes("enum SensorPayload"), `${variant.id} has SensorPayload`);
        assert(sensorPayload.includes("import Foundation"), `${variant.id} SensorPayload imports Foundation`);
        assert(!sensorPayload.includes("import CoreMotion"), `${variant.id} SensorPayload stays independent from CoreMotion`);
        assert(sensorPayload.includes("struct StreamRequest"), `${variant.id} SensorPayload owns stream request model`);
        assert(sensorPayload.includes("static func streamRequest"), `${variant.id} SensorPayload owns stream request normalization`);
        assert(sensorPayload.includes("static func capabilitiesResponse"), `${variant.id} SensorPayload owns sensor capability responses`);
        assert(sensorPayload.includes("static func streamStartResponse"), `${variant.id} SensorPayload owns stream start responses`);
        assert(sensorPayload.includes("static func stopResponse"), `${variant.id} SensorPayload owns stream stop responses`);
        assert(sensorPayload.includes("static func errorResponse"), `${variant.id} SensorPayload owns sensor error responses`);
        assert(sensorPayload.includes("static func sensorDataEvent"), `${variant.id} SensorPayload owns sensor data events`);
        assert(sensorPayload.includes('"sensors"'), `${variant.id} iOS sensorData stays batched under sensors`);
        assert(sensorBridge.includes("SensorPayload.capabilitiesResponse"), `${variant.id} SensorBridge delegates capability responses`);
        assert(sensorBridge.includes("SensorPayload.streamRequest"), `${variant.id} SensorBridge delegates stream request normalization`);
        assert(sensorBridge.includes("SensorPayload.streamStartResponse"), `${variant.id} SensorBridge delegates stream start responses`);
        assert(sensorBridge.includes("SensorPayload.stopResponse"), `${variant.id} SensorBridge delegates stream stop responses`);
        assert(sensorBridge.includes("SensorPayload.sensorDataEvent"), `${variant.id} SensorBridge delegates sensor data events`);
        assert(!sensorBridge.includes("private func baseResponse"), `${variant.id} sensor base response stays out of SensorBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/SensorPayloadTests.swift", "testStreamRequestDefaultsAndClampsInterval"), `${variant.id} tests iOS sensor stream request normalization`);
        assert(contains("ios/swiftHTMLWebviewAppTests/SensorPayloadTests.swift", "testSensorDataEventUsesCatalogedPayloadShape"), `${variant.id} tests iOS sensor data event shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/SensorPayloadTests.swift", "testErrorResponseKeepsRequestId"), `${variant.id} tests iOS sensor error response shape`);
        assert(locationPayload.includes("enum LocationPayload"), `${variant.id} has LocationPayload`);
        assert(locationPayload.includes("import Foundation"), `${variant.id} LocationPayload imports Foundation`);
        assert(!locationPayload.includes("import CoreLocation"), `${variant.id} LocationPayload stays independent from CoreLocation`);
        assert(locationPayload.includes("struct LocationObject"), `${variant.id} LocationPayload has CoreLocation-free location object`);
        assert(locationPayload.includes("static func response"), `${variant.id} LocationPayload owns location responses`);
        assert(locationPayload.includes("static func locationPayload"), `${variant.id} LocationPayload owns location objects`);
        assert(locationPayload.includes("static func startResponse"), `${variant.id} LocationPayload owns location start responses`);
        assert(locationPayload.includes("static func stopResponse"), `${variant.id} LocationPayload owns location stop responses`);
        assert(locationPayload.includes("static func errorResponse"), `${variant.id} LocationPayload owns location errors`);
        assert(locationPayload.includes("BridgeResponse.base"), `${variant.id} LocationPayload uses shared bridge base response`);
        assert(locationPayload.includes('"provider"'), `${variant.id} LocationPayload includes location provider field`);
        assert(locationBridge.includes("LocationPayload.response"), `${variant.id} LocationBridge delegates location responses`);
        assert(locationBridge.includes("LocationPayload.startResponse"), `${variant.id} LocationBridge delegates start responses`);
        assert(locationBridge.includes("LocationPayload.stopResponse"), `${variant.id} LocationBridge delegates stop responses`);
        assert(locationBridge.includes("LocationPayload.errorResponse"), `${variant.id} LocationBridge delegates error responses`);
        assert(!locationBridge.includes("private func baseResponse"), `${variant.id} location base response stays out of LocationBridge`);
        assert(!locationBridge.includes("private func errorResponse"), `${variant.id} location error response stays out of LocationBridge`);
        assert(!locationBridge.includes('"latitude"'), `${variant.id} location latitude field mapping stays out of LocationBridge`);
        assert(!locationBridge.includes('"timestampMs"'), `${variant.id} location timestamp field mapping stays out of LocationBridge`);
        assert(!locationBridge.includes("NSNull()"), `${variant.id} location null payload mapping stays out of LocationBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/LocationPayloadTests.swift", "testResponseWrapsLocationInCommonBridgeEnvelope"), `${variant.id} tests iOS location response envelope`);
        assert(contains("ios/swiftHTMLWebviewAppTests/LocationPayloadTests.swift", "testLocationPayloadUsesNullForMissingOptionalSignals"), `${variant.id} tests iOS location optional nulls`);
        assert(contains("ios/swiftHTMLWebviewAppTests/LocationPayloadTests.swift", "testLocationPayloadIncludesProviderTimestampAndAvailableSignals"), `${variant.id} tests iOS location provider field`);
        assert(contains("ios/swiftHTMLWebviewAppTests/LocationPayloadTests.swift", "testStartStopErrorsAndDistanceUseCommonShape"), `${variant.id} tests iOS location start stop and error shape`);
        assert(orientationPayload.includes("enum OrientationPayload"), `${variant.id} has OrientationPayload`);
        assert(orientationPayload.includes("import Foundation"), `${variant.id} OrientationPayload imports Foundation`);
        assert(!orientationPayload.includes("import UIKit"), `${variant.id} OrientationPayload stays independent from UIKit`);
        assert(orientationPayload.includes("static func mode(from request"), `${variant.id} OrientationPayload owns mode alias normalization`);
        assert(orientationPayload.includes("static func setResponse"), `${variant.id} OrientationPayload owns orientation set responses`);
        assert(orientationPayload.includes("static func statusResponse"), `${variant.id} OrientationPayload owns orientation status responses`);
        assert(orientationPayload.includes("BridgeResponse.base"), `${variant.id} OrientationPayload uses shared bridge base response`);
        assert(orientationController.includes("OrientationPayload.mode(from:"), `${variant.id} OrientationController delegates mode normalization`);
        assert(orientationController.includes("OrientationPayload.setResponse"), `${variant.id} OrientationController delegates set responses`);
        assert(orientationController.includes("OrientationPayload.statusResponse"), `${variant.id} OrientationController delegates status responses`);
        assert(!orientationController.includes("private func baseResponse"), `${variant.id} orientation base response stays out of OrientationController`);
        assert(contentView.includes("OrientationController.shared.setPayload(request: message)"), `${variant.id} ContentView delegates full orientation set request`);
        assert(contains("ios/swiftHTMLWebviewAppTests/OrientationPayloadTests.swift", "testModePrefersModeOverOrientationAndNormalizesAliases"), `${variant.id} tests iOS orientation aliases`);
        assert(contains("ios/swiftHTMLWebviewAppTests/OrientationPayloadTests.swift", "testSetResponseUsesCommonEnvelopeAndEchoesMask"), `${variant.id} tests iOS orientation set response shape`);
        assert(contains("ios/swiftHTMLWebviewAppTests/OrientationPayloadTests.swift", "testStatusResponseUsesCommonEnvelopeAndCurrentOrientation"), `${variant.id} tests iOS orientation status response shape`);
        assert(printerPayload.includes("enum PrinterPayload"), `${variant.id} has PrinterPayload`);
        assert(printerPayload.includes("import Foundation"), `${variant.id} PrinterPayload imports Foundation`);
        assert(!printerPayload.includes("import Printercore"), `${variant.id} PrinterPayload stays independent from Printercore`);
        assert(!printerPayload.includes("import UIKit"), `${variant.id} PrinterPayload stays independent from UIKit`);
        assert(!printerPayload.includes("DispatchQueue"), `${variant.id} PrinterPayload stays independent from queues`);
        assert(printerPayload.includes("struct EpsonHelloWorldRequest"), `${variant.id} PrinterPayload owns Epson request model`);
        assert(printerPayload.includes("static func epsonRequest"), `${variant.id} PrinterPayload owns Epson request parsing`);
        assert(printerPayload.includes("static func selectedPrinterKind"), `${variant.id} PrinterPayload owns printer kind routing`);
        assert(printerPayload.includes("static func selectedPrinterLabel"), `${variant.id} PrinterPayload owns printer labels`);
        assert(printerPayload.includes("static func discoveryOptionsJSON"), `${variant.id} PrinterPayload owns discovery JSON options`);
        assert(printerPayload.includes("static func coreResponse"), `${variant.id} PrinterPayload owns printercore JSON parsing`);
        assert(printerPayload.includes("static func epsonJobResponse"), `${variant.id} PrinterPayload owns Epson job responses`);
        assert(printerPayload.includes("static func printercoreUnavailable"), `${variant.id} PrinterPayload owns printercore unavailable responses`);
        assert(printerPayload.includes("static func discoveryUnavailable"), `${variant.id} PrinterPayload owns discovery unavailable responses`);
        assert(printerPayload.includes("static func unsupportedKindResponse"), `${variant.id} PrinterPayload owns unsupported printer responses`);
        assert(printerPayload.includes("BridgeResponse.base"), `${variant.id} PrinterPayload uses shared bridge base response`);
        assert(printerPayload.includes("BridgeResponse.unavailable"), `${variant.id} PrinterPayload uses shared unavailable response`);
        assert(printerBridge.includes("PrinterPayload.selectedPrinterKind"), `${variant.id} PrinterBridge delegates printer kind routing`);
        assert(printerBridge.includes("PrinterPayload.epsonRequest"), `${variant.id} PrinterBridge delegates Epson request parsing`);
        assert(printerBridge.includes("PrinterPayload.coreResponse"), `${variant.id} PrinterBridge delegates printercore JSON parsing`);
        assert(printerBridge.includes("PrinterPayload.epsonJobResponse"), `${variant.id} PrinterBridge delegates Epson job responses`);
        assert(printerBridge.includes("PrinterPayload.printercoreUnavailable"), `${variant.id} PrinterBridge delegates printercore unavailable responses`);
        assert(printerBridge.includes("PrinterPayload.discoveryOptionsJSON"), `${variant.id} PrinterBridge delegates discovery JSON options`);
        assert(printerBridge.includes("PrinterPayload.discoveryUnavailable"), `${variant.id} PrinterBridge delegates discovery unavailable responses`);
        assert(printerBridge.includes("PrinterPayload.unsupportedKindResponse"), `${variant.id} PrinterBridge delegates unsupported printer responses`);
        assert(!printerBridge.includes("private func baseResponse"), `${variant.id} printer base response stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func jsonString"), `${variant.id} printer discovery JSON stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func parseCoreResponse"), `${variant.id} printercore parsing stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func selectedPrinterKind"), `${variant.id} printer kind routing stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func selectedPrinterLabel"), `${variant.id} printer label routing stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func stringValue"), `${variant.id} printer string parsing stays out of PrinterBridge`);
        assert(!printerBridge.includes("private func intValue"), `${variant.id} printer integer parsing stays out of PrinterBridge`);
        assert(contains("ios/swiftHTMLWebviewAppTests/PrinterPayloadTests.swift", "testSelectedPrinterKindUsesDirectNestedAndDefaultEpson"), `${variant.id} tests iOS printer kind routing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/PrinterPayloadTests.swift", "testEpsonRequestTrimsAndDefaultsFields"), `${variant.id} tests iOS printer request parsing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/PrinterPayloadTests.swift", "testCoreResponseParsesJSONAndReportsInvalidJSON"), `${variant.id} tests iOS printercore JSON parsing`);
        assert(contains("ios/swiftHTMLWebviewAppTests/PrinterPayloadTests.swift", "testEpsonJobResponseMergesCoreFieldsAndBackfillsError"), `${variant.id} tests iOS printer job response shape`);
        assert(bridgeDispatcher.includes("enum BridgeDispatcher"), `${variant.id} has BridgeDispatcher`);
        assert(bridgeDispatcher.includes("static func action"), `${variant.id} BridgeDispatcher extracts actions`);
        assert(bridgeDispatcher.includes("missingActionResponse"), `${variant.id} BridgeDispatcher handles missing actions`);
        assert(bridgeDispatcher.includes("unknownActionResponse"), `${variant.id} BridgeDispatcher handles unknown actions`);
        assert(bridgeRouter.includes("struct BridgeRouter"), `${variant.id} has BridgeRouter`);
        assert(bridgeRouter.includes("BridgeDispatcher.action"), `${variant.id} BridgeRouter delegates action extraction`);
        assert(bridgeRouter.includes("BridgeDispatcher.missingActionResponse"), `${variant.id} BridgeRouter delegates missing action response`);
        assert(bridgeRouter.includes("BridgeDispatcher.unknownActionResponse"), `${variant.id} BridgeRouter delegates unknown action response`);
        assert(bridgeActionCatalog.includes("enum BridgeActionCatalog"), `${variant.id} has BridgeActionCatalog`);
        assert(bridgeActionCatalog.includes("static let publicActions"), `${variant.id} BridgeActionCatalog records public bridge actions`);
        assert(bridgeActionCatalog.includes("static let internalActions"), `${variant.id} BridgeActionCatalog records internal bridge actions`);
        assert(bridgeActionCatalog.includes("static var registeredActions"), `${variant.id} BridgeActionCatalog owns registered action set`);
        assert(bridgeScriptBuilder.includes("enum BridgeScriptBuilder"), `${variant.id} has BridgeScriptBuilder`);
        assert(bridgeScriptBuilder.includes("nativeResultScript"), `${variant.id} BridgeScriptBuilder owns native result script creation`);
        assert(bridgeScriptBuilder.includes("JSONSerialization.isValidJSONObject"), `${variant.id} BridgeScriptBuilder validates JSON payloads`);
        assert(bridgeScriptBuilder.includes("window.handleNativeResult"), `${variant.id} BridgeScriptBuilder targets handleNativeResult`);
        assert(webViewStore.includes("BridgeScriptBuilder.nativeResultScript"), `${variant.id} WebViewStore delegates native result script creation`);
        assert(!webViewStore.includes("JSONSerialization.data(withJSONObject: data"), `${variant.id} native result JSON serialization stays out of WebViewStore`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeScriptBuilderTests.swift", "testNativeResultScriptWrapsSerializablePayload"), `${variant.id} tests iOS bridge result script payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeScriptBuilderTests.swift", "testNativeResultScriptFallsBackForInvalidJSONPayload"), `${variant.id} tests iOS bridge result script fallback`);
        assert(webViewErrorPayload.includes("enum WebViewErrorPayload"), `${variant.id} has WebViewErrorPayload`);
        assert(webViewErrorPayload.includes("BridgeResponse.error"), `${variant.id} WebViewErrorPayload uses shared bridge error response`);
        assert(webViewStore.includes("WebViewErrorPayload.response"), `${variant.id} WebViewStore delegates web view error payloads`);
        assert(!webViewStore.includes("var errorDict"), `${variant.id} WebViewStore does not own ad hoc error dictionaries`);
        assert(contains("ios/swiftHTMLWebviewAppTests/WebViewErrorPayloadTests.swift", "testResponseUsesSharedBridgeErrorShapeForAppErrors"), `${variant.id} tests iOS WebView AppError payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/WebViewErrorPayloadTests.swift", "testResponseWrapsGenericErrorsAsInternalErrors"), `${variant.id} tests iOS WebView generic error payloads`);
        assert(contentView.includes("private func makeBridgeRouter() -> BridgeRouter"), `${variant.id} ContentView registers bridge router actions`);
        assert(contentView.includes("@State private var bridgeRouter: BridgeRouter?"), `${variant.id} ContentView stores bridge router`);
        assert(contentView.includes("private func installBridgeRouterIfNeeded()"), `${variant.id} ContentView installs bridge router once`);
        assert(contentView.includes("bridgeRouter?.postMessage(message)"), `${variant.id} ContentView delegates script messages to BridgeRouter`);
        assert(contentView.includes("BridgeActionCatalog.assertRegisteredActions(router.actions)"), `${variant.id} ContentView checks router action registration against catalog`);
        assert(contentView.includes("BridgeActionCatalog.continuousScannerStartActions"), `${variant.id} ContentView uses cataloged continuous scanner start aliases`);
        assert(contentView.includes("BridgeActionCatalog.arOverlayOpenActions"), `${variant.id} ContentView uses cataloged AR overlay aliases`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeRouterTests.swift", "testPostMessageRoutesKnownActions"), `${variant.id} BridgeRouter has unit tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeActionCatalogTests.swift", "testRegisteredActionsMatchCurrentIOSBridgeSurface"), `${variant.id} BridgeActionCatalog has action surface tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeDispatcherTests.swift", "testUnknownActionResponseEchoesUnknownAction"), `${variant.id} BridgeDispatcher has unit tests`);
        assert(settingsBridge.includes("BridgeResponse.base"), `${variant.id} SettingsBridge uses BridgeResponse base`);
        assert(settingsBridge.includes("BridgeResponse.error"), `${variant.id} SettingsBridge uses BridgeResponse error`);
        assert(nativeCommandPayload.includes("enum NativeCommandPayload"), `${variant.id} has NativeCommandPayload`);
        assert(nativeCommandPayload.includes("static func reloadResponse"), `${variant.id} NativeCommandPayload owns reload responses`);
        assert(nativeCommandPayload.includes("static func launchConfettiResponse"), `${variant.id} NativeCommandPayload owns launchConfetti responses`);
        assert(contentView.includes("NativeCommandPayload.reloadResponse"), `${variant.id} ContentView sends reload acknowledgement`);
        assert(contentView.includes("NativeCommandPayload.launchConfettiResponse"), `${variant.id} ContentView sends launchConfetti acknowledgement`);
        assert(contentView.includes("DispatchQueue.main.asyncAfter"), `${variant.id} ContentView delays reload after acknowledgement`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NativeCommandPayloadTests.swift", "testReloadResponseUsesNativeCommandEnvelope"), `${variant.id} tests iOS reload native command response`);
        assert(contains("ios/swiftHTMLWebviewAppTests/NativeCommandPayloadTests.swift", "testLaunchConfettiResponseUsesNativeCommandEnvelopeAndMetadata"), `${variant.id} tests iOS launchConfetti native command response`);
        assert(tapToPayPayload.includes("enum TapToPayPayload"), `${variant.id} has TapToPayPayload`);
        assert(tapToPayPayload.includes("static func availability"), `${variant.id} TapToPayPayload owns availability responses`);
        assert(tapToPayPayload.includes("static func collectSuccess"), `${variant.id} TapToPayPayload owns collect success responses`);
        assert(tapToPayPayload.includes("static func error"), `${variant.id} TapToPayPayload owns collect error responses`);
        assert(tapToPayPayload.includes("BridgeResponse.base"), `${variant.id} TapToPayPayload uses shared bridge base response`);
        assert(tapToPayPayload.includes("BridgeResponse.error"), `${variant.id} TapToPayPayload uses shared bridge error response`);
        assert(tapToPayBridge.includes("TapToPayPayload.availability"), `${variant.id} TapToPayBridge delegates availability payloads`);
        assert(tapToPayBridge.includes("TapToPayPayload.collectSuccess"), `${variant.id} TapToPayBridge delegates collect success payloads`);
        assert(tapToPayBridge.includes("TapToPayPayload.error"), `${variant.id} TapToPayBridge delegates collect error payloads`);
        assert(contains("ios/swiftHTMLWebviewAppTests/TapToPayPayloadTests.swift", "testAvailabilityUnavailableUsesContractEnvelope"), `${variant.id} tests iOS Tap to Pay availability envelope`);
        assert(contains("ios/swiftHTMLWebviewAppTests/TapToPayPayloadTests.swift", "testCollectErrorUsesContractEnvelopeAndPaymentId"), `${variant.id} tests iOS Tap to Pay error envelope`);
        assert(contentView.includes("BridgeResponse.unavailable"), `${variant.id} unavailable iOS actions use BridgeResponse`);
        assert(contains("ios/swiftHTMLWebviewAppTests/BridgeResponseTests.swift", "testUnavailableResponseMarksAvailability"), `${variant.id} BridgeResponse has unit tests`);
        assert(settingsBridge.includes("struct SettingsBridge"), `${variant.id} has SettingsBridge`);
        assert(settingsBridge.includes("func getResponse"), `${variant.id} SettingsBridge handles settingsGet`);
        assert(settingsBridge.includes("func setResponse"), `${variant.id} SettingsBridge handles settingsSet`);
        assert(contentView.includes("private let settingsBridge = SettingsBridge()"), `${variant.id} ContentView owns SettingsBridge`);
        assert(contentView.includes("settingsBridge.getResponse"), `${variant.id} ContentView delegates settingsGet`);
        assert(contentView.includes("settingsBridge.setResponse"), `${variant.id} ContentView delegates settingsSet`);
        assert(!contentView.includes("securityToken is required for settingsSet."), `${variant.id} settings token validation stays out of ContentView`);
        assert(contains("ios/swiftHTMLWebviewAppTests/SettingsBridgeTests.swift", "testSettingsSetAppliesNestedSettingsWhenTokenMatches"), `${variant.id} SettingsBridge has unit tests`);
        assert(startupURLResolver.includes("struct StartupURLResolver"), `${variant.id} has StartupURLResolver`);
        assert(startupURLResolver.includes("func candidates"), `${variant.id} StartupURLResolver resolves URL candidates`);
        assert(appSettings.includes("private let startupURLResolver: StartupURLResolver"), `${variant.id} AppSettings owns StartupURLResolver`);
        assert(appSettings.includes("startupURLResolver.candidates"), `${variant.id} AppSettings delegates startup URL candidate resolution`);
        assert(!appSettings.includes("func normalizedURLIdentity"), `${variant.id} URL identity normalization stays out of AppSettings`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupURLResolverTests.swift", "testCandidatesDeduplicateRemoteAndLocalURLs"), `${variant.id} StartupURLResolver has unit tests`);
        assert(startupReachabilityPolicy.includes("enum StartupReachabilityPolicy"), `${variant.id} has StartupReachabilityPolicy`);
        assert(startupReachabilityPolicy.includes("static func probeURLs"), `${variant.id} StartupReachabilityPolicy builds probe URLs`);
        assert(startupReachabilityPolicy.includes("static func probeTimeout"), `${variant.id} StartupReachabilityPolicy clamps probe timeout`);
        assert(startupReachabilityPolicy.includes("static func loadTimeout"), `${variant.id} StartupReachabilityPolicy owns load timeout policy`);
        assert(webViewStore.includes("StartupReachabilityPolicy.probeURLs"), `${variant.id} WebViewStore delegates startup probe URLs`);
        assert(webViewStore.includes("StartupReachabilityPolicy.probeTimeout"), `${variant.id} WebViewStore delegates probe timeout policy`);
        assert(webViewStore.includes("StartupReachabilityPolicy.loadTimeout"), `${variant.id} WebViewStore delegates load timeout policy`);
        assert(!webViewStore.includes("private func availabilityProbeURLs"), `${variant.id} startup probe URL construction stays out of WebViewStore`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupReachabilityPolicyTests.swift", "testProbeURLsUseHealthEndpointThenOriginalURL"), `${variant.id} tests iOS startup probe URL policy`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupReachabilityPolicyTests.swift", "testProbeTimeoutClampsToShortAvailabilityWindow"), `${variant.id} tests iOS startup probe timeout policy`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupReachabilityPolicyTests.swift", "testLoadTimeoutUsesLongDefaultWhenHighAvailabilityIsDisabled"), `${variant.id} tests iOS startup load timeout policy`);
        assert(startupLoadState.includes("struct StartupLoadState"), `${variant.id} has StartupLoadState`);
        assert(startupLoadState.includes("mutating func reset"), `${variant.id} StartupLoadState resets configured candidates`);
        assert(startupLoadState.includes("func hasRemainingCandidates"), `${variant.id} StartupLoadState owns HA candidate availability`);
        assert(startupLoadState.includes("mutating func advance"), `${variant.id} StartupLoadState owns HA advancement`);
        assert(startupLoadState.includes("func recoveryCandidates"), `${variant.id} StartupLoadState owns recovery candidate fallback`);
        assert(startupLoadCoordinator.includes("struct StartupLoadCoordinator"), `${variant.id} has StartupLoadCoordinator`);
        assert(startupLoadCoordinator.includes("enum Command"), `${variant.id} StartupLoadCoordinator exposes load commands`);
        assert(startupLoadCoordinator.includes("case load"), `${variant.id} StartupLoadCoordinator owns load URL commands`);
        assert(startupLoadCoordinator.includes("case showRecovery"), `${variant.id} StartupLoadCoordinator owns recovery commands`);
        assert(startupLoadCoordinator.includes("mutating func start"), `${variant.id} StartupLoadCoordinator owns startup decisions`);
        assert(startupLoadCoordinator.includes("mutating func mainFrameFailed"), `${variant.id} StartupLoadCoordinator owns main-frame failover decisions`);
        assert(startupLoadCoordinator.includes("mutating func timeout"), `${variant.id} StartupLoadCoordinator owns timeout failover decisions`);
        assert(!startupLoadCoordinator.includes("WKWebView"), `${variant.id} StartupLoadCoordinator has no WebKit dependency`);
        assert(!startupLoadCoordinator.includes("URLSession"), `${variant.id} StartupLoadCoordinator has no network dependency`);
        assert(!startupLoadCoordinator.includes("DispatchQueue"), `${variant.id} StartupLoadCoordinator has no timer dependency`);
        assert(webViewStore.includes("private var startupLoadCoordinator = StartupLoadCoordinator()"), `${variant.id} WebViewStore owns StartupLoadCoordinator`);
        assert(webViewStore.includes("startupLoadCoordinator.start"), `${variant.id} WebViewStore delegates startup decision state`);
        assert(webViewStore.includes("startupLoadCoordinator.selectCandidate"), `${variant.id} WebViewStore delegates candidate selection decisions`);
        assert(webViewStore.includes("startupLoadCoordinator.mainFrameFailed"), `${variant.id} WebViewStore delegates main-frame failover decisions`);
        assert(webViewStore.includes("startupLoadCoordinator.timeout"), `${variant.id} WebViewStore delegates timeout failover decisions`);
        assert(webViewStore.includes("private func applyStartupLoadCommand"), `${variant.id} WebViewStore only applies startup load commands`);
        assert(!webViewStore.includes("private var startupLoadState = StartupLoadState()"), `${variant.id} WebViewStore does not own raw StartupLoadState`);
        assert(!webViewStore.includes("private var loadCandidates"), `${variant.id} startup candidate list stays out of WebViewStore`);
        assert(!webViewStore.includes("private var candidateIndex"), `${variant.id} startup candidate index stays out of WebViewStore`);
        assert(!webViewStore.includes("private var isShowingRecoveryPage"), `${variant.id} startup recovery flag stays out of WebViewStore`);
        assert(!webViewStore.includes("private var hasRemainingCandidates"), `${variant.id} startup HA candidate policy stays out of WebViewStore`);
        assert(!webViewStore.includes("private func candidateSignature"), `${variant.id} startup candidate signature stays out of WebViewStore`);
        assert(!webViewStore.includes("private func displayName"), `${variant.id} startup display-name mapping stays out of WebViewStore`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadStateTests.swift", "testAdvanceRequiresHighAvailabilityAndRemainingCandidate"), `${variant.id} tests iOS startup load advancement`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadStateTests.swift", "testRecoveryCandidatesUseFallbackBeforeResetAndConfiguredListAfterReset"), `${variant.id} tests iOS startup recovery candidates`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadStateTests.swift", "testCurrentLocalPageMatchesLocalAliasesAndFileURLs"), `${variant.id} tests iOS startup local page matching`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadCoordinatorTests.swift", "testMainFrameFailureAdvancesToNextHighAvailabilityCandidate"), `${variant.id} tests iOS startup failover coordinator`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadCoordinatorTests.swift", "testLastFailureShowsRecoveryWithOriginalCandidateList"), `${variant.id} tests iOS startup recovery coordinator`);
        assert(contains("ios/swiftHTMLWebviewAppTests/StartupLoadCoordinatorTests.swift", "testReloadResetsCandidateIndexAndRecoveryState"), `${variant.id} tests iOS startup coordinator reload reset`);
        assert(recoveryConfigParser.includes("struct RecoveryConfigParser"), `${variant.id} has RecoveryConfigParser`);
        assert(recoveryConfigParser.includes("func serverURL"), `${variant.id} RecoveryConfigParser parses recovery QR server URLs`);
        assert(recoveryConfigParser.includes("struct RecoveryBarcodeHandler"), `${variant.id} has RecoveryBarcodeHandler`);
        assert(recoveryConfigParser.includes("func handle(code: String, action: String)"), `${variant.id} RecoveryBarcodeHandler handles recovery barcode decisions`);
        assert(recoveryConfigParser.includes("applyConfiguration([\"serverURL\": serverURL])"), `${variant.id} RecoveryBarcodeHandler owns recovery server URL persistence`);
        assert(contentView.includes("RecoveryBarcodeHandler("), `${variant.id} ContentView owns RecoveryBarcodeHandler`);
        assert(contentView.includes("recoveryBarcodeHandler.handle(code: code, action: action)"), `${variant.id} ContentView delegates recovery barcode handling`);
        assert(contentView.includes("RecoveryBarcodeHandler.isRecoveryRequest"), `${variant.id} ContentView delegates recovery request detection`);
        assert(!contentView.includes("recoveryConfigParser.serverURL(from: code)"), `${variant.id} recovery QR parsing stays out of ContentView`);
        assert(!contentView.includes("AppSettings.shared.applyConfiguration([\"serverURL\": serverURL])"), `${variant.id} recovery settings persistence stays out of ContentView`);
        assert(!contentView.includes("private func recoveryServerURL"), `${variant.id} recovery QR parsing stays out of ContentView`);
        assert(!contentView.includes("private func normalizedRecoveryMobileURL"), `${variant.id} recovery URL normalization stays out of ContentView`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryConfigParserTests.swift", "testParsesDirectServerURLFromJSONAndAddsLink"), `${variant.id} RecoveryConfigParser has JSON URL tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryConfigParserTests.swift", "testKeepsExistingLinkAndRemovesFragment"), `${variant.id} RecoveryConfigParser has URL normalization tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryConfigParserTests.swift", "testRecoveryBarcodeHandlerAppliesNormalizedServerURL"), `${variant.id} RecoveryBarcodeHandler has persistence tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryConfigParserTests.swift", "testRecoveryBarcodeHandlerReturnsInvalidResponseWithoutApplyingSettings"), `${variant.id} RecoveryBarcodeHandler has invalid QR tests`);
        assert(contains("ios/swiftHTMLWebviewAppTests/RecoveryConfigParserTests.swift", "testRecoveryBarcodeRequestDetectionUsesSourceField"), `${variant.id} RecoveryBarcodeHandler has source detection tests`);
        assert(extractSettingsBundleDefault("server_url_preference") === variant.runtimeDefaults.serverURL, `${variant.id} Settings.bundle server URL matches`);
        assert(extractSettingsBundleDefault("security_token_preference") === variant.runtimeDefaults.securityToken, `${variant.id} Settings.bundle security token matches`);
        assert(extractSettingsBundleDefault("ha_timeout") === variant.runtimeDefaults.highAvailabilityTimeoutSeconds, `${variant.id} Settings.bundle HA timeout matches`);
        assert(extractSettingsBundleDefault("beacon_uuid") === variant.runtimeDefaults.beaconUUID, `${variant.id} Settings.bundle beacon UUID matches`);
      }
    }

      if (variant.platform === "android") {
      const settings = read("android/settings.gradle");
      const build = read(variant.buildFile);
      const manifestLabel = extractAndroidManifestLabel(variant.manifest);
      const mainActivity = read("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java");

      assert(settings.includes(`include '${variant.gradleModule}'`), `${variant.id} Gradle module is included`);
      assert(
        androidDocs.includes(`${variant.applicationId}/com.ilass.swifthtmlwebviewapp.MainActivity`),
        `${variant.id} Android docs include variant launch component`
      );
      assert(build.includes(`namespace '${variant.namespace}'`), `${variant.id} namespace matches`);
      assert(build.includes(`applicationId '${variant.applicationId}'`), `${variant.id} applicationId matches`);
      assert(build.includes("testImplementation 'junit:junit:4.13.2'"), `${variant.id} has JUnit test dependency`);
      assert(build.includes("testImplementation 'org.json:json:20240303'"), `${variant.id} has real JSON dependency for JVM payload tests`);

      if (manifestLabel.startsWith("@string/")) {
        const key = manifestLabel.slice("@string/".length);
        assert(extractAndroidStringValue(variant.labelResource, key) === variant.label, `${variant.id} label resource matches`);
      } else {
        assert(manifestLabel === variant.label, `${variant.id} manifest label matches`);
      }

      assert(
        !(variant.optionalModules || []).includes("stripe-terminal-tap-to-pay"),
        `${variant.id} does not keep product-selected Stripe Tap to Pay implementation in the open-source wrapper`
      );

      if (variant.runtimeDefaults) {
        if (variant.runtimeDefaults.serverURL) {
          const manifestDefault = extractAndroidMetaDataValue(variant.manifest, "com.ilass.DEFAULT_SERVER_URL");
          assert(manifestDefault === variant.runtimeDefaults.serverURL, `${variant.id} manifest server URL default matches`);
          assert(!mainActivity.includes(`DEFAULT_SERVER_URL = "${variant.runtimeDefaults.serverURL}"`), `${variant.id} server URL default stays out of shared MainActivity`);
        }
        if (variant.runtimeDefaults.securityToken) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.DEFAULT_SECURITY_TOKEN") === variant.runtimeDefaults.securityToken, `${variant.id} manifest security token default matches`);
        }
        if (variant.runtimeDefaults.beaconUUID) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.DEFAULT_BEACON_UUID") === variant.runtimeDefaults.beaconUUID, `${variant.id} manifest beacon UUID default matches`);
        }
        if (variant.runtimeDefaults.recoveryShortMark) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.RECOVERY_SHORT_MARK") === variant.runtimeDefaults.recoveryShortMark, `${variant.id} manifest recovery short mark matches`);
        }
        if (variant.runtimeDefaults.recoveryTitle) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.RECOVERY_TITLE") === variant.runtimeDefaults.recoveryTitle, `${variant.id} manifest recovery title matches`);
          assert(!mainActivity.includes(`<title>${variant.runtimeDefaults.recoveryTitle}</title>`), `${variant.id} recovery title stays out of shared MainActivity HTML`);
        }
        if (variant.runtimeDefaults.recoveryBody) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.RECOVERY_BODY") === variant.runtimeDefaults.recoveryBody, `${variant.id} manifest recovery body matches`);
          assert(!mainActivity.includes(variant.runtimeDefaults.recoveryBody), `${variant.id} recovery body stays out of shared MainActivity`);
        }
        if (variant.runtimeDefaults.recoverySuccessMessage) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.RECOVERY_SUCCESS_MESSAGE") === variant.runtimeDefaults.recoverySuccessMessage, `${variant.id} manifest recovery success message matches`);
          assert(!mainActivity.includes(variant.runtimeDefaults.recoverySuccessMessage), `${variant.id} recovery success message stays out of shared MainActivity`);
        }
        if (variant.runtimeDefaults.recoveryInvalidQRMessage) {
          assert(extractAndroidMetaDataValue(variant.manifest, "com.ilass.RECOVERY_INVALID_QR_MESSAGE") === variant.runtimeDefaults.recoveryInvalidQRMessage, `${variant.id} manifest recovery invalid QR message matches`);
          assert(!mainActivity.includes(variant.runtimeDefaults.recoveryInvalidQRMessage), `${variant.id} recovery invalid QR message stays out of shared MainActivity`);
        }
      }

      if (variant.id === "demo-android") {
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/DemoVariantTest.java", "appVariantDoesNotPullStripeTerminal"), `${variant.id} has identity and Stripe absence tests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/TapToPayBridgeHost.java", "interface TapToPayBridgeHost"), `${variant.id} exposes Tap to Pay host interface`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "getDeclaredConstructor(TapToPayBridgeHost.class)"), `${variant.id} loads optional Tap to Pay bridge through host interface`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java", "final class AndroidHostBridgePayload"), `${variant.id} has AndroidHostBridgePayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java", "static JSONObject baseResponse"), `${variant.id} AndroidHostBridgePayload owns host base responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java", "static JSONObject errorResponse"), `${variant.id} AndroidHostBridgePayload owns host error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java", "BridgeResponse.base("), `${variant.id} AndroidHostBridgePayload uses shared base envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java", "BridgeResponse.error("), `${variant.id} AndroidHostBridgePayload uses shared error envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidHostBridgePayload.errorResponse(source, action, error)"), `${variant.id} Tap to Pay host errors delegate to shared host payload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidHostBridgePayload.baseResponse(message, action)"), `${variant.id} host base responses delegate to shared host payload`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/DemoVariantTest.java", "tapToPayHostErrorsUseSharedBridgeErrorEnvelope"), `${variant.id} tests Tap to Pay host error envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayloadTest.java", "baseResponseUsesSharedBridgeEnvelope"), `${variant.id} tests Android host base response envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayloadTest.java", "errorResponseDefaultsMissingInputs"), `${variant.id} tests Android host error defaults`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayloadTest.java", "errorResponseUsesSharedBridgeErrorEnvelope"), `${variant.id} tests Android host error envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayload.java", "final class AndroidTapToPayPayload"), `${variant.id} has AndroidTapToPayPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayload.java", "static JSONObject availabilityUnavailable"), `${variant.id} AndroidTapToPayPayload owns no-Stripe availability responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayload.java", "static JSONObject collectUnavailable"), `${variant.id} AndroidTapToPayPayload owns no-Stripe collect errors`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayload.java", "BridgeResponse.base"), `${variant.id} AndroidTapToPayPayload uses shared base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayload.java", "BridgeResponse.error"), `${variant.id} AndroidTapToPayPayload uses shared error response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidTapToPayPayload.availabilityUnavailable"), `${variant.id} MainActivity delegates no-Stripe availability responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidTapToPayPayload.collectUnavailable"), `${variant.id} MainActivity delegates no-Stripe collect errors`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayloadTest.java", "availabilityUnavailableUsesContractEnvelope"), `${variant.id} tests Android no-Stripe Tap to Pay availability envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidTapToPayPayloadTest.java", "collectUnavailableUsesSharedErrorEnvelope"), `${variant.id} tests Android no-Stripe Tap to Pay collect error envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/StartupUrlResolver.java", "final class StartupUrlResolver"), `${variant.id} has pure startup URL resolver`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "StartupUrlResolver.candidates"), `${variant.id} AndroidSettingsStore delegates startup URL candidate resolution`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/StartupUrlResolverTest.java", "candidatesDeduplicateRemoteAndLocalUrls"), `${variant.id} tests startup URL candidate resolution`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "final class AndroidStartupLoadCoordinator"), `${variant.id} has AndroidStartupLoadCoordinator`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "LOAD_URL"), `${variant.id} AndroidStartupLoadCoordinator owns load URL commands`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "SHOW_RECOVERY"), `${variant.id} AndroidStartupLoadCoordinator owns recovery commands`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "Command start"), `${variant.id} AndroidStartupLoadCoordinator owns configured startup decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "Command mainFrameFailed"), `${variant.id} AndroidStartupLoadCoordinator owns main-frame failover decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinator.java", "Command timeout"), `${variant.id} AndroidStartupLoadCoordinator owns timeout failover decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "startupLoadCoordinator.start"), `${variant.id} MainActivity delegates configured startup decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "startupLoadCoordinator.mainFrameFailed"), `${variant.id} MainActivity delegates main-frame failover decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "startupLoadCoordinator.timeout"), `${variant.id} MainActivity delegates timeout failover decisions`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private final ArrayList<String> loadCandidates"), `${variant.id} startup candidate state stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "loadCandidateIndex"), `${variant.id} startup candidate index stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "showingRecoveryPage"), `${variant.id} recovery page state stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private boolean hasRemainingLoadCandidates"), `${variant.id} HA failover policy stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinatorTest.java", "mainFrameFailureAdvancesToNextHighAvailabilityCandidate"), `${variant.id} tests Android startup failover`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinatorTest.java", "lastFailureShowsRecoveryWithOriginalCandidateList"), `${variant.id} tests Android startup recovery state`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidStartupLoadCoordinatorTest.java", "reloadResetsCandidateIndexAndRecoveryState"), `${variant.id} tests Android startup reload reset`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", "final class AndroidCaptureResponseBuilder"), `${variant.id} has AndroidCaptureResponseBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", "static JSONObject documentPdf"), `${variant.id} AndroidCaptureResponseBuilder builds document PDF payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", "static JSONObject documentImages"), `${variant.id} AndroidCaptureResponseBuilder builds document image payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", "static JSONObject photo"), `${variant.id} AndroidCaptureResponseBuilder builds photo payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", "static String photoFormat"), `${variant.id} AndroidCaptureResponseBuilder owns photo format selection`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilder.java", `response.put("success", true);`), `${variant.id} AndroidCaptureResponseBuilder marks success payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidCaptureResponseBuilder.documentPdf"), `${variant.id} MainActivity delegates document PDF payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidCaptureResponseBuilder.documentImages"), `${variant.id} MainActivity delegates document image payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidCaptureResponseBuilder.photo"), `${variant.id} MainActivity delegates photo payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidCaptureResponseBuilder.photoFormat"), `${variant.id} MainActivity delegates photo format selection`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "String requestedFormat = pendingRequest.optString(\"outputType\""), `${variant.id} photo format selection stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilderTest.java", "documentPdfResponseUsesPdfDataField"), `${variant.id} tests Android document PDF payload field`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilderTest.java", "documentImageResponseDerivesPageCountAndJpegFormat"), `${variant.id} tests Android document image derived metadata`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilderTest.java", "photoFormatPrefersPngForBackgroundRemovalOrRequestedPng"), `${variant.id} tests Android photo format selection`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilderTest.java", `response.getBoolean("success")`), `${variant.id} tests Android capture success flag`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidCaptureResponseBuilderTest.java", "photoResponseIncludesBackgroundRemovalMetadata"), `${variant.id} tests Android photo metadata`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", "final class AndroidBarcodeResponseBuilder"), `${variant.id} has AndroidBarcodeResponseBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", "static JSONObject success"), `${variant.id} AndroidBarcodeResponseBuilder builds success payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", `response.put("success", true);`), `${variant.id} AndroidBarcodeResponseBuilder marks success payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", "static JSONObject configChanged"), `${variant.id} AndroidBarcodeResponseBuilder builds config-change payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", "static JSONObject recoveryApplied"), `${variant.id} AndroidBarcodeResponseBuilder builds recovery payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilder.java", "static String formatName"), `${variant.id} AndroidBarcodeResponseBuilder owns barcode format names`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandler.java", "final class AndroidBarcodeConfigHandler"), `${variant.id} has AndroidBarcodeConfigHandler`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandler.java", "static Result evaluate"), `${variant.id} AndroidBarcodeConfigHandler evaluates barcode config decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandler.java", "Kind.CONFIG_CHANGE"), `${variant.id} AndroidBarcodeConfigHandler owns config-change decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandler.java", "Kind.RECOVERY_SERVER_URL"), `${variant.id} AndroidBarcodeConfigHandler owns recovery URL decisions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBarcodeResponseBuilder.configChanged"), `${variant.id} MainActivity delegates barcode config-change payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBarcodeResponseBuilder.recoveryApplied"), `${variant.id} MainActivity delegates barcode recovery payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBarcodeResponseBuilder.success"), `${variant.id} MainActivity delegates barcode success payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBarcodeConfigHandler.evaluate"), `${variant.id} MainActivity delegates barcode config decisions`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private boolean tryApplyConfigQRCode"), `${variant.id} config QR decisions stay out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "\"changeConfig\".equals"), `${variant.id} config QR toolmode checks stay out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilderTest.java", "successResponseUsesCurrentScannerFields"), `${variant.id} tests Android barcode success payload field`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilderTest.java", `response.getBoolean("success")`), `${variant.id} tests Android barcode success flag`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeResponseBuilderTest.java", "recoveryAppliedResponseMarksPersistedServerUrl"), `${variant.id} tests Android barcode recovery payload`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandlerTest.java", "changeConfigRequiresSecurityTokenAndMapsDefaultServerUrl"), `${variant.id} tests Android config QR token and URL alias handling`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandlerTest.java", "recoverySourcePersistsServerUrlFromCode"), `${variant.id} tests Android recovery QR decision handling`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "final class AndroidContinuousScannerConfig"), `${variant.id} has AndroidContinuousScannerConfig`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "static AndroidContinuousScannerConfig from"), `${variant.id} AndroidContinuousScannerConfig normalizes requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "static JSONObject stopResponse"), `${variant.id} AndroidContinuousScannerConfig owns stop responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "static JSONObject errorResponse"), `${variant.id} AndroidContinuousScannerConfig owns error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "static JSONObject closedByUserResponse"), `${variant.id} AndroidContinuousScannerConfig owns closed-by-user responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfig.java", "static int[] barcodeFormats"), `${variant.id} AndroidContinuousScannerConfig owns scanner barcode formats`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerEventBuilder.java", "final class AndroidContinuousScannerEventBuilder"), `${variant.id} has AndroidContinuousScannerEventBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerEventBuilder.java", "static JSONObject event"), `${variant.id} AndroidContinuousScannerEventBuilder builds event payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/ContinuousBarcodeScannerController.java", "AndroidContinuousScannerConfig.from"), `${variant.id} ContinuousBarcodeScannerController delegates config normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/ContinuousBarcodeScannerController.java", "AndroidContinuousScannerConfig.barcodeFormats"), `${variant.id} ContinuousBarcodeScannerController delegates barcode format selection`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/ContinuousBarcodeScannerController.java", "AndroidContinuousScannerConfig.stopResponse"), `${variant.id} ContinuousBarcodeScannerController delegates stop responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/ContinuousBarcodeScannerController.java", "AndroidContinuousScannerEventBuilder.event"), `${variant.id} ContinuousBarcodeScannerController delegates scanner event payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidContinuousScannerConfig.errorResponse"), `${variant.id} MainActivity delegates continuous scanner error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidContinuousScannerConfig.closedByUserResponse"), `${variant.id} MainActivity delegates continuous scanner close responses`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "response.put(\"closedByUser\""), `${variant.id} continuous scanner closed-by-user payload stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfigTest.java", "loginScanDefaultsToLoginModeAndFrontCamera"), `${variant.id} tests Android continuous scanner login defaults`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfigTest.java", "stopResponseUsesRequestedActionAndCommonEnvelope"), `${variant.id} tests Android continuous scanner stop responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfigTest.java", "errorAndClosedByUserResponsesUseStreamControlShape"), `${variant.id} tests Android continuous scanner error and close responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerConfigTest.java", "barcodeFormatsDeduplicateAndSkipUnknownValues"), `${variant.id} tests Android scanner barcode format selection`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerEventBuilderTest.java", "dataEventUsesBarcodeDataAndSourceAction"), `${variant.id} tests Android continuous scanner data events`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerEventBuilderTest.java", "loginEventUsesBarcodeLogin"), `${variant.id} tests Android continuous scanner login events`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidContinuousScannerEventBuilderTest.java", "continuousScanStartUsesExplicitModeForEventAction"), `${variant.id} tests Android continuousScanStart mode-selected event action`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryConfigParser.java", "final class AndroidRecoveryConfigParser"), `${variant.id} has AndroidRecoveryConfigParser`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryConfigParser.java", "static String serverUrlFromCode"), `${variant.id} AndroidRecoveryConfigParser parses recovery QR codes`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryConfigParser.java", "static String serverUrlFromPayload"), `${variant.id} AndroidRecoveryConfigParser parses setting payload aliases`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBarcodeConfigHandler.java", "AndroidRecoveryConfigParser.serverUrlFromCode"), `${variant.id} AndroidBarcodeConfigHandler delegates recovery QR URL parsing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidRecoveryConfigParser.serverUrlFromPayload(request)"), `${variant.id} MainActivity delegates server URL persistence parsing`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String recoveryServerUrlFromCode"), `${variant.id} recovery QR parsing stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String normalizeRecoveryMobileUrl"), `${variant.id} recovery URL normalization stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryConfigParserTest.java", "parsesDirectServerUrlFromJsonAndAddsLink"), `${variant.id} tests Android recovery JSON URL parsing`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryConfigParserTest.java", "keepsExistingLinkAndRemovesFragment"), `${variant.id} tests Android recovery URL normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryPageBuilder.java", "final class AndroidRecoveryPageBuilder"), `${variant.id} has AndroidRecoveryPageBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryPageBuilder.java", "static String html"), `${variant.id} AndroidRecoveryPageBuilder builds recovery HTML`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryPageBuilder.java", "escapeJavaScriptString"), `${variant.id} AndroidRecoveryPageBuilder owns JS escaping`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidRecoveryPageBuilder.html"), `${variant.id} MainActivity delegates recovery page HTML`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidRecoveryPageBuilder.BASE_URL"), `${variant.id} MainActivity delegates recovery base URL`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String recoveryPageHtml"), `${variant.id} recovery HTML stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String escapeHtml"), `${variant.id} recovery HTML escaping stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryPageBuilderTest.java", "htmlUsesVariantBrandingAndEscapesText"), `${variant.id} tests Android recovery page branding and escaping`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidRecoveryPageBuilderTest.java", "htmlKeepsRecoveryBridgeActions"), `${variant.id} tests Android recovery page bridge actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridge.java", "final class AndroidSettingsBridge"), `${variant.id} has AndroidSettingsBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeDispatcher.java", "final class BridgeDispatcher"), `${variant.id} has BridgeDispatcher`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeDispatcher.java", "static String action"), `${variant.id} BridgeDispatcher extracts actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeDispatcher.java", "missingActionResponse"), `${variant.id} BridgeDispatcher handles missing actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeDispatcher.java", "unknownActionResponse"), `${variant.id} BridgeDispatcher handles unknown actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeRouter.java", "final class AndroidBridgeRouter"), `${variant.id} has AndroidBridgeRouter`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeRouter.java", "BridgeDispatcher.action"), `${variant.id} AndroidBridgeRouter delegates action extraction`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeRouter.java", "BridgeDispatcher.missingActionResponse"), `${variant.id} AndroidBridgeRouter delegates missing action response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeRouter.java", "BridgeDispatcher.unknownActionResponse"), `${variant.id} AndroidBridgeRouter delegates unknown action response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalog.java", "final class AndroidBridgeActionCatalog"), `${variant.id} has AndroidBridgeActionCatalog`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalog.java", "static final Set<String> PUBLIC_ACTIONS"), `${variant.id} AndroidBridgeActionCatalog records public bridge actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalog.java", "static final Set<String> INTERNAL_ACTIONS"), `${variant.id} AndroidBridgeActionCatalog records internal bridge actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalog.java", "static final Set<String> REGISTERED_ACTIONS"), `${variant.id} AndroidBridgeActionCatalog owns registered action set`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private AndroidBridgeRouter createBridgeRouter()"), `${variant.id} MainActivity registers bridge router actions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeActionCatalog.assertRegisteredActions(router.actions())"), `${variant.id} MainActivity checks router action registration against catalog`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeActionCatalog.CONTINUOUS_SCANNER_START_ACTIONS"), `${variant.id} MainActivity uses cataloged continuous scanner aliases`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeActionCatalog.AR_POSITION_ACTIONS"), `${variant.id} MainActivity uses cataloged AR unavailable aliases`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeActionCatalog.CONFIG_PAIRING_ACTIONS"), `${variant.id} MainActivity uses cataloged config pairing aliases`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "bridgeRouter.postMessage(rawMessage);"), `${variant.id} NativeBridge delegates postMessage to AndroidBridgeRouter`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeRouterTest.java", "postMessageRoutesKnownActions"), `${variant.id} AndroidBridgeRouter has unit tests`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeActionCatalogTest.java", "registeredActionsMatchCurrentAndroidBridgeSurface"), `${variant.id} AndroidBridgeActionCatalog has action surface tests`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/BridgeDispatcherTest.java", "unknownActionResponseEchoesUnknownAction"), `${variant.id} BridgeDispatcher has unit tests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilder.java", "final class AndroidBridgeShimBuilder"), `${variant.id} has AndroidBridgeShimBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilder.java", "static String bridgeShimScript"), `${variant.id} AndroidBridgeShimBuilder owns bridge shim script`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilder.java", "static String idleActivityShimScript"), `${variant.id} AndroidBridgeShimBuilder owns idle activity shim script`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilder.java", "window.webkit.messageHandlers.swiftBridge"), `${variant.id} AndroidBridgeShimBuilder keeps iOS-compatible bridge facade`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeShimBuilder.bridgeShimScript()"), `${variant.id} MainActivity delegates bridge shim script creation`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeShimBuilder.idleActivityShimScript()"), `${variant.id} MainActivity delegates idle shim script creation`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "window.webkit.messageHandlers.swiftBridge={postMessage:function(message){"), `${variant.id} Android bridge shim string stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "window.__swiftHTMLIdleShimInstalled=true;"), `${variant.id} Android idle shim string stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilderTest.java", "bridgeShimInstallsIosCompatiblePostMessageFacade"), `${variant.id} tests Android bridge shim facade`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeShimBuilderTest.java", "idleActivityShimInstallsOnceAndPostsIdleActivity"), `${variant.id} tests Android idle activity shim`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeResponse.java", "final class BridgeResponse"), `${variant.id} has BridgeResponse helper`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeResponse.java", "static JSONObject error"), `${variant.id} BridgeResponse has error response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/BridgeResponse.java", "static JSONObject unavailable"), `${variant.id} BridgeResponse has unavailable response`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private JSONObject errorResponse"), `${variant.id} MainActivity does not own private error envelope builder`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/DemoVariantTest.java", "mainActivityDoesNotOwnPrivateErrorEnvelopeBuilder"), `${variant.id} tests MainActivity does not own private error envelope builder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeScriptBuilder.java", "final class AndroidBridgeScriptBuilder"), `${variant.id} has AndroidBridgeScriptBuilder`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeScriptBuilder.java", "static String nativeResultScript"), `${variant.id} AndroidBridgeScriptBuilder owns native result script creation`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeScriptBuilder.java", "window.handleNativeResult"), `${variant.id} AndroidBridgeScriptBuilder targets handleNativeResult`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidBridgeScriptBuilder.nativeResultScript(payload)"), `${variant.id} MainActivity delegates native result script creation`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "if(window.handleNativeResult){window.handleNativeResult("), `${variant.id} native result script string stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeScriptBuilderTest.java", "nativeResultScriptWrapsPayloadForHandleNativeResult"), `${variant.id} tests Android bridge result script payloads`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBridgeScriptBuilderTest.java", "nativeResultScriptUsesJsonEscapingForStringValues"), `${variant.id} tests Android bridge result script JSON escaping`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNativeCommandPayload.java", "final class AndroidNativeCommandPayload"), `${variant.id} has AndroidNativeCommandPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNativeCommandPayload.java", "static JSONObject reloadResponse"), `${variant.id} AndroidNativeCommandPayload owns reload responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNativeCommandPayload.java", "static JSONObject launchConfettiResponse"), `${variant.id} AndroidNativeCommandPayload owns launchConfetti responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidNativeCommandPayload.reloadResponse"), `${variant.id} MainActivity delegates reload native command payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidNativeCommandPayload.launchConfettiResponse"), `${variant.id} MainActivity delegates launchConfetti native command payloads`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNativeCommandPayloadTest.java", "launchConfettiResponseUsesNativeCommandEnvelopeAndMetadata"), `${variant.id} tests Android launchConfetti native command response`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNativeCommandPayloadTest.java", "reloadResponseUsesNativeCommandEnvelope"), `${variant.id} tests Android reload native command response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridge.java", "BridgeResponse.base"), `${variant.id} AndroidSettingsBridge uses BridgeResponse base`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridge.java", "BridgeResponse.error"), `${variant.id} AndroidSettingsBridge uses BridgeResponse error`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "return AndroidHostBridgePayload.baseResponse(message, action);"), `${variant.id} MainActivity baseResponse delegates to host payload`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/BridgeResponseTest.java", "unavailableResponseMarksAvailability"), `${variant.id} BridgeResponse has unit tests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridge.java", "final class AndroidUnavailableBridge"), `${variant.id} has AndroidUnavailableBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridge.java", "static JSONObject arPosition"), `${variant.id} AndroidUnavailableBridge handles AR position unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridge.java", "static JSONObject roomPlan"), `${variant.id} AndroidUnavailableBridge handles RoomPlan unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridge.java", "static JSONObject arGuided"), `${variant.id} AndroidUnavailableBridge handles guided AR unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridge.java", "static JSONObject arOverlay"), `${variant.id} AndroidUnavailableBridge handles AR overlay unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidUnavailableBridge.arPosition(message)"), `${variant.id} MainActivity delegates AR position unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidUnavailableBridge.roomPlan(message)"), `${variant.id} MainActivity delegates RoomPlan unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidUnavailableBridge.arGuided(message)"), `${variant.id} MainActivity delegates guided AR unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidUnavailableBridge.arOverlay(message)"), `${variant.id} MainActivity delegates AR overlay unavailable responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridgeTest.java", "arPositionUnavailableUsesRequestActionAndCommonShape"), `${variant.id} tests AR position unavailable response shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridgeTest.java", "roomPlanUnavailableUsesRoomPlanSource"), `${variant.id} tests RoomPlan unavailable response shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridgeTest.java", "arGuidedUnavailableUsesGuidedSource"), `${variant.id} tests guided AR unavailable response shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidUnavailableBridgeTest.java", "arOverlayUnavailableUsesOverlaySourceAndDefaultAction"), `${variant.id} tests AR overlay unavailable response shape`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceCapabilities.java", "final class AndroidDeviceCapabilities"), `${variant.id} has AndroidDeviceCapabilities`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceCapabilities.java", "static JSONObject build"), `${variant.id} AndroidDeviceCapabilities builds capability payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceCapabilities.java", "tapToPayIncluded"), `${variant.id} AndroidDeviceCapabilities accepts runtime Tap to Pay availability`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceCapabilities.build"), `${variant.id} MainActivity delegates device capabilities`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceCapabilitiesTest.java", "buildKeepsCommonWrapperCapabilitiesEnabled"), `${variant.id} tests Android common device capabilities`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceCapabilitiesTest.java", "buildReflectsRuntimeOptionalModules"), `${variant.id} tests Android runtime optional capabilities`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "final class AndroidPermissionPolicy"), `${variant.id} has AndroidPermissionPolicy`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static String[] cameraPermissions"), `${variant.id} AndroidPermissionPolicy owns camera permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static String[] locationPermissions"), `${variant.id} AndroidPermissionPolicy owns location permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static String[] beaconScanPermissions"), `${variant.id} AndroidPermissionPolicy owns beacon scan permissions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static String[] beaconAdvertisePermissions"), `${variant.id} AndroidPermissionPolicy owns beacon advertise permissions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static String[] configPairingPermissions"), `${variant.id} AndroidPermissionPolicy owns config pairing permissions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicy.java", "static boolean allGranted"), `${variant.id} AndroidPermissionPolicy owns permission grant checks`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidPermissionPolicy.cameraPermissions()"), `${variant.id} MainActivity delegates camera permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidPermissionPolicy.locationPermissions()"), `${variant.id} MainActivity delegates location permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidPermissionPolicy.beaconScanPermissions"), `${variant.id} MainActivity delegates beacon scan permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidPermissionPolicy.beaconAdvertisePermissions"), `${variant.id} MainActivity delegates beacon advertise permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidPermissionPolicy.configPairingPermissions"), `${variant.id} MainActivity delegates config pairing permission requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconBridge.java", "AndroidPermissionPolicy.beaconScanPermissions"), `${variant.id} AndroidBeaconBridge delegates required permissions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconAdvertiserBridge.java", "AndroidPermissionPolicy.beaconAdvertisePermissions"), `${variant.id} AndroidBeaconAdvertiserBridge delegates required permissions`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String[] beaconPermissions"), `${variant.id} beacon permission policy stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String[] beaconAdvertisePermissions"), `${variant.id} beacon advertiser permission policy stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String[] configPairingPermissions"), `${variant.id} config pairing permission policy stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "new String[]{Manifest.permission.CAMERA}"), `${variant.id} camera permission arrays stay out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicyTest.java", "commonPermissionSetsStayCentralized"), `${variant.id} tests Android common permission sets`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicyTest.java", "beaconScanPermissionsRequireLocationAndModernBluetoothScanRights"), `${variant.id} tests Android beacon scan permissions`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPermissionPolicyTest.java", "configPairingPermissionsMatchActionAndSdkRequirements"), `${variant.id} tests Android config pairing permissions`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "final class AndroidDeviceInfoPayload"), `${variant.id} has AndroidDeviceInfoPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject response"), `${variant.id} AndroidDeviceInfoPayload owns device info responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject configPairingDeviceSummary"), `${variant.id} AndroidDeviceInfoPayload owns config pairing device summaries`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject battery"), `${variant.id} AndroidDeviceInfoPayload owns battery diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject screen"), `${variant.id} AndroidDeviceInfoPayload owns screen diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject memory"), `${variant.id} AndroidDeviceInfoPayload owns memory diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject camera"), `${variant.id} AndroidDeviceInfoPayload owns camera diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "static JSONObject sensor"), `${variant.id} AndroidDeviceInfoPayload owns sensor diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayload.java", "BridgeResponse.base"), `${variant.id} AndroidDeviceInfoPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.response"), `${variant.id} MainActivity delegates device info responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.configPairingDeviceSummary"), `${variant.id} MainActivity delegates config pairing device summaries`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.battery"), `${variant.id} MainActivity delegates battery diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.screen"), `${variant.id} MainActivity delegates screen diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.memory"), `${variant.id} MainActivity delegates memory diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.camera"), `${variant.id} MainActivity delegates camera diagnostics`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidDeviceInfoPayload.sensor"), `${variant.id} MainActivity delegates sensor diagnostics`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "baseResponse(message, \"deviceInfoGet\")"), `${variant.id} device info base response stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "info.put(\"manufacturer\""), `${variant.id} config pairing device summary payload stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "info.put(\"powerSource\""), `${variant.id} battery diagnostics payload stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "screen.put(\"widthPixels\""), `${variant.id} screen diagnostics payload stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "memory.put(\"totalBytes\""), `${variant.id} memory diagnostics payload stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "camera.put(\"lensFacing\""), `${variant.id} camera diagnostics payload stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "item.put(\"maximumRange\""), `${variant.id} sensor diagnostics payload stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "responseUsesDiagnosticsEnvelopeAndRuntimeSnapshots"), `${variant.id} tests Android device info response envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "responseKeepsStableKeysWhenSnapshotValuesAreMissing"), `${variant.id} tests Android device info stable empty shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "configPairingDeviceSummaryUsesStableRuntimeShape"), `${variant.id} tests Android config pairing device summary shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "batteryPayloadCalculatesPercentChargingAndPowerSource"), `${variant.id} tests Android battery diagnostics payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "screenPayloadUsesDisplayMetricsShape"), `${variant.id} tests Android screen diagnostics payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "memoryPayloadUsesRuntimeMemoryShape"), `${variant.id} tests Android memory diagnostics payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "cameraPayloadNormalizesLensFacingValues"), `${variant.id} tests Android camera diagnostics payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidDeviceInfoPayloadTest.java", "sensorPayloadUsesStableDiagnosticsShape"), `${variant.id} tests Android sensor diagnostics payload shape`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayload.java", "final class AndroidSoundPayload"), `${variant.id} has AndroidSoundPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayload.java", "static Request request"), `${variant.id} AndroidSoundPayload owns sound request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayload.java", "static JSONObject response"), `${variant.id} AndroidSoundPayload owns sound responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayload.java", "BridgeResponse.base"), `${variant.id} AndroidSoundPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidSoundPayload.request"), `${variant.id} MainActivity delegates sound request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidSoundPayload.response"), `${variant.id} MainActivity delegates sound responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayloadTest.java", "requestClampsFrequencyDurationAndVolume"), `${variant.id} tests Android sound request normalization`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSoundPayloadTest.java", "responseUsesNativeCommandEnvelopeAndEchoesNormalizedValues"), `${variant.id} tests Android sound response envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayload.java", "final class AndroidScreenshotPayload"), `${variant.id} has AndroidScreenshotPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayload.java", "static Request request"), `${variant.id} AndroidScreenshotPayload owns screenshot request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayload.java", "static JSONObject response"), `${variant.id} AndroidScreenshotPayload owns screenshot responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayload.java", "BridgeResponse.base"), `${variant.id} AndroidScreenshotPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidScreenshotPayload.request"), `${variant.id} MainActivity delegates screenshot request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidScreenshotPayload.response"), `${variant.id} MainActivity delegates screenshot responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayloadTest.java", "requestClampsMaxWidthAndQuality"), `${variant.id} tests Android screenshot request normalization`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenshotPayloadTest.java", "responseUsesDiagnosticsEnvelopeAndImageMetadata"), `${variant.id} tests Android screenshot response envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayload.java", "final class AndroidBeaconPayload"), `${variant.id} has AndroidBeaconPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayload.java", "static JSONObject beaconsEvent"), `${variant.id} AndroidBeaconPayload owns beacon event payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayload.java", "static BeaconAdvertiseConfig advertiseConfigFrom"), `${variant.id} AndroidBeaconPayload owns beacon advertise request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayload.java", "static JSONObject advertiseStateEvent"), `${variant.id} AndroidBeaconPayload owns beacon advertise state events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayload.java", "BridgeResponse.base"), `${variant.id} AndroidBeaconPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconBridge.java", "AndroidBeaconPayload.rangingStartResponse"), `${variant.id} AndroidBeaconBridge delegates ranging start payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconBridge.java", "AndroidBeaconPayload.beaconsEvent"), `${variant.id} AndroidBeaconBridge delegates beacon event payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconAdvertiserBridge.java", "AndroidBeaconPayload.advertiseConfigFrom"), `${variant.id} AndroidBeaconAdvertiserBridge delegates advertise request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconAdvertiserBridge.java", "AndroidBeaconPayload.advertiseStateEvent"), `${variant.id} AndroidBeaconAdvertiserBridge delegates advertise state events`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconBridge.java", "private static JSONObject baseResponse"), `${variant.id} beacon ranging base response stays out of AndroidBeaconBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconAdvertiserBridge.java", "private static JSONObject baseResponse"), `${variant.id} beacon advertiser base response stays out of AndroidBeaconAdvertiserBridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayloadTest.java", "advertiseConfigAcceptsAliasesDefaultsAndNormalizesUuid"), `${variant.id} tests Android beacon advertise config aliases`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidBeaconPayloadTest.java", "beaconEventUsesCatalogedPayloadShapeAndLegacyMap"), `${variant.id} tests Android beacon event shape`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "final class AndroidPrinterBridge"), `${variant.id} has AndroidPrinterBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "final class AndroidPrinterPayload"), `${variant.id} has AndroidPrinterPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "BridgeResponse.base"), `${variant.id} AndroidPrinterPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "BridgeResponse.unavailable"), `${variant.id} AndroidPrinterPayload uses shared unavailable response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static String selectedPrinterKind"), `${variant.id} AndroidPrinterPayload owns printer kind routing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static String selectedPrinterLabel"), `${variant.id} AndroidPrinterPayload owns printer label routing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static final class EpsonHelloWorldRequest"), `${variant.id} AndroidPrinterPayload owns Epson request model`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static EpsonHelloWorldRequest epsonHelloWorldRequest"), `${variant.id} AndroidPrinterPayload owns Epson request parsing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject discoveryOptions"), `${variant.id} AndroidPrinterPayload owns printer discovery options`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject discoveryUnavailableResponse"), `${variant.id} AndroidPrinterPayload owns printer discovery unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject discoveryResponse"), `${variant.id} AndroidPrinterPayload owns printer discovery responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static void appendSunmiInternalPrinter"), `${variant.id} AndroidPrinterPayload owns Sunmi discovery entries`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject printercoreUnavailableResponse"), `${variant.id} AndroidPrinterPayload owns printercore unavailable responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject epsonJobResponse"), `${variant.id} AndroidPrinterPayload owns Epson job responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayload.java", "static JSONObject sunmiJobResponse"), `${variant.id} AndroidPrinterPayload owns Sunmi job responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.selectedPrinterKind"), `${variant.id} AndroidPrinterBridge delegates printer kind routing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.selectedPrinterLabel"), `${variant.id} AndroidPrinterBridge delegates printer label routing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.epsonHelloWorldRequest"), `${variant.id} AndroidPrinterBridge delegates Epson request parsing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.discoveryOptions"), `${variant.id} AndroidPrinterBridge delegates printer discovery options`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.discoveryUnavailableResponse"), `${variant.id} AndroidPrinterBridge delegates discovery unavailable payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.discoveryResponse"), `${variant.id} AndroidPrinterBridge delegates discovery response payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.appendSunmiInternalPrinter"), `${variant.id} AndroidPrinterBridge delegates Sunmi discovery entries`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.printercoreUnavailableResponse"), `${variant.id} AndroidPrinterBridge delegates printercore unavailable payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.epsonJobResponse"), `${variant.id} AndroidPrinterBridge delegates Epson job responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "AndroidPrinterPayload.sunmiJobResponse"), `${variant.id} AndroidPrinterBridge delegates Sunmi job responses`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "\"printercore.aar is not linked in this build.\""), `${variant.id} printercore unavailable message stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "host.baseResponse(request, \"printerDiscover\")"), `${variant.id} printer discovery base response stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "private static void copyFields"), `${variant.id} printer discovery field copying stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "sunmiPrinter.put"), `${variant.id} Sunmi discovery object shape stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "response.put(\"host\", hostAddress)"), `${variant.id} Epson job host payload stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "response.put(\"printerKind\", \"epson_epos_xml\")"), `${variant.id} Epson job printer metadata stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "request.optString(\"host\""), `${variant.id} Epson host parsing stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "request.optString(\"devid\""), `${variant.id} Epson devid parsing stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "request.optLong(\"timeoutMs\""), `${variant.id} Epson timeout parsing stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "response.put(\"printerKind\", \"sunmi_internal\")"), `${variant.id} Sunmi job printer metadata stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "response.put(\"provider\", \"android_aidl\")"), `${variant.id} Sunmi job provider metadata stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "private void putSunmiOutcome"), `${variant.id} Sunmi outcome payload shaping stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "static JSONObject buildDiscoveryOptions"), `${variant.id} printer discovery options stay out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "hasDiscoveryTargets"), `${variant.id} printer discovery target detection stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "static String selectedPrinterKind"), `${variant.id} printer kind routing stays out of AndroidPrinterBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterBridge.java", "static String selectedPrinterLabel"), `${variant.id} printer label routing stays out of AndroidPrinterBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "printerBridge::printHelloWorld"), `${variant.id} MainActivity delegates printerHelloWorld`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "printerBridge::discoverPrinters"), `${variant.id} MainActivity delegates printerDiscover`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private void printHelloWorld"), `${variant.id} printer action implementation stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "PRINTERCORE_CLASS_NAME"), `${variant.id} printercore reflection stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "SunmiPrintOutcome"), `${variant.id} Sunmi printer implementation stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "discoveryOptionsAddsLocalCidrsOnlyWhenNoTargetsAreProvided"), `${variant.id} tests Android printer discovery options`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "selectedPrinterKindUsesDirectNestedAndDefaultEpson"), `${variant.id} tests Android printer kind routing`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "selectedPrinterLabelUsesNestedLabelOrFallback"), `${variant.id} tests Android printer label routing`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "epsonHelloWorldRequestTrimsAndDefaultsFields"), `${variant.id} tests Android Epson request parsing`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "discoveryResponseMergesCoreFieldsAndVersion"), `${variant.id} tests Android printer discovery response envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "appendSunmiInternalPrinterAddsOnlyOneConfirmedLocalPrinter"), `${variant.id} tests Android Sunmi discovery entry`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "discoveryUnavailableResponseUsesStablePrintercoreEnvelope"), `${variant.id} tests Android printer discovery unavailable envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "printercoreUnavailableResponseMarksKindAndAvailability"), `${variant.id} tests Android printercore unavailable envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "epsonJobResponseMergesCoreFieldsAndBackfillsError"), `${variant.id} tests Android Epson job response envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidPrinterPayloadTest.java", "sunmiJobResponseUsesAidlProviderMetadataAndOutcomeFields"), `${variant.id} tests Android Sunmi job response envelope`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenOrientationBridge.java", "final class AndroidScreenOrientationBridge"), `${variant.id} has AndroidScreenOrientationBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenOrientationBridge.java", "static OrientationRequest orientationRequest"), `${variant.id} AndroidScreenOrientationBridge owns orientation mode mapping`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "screenOrientationBridge.get(message)"), `${variant.id} MainActivity delegates screenOrientationGet`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "screenOrientationBridge.set(message)"), `${variant.id} MainActivity delegates screenOrientationSet`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private JSONObject screenOrientationGet"), `${variant.id} screen orientation get stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "SCREEN_ORIENTATION_SENSOR_PORTRAIT"), `${variant.id} screen orientation mapping stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenOrientationBridgeTest.java", "orientationRequestMapsKnownModes"), `${variant.id} tests Android orientation mode mapping`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenOrientationBridgeTest.java", "setAppliesRequestedOrientationAndReturnsMode"), `${variant.id} tests Android orientation set response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "final class AndroidIdleTimerBridge"), `${variant.id} has AndroidIdleTimerBridge`);
        assert(fileExists("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayload.java"), `${variant.id} has AndroidIdleTimerPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayload.java", "static long timeoutMillis"), `${variant.id} AndroidIdleTimerPayload owns idle timer normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayload.java", "static JSONObject startResponse"), `${variant.id} AndroidIdleTimerPayload owns start responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayload.java", "static JSONObject event"), `${variant.id} AndroidIdleTimerPayload owns idle timer event payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "AndroidIdleTimerPayload.timeoutMillis"), `${variant.id} AndroidIdleTimerBridge delegates idle timer normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "AndroidIdleTimerPayload.startResponse"), `${variant.id} AndroidIdleTimerBridge delegates idle timer start responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "AndroidIdleTimerPayload.stopResponse"), `${variant.id} AndroidIdleTimerBridge delegates idle timer stop responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "AndroidIdleTimerPayload.resetResponse"), `${variant.id} AndroidIdleTimerBridge delegates idle timer reset responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "AndroidIdleTimerPayload.event"), `${variant.id} AndroidIdleTimerBridge delegates idle timer event payloads`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "BridgeResponse.base"), `${variant.id} idle timer base responses stay out of AndroidIdleTimerBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridge.java", "event.put(\"action\""), `${variant.id} idle timer event payload assembly stays out of AndroidIdleTimerBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "idleTimerBridge.start(message)"), `${variant.id} MainActivity delegates idleTimerStart`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "idleTimerBridge.recordActivity()"), `${variant.id} MainActivity delegates idle activity tracking`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private JSONObject startIdleTimer"), `${variant.id} idle timer start implementation stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "idleTimedOut"), `${variant.id} idle timeout state stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayloadTest.java", "startResponseClampsAndUsesCommonEnvelope"), `${variant.id} tests Android idle timer payload start response`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerPayloadTest.java", "eventsUseCatalogedPayloadShape"), `${variant.id} tests Android idle timer event payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridgeTest.java", "startClampsTimeoutAndIntervalAndSchedulesTick"), `${variant.id} tests Android idle timer start response`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidIdleTimerBridgeTest.java", "tickEmitsIdleTickAndSingleTimeout"), `${variant.id} tests Android idle timeout events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "final class AndroidNotificationPayload"), `${variant.id} has AndroidNotificationPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject permissionError"), `${variant.id} AndroidNotificationPayload owns permission errors`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject permissionStatusResponse"), `${variant.id} AndroidNotificationPayload owns permission status responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject permissionRequestResponse"), `${variant.id} AndroidNotificationPayload owns permission request responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject showResponse"), `${variant.id} AndroidNotificationPayload owns show responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject scheduleResponse"), `${variant.id} AndroidNotificationPayload owns schedule responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject cancelResponse"), `${variant.id} AndroidNotificationPayload owns cancel responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject cancelAllResponse"), `${variant.id} AndroidNotificationPayload owns cancel-all responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject listResponse"), `${variant.id} AndroidNotificationPayload owns list responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject notificationPayload"), `${variant.id} AndroidNotificationPayload owns notification payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONArray idsFromRequest"), `${variant.id} AndroidNotificationPayload owns notification cancel IDs`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayload.java", "static JSONObject openedEvent"), `${variant.id} AndroidNotificationPayload owns opened events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.permissionStatusResponse"), `${variant.id} AndroidNotificationBridge delegates permission status responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.permissionRequestResponse"), `${variant.id} AndroidNotificationBridge delegates permission request responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.showResponse"), `${variant.id} AndroidNotificationBridge delegates show responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.scheduleResponse"), `${variant.id} AndroidNotificationBridge delegates schedule responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.cancelResponse"), `${variant.id} AndroidNotificationBridge delegates cancel responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.cancelAllResponse"), `${variant.id} AndroidNotificationBridge delegates cancel-all responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.listResponse"), `${variant.id} AndroidNotificationBridge delegates list responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.notificationPayload"), `${variant.id} AndroidNotificationBridge delegates notification payloads`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "private JSONObject baseResponse"), `${variant.id} notification base response stays out of AndroidNotificationBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "AndroidNotificationPayload.baseResponse"), `${variant.id} notification command response assembly stays out of AndroidNotificationBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "response.put(\"success\""), `${variant.id} notification response field assembly stays out of AndroidNotificationBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationBridge.java", "private JSONArray idsFromRequest"), `${variant.id} notification ID parsing stays out of AndroidNotificationBridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayloadTest.java", "permissionResponsesUseCommonBridgeShape"), `${variant.id} tests Android notification permission envelopes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayloadTest.java", "commandResponsesUseCommonBridgeShape"), `${variant.id} tests Android notification command envelopes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayloadTest.java", "listResponseWrapsPendingAndDeliveredArrays"), `${variant.id} tests Android notification list envelopes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayloadTest.java", "notificationPayloadNormalizesFallbacksAndData"), `${variant.id} tests Android notification payload defaults`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNotificationPayloadTest.java", "openedEventWrapsNotificationAndDataPayloads"), `${variant.id} tests Android notification opened events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "final class AndroidLocationPayload"), `${variant.id} has AndroidLocationPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "static JSONObject response"), `${variant.id} AndroidLocationPayload owns location responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "static JSONObject startResponse"), `${variant.id} AndroidLocationPayload owns location stream start responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "static JSONObject stopResponse"), `${variant.id} AndroidLocationPayload owns location stream stop responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "static JSONObject errorResponse"), `${variant.id} AndroidLocationPayload owns location error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "static JSONObject locationObject"), `${variant.id} AndroidLocationPayload owns location objects`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "BridgeResponse.base"), `${variant.id} AndroidLocationPayload uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayload.java", "BridgeResponse.error"), `${variant.id} AndroidLocationPayload uses shared bridge error response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidLocationPayload.response"), `${variant.id} MainActivity delegates location response payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidLocationPayload.startResponse"), `${variant.id} MainActivity delegates location stream start responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidLocationPayload.stopResponse"), `${variant.id} MainActivity delegates location stream stop responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidLocationPayload.errorResponse"), `${variant.id} MainActivity delegates location error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidLocationPayload.locationObject"), `${variant.id} MainActivity delegates location object payloads`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "payload.put(\"latitude\""), `${variant.id} location payload field mapping stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "baseResponse(request, \"geoLocationStart\")"), `${variant.id} location start envelope stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "baseResponse(message, \"geoLocationStop\")"), `${variant.id} location stop envelope stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "BridgeResponse.error(request, \"geoLocationStart\""), `${variant.id} location start error envelope stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayloadTest.java", "responseWrapsLocationInCommonBridgeEnvelope"), `${variant.id} tests Android location response envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayloadTest.java", "startResponseUsesStreamControlEnvelopeAndOptionalLastLocation"), `${variant.id} tests Android location stream start envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayloadTest.java", "stopResponseUsesStreamControlEnvelope"), `${variant.id} tests Android location stream stop envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayloadTest.java", "errorResponseUsesCommonBridgeEnvelope"), `${variant.id} tests Android location error envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidLocationPayloadTest.java", "locationObjectUsesJsonNullForMissingOptionalSignals"), `${variant.id} tests Android location optional nulls`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayload.java", "final class AndroidScreenStreamPayload"), `${variant.id} has AndroidScreenStreamPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayload.java", "static StreamRequest streamRequest"), `${variant.id} AndroidScreenStreamPayload owns stream request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayload.java", "static JSONObject startAck"), `${variant.id} AndroidScreenStreamPayload owns start acknowledgements`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayload.java", "static JSONObject stats"), `${variant.id} AndroidScreenStreamPayload owns stats events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamBridge.java", "AndroidScreenStreamPayload.streamRequest"), `${variant.id} AndroidScreenStreamBridge delegates stream request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamBridge.java", "AndroidScreenStreamPayload.startAck"), `${variant.id} AndroidScreenStreamBridge delegates start acknowledgements`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamBridge.java", "AndroidScreenStreamPayload.stats"), `${variant.id} AndroidScreenStreamBridge delegates stats events`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamBridge.java", "private JSONObject response"), `${variant.id} screen stream response builder stays out of AndroidScreenStreamBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamBridge.java", "private int clamp"), `${variant.id} screen stream normalization stays out of AndroidScreenStreamBridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayloadTest.java", "streamRequestNormalizesAliasesAndClampsValues"), `${variant.id} tests Android screen stream request normalization`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidScreenStreamPayloadTest.java", "metaEventsAndStatsUseCatalogedEventShapes"), `${variant.id} tests Android screen stream event shapes`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayload.java", "final class AndroidSensorPayload"), `${variant.id} has AndroidSensorPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayload.java", "static JSONObject sensorDataEvent"), `${variant.id} AndroidSensorPayload owns sensor data events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayload.java", "static int sensorTypeFromString"), `${variant.id} AndroidSensorPayload owns sensor type aliases`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayload.java", "static String sensorTypeName"), `${variant.id} AndroidSensorPayload owns sensor type names`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "AndroidSensorPayload.sensorInfo"), `${variant.id} AndroidSensorBridge delegates capability payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "AndroidSensorPayload.streamStartResponse"), `${variant.id} AndroidSensorBridge delegates stream start payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "AndroidSensorPayload.sensorDataEvent"), `${variant.id} AndroidSensorBridge delegates sensor data events`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "AndroidSensorPayload.errorResponse"), `${variant.id} AndroidSensorBridge delegates sensor errors`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "private JSONObject baseResponse"), `${variant.id} sensor base response stays out of AndroidSensorBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSensorBridge.java", "private int sensorTypeFromString"), `${variant.id} sensor type alias mapping stays out of AndroidSensorBridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayloadTest.java", "sensorTypeMappingAcceptsAliasesAndUnknowns"), `${variant.id} tests Android sensor type aliases`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSensorPayloadTest.java", "sensorDataEventUsesCatalogedPayloadShape"), `${variant.id} tests Android sensor data event shape`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "final class AndroidNfcPayload"), `${variant.id} has AndroidNfcPayload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static JSONObject tagPayload"), `${variant.id} AndroidNfcPayload owns tag payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static JSONObject nfcAPayload"), `${variant.id} AndroidNfcPayload owns NfcA detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static JSONObject isoDepPayload"), `${variant.id} AndroidNfcPayload owns IsoDep detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static JSONObject mifareClassicPayload"), `${variant.id} AndroidNfcPayload owns Mifare detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static JSONObject recordPayload"), `${variant.id} AndroidNfcPayload owns NDEF record payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayload.java", "static String decodeTextRecord"), `${variant.id} AndroidNfcPayload owns text record decoding`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.tagPayload"), `${variant.id} AndroidNfcTagReaderBridge delegates tag payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.nfcAPayload"), `${variant.id} AndroidNfcTagReaderBridge delegates NfcA detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.isoDepPayload"), `${variant.id} AndroidNfcTagReaderBridge delegates IsoDep detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.mifareClassicPayload"), `${variant.id} AndroidNfcTagReaderBridge delegates Mifare detail payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.recordPayload"), `${variant.id} AndroidNfcTagReaderBridge delegates record payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "AndroidNfcPayload.errorResponse"), `${variant.id} AndroidNfcTagReaderBridge delegates error payloads`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "private JSONObject baseResponse"), `${variant.id} NFC base response stays out of AndroidNfcTagReaderBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "info.put(\"atqaHex\""), `${variant.id} NFC technology detail fields stay out of AndroidNfcTagReaderBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "info.put(\"historicalBytesHex\""), `${variant.id} NFC IsoDep detail fields stay out of AndroidNfcTagReaderBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "private String decodeTextRecord"), `${variant.id} NFC text decoding stays out of AndroidNfcTagReaderBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidNfcTagReaderBridge.java", "Base64.encodeToString"), `${variant.id} NFC base64 encoding stays out of AndroidNfcTagReaderBridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayloadTest.java", "tagPayloadNormalizesIdentifierAndTechnologies"), `${variant.id} tests Android NFC tag payloads`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayloadTest.java", "technologyDetailPayloadsUseStableFieldNames"), `${variant.id} tests Android NFC technology detail payloads`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidNfcPayloadTest.java", "textRecordDecodesLanguageAndUtf8Text"), `${variant.id} tests Android NFC text record decoding`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "final class AndroidWifiBridge"), `${variant.id} has AndroidWifiBridge`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "static ConfigureRequest configureRequest"), `${variant.id} AndroidWifiBridge owns Wi-Fi request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "static JSONObject statusPayload"), `${variant.id} AndroidWifiBridge owns Wi-Fi status payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "static JSONObject configureErrorResponse"), `${variant.id} AndroidWifiBridge owns Wi-Fi configure errors`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "static JSONObject addNetworksResultResponse"), `${variant.id} AndroidWifiBridge owns Android 11 Wi-Fi dialog response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridge.java", "static String quoteWifiValue"), `${variant.id} AndroidWifiBridge owns legacy Wi-Fi quoting`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidWifiBridge.configureRequest"), `${variant.id} MainActivity delegates Wi-Fi request normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidWifiBridge.statusPayload"), `${variant.id} MainActivity delegates Wi-Fi status payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidWifiBridge.statusResponse"), `${variant.id} MainActivity delegates Wi-Fi status responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidWifiBridge.configureErrorResponse"), `${variant.id} MainActivity delegates Wi-Fi configure errors`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidWifiBridge.networkSuggestionResponse"), `${variant.id} MainActivity delegates Android 10 Wi-Fi response`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "BridgeResponse.error(request, \"wifiConfigure\""), `${variant.id} Wi-Fi configure error envelope stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String quoteWifiValue"), `${variant.id} Wi-Fi legacy quoting stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "network.put(\"ssidAvailable\""), `${variant.id} Wi-Fi status payload shape stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private String sanitizeWifiSsid"), `${variant.id} Wi-Fi SSID sanitizing stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "private boolean isRealWifiSsid"), `${variant.id} Wi-Fi SSID availability rules stay out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "putServerUrlPersistence(response, request)"), `${variant.id} Wi-Fi server URL persistence response markers stay out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "configureRequestFallsBackToPasswordAndMarksPersistedServerUrl"), `${variant.id} tests Android Wi-Fi provisioning URL persistence`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "configureErrorResponseUsesCommonErrorShape"), `${variant.id} tests Android Wi-Fi configure error envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "networkSuggestionAndLegacyResponsesKeepMethodSpecificFields"), `${variant.id} tests Android Wi-Fi method-specific responses`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "statusPayloadReportsMissingWifiServiceWithStableDefaults"), `${variant.id} tests Android Wi-Fi missing-service status payload`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "statusPayloadRedactsSsidWhenPermissionIsMissing"), `${variant.id} tests Android Wi-Fi SSID redaction payload`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidWifiBridgeTest.java", "statusPayloadExposesConnectedWifiDetailsAndSecurity"), `${variant.id} tests Android Wi-Fi connected status payload`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "final class AndroidConfigPairingProtocol"), `${variant.id} has AndroidConfigPairingProtocol`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static String pairingPayload"), `${variant.id} AndroidConfigPairingProtocol owns pairing payload construction`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject commandFromRequest"), `${variant.id} AndroidConfigPairingProtocol owns config command construction`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject internalRequest"), `${variant.id} AndroidConfigPairingProtocol owns internal UI requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject showResponse"), `${variant.id} AndroidConfigPairingProtocol owns show responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject acknowledgementResponse"), `${variant.id} AndroidConfigPairingProtocol owns acknowledgement responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject connectResponse"), `${variant.id} AndroidConfigPairingProtocol owns connect responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject sendResponse"), `${variant.id} AndroidConfigPairingProtocol owns send responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject errorResponse"), `${variant.id} AndroidConfigPairingProtocol owns error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static JSONObject unknownActionResponse"), `${variant.id} AndroidConfigPairingProtocol owns unknown action responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "BridgeResponse.base"), `${variant.id} AndroidConfigPairingProtocol uses shared bridge base response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "BridgeResponse.error"), `${variant.id} AndroidConfigPairingProtocol uses shared bridge error response`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static final class PairingTarget"), `${variant.id} AndroidConfigPairingProtocol owns pairing target parsing`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocol.java", "static final class ChunkAccumulator"), `${variant.id} AndroidConfigPairingProtocol owns chunk reassembly state`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.pairingPayload"), `${variant.id} AndroidConfigPairingBridge delegates pairing payload construction`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.commandFromRequest"), `${variant.id} AndroidConfigPairingBridge delegates config command construction`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidConfigPairingProtocol.internalRequest"), `${variant.id} MainActivity delegates config pairing internal requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.showResponse"), `${variant.id} AndroidConfigPairingBridge delegates show responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.acknowledgementResponse"), `${variant.id} AndroidConfigPairingBridge delegates acknowledgement responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.connectResponse"), `${variant.id} AndroidConfigPairingBridge delegates connect responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.sendResponse"), `${variant.id} AndroidConfigPairingBridge delegates send responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "AndroidConfigPairingProtocol.errorResponse"), `${variant.id} AndroidConfigPairingBridge delegates error responses`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidConfigPairingProtocol.unknownActionResponse(request)"), `${variant.id} MainActivity delegates unknown config pairing errors`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "private static final class PairingTarget"), `${variant.id} pairing target parsing stays out of AndroidConfigPairingBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "private static final class ChunkAccumulator"), `${variant.id} chunk accumulator stays out of AndroidConfigPairingBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "private JSONObject baseResponse"), `${variant.id} config pairing base response stays out of AndroidConfigPairingBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingBridge.java", "private JSONObject errorResponse"), `${variant.id} config pairing error response stays out of AndroidConfigPairingBridge`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "Unknown config pairing action:"), `${variant.id} unknown config pairing error copy stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "request.put(\"action\", \"configPairingShow\""), `${variant.id} config pairing internal show request stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "new JSONObject().put(\"action\", \"configPairingStop\")"), `${variant.id} config pairing internal stop request stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "pairingPayloadRoundTripsIdentityFields"), `${variant.id} tests Android config pairing payload roundtrip`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "bridgeResponsesUseSharedEnvelopeAndTargetIdentity"), `${variant.id} tests Android config pairing response envelopes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "sendAndErrorResponsesUseSharedEnvelope"), `${variant.id} tests Android config pairing send/error envelopes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "unknownActionResponseUsesSharedEnvelope"), `${variant.id} tests Android config pairing unknown action envelope`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "chunkAccumulatorReassemblesOutOfOrderPayloads"), `${variant.id} tests Android config pairing chunk reassembly`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidConfigPairingProtocolTest.java", "internalRequestUsesActionAndOptionalSource"), `${variant.id} tests Android config pairing internal requests`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "AndroidSettingsBridge.Host"), `${variant.id} MainActivity exposes settings bridge host`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "settingsBridge.getResponse"), `${variant.id} MainActivity delegates settingsGet`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "settingsBridge.setResponse"), `${variant.id} MainActivity delegates settingsSet`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridge.java", "static JSONObject snapshotPayload"), `${variant.id} AndroidSettingsBridge owns settings snapshot payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "final class AndroidSettingsStore"), `${variant.id} has AndroidSettingsStore`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "JSONObject snapshotPayload"), `${variant.id} AndroidSettingsStore owns settings snapshot reads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "JSONObject apply"), `${variant.id} AndroidSettingsStore owns settings writes`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "putDeviceUUIDSetting"), `${variant.id} AndroidSettingsStore owns device UUID normalization`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java", "StartupUrlResolver.resolveStartUrl"), `${variant.id} AndroidSettingsStore owns startup URL resolution`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "settingsStore().snapshotPayload()"), `${variant.id} MainActivity delegates settings snapshot payloads`);
        assert(contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "settingsStore().apply(values)"), `${variant.id} MainActivity delegates settings writes`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "securityToken is required for settingsSet."), `${variant.id} settings token validation stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "settings.put(\"securityTokenSet\""), `${variant.id} settings snapshot payload shape stays out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "putStringSetting"), `${variant.id} settings alias writes stay out of MainActivity`);
        assert(!contains("android/app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java", "putDeviceUUIDSetting"), `${variant.id} device UUID normalization stays out of MainActivity`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridgeTest.java", "settingsSetAppliesNestedSettingsWhenTokenMatches"), `${variant.id} tests Android settings bridge`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridgeTest.java", "settingsSnapshotUsesPublicConfigShapeWithoutTokenValue"), `${variant.id} tests Android settings snapshot payload shape`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStoreTest.java", "applySettingsUsesAliasesAndNormalizesValues"), `${variant.id} tests Android settings alias writes`);
        assert(contains("android/app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStoreTest.java", "snapshotUsesDefaultsAndGeneratesMissingDeviceUuid"), `${variant.id} tests Android settings defaults and UUID generation`);
      }
    }
  }
}

function runVariantVerification() {
  const variants = readJSON("docs/app-variants.json");
  const implemented = variants.variants.filter((variant) => variant.status === "implemented");

  for (const variant of implemented) {
    for (const key of ["build", "test"]) {
      const command = variant.verification && variant.verification[key];
      if (!isNonEmptyString(command)) {
        fail(`${variant.id} has no ${key} verification command`);
        continue;
      }
      console.log(`\nRunning ${variant.id} ${key}: ${command}`);
      try {
        execSync(command, {
          cwd: root,
          stdio: "inherit",
          shell: "/bin/zsh"
        });
      } catch (error) {
        fail(`${variant.id} ${key} verification command failed`);
      }
    }
  }
}

function main() {
  const runVerification = process.argv.includes("--run-verification");

  validateContract();
  validateVariants();

  if (failures > 0) {
    console.error(`\n${failures} validation failure(s).`);
    process.exit(1);
  }

  console.log("\nContract validation passed.");

  if (runVerification) {
    runVariantVerification();
    if (failures > 0) {
      console.error(`\n${failures} validation failure(s).`);
      process.exit(1);
    }
    console.log("\nVariant verification passed.");
  }
}

main();
