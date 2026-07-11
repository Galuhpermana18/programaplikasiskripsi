package com.DLabs.air_fresh

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.Calendar

class DailyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val db = AirQualityDatabase(context)
                db.deleteOlderThan(7)

                if (!db.hasFreshDataYesterday()) {
                    Log.d(TAG, "Tidak ada data kemarin. Notifikasi harian dilewati.")
                    scheduleNextAlarm(context)
                    return@launch
                }

                if (!hasRecentlyActiveDevice(context)) {
                    Log.d(TAG, "Device tidak aktif. Notifikasi harian dilewati.")
                    scheduleNextAlarm(context)
                    return@launch
                }

                val avgPm25 = db.getAveragePm25Yesterday()
                val status = getStatusFromPm25(avgPm25)

                NotificationHelper.showDailyAirQualityNotification(
                    context,
                    "Laporan Harian Udara",
                    "Rata-rata PM2.5 kemarin: $avgPm25\nStatus Udara: $status"
                )

                scheduleNextAlarm(context)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun getStatusFromPm25(pm25: Int): String {
        return when (pm25) {
            in 0..12 -> "BAIK"
            in 13..35 -> "SEDANG"
            in 36..55 -> "TIDAK SEHAT BAGI YANG SENSITIF"
            in 56..150 -> "TIDAK SEHAT"
            in 151..250 -> "SANGAT TIDAK SEHAT"
            else -> "BERBAHAYA"
        }
    }

    companion object {
        private const val TAG = "DailyReceiver"
        private const val SERVICE_PREFS_NAME = "airfresh_service_prefs"
        private const val STATUS_PREFS_NAME = "air_status_prefs"
        private const val KEY_DEVICE_ID = "device_id"
        private const val ACTIVE_WINDOW_MILLIS = 15 * 60 * 1000L

        private fun hasRecentlyActiveDevice(context: Context): Boolean {
            val deviceId = context.getSharedPreferences(SERVICE_PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_DEVICE_ID, "")
                ?.trim()
                .orEmpty()

            if (deviceId.isEmpty()) {
                Log.d(TAG, "Device ID kosong. Status aktif tidak bisa dicek.")
                return false
            }

            val lastActiveAt = context.getSharedPreferences(STATUS_PREFS_NAME, Context.MODE_PRIVATE)
                .getLong("last_active_at_$deviceId", 0L)

            if (lastActiveAt <= 0L) {
                Log.d(TAG, "Belum ada heartbeat aktif untuk device: $deviceId")
                return false
            }

            val age = System.currentTimeMillis() - lastActiveAt
            Log.d(TAG, "Heartbeat terakhir device $deviceId: ${age / 1000L} detik lalu")
            return age in 0..ACTIVE_WINDOW_MILLIS
        }

        fun scheduleNextAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DailyReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val calendar = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 6)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)

                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }

            Log.d(TAG, "Alarm harian disetel: ${calendar.time}")
        }
    }
}
