package com.ilass.swifthtmlwebviewapp;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class NotificationReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null && AndroidNotificationBridge.ACTION_FIRE_NOTIFICATION.equals(intent.getAction())) {
            AndroidNotificationBridge.handleAlarmIntent(context, intent);
        }
    }
}
