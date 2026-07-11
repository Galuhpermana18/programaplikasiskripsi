// package com.DLabs.air_fresh
// import android.app.*
// import android.content.Context
// import android.content.Intent
// import android.graphics.BitmapFactory
// import android.os.*
// import android.util.Log
// import androidx.core.app.NotificationCompat
// import com.google.firebase.database.FirebaseDatabase
// import com.google.firebase.database.DatabaseReference
// import com.google.firebase.database.DataSnapshot
// import com.google.firebase.database.DatabaseError
// import com.google.firebase.database.ValueEventListener
// import java.util.*

// class ForegroundService : Service() {
//     private val handler = Handler(Looper.getMainLooper())
//     private lateinit var db: AirQualityDatabase
//      private var deviceId: String = "" 
//     override fun onCreate() {
//         super.onCreate()
//         deviceId = intent?.getStringExtra("DEVICE_ID") ?: ""
//         if (deviceId.isEmpty()) {
//             Log.e("ForegroundService", "Device ID kosong! Service tidak bisa jalan.")
//             stopSelf() // Stop service jika tidak ada Device ID
//             return START_NOT_STICKY
//         }
//         db = AirQualityDatabase(this)
    
//         getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
//             .edit().putString("last_air_status", "").apply()
//         startForegroundServiceNotification()
//         startListeningFirebase()
//         scheduleDailyNotification()
//     }

//     override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
//         return START_STICKY
//     }

//     private fun startForegroundServiceNotification() {
//         try {
//             val channelId = "airfresh_background_channel"
//             val channelName = "Notifikasi Monitoring Latar Belakang"
//             val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

//             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//                 val channel = NotificationChannel(
//                     channelId,
//                     channelName,
//                     NotificationManager.IMPORTANCE_MIN
//                 )
//                 notificationManager.createNotificationChannel(channel)
//             }

//             val intent = Intent(this, MainActivity::class.java).apply {
//                 flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
//             }
//             val pendingIntent = PendingIntent.getActivity(
//                 this, 0, intent,
//                 PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
//             )

//             val notification = NotificationCompat.Builder(this, channelId)
//                 .setContentTitle("🔔 Monitoring udara aktif")
//                 .setContentText("⏰ Airfresh aktif di latar belakang...")
//                 .setStyle(NotificationCompat.BigTextStyle().bigText("⏰ Airfresh aktif di latar belakang untuk memastikan notifikasi tetap diterima..."))
//                 .setSmallIcon(R.drawable.notif)
//                 .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.notif))
//                 .setContentIntent(pendingIntent)
//                 .setPriority(NotificationCompat.PRIORITY_MIN)
//                 .setSilent(true)
//                 .setAutoCancel(false)
//                 .build()

//             startForeground(1, notification)

//         } catch (e: Exception) {
//         }
//     }

    
//     private fun startListeningFirebase(deviceId: String) {
//         val database = FirebaseDatabase.getInstance(
//             "https://airfresh-c8bb6-default-rtdb.asia-southeast1.firebasedatabase.app/"
//         )
        
//         val ref = database.getReference("Devices/$deviceId/sensors")
        
//         ref.addValueEventListener(object : ValueEventListener {
//             override fun onDataChange(snapshot: DataSnapshot) {
//                 if (snapshot.exists()) {
//                     val pm10 = snapshot.child("pm10").getValue(Int::class.java) ?: 0
//                     val pm25 = snapshot.child("pm25").getValue(Int::class.java) ?: 0
//                     val filterLife = snapshot.child("filterlife").getValue(Int::class.java) ?: 100

//                     val prefs = getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
//                     val lastSavedValue = prefs.getString("last_saved_value_$deviceId", "")
//                     val newValue = "$pm25,$pm10,$filterLife"

//                     if (newValue != lastSavedValue) {
//                         db.insertData(pm25, pm10, filterLife)
//                         Log.d("SQLite", "[$deviceId] Data saved: pm25=$pm25, pm10=$pm10")
//                         prefs.edit().putString("last_saved_value_$deviceId", newValue).apply()
//                     }

//                     val hasSentFilterWarning = prefs.getBoolean("filter_warn_sent_$deviceId", false)
//                     if (filterLife <= 30 && !hasSentFilterWarning) {
//                         showFilterNotification(
//                             "⚠️ Filter Alert - $deviceId",
//                             "Filter tersisa $filterLife%. Segera bersihkan!"
//                         )
//                         prefs.edit().putBoolean("filter_warn_sent_$deviceId", true).apply()
//                     } else if (filterLife > 30 && hasSentFilterWarning) {
//                         prefs.edit().putBoolean("filter_warn_sent_$deviceId", false).apply()
//                     }
//                 }
//             }

//             override fun onCancelled(error: DatabaseError) {
//                 Log.e("Firebase", "[$deviceId] Error: ${error.message}")
//             }
//         })
//     }


//     private fun scheduleDailyNotification() {
//         val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
//         val intent = Intent(this, DailyReceiver::class.java)
//         val pendingIntent = PendingIntent.getBroadcast(
//             this,
//             0,
//             intent,
//             PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
//         )

//         val calendar = Calendar.getInstance().apply {
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

//        // Log.d("AlarmManager", "Alarm harian disetel: ${calendar.time}")
//     }

//     private fun showAirQualityNotification(title: String, message: String) {
//         val channelId = "air_quality_alert_channel"
//         val channelName = "Notifikasi Kualitas Udara"
//         val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//             val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH)
//             notificationManager.createNotificationChannel(channel)
//         }

//         val intent = Intent(this, MainActivity::class.java).apply {
//             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
//         }

//         val pendingIntent = PendingIntent.getActivity(this, 0, intent,
//             PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

//         val notification = NotificationCompat.Builder(this, channelId)
//             .setContentTitle(title)
//             .setContentText(message)
//             .setStyle(NotificationCompat.BigTextStyle().bigText(message))
//             .setSmallIcon(R.drawable.notif)
//             .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.notif))
//             .setPriority(NotificationCompat.PRIORITY_HIGH)
//             .setContentIntent(pendingIntent)
//             .setAutoCancel(true)
//             .build()

//         notificationManager.notify(System.currentTimeMillis().toInt(), notification)
//     }

//     private fun showFilterNotification(title: String, message: String) {
//         val channelId = "filter_warning_channel"
//         val channelName = "Peringatan Filter"
//         val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//             val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH)
//             notificationManager.createNotificationChannel(channel)
//         }

//         val intent = Intent(this, MainActivity::class.java).apply {
//             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
//         }

//         val pendingIntent = PendingIntent.getActivity(this, 0, intent,
//             PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

//         val notification = NotificationCompat.Builder(this, channelId)
//             .setContentTitle(title)
//             .setContentText(message)
//             .setStyle(NotificationCompat.BigTextStyle().bigText(message))
//             .setSmallIcon(R.drawable.notif)
//             .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.notif))
//             .setPriority(NotificationCompat.PRIORITY_HIGH)
//             .setContentIntent(pendingIntent)
//             .setAutoCancel(true)
//             .build()

//         notificationManager.notify(System.currentTimeMillis().toInt(), notification)
//     }

//     override fun onBind(intent: Intent?): IBinder? = null
// }



package com.DLabs.air_fresh

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.ValueEventListener
import java.util.*

class ForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var db: AirQualityDatabase
    private var deviceId: String = ""
    
    override fun onCreate() {
        super.onCreate()
        db = AirQualityDatabase(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        deviceId = intent?.getStringExtra("DEVICE_ID") ?: ""
        
        if (deviceId.isEmpty()) {
            Log.e("ForegroundService", "Device ID kosong! Service tidak bisa jalan.")
            stopSelf()
            return START_NOT_STICKY
        }
        
        Log.d("ForegroundService", "Service started with device: $deviceId")
        startForegroundServiceNotification()
        startListeningFirebase(deviceId)
        try {
            scheduleDailyNotification()
        } catch (error: Exception) {
            Log.e("AlarmManager", "Alarm harian gagal dijadwalkan", error)
        }
        
        return START_STICKY
    }

    private fun startForegroundServiceNotification() {
        try {
            val channelId = "airfresh_background_channel"
            val channelName = "Notifikasi Monitoring Latar Belakang"
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    channelName,
                    NotificationManager.IMPORTANCE_MIN
                )
                notificationManager.createNotificationChannel(channel)
            }

            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, channelId)
                .setContentTitle("🔔 Monitoring udara aktif")
                .setContentText("⏰ Monitoring device: $deviceId")
                .setStyle(NotificationCompat.BigTextStyle().bigText("⏰ Airfresh aktif di latar belakang untuk memastikan notifikasi tetap diterima..."))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
                .setContentIntent(pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setSilent(true)
                .setAutoCancel(false)
                .build()

            startForeground(1, notification)

        } catch (e: Exception) {
            Log.e("ForegroundService", "Error creating notification: ${e.message}")
        }
    }
    
    private fun startListeningFirebase(deviceId: String) {
        val database = FirebaseDatabase.getInstance(
            "https://airfreshskripsi-default-rtdb.asia-southeast1.firebasedatabase.app/"
        )
        
        val ref = database.getReference("Devices/$deviceId")
        
        ref.addValueEventListener(object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                if (snapshot.exists()) {
                    val sensors = snapshot.child("sensors")
                    val pm10 = sensors.child("pm10").getValue(Int::class.java) ?: 0
                    val co2 = sensors.child("co2").getValue(Int::class.java) ?: 0
                    val tvoc = sensors.child("tvoc").getValue(Int::class.java) ?: 0
                    val pm25 = sensors.child("pm25").getValue(Int::class.java) ?: 0
                    val temperature = (sensors.child("temp").value as? Number)?.toDouble() ?: 0.0
                    val humidity = (sensors.child("hum").value as? Number)?.toDouble() ?: 0.0
                    val filterLife = snapshot.child("filter/filterlife")
                        .getValue(Int::class.java) ?: 100

                    val prefs = getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
                    val lastSavedValue = prefs.getString("last_saved_value_$deviceId", "")
                    val newValue = "$pm25,$co2,$tvoc,$pm10,$temperature,$humidity,$filterLife"

                    if (newValue != lastSavedValue) {
                        db.insertData(
                            pm25,
                            co2,
                            tvoc,
                            pm10,
                            temperature,
                            humidity,
                            filterLife
                        )
                        Log.d(
                            "SQLite",
                            "[$deviceId] Data saved: pm25=$pm25, pm10=$pm10, " +
                                "co2=$co2, tvoc=$tvoc, temp=$temperature, hum=$humidity, " +
                                "filterLife=$filterLife"
                        )
                        prefs.edit().putString("last_saved_value_$deviceId", newValue).apply()
                    } else {
                        Log.d("SQLite", "[$deviceId] Data TIDAK disimpan karena tidak ada perubahan")
                    }

                    // Cek notifikasi filter
                    val hasSentFilterWarning = prefs.getBoolean("filter_warn_sent_$deviceId", false)
                    if (filterLife <= 30 && !hasSentFilterWarning) {
                        showFilterNotification(
                            "⚠️ Filter Alert - $deviceId",
                            "Filter tersisa $filterLife%. Segera bersihkan!"
                        )
                        prefs.edit().putBoolean("filter_warn_sent_$deviceId", true).apply()
                    } else if (filterLife > 30 && hasSentFilterWarning) {
                        prefs.edit().putBoolean("filter_warn_sent_$deviceId", false).apply()
                    }
                    
                    Log.d(
                        "Notification",
                        "Notifikasi perubahan kategori PM2.5 dinonaktifkan. pm25=$pm25, pm10=$pm10"
                    )
                }
            }

            override fun onCancelled(error: DatabaseError) {
                Log.e("Firebase", "[$deviceId] Error: ${error.message}")
            }
        })
    }
    
    // private fun checkAirQualityAndNotify(pm25: Int, pm10: Int) {
    //     val prefs = getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
    //     val lastStatus = prefs.getString("last_air_status", "")
        
    //     val status = when {
    //         pm25 > 55 || pm10 > 154 -> "TIDAK SEHAT"
    //         pm25 > 35 || pm10 > 100 -> "SEDANG"
    //         else -> "BAIK"
    //     }
        
    //     if (status != lastStatus && status != "BAIK") {
    //         val title = when (status) {
    //             "TIDAK SEHAT" -> "KUALITAS UDARA BURUK"
    //             "SEDANG" -> "KUALITAS UDARA SEDANG"
    //             else -> ""
    //         }
            
    //         val message = "PM2.5: $pm25 µg/m³, PM10: $pm10 µg/m³\nSebaiknya gunakan masker jika keluar rumah."
            
    //         showAirQualityNotification(title, message)
    //         prefs.edit().putString("last_air_status", status).apply()
    //     } else if (status == "BAIK" && lastStatus != "BAIK") {
    //         prefs.edit().putString("last_air_status", status).apply()
    //     }
    // }

    private fun checkAirQualityAndNotify(pm25: Int, pm10: Int) {
        val prefs = getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
        val lastStatus = prefs.getString("last_air_status", "")

        val status = when {
            pm25 <= 9 -> "BAIK"
            pm25 <= 35 -> "SEDANG"
            pm25 <= 55 -> "TIDAK SEHAT UNTUK KELOMPOK SENSITIF"
            pm25 <= 125 -> "TIDAK SEHAT"
            pm25 <= 225 -> "SANGAT TIDAK SEHAT"
            else -> "BERBAHAYA"
        }

        if (status != lastStatus) {
            prefs.edit().putString("last_air_status", status).apply()

            if (status != "BAIK") {
                val message =
                    "PM2.5: $pm25 µg/m³, PM10: $pm10 µg/m³\n" +
                        "Status udara: $status"
                showAirQualityNotification("Peringatan Kualitas Udara", message)
            }
        }
    }

    private fun scheduleDailyNotification() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, DailyReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
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

        Log.d("AlarmManager", "Alarm harian disetel: ${calendar.time}")
    }

    private fun showAirQualityNotification(title: String, message: String) {
        if (!notificationsAllowed()) {
            Log.w("Notification", "Izin notifikasi belum diberikan")
            return
        }

        val channelId = "air_quality_alert_channel"
        val channelName = "Notifikasi Kualitas Udara"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }

        val pendingIntent = PendingIntent.getActivity(this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun showFilterNotification(title: String, message: String) {
        if (!notificationsAllowed()) {
            Log.w("Notification", "Izin notifikasi belum diberikan")
            return
        }

        val channelId = "filter_warning_channel"
        val channelName = "Peringatan Filter"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }

        val pendingIntent = PendingIntent.getActivity(this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun notificationsAllowed(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
