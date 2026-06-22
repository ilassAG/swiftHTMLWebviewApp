package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.junit.Test;

public class DemoVariantTest {
    @Test
    public void appIdentityMatchesDemoVariant() throws IOException {
        Path root = androidRoot();
        String settings = read(root.resolve("settings.gradle"));
        String build = read(root.resolve("app/build.gradle"));
        String manifest = read(root.resolve("app/src/main/AndroidManifest.xml"));
        String strings = read(root.resolve("app/src/main/res/values/strings.xml"));

        assertTrue(settings.contains("include ':app'"));
        assertTrue(build.contains("namespace 'com.ilass.swifthtmlwebviewapp'"));
        assertTrue(build.contains("applicationId 'com.ilass.swifthtmlwebviewapp'"));
        assertTrue(manifest.contains("android:label=\"@string/app_name\""));
        assertTrue(manifest.contains("android:allowBackup=\"false\""));
        assertTrue(manifest.contains("android:usesCleartextTraffic=\"true\""));
        assertTrue(strings.contains("<string name=\"app_name\">swiftHTMLWebviewApp</string>"));
    }

    @Test
    public void appVariantDoesNotPullStripeTerminal() throws IOException {
        Path root = androidRoot();
        String build = read(root.resolve("app/build.gradle"));

        assertFalse(build.contains("com.stripe:stripeterminal"));
        assertFalse(Files.exists(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/StripeTapToPayBridge.java")));
    }

    @Test
    public void sharedSourcesExposeNarrowTapToPayHostInterface() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));
        String host = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/TapToPayBridgeHost.java"));

        assertTrue(mainActivity.contains("implements ConfettiView.ActivityHost, TapToPayBridgeHost"));
        assertTrue(mainActivity.contains("getDeclaredConstructor(TapToPayBridgeHost.class)"));
        assertTrue(host.contains("interface TapToPayBridgeHost"));
        assertTrue(host.contains("Context applicationContext()"));
        assertTrue(host.contains("boolean hasSystemFeature(String featureName)"));
        assertTrue(host.contains("JSONObject baseResponse(JSONObject message, String action)"));
    }

    @Test
    public void tapToPayHostErrorsUseSharedBridgeErrorEnvelope() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));
        String payload = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidHostBridgePayload.java"));

        assertTrue(mainActivity.contains("AndroidHostBridgePayload.errorResponse(source, action, error)"));
        assertTrue(payload.contains("BridgeResponse.error("));
    }

    @Test
    public void mainActivityDoesNotOwnPrivateErrorEnvelopeBuilder() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));

        assertFalse(mainActivity.contains("private JSONObject errorResponse"));
        assertFalse(mainActivity.contains("baseResponse(request, action)"));
        assertFalse(mainActivity.contains("BridgeResponse.base(message, action)"));
    }

    @Test
    public void startupUrlResolutionLivesOutsideMainActivity() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));
        String resolver = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/StartupUrlResolver.java"));
        String settingsStore = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java"));
        String resolverTest = read(root.resolve("app/src/test/java/com/ilass/swifthtmlwebviewapp/StartupUrlResolverTest.java"));

        assertTrue(mainActivity.contains("settingsStore().configuredStartUrl"));
        assertTrue(mainActivity.contains("settingsStore().startUrlCandidates"));
        assertTrue(settingsStore.contains("StartupUrlResolver.resolveStartUrl"));
        assertTrue(settingsStore.contains("StartupUrlResolver.candidates"));
        assertTrue(resolver.contains("final class StartupUrlResolver"));
        assertTrue(resolverTest.contains("candidatesDeduplicateRemoteAndLocalUrls"));
    }

    @Test
    public void settingsBridgeLivesOutsideMainActivity() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));
        String bridge = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridge.java"));
        String store = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStore.java"));
        String bridgeTest = read(root.resolve("app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsBridgeTest.java"));
        String storeTest = read(root.resolve("app/src/test/java/com/ilass/swifthtmlwebviewapp/AndroidSettingsStoreTest.java"));

        assertTrue(mainActivity.contains("implements ConfettiView.ActivityHost, TapToPayBridgeHost, AndroidSettingsBridge.Host"));
        assertTrue(mainActivity.contains("settingsBridge = new AndroidSettingsBridge(this)"));
        assertTrue(mainActivity.contains("settingsBridge.getResponse(message)"));
        assertTrue(mainActivity.contains("settingsBridge.setResponse(message)"));
        assertTrue(mainActivity.contains("settingsStore().snapshotPayload()"));
        assertTrue(mainActivity.contains("settingsStore().apply(values)"));
        assertTrue(bridge.contains("final class AndroidSettingsBridge"));
        assertTrue(bridge.contains("JSONObject getResponse"));
        assertTrue(bridge.contains("JSONObject setResponse"));
        assertTrue(store.contains("final class AndroidSettingsStore"));
        assertTrue(store.contains("JSONObject snapshotPayload"));
        assertTrue(store.contains("JSONObject apply"));
        assertTrue(bridgeTest.contains("settingsSetAppliesNestedSettingsWhenTokenMatches"));
        assertTrue(storeTest.contains("applySettingsUsesAliasesAndNormalizesValues"));
        assertFalse(mainActivity.contains("securityToken is required for settingsSet."));
        assertFalse(mainActivity.contains("putStringSetting"));
    }

    @Test
    public void runtimeDefaultsAreDeclaredAsVariantMetadata() throws IOException {
        Path root = androidRoot();
        String manifest = read(root.resolve("app/src/main/AndroidManifest.xml"));
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));

        assertTrue(manifest.contains("android:name=\"com.ilass.DEFAULT_SERVER_URL\""));
        assertTrue(manifest.contains("android:value=\"local\""));
        assertTrue(manifest.contains("android:name=\"com.ilass.DEFAULT_SECURITY_TOKEN\""));
        assertTrue(manifest.contains("android:value=\"\""));
        assertTrue(manifest.contains("android:name=\"com.ilass.DEFAULT_BEACON_UUID\""));
        assertTrue(manifest.contains("android:value=\"00000000-0000-0000-0000-000000000000\""));
        assertTrue(manifest.contains("android:name=\"com.ilass.RECOVERY_SHORT_MARK\""));
        assertTrue(manifest.contains("android:value=\"SW\""));
        assertTrue(manifest.contains("android:name=\"com.ilass.RECOVERY_TITLE\""));
        assertTrue(manifest.contains("android:value=\"swiftHTMLWebviewApp\""));
        assertTrue(mainActivity.contains("META_DEFAULT_SERVER_URL"));
        assertTrue(mainActivity.contains("META_DEFAULT_SECURITY_TOKEN"));
        assertTrue(mainActivity.contains("META_DEFAULT_BEACON_UUID"));
        assertTrue(mainActivity.contains("META_RECOVERY_SHORT_MARK"));
        assertTrue(mainActivity.contains("META_RECOVERY_TITLE"));
        assertFalse(mainActivity.contains("DEFAULT_SERVER_URL = \"https://example.invalid/mobile/\""));
        assertFalse(mainActivity.contains("<title>swiftHTMLWebviewApp Verbindung</title>"));
        assertFalse(mainActivity.contains("<div class=\\\"mark\\\">SW</div>"));
    }

    @Test
    public void configPairingTokenGateRequiresStoredAndIncomingToken() throws IOException {
        Path root = androidRoot();
        String mainActivity = read(root.resolve("app/src/main/java/com/ilass/swifthtmlwebviewapp/MainActivity.java"));

        assertTrue(mainActivity.contains("String storedToken = configSecurityToken();"));
        assertTrue(mainActivity.contains("String incomingToken = token != null ? token.trim() : \"\";"));
        assertTrue(mainActivity.contains("!storedToken.isEmpty() && !incomingToken.isEmpty() && storedToken.equals(incomingToken)"));
        assertTrue(mainActivity.contains("DEFAULT_SECURITY_TOKEN = \"\""));
    }

    private static Path androidRoot() {
        Path current = Paths.get("").toAbsolutePath();
        while (current != null) {
            if (Files.exists(current.resolve("settings.gradle")) && Files.exists(current.resolve("app/build.gradle"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("Could not locate Android project root from " + Paths.get("").toAbsolutePath());
    }

    private static String read(Path path) throws IOException {
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }
}
