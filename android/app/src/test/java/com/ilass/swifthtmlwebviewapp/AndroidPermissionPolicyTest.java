package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertArrayEquals;

import android.Manifest;
import android.os.Build;

import org.junit.Test;

public class AndroidPermissionPolicyTest {
    @Test
    public void commonPermissionSetsStayCentralized() {
        assertArrayEquals(
                new String[]{Manifest.permission.CAMERA},
                AndroidPermissionPolicy.cameraPermissions()
        );
        assertArrayEquals(
                new String[]{
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                },
                AndroidPermissionPolicy.locationPermissions()
        );
        assertArrayEquals(
                new String[]{Manifest.permission.ACCESS_FINE_LOCATION},
                AndroidPermissionPolicy.tapToPayLocationPermissions()
        );
    }

    @Test
    public void notificationPermissionOnlyAppliesOnAndroid13Plus() {
        assertArrayEquals(
                new String[]{},
                AndroidPermissionPolicy.notificationPermissions(Build.VERSION_CODES.S)
        );
        assertArrayEquals(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                AndroidPermissionPolicy.notificationPermissions(Build.VERSION_CODES.TIRAMISU)
        );
    }

    @Test
    public void beaconScanPermissionsRequireLocationAndModernBluetoothScanRights() {
        assertArrayEquals(
                new String[]{Manifest.permission.ACCESS_FINE_LOCATION},
                AndroidPermissionPolicy.beaconScanPermissions(Build.VERSION_CODES.R)
        );

        assertArrayEquals(
                new String[]{
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.BLUETOOTH_SCAN,
                        Manifest.permission.BLUETOOTH_CONNECT
                },
                AndroidPermissionPolicy.beaconScanPermissions(Build.VERSION_CODES.S)
        );
    }

    @Test
    public void beaconAdvertisePermissionsOnlyRequireRuntimeBluetoothRightsOnAndroid12Plus() {
        assertArrayEquals(
                new String[]{},
                AndroidPermissionPolicy.beaconAdvertisePermissions(Build.VERSION_CODES.R)
        );

        assertArrayEquals(
                new String[]{
                        Manifest.permission.BLUETOOTH_ADVERTISE,
                        Manifest.permission.BLUETOOTH_CONNECT
                },
                AndroidPermissionPolicy.beaconAdvertisePermissions(Build.VERSION_CODES.S)
        );
    }

    @Test
    public void configPairingPermissionsMatchActionAndSdkRequirements() {
        assertArrayEquals(
                new String[]{Manifest.permission.ACCESS_FINE_LOCATION},
                AndroidPermissionPolicy.configPairingPermissions("configPairingConnect", Build.VERSION_CODES.R)
        );
        assertArrayEquals(
                new String[]{Manifest.permission.CAMERA},
                AndroidPermissionPolicy.configPairingPermissions("configPairingShow", Build.VERSION_CODES.R)
        );

        assertArrayEquals(
                new String[]{
                        Manifest.permission.CAMERA,
                        Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_SCAN,
                        Manifest.permission.BLUETOOTH_ADVERTISE
                },
                AndroidPermissionPolicy.configPairingPermissions("configPairingShow", Build.VERSION_CODES.S)
        );
        assertArrayEquals(
                new String[]{Manifest.permission.BLUETOOTH_CONNECT},
                AndroidPermissionPolicy.configPairingPermissions("configPairingSend", Build.VERSION_CODES.S)
        );
        assertArrayEquals(
                new String[]{},
                AndroidPermissionPolicy.configPairingPermissions("configPairingStop", Build.VERSION_CODES.S)
        );
        assertArrayEquals(
                new String[]{},
                AndroidPermissionPolicy.configPairingPermissions("configPairingDisconnect", Build.VERSION_CODES.S)
        );
    }
}
