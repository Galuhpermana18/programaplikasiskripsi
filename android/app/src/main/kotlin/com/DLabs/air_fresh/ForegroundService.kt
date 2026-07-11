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
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.ValueEventListener
import java.util.*

class ForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var db: AirQualityDatabase
    private var deviceId: String = ""
    private var firebaseRef: DatabaseReference? = null
    private var firebaseListener: ValueEventListener? = null

    companion object {
        private const val TAG = "ForegroundService"
        private const val PREFS_NAME = "airfresh_service_prefs"
        private const val KEY_DEVICE_ID = "device_id"
        private const val ACTION_START = "com.DLabs.air_fresh.action.START_FOREGROUND"
        private const val RESTART_REQUEST_CODE = 1207

        fun start(context: Context, deviceId: String? = null) {
            val intent = Intent(context, ForegroundService::class.java).apply {
                action = ACTION_START
                deviceId?.trim()?.takeIf { it.isNotEmpty() }?.let {
                    putExtra("DEVICE_ID", it)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        db = AirQualityDatabase(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        deviceId = intent?.getStringExtra("DEVICE_ID")?.trim().orEmpty()
        if (deviceId.isEmpty()) {
            deviceId = loadSavedDeviceId()
        } else {
            saveDeviceId(deviceId)
        }
        
        if (deviceId.isEmpty()) {
            Log.e(TAG, "Device ID kosong! Service tidak bisa jalan.")
            stopSelf()
            return START_NOT_STICKY
        }
        
        Log.d(TAG, "Service started with device: $deviceId")
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
                .setOngoing(true)
                .build()

            startForeground(1, notification)

        } catch (e: Exception) {
            Log.e(TAG, "Error creating notification: ${e.message}")
        }
    }
    
    private fun startListeningFirebase(deviceId: String) {
        stopListeningFirebase()

        val database = FirebaseDatabase.getInstance(
            "https://airfreshskripsi-default-rtdb.asia-southeast1.firebasedatabase.app/"
        )
        
        val ref = database.getReference("Devices/$deviceId")
        firebaseRef = ref
        
        firebaseListener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                if (snapshot.exists()) {
                    val sensors = snapshot.child("sensors")
                    val pm10 = sensors.child("pm10").getValue(Int::class.java) ?: 0
                    val co2 = sensors.child("co2").getValue(Int::class.java) ?: 0
                    val tvoc = sensors.child("tvoc").getValue(Int::class.java) ?: 0
                    val pm25 = sensors.child("pm25").getValue(Int::class.java) ?: 0
                    val temperature = (sensors.child("temp").value as? Number)?.toDouble() ?: 0.0
                    val humidity = (sensors.child("hum").value as? Number)?.toDouble() ?: 0.0
                    val sensorTimestamp = sensors.child("timestamp").value
                        ?.toString()
                        ?.trim()
                        .orEmpty()
                    val filterLife = snapshot.child("filter/filterlife")
                        .getValue(Int::class.java) ?: 100

                    val prefs = getSharedPreferences("air_status_prefs", Context.MODE_PRIVATE)
                    val lastSensorTimestamp = prefs.getString("last_sensor_timestamp_$deviceId", "")
                    if (sensorTimestamp.isNotEmpty() && sensorTimestamp != lastSensorTimestamp) {
                        prefs.edit()
                            .putString("last_sensor_timestamp_$deviceId", sensorTimestamp)
                            .putLong("last_active_at_$deviceId", System.currentTimeMillis())
                            .apply()
                    }

                    val lastSavedValue = prefs.getString("last_saved_value_$deviceId", "")
                    val newValue =
                        "$sensorTimestamp,$pm25,$co2,$tvoc,$pm10,$temperature,$humidity,$filterLife"

                    if (newValue != lastSavedValue) {
                        if (sensorTimestamp.isEmpty()) {
                            prefs.edit()
                                .putLong("last_active_at_$deviceId", System.currentTimeMillis())
                                .apply()
                        }
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
        }
        ref.addValueEventListener(firebaseListener!!)
    }

    private fun stopListeningFirebase() {
        val listener = firebaseListener
        if (listener != null) {
            firebaseRef?.removeEventListener(listener)
        }
        firebaseRef = null
        firebaseListener = null
    }
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
        DailyReceiver.scheduleNextAlarm(this)
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

    private fun saveDeviceId(deviceId: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DEVICE_ID, deviceId)
            .apply()
    }

    private fun loadSavedDeviceId(): String {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_ID, "")
            ?.trim()
            .orEmpty()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (deviceId.isNotEmpty()) {
            scheduleServiceRestart()
        }
    }

    private fun scheduleServiceRestart() {
        val restartIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_START
            putExtra("DEVICE_ID", deviceId)
        }
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this,
                RESTART_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                this,
                RESTART_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 1000L,
            pendingIntent
        )
        Log.d(TAG, "Service restart dijadwalkan setelah task dihapus")
    }

    override fun onDestroy() {
        stopListeningFirebase()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
