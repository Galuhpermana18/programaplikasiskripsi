package com.DLabs.air_fresh
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.*


class DailyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Log.e("DailyReceiver", "🔥 Alarm aktif - DailyReceiver berjalan!")

        CoroutineScope(Dispatchers.IO).launch {
            val db = AirQualityDatabase(context)
            db.deleteOlderThan(7)
            val avgPm25 = db.getAveragePm25Yesterday()
            val status = getStatusFromPm25(avgPm25)
            NotificationHelper.showDailyAirQualityNotification(
                context,
                "📋 Laporan Harian Udara 🙂",
                "📊 Rata-rata PM2.5 kemarin: $avgPm25\n ☁️ Status Udara: $status"
            )
            scheduleNextAlarm(context)
        }
    }

    private fun getStatusFromPm25(pm25: Int): String {
        return when (pm25) {
            in 0..12 -> "🙂 BAIK"
            in 13..35 -> "😐 SEDANG"
            in 36..55 -> "😌 TIDAK SEHAT BAGI YANG SENSITIF"
            in 56..150 -> "😷 TIDAK SEHAT"
            in 151..250 -> "🤢 SANGAT TIDAK SEHAT"
            else -> "BERBAHAYA"
        }
    }

    private fun scheduleNextAlarm(context: Context) {
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

        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            calendar.timeInMillis,
            pendingIntent
        )

        // Log.e("DailyReceiver", "📆 Alarm berikutnya disetel: ${calendar.time}")
    }
}


// package com.dlabs.airfresh

// import android.app.AlarmManager
// import android.app.PendingIntent
// import android.content.BroadcastReceiver
// import android.content.Context
// import android.content.Intent
// import android.util.Log
// import kotlinx.coroutines.CoroutineScope
// import kotlinx.coroutines.Dispatchers
// import kotlinx.coroutines.launch
// import java.util.*

// class DailyReceiver : BroadcastReceiver() {
//     override fun onReceive(context: Context, intent: Intent) {
//         Log.e("DailyReceiver", "🔥 Alarm aktif - DailyReceiver berjalan!")

//         CoroutineScope(Dispatchers.IO).launch {
//             val db = AirQualityDatabase(context)
        
//             db.deleteOlderThan(7) 
//             val avgPm25 = db.getAveragePm25Yesterday()
//             val dominantStatus = db.getDominantStatusYesterday()

//             NotificationHelper.showDailyAirQualityNotification(
//                 context,
//                 "✅ Laporan Harian Udara 🙂",
//                 "📊 Rata-rata PM2.5 kemarin : $avgPm25\n🌫️ Status Udara : $dominantStatus"
//             )

//             scheduleNextAlarm(context)
//         }
//     }

//     private fun scheduleNextAlarm(context: Context) {
//         val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
//         val intent = Intent(context, DailyReceiver::class.java)
//         val pendingIntent = PendingIntent.getBroadcast(
//             context,
//             0,
//             intent,
//             PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
//         )

//          val calendar = Calendar.getInstance().apply {
//             set(Calendar.HOUR_OF_DAY, 6)
//             set(Calendar.MINUTE, 0)
//             set(Calendar.SECOND, 0)
//             set(Calendar.MILLISECOND, 0)

//             if (timeInMillis <= System.currentTimeMillis()) {
//                 add(Calendar.DAY_OF_YEAR, 1)
//             }
//         }
        
//         alarmManager.setExactAndAllowWhileIdle(
//             AlarmManager.RTC_WAKEUP,
//             calendar.timeInMillis,
//             pendingIntent
//         )

//         Log.e("DailyReceiver", "📆 Alarm berikutnya disetel: ${calendar.time}")
//     }
// }


