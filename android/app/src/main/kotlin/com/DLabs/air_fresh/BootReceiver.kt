package com.DLabs.air_fresh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_DATE_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            Log.d(TAG, "Waktu/tanggal berubah, alarm harian dijadwalkan ulang")
            DailyReceiver.scheduleNextAlarm(context)
            return
        }

        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val deviceId = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_ID, "")
            ?.trim()
            .orEmpty()

        if (deviceId.isEmpty()) {
            Log.w(TAG, "Device ID kosong, foreground service tidak dijalankan saat boot")
            return
        }

        Log.d(TAG, "Menjalankan foreground service setelah event: $action")
        DailyReceiver.scheduleNextAlarm(context)
        ForegroundService.start(context, deviceId)
    }

    private companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "airfresh_service_prefs"
        private const val KEY_DEVICE_ID = "device_id"
    }
}
