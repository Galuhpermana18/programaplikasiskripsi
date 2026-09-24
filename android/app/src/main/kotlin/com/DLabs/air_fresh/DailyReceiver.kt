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
        // Jadwalkan hari berikutnya sebelum pekerjaan dimulai. Dengan begitu,
        // error database atau proses receiver yang dihentikan Android tidak
        // memutus rantai alarm harian.
        scheduleNextAlarm(context)
        val pendingResult = goAsync()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val db = AirQualityDatabase(context)
                db.deleteOlderThan(7)

                if (!db.hasFreshDataYesterday()) {
                    Log.d(TAG, "Tidak ada data kemarin. Laporan tanpa data dikirim.")
                    NotificationHelper.showDailyAirQualityNotification(
                        context,
                        "Laporan Harian Udara",
                        "Belum ada data kualitas udara yang tercatat kemarin."
                    )
                    return@launch
                }

                if (!hasRecentlyActiveDevice(context)) {
                    Log.d(TAG, "Device tidak aktif atau heartbeat lama. Notifikasi harian tetap akan dikirim berdasarkan data kemarin.")
                }

                val avgPm25 = db.getAveragePm25Yesterday()
                val status = getStatusFromPm25(avgPm25)

                NotificationHelper.showDailyAirQualityNotification(
                    context,
                    "Laporan Harian Udara",
                    "Rata-rata PM2.5 kemarin: $avgPm25\nStatus Udara: $status"
                )

            } catch (error: Exception) {
                Log.e(TAG, "Gagal membuat laporan harian", error)
                NotificationHelper.showDailyAirQualityNotification(
                    context,
                    "Laporan Harian Udara",
                    "Laporan hari ini belum dapat dibuat. Monitoring akan tetap dilanjutkan."
                )
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun getStatusFromPm25(pm25: Int): String {
        return when (pm25) {
            in 0..9 -> "BAIK"
            in 10..35 -> "SEDANG"
            in 36..55 -> "TIDAK SEHAT UNTUK KELOMPOK SENSITIF"
            in 56..125 -> "TIDAK SEHAT"
            in 126..225 -> "SANGAT TIDAK SEHAT"
            in 226..Int.MAX_VALUE -> "BERBAHAYA"
            else -> "TIDAK DIKETAHUI"
        }
    }

    companion object {
        private const val TAG = "DailyReceiver"
        private const val SERVICE_PREFS_NAME = "airfresh_service_prefs"
        private const val STATUS_PREFS_NAME = "air_status_prefs"
        private const val KEY_DEVICE_ID = "device_id"
        private const val ACTIVE_WINDOW_MILLIS = 24 * 60 * 60 * 1000L

        private fun hasRecentlyActiveDevice(context: Context): Boolean {
            val deviceId = context.getSharedPreferences(SERVICE_PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_DEVICE_ID, "")
                ?.trim()
                .orEmpty()

            if (deviceId.isEmpty()) {
                Log.d(TAG, "Device ID kosong. Pemeriksaan heartbeat dilewati, notifikasi harian tetap akan diproses.")
                return true
            }

            val lastActiveAt = context.getSharedPreferences(STATUS_PREFS_NAME, Context.MODE_PRIVATE)
                .getLong("last_active_at_$deviceId", 0L)

            if (lastActiveAt <= 0L) {
                Log.d(TAG, "Belum ada heartbeat aktif untuk device: $deviceId. Notifikasi harian tetap akan diproses.")
                return true
            }

            val age = System.currentTimeMillis() - lastActiveAt
            Log.d(TAG, "Heartbeat terakhir device $deviceId: ${age / 1000L} detik lalu")
            return age in 0..ACTIVE_WINDOW_MILLIS
        }

        fun scheduleNextAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DailyReceiver::class.java).apply {
                action = ACTION_DAILY_REPORT
            }
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

            try {
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
            } catch (error: SecurityException) {
                Log.w(TAG, "Exact alarm tidak diizinkan; memakai alarm fleksibel", error)
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }

            Log.d(TAG, "Alarm harian disetel: ${calendar.time}")
        }

        private const val ACTION_DAILY_REPORT =
            "com.DLabs.air_fresh.action.DAILY_AIR_QUALITY_REPORT"
    }
}
