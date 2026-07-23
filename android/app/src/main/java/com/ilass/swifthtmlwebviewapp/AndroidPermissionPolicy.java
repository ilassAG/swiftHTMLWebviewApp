package com.ilass.swifthtmlwebviewapp;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.content.ContextCompat;

import java.util.ArrayList;

final class AndroidPermissionPolicy {
    private AndroidPermissionPolicy() {
    }

    static String[] cameraPermissions() {
        return new String[]{Manifest.permission.CAMERA};
    }

    static String[] locationPermissions() {
        return new String[]{
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
        };
    }

    static String[] tapToPayLocationPermissions() {
        return new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
    }

    static String[] notificationPermissions(int sdkInt) {
        if (sdkInt < Build.VERSION_CODES.TIRAMISU) {
            return new String[0];
        }
        return new String[]{Manifest.permission.POST_NOTIFICATIONS};
    }

    static String[] beaconScanPermissions(int sdkInt) {
        ArrayList<String> permissions = new ArrayList<>();
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
        if (sdkInt >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
        }
        return permissions.toArray(new String[0]);
    }

    static String[] beaconAdvertisePermissions(int sdkInt) {
        ArrayList<String> permissions = new ArrayList<>();
        if (sdkInt >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE);
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
        }
        return permissions.toArray(new String[0]);
    }

    static String[] configPairingPermissions(String action, int sdkInt) {
        if (action != null && action.startsWith("configDevice")) {
            return new String[0];
        }
        if ("configPairingStop".equals(action) || "configPairingDisconnect".equals(action)) {
            return new String[0];
        }

        ArrayList<String> permissions = new ArrayList<>();
        if ("configPairingShow".equals(action)) {
            permissions.add(Manifest.permission.CAMERA);
        }
        if (sdkInt >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT);
            if (!"configPairingSend".equals(action)) {
                permissions.add(Manifest.permission.BLUETOOTH_SCAN);
            }
            if ("configPairingShow".equals(action)) {
                permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE);
            }
        } else if ("configPairingConnect".equals(action)) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }
        return permissions.toArray(new String[0]);
    }

    static boolean allGranted(Context context, String[] permissions) {
        for (String permission : permissions) {
            if (ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }
}
