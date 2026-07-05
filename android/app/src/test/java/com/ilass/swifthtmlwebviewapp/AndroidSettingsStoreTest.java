package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.json.JSONObject;
import org.junit.Test;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

public class AndroidSettingsStoreTest {
    @Test
    public void snapshotUsesDefaultsAndGeneratesMissingDeviceUuid() throws Exception {
        MemoryPreferences preferences = new MemoryPreferences();
        AndroidSettingsStore store = new AndroidSettingsStore(
                preferences,
                "https://default.example.invalid/app/",
                "default-token",
                "D57092AC-DFAA-446C-8EF3-C81AA22815B5"
        );

        JSONObject snapshot = store.snapshotPayload();
        String appUUID = snapshot.getString("appUUID");
        String uuid = snapshot.getString("deviceUUID");

        assertEquals("https://default.example.invalid/app/", snapshot.getString("serverURL"));
        assertTrue(snapshot.getBoolean("securityTokenSet"));
        assertEquals("D57092AC-DFAA-446C-8EF3-C81AA22815B5", snapshot.getString("beaconUUID"));
        assertEquals(5, snapshot.getInt("highAvailabilityTimeoutSeconds"));
        assertFalse(appUUID.isEmpty());
        assertEquals(appUUID, UUID.fromString(appUUID).toString().toUpperCase(Locale.US));
        assertEquals(appUUID, preferences.strings.get(AndroidSettingsStore.APP_UUID_KEY));
        assertFalse(uuid.isEmpty());
        assertEquals(uuid, UUID.fromString(uuid).toString().toUpperCase(Locale.US));
        assertEquals(uuid, preferences.strings.get(AndroidSettingsStore.DEVICE_UUID_KEY));
    }

    @Test
    public void appUuidPersistsAndCannotBeChangedBySettings() throws Exception {
        MemoryPreferences preferences = new MemoryPreferences();
        AndroidSettingsStore store = new AndroidSettingsStore(
                preferences,
                "https://default.example.invalid/app/",
                "default-token",
                "default-beacon"
        );

        String originalAppUUID = store.snapshotPayload().getString("appUUID");
        String replacementUUID = "11111111-2222-3333-4444-555555555555";
        JSONObject snapshot = store.apply(new JSONObject()
                .put("appUUID", replacementUUID)
                .put("appUuid", replacementUUID)
                .put("app_uuid", replacementUUID));

        assertFalse(originalAppUUID.equals(replacementUUID));
        assertEquals(originalAppUUID, snapshot.getString("appUUID"));
        assertEquals(originalAppUUID, preferences.strings.get(AndroidSettingsStore.APP_UUID_KEY));
    }

    @Test
    public void applySettingsUsesAliasesAndNormalizesValues() throws Exception {
        MemoryPreferences preferences = new MemoryPreferences();
        AndroidSettingsStore store = new AndroidSettingsStore(
                preferences,
                "https://default.example.invalid/app/",
                "default-token",
                "default-beacon"
        );

        JSONObject snapshot = store.apply(new JSONObject()
                .put("mobileUrl", " https://mobile.example.invalid/app/ ")
                .put("haURL2", " https://ha2.example.invalid/app/ ")
                .put("beacon_uuid", " beacon-one ")
                .put("name", " Demo Tablet 03 ")
                .put("uuid", "not-a-uuid")
                .put("location", " Eingang ")
                .put("securityToken", " rotated-token ")
                .put("ha_enabled", "ja")
                .put("ha_timeout", "0")
                .put("appConfig", new JSONObject()
                        .put("siteKey", "Demo Site")
                        .put("terminalId", "A1")));

        assertEquals("https://mobile.example.invalid/app/", snapshot.getString("serverURL"));
        assertEquals("https://ha2.example.invalid/app/", snapshot.getString("highAvailabilityURL2"));
        assertEquals("beacon-one", snapshot.getString("beaconUUID"));
        assertEquals("Demo Tablet 03", snapshot.getString("deviceName"));
        assertEquals("Eingang", snapshot.getString("deviceLocation"));
        assertTrue(snapshot.getBoolean("highAvailabilityEnabled"));
        assertEquals(1, snapshot.getInt("highAvailabilityTimeoutSeconds"));
        assertEquals("Demo Site", snapshot.getJSONObject("appConfig").getString("siteKey"));
        assertEquals("A1", snapshot.getJSONObject("appConfig").getString("terminalId"));
        assertEquals("rotated-token", store.securityToken());
        assertEquals(
                snapshot.getString("deviceUUID"),
                UUID.fromString(snapshot.getString("deviceUUID")).toString().toUpperCase(Locale.US)
        );
    }

    @Test
    public void appConfigMergesAssociativeStoreValues() throws Exception {
        MemoryPreferences preferences = new MemoryPreferences();
        AndroidSettingsStore store = new AndroidSettingsStore(
                preferences,
                "https://default.example.invalid/app/",
                "default-token",
                "default-beacon"
        );

        store.apply(new JSONObject().put("appConfig", new JSONObject()
                .put("siteKey", "Demo Site")
                .put("terminalId", "A1")));
        JSONObject snapshot = store.apply(new JSONObject().put("store", new JSONObject()
                .put("terminalId", "A2")
                .put("mode", "counter")));

        assertEquals("Demo Site", snapshot.getJSONObject("appConfig").getString("siteKey"));
        assertEquals("A2", snapshot.getJSONObject("appConfig").getString("terminalId"));
        assertEquals("counter", snapshot.getJSONObject("appConfig").getString("mode"));
    }

    @Test
    public void invalidIntegerSettingsAreIgnored() throws Exception {
        MemoryPreferences preferences = new MemoryPreferences();
        preferences.ints.put(AndroidSettingsStore.HA_TIMEOUT_KEY, 12);
        AndroidSettingsStore store = new AndroidSettingsStore(
                preferences,
                "https://default.example.invalid/app/",
                "",
                "default-beacon"
        );

        JSONObject snapshot = store.apply(new JSONObject().put("highAvailabilityTimeoutSeconds", "soon"));

        assertEquals(12, snapshot.getInt("highAvailabilityTimeoutSeconds"));
    }

    private static final class MemoryPreferences implements AndroidSettingsStore.Preferences {
        final Map<String, String> strings = new HashMap<>();
        final Map<String, Boolean> booleans = new HashMap<>();
        final Map<String, Integer> ints = new HashMap<>();

        @Override
        public String getString(String key, String fallback) {
            return strings.containsKey(key) ? strings.get(key) : fallback;
        }

        @Override
        public boolean getBoolean(String key, boolean fallback) {
            return booleans.containsKey(key) ? booleans.get(key) : fallback;
        }

        @Override
        public int getInt(String key, int fallback) {
            return ints.containsKey(key) ? ints.get(key) : fallback;
        }

        @Override
        public Editor edit() {
            return new Editor() {
                @Override
                public Editor putString(String key, String value) {
                    strings.put(key, value);
                    return this;
                }

                @Override
                public Editor putBoolean(String key, boolean value) {
                    booleans.put(key, value);
                    return this;
                }

                @Override
                public Editor putInt(String key, int value) {
                    ints.put(key, value);
                    return this;
                }

                @Override
                public void apply() {
                    // Memory writes are immediate.
                }
            };
        }
    }
}
