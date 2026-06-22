package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class AndroidBeaconPayloadTest {
    @Test
    public void advertiseConfigAcceptsAliasesDefaultsAndNormalizesUuid() throws Exception {
        JSONObject request = new JSONObject()
                .put("requestId", "req-beacon")
                .put("beaconUuid", "7763a937-b779-4d31-a20c-49e83047048f")
                .put("major", 7)
                .put("minor", 9)
                .put("txPower", -65);

        AndroidBeaconPayload.BeaconAdvertiseConfig config = AndroidBeaconPayload.advertiseConfigFrom(request);

        assertNotNull(config);
        assertEquals("7763A937-B779-4D31-A20C-49E83047048F", config.uuid);
        assertEquals(7, config.major);
        assertEquals(9, config.minor);
        assertEquals(-65, config.measuredPower);

        AndroidBeaconPayload.BeaconAdvertiseConfig defaults = AndroidBeaconPayload.advertiseConfigFrom(new JSONObject());
        assertNotNull(defaults);
        assertEquals(AndroidBeaconPayload.DEFAULT_BEACON_UUID, defaults.uuid);
        assertEquals(AndroidBeaconPayload.DEFAULT_MAJOR, defaults.major);
        assertEquals(AndroidBeaconPayload.DEFAULT_MINOR, defaults.minor);
        assertEquals(AndroidBeaconPayload.DEFAULT_TX_POWER, defaults.measuredPower);
    }

    @Test
    public void advertiseConfigRejectsInvalidUuidMajorMinorAndPower() throws Exception {
        assertNull(AndroidBeaconPayload.advertiseConfigFrom(new JSONObject().put("uuid", "not-a-uuid")));
        assertNull(AndroidBeaconPayload.advertiseConfigFrom(new JSONObject().put("major", -1)));
        assertNull(AndroidBeaconPayload.advertiseConfigFrom(new JSONObject().put("minor", 65536)));
        assertNull(AndroidBeaconPayload.advertiseConfigFrom(new JSONObject().put("measuredPower", -128)));
        assertNull(AndroidBeaconPayload.advertiseConfigFrom(new JSONObject().put("measuredPowerDbm", 21)));
    }

    @Test
    public void rangingStartStopAndAdvertiseResponsesUseCommonBridgeShape() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-beacon");
        String uuid = "7763a937-b779-4d31-a20c-49e83047048f";
        AndroidBeaconPayload.BeaconAdvertiseConfig config = AndroidBeaconPayload.advertiseConfigFrom(
                new JSONObject().put("uuid", uuid)
        );

        JSONObject rangingStart = AndroidBeaconPayload.rangingStartResponse(request, uuid);
        assertEquals("android", rangingStart.getString("platform"));
        assertEquals("beaconsStart", rangingStart.getString("action"));
        assertEquals("req-beacon", rangingStart.getString("requestId"));
        assertTrue(rangingStart.getBoolean("success"));
        assertEquals("7763A937-B779-4D31-A20C-49E83047048F", rangingStart.getString("uuid"));
        assertEquals(AndroidBeaconPayload.RANGING_PROVIDER, rangingStart.getString("provider"));

        JSONObject rangingStop = AndroidBeaconPayload.rangingStopResponse(request);
        assertEquals("beaconsStop", rangingStop.getString("action"));
        assertTrue(rangingStop.getBoolean("success"));

        JSONObject advertiseStart = AndroidBeaconPayload.advertiseStartResponse(request, config, "starting");
        assertEquals("beaconAdvertiseStart", advertiseStart.getString("action"));
        assertEquals(AndroidBeaconPayload.ADVERTISER_PROVIDER, advertiseStart.getString("provider"));
        assertEquals("starting", advertiseStart.getString("state"));
        assertFalse(advertiseStart.getBoolean("advertising"));
        assertEquals(-59, advertiseStart.getInt("measuredPower"));

        JSONObject advertiseStop = AndroidBeaconPayload.advertiseStopResponse(request);
        assertEquals("beaconAdvertiseStop", advertiseStop.getString("action"));
        assertEquals("stopped", advertiseStop.getString("state"));
        assertTrue(advertiseStop.getBoolean("success"));
    }

    @Test
    public void beaconEventUsesCatalogedPayloadShapeAndLegacyMap() throws Exception {
        JSONObject beacon = AndroidBeaconPayload.beaconObject(
                "7763a937-b779-4d31-a20c-49e83047048f",
                10,
                20,
                "near",
                2.25,
                -71,
                1500L
        );
        JSONArray beacons = new JSONArray().put(beacon);
        JSONObject legacyMap = new JSONObject().put("20", beacon);

        JSONObject event = AndroidBeaconPayload.beaconsEvent(
                "7763a937-b779-4d31-a20c-49e83047048f",
                beacons,
                legacyMap,
                1710000000123L
        );

        assertEquals("android", event.getString("platform"));
        assertEquals("beacons", event.getString("action"));
        assertTrue(event.getBoolean("success"));
        assertEquals(1, event.getInt("count"));
        assertEquals("7763A937-B779-4D31-A20C-49E83047048F", event.getString("uuid"));
        assertEquals("7763A937-B779-4D31-A20C-49E83047048F", event.getJSONArray("beacons").getJSONObject(0).getString("proximityUUID"));
        assertEquals(10, event.getJSONArray("beacons").getJSONObject(0).getInt("major"));
        assertEquals(20, event.getJSONObject("legacyBeacons").getJSONObject("20").getInt("minor"));
        assertEquals(1.5, event.getJSONArray("beacons").getJSONObject(0).getDouble("age"), 0.001);
        assertTrue(event.getString("timestamp").startsWith("2024-03-09T"));
    }

    @Test
    public void advertiseStateAndErrorResponsesUseCommonShape() throws Exception {
        JSONObject request = new JSONObject().put("requestId", "req-adv");
        AndroidBeaconPayload.BeaconAdvertiseConfig config = AndroidBeaconPayload.advertiseConfigFrom(
                new JSONObject().put("uuid", AndroidBeaconPayload.DEFAULT_BEACON_UUID)
        );

        JSONObject state = AndroidBeaconPayload.advertiseStateEvent(
                request,
                config,
                false,
                "advertisingFailed",
                false,
                "BLE advertising failed."
        );

        assertEquals("beaconAdvertiseStart", state.getString("action"));
        assertEquals("req-adv", state.getString("requestId"));
        assertFalse(state.getBoolean("success"));
        assertEquals("advertisingFailed", state.getString("state"));
        assertEquals("BLE advertising failed.", state.getString("error"));

        JSONObject error = AndroidBeaconPayload.errorResponse(request, "beaconAdvertiseStart", "Invalid iBeacon parameters.");
        assertEquals("android", error.getString("platform"));
        assertEquals("beaconAdvertiseStart", error.getString("action"));
        assertFalse(error.getBoolean("success"));
        assertEquals("Invalid iBeacon parameters.", error.getString("error"));
    }

    @Test
    public void rangingUuidAndProximityNormalizeFallbacks() throws Exception {
        assertEquals(AndroidBeaconPayload.DEFAULT_BEACON_UUID, AndroidBeaconPayload.rangingUUID(new JSONObject()));
        assertEquals(AndroidBeaconPayload.DEFAULT_BEACON_UUID, AndroidBeaconPayload.rangingUUID(new JSONObject().put("uuid", "bad")));
        assertEquals("7763A937-B779-4D31-A20C-49E83047048F", AndroidBeaconPayload.rangingUUID(
                new JSONObject().put("uuid", "7763a937-b779-4d31-a20c-49e83047048f")
        ));

        assertEquals("unknown", AndroidBeaconPayload.proximityLabel(-1));
        assertEquals("immediate", AndroidBeaconPayload.proximityLabel(0.5));
        assertEquals("near", AndroidBeaconPayload.proximityLabel(3.0));
        assertEquals("far", AndroidBeaconPayload.proximityLabel(3.1));
    }
}
