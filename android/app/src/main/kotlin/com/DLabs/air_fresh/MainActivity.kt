package com.DLabs.air_fresh

import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var currentDeviceId: String = ""
    
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_SERVICE = "start_service"
        private const val CHANNEL_CSV = "airfresh/csv"
        private const val CHANNEL_AIR_QUALITY = "com.DLabs.air_fresh/air_quality"
        private const val CHANNEL_DEVICE = "com.DLabs.air_fresh/device"
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        setupServiceChannel(flutterEngine)
        setupCsvChannel(flutterEngine)
        setupAirQualityChannel(flutterEngine)
        setupDeviceChannel(flutterEngine)
    }
    
    // Channel 1: Start/Stop Service
    private fun setupServiceChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SERVICE)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startForegroundService" -> {
                            if (currentDeviceId.isEmpty()) {
                                Log.w(TAG, "Attempt to start service without Device ID")
                                result.error("NO_DEVICE_ID", "Device ID belum di-set!", null)
                                return@setMethodCallHandler
                            }
                            
                            val intent = Intent(this, ForegroundService::class.java).apply {
                                putExtra("DEVICE_ID", currentDeviceId)
                            }
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            
                            Log.d(TAG, "Service started with device: $currentDeviceId")
                            result.success("Service started with device: $currentDeviceId")
                        }
                        
                        "stopForegroundService" -> {
                            val intent = Intent(this, ForegroundService::class.java)
                            stopService(intent)
                            Log.d(TAG, "Service stopped")
                            result.success("Service stopped")
                        }
                        
                        "moveTaskToBack" -> {
                            moveTaskToBack(true)
                            Log.d(TAG, "App moved to background")
                            result.success("Moved to background")
                        }
                        
                        else -> {
                            Log.w(TAG, "Unknown method: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error in service channel: ${e.message}", e)
                    result.error("SERVICE_ERROR", e.message ?: "Unknown error", e.toString())
                }
            }
    }
    
    // Channel 2: Export CSV
    private fun setupCsvChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CSV)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "exportCsv" -> {
                            val db = AirQualityDatabase(this)
                            try {
                                db.exportPmDataToCsv(this)
                                Log.d(TAG, "CSV exported successfully")
                                result.success("CSV berhasil diekspor")
                            } catch (e: Exception) {
                                Log.w(TAG, "CSV export failed: ${e.message}")
                                result.error("EXPORT_FAILED", "Tidak ada data untuk diekspor", e.message)
                            }
                        }
                        else -> {
                            Log.w(TAG, "Unknown method in CSV channel: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error exporting CSV: ${e.message}", e)
                    result.error("CSV_ERROR", e.message ?: "Gagal mengekspor CSV", e.toString())
                }
            }
    }
    
    // Channel 3: Get Daily Data
    private fun setupAirQualityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_AIR_QUALITY)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getPmDailyData" -> {
                            val db = AirQualityDatabase(this)
                            val results = db.getAveragePmPerDay(7)

                            if (results.isEmpty()) {
                                Log.w(TAG, "No daily data available")
                                result.success("[]")
                                return@setMethodCallHandler
                            }

                            val jsonArray = org.json.JSONArray()
                            for (day in results) {
                                val obj = org.json.JSONObject().apply {
                                    put("timestamp", day.timestamp)
                                    put("pm25", day.pm25)
                                    put("pm10", day.pm10)
                                }
                                jsonArray.put(obj)
                            }
                            
                            Log.d(TAG, "Returned ${results.size} days of data")
                            result.success(jsonArray.toString())
                        }
                        else -> {
                            Log.w(TAG, "Unknown method in air quality channel: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting daily data: ${e.message}", e)
                    result.error("DATA_ERROR", e.message ?: "Gagal mengambil data", e.toString())
                }
            }
    }
    
    // Channel 4: Device ID Management
    private fun setupDeviceChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_DEVICE)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "setDeviceId" -> {
                            val deviceId = call.argument<String>("deviceId")
                            
                            when {
                                deviceId == null -> {
                                    Log.e(TAG, "Device ID is null")
                                    result.error("INVALID_ID", "Device ID null", null)
                                }
                                deviceId.isEmpty() -> {
                                    Log.e(TAG, "Device ID is empty")
                                    result.error("INVALID_ID", "Device ID kosong", null)
                                }
                                deviceId.length < 3 -> {
                                    Log.e(TAG, "Device ID too short: $deviceId")
                                    result.error("INVALID_ID", "Device ID terlalu pendek", null)
                                }
                                else -> {
                                    currentDeviceId = deviceId
                                    Log.d(TAG, "Device ID updated: $deviceId")
                                    result.success("Device ID updated: $deviceId")
                                }
                            }
                        }
                        
                        "getDeviceId" -> {
                            Log.d(TAG, "Current Device ID: $currentDeviceId")
                            result.success(currentDeviceId)
                        }
                        
                        else -> {
                            Log.w(TAG, "Unknown method in device channel: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error in device channel: ${e.message}", e)
                    result.error("DEVICE_ERROR", e.message ?: "Unknown error", e.toString())
                }
            }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "MainActivity destroyed")
    }
}

// package com.DLabs.air_fresh

// import android.content.Intent
// import android.os.Build
// import android.util.Log
// import io.flutter.embedding.android.FlutterActivity
// import io.flutter.embedding.engine.FlutterEngine
// import io.flutter.plugin.common.MethodChannel

// class MainActivity : FlutterActivity() {
//     private var currentDeviceId: String = ""
//     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//         super.configureFlutterEngine(flutterEngine)
        
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "start_service")
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "startForegroundService" -> {

//                         if (currentDeviceId.isEmpty()) {
//                             result.error("NO_DEVICE_ID", "Device ID belum di-set!", null)
//                             return@setMethodCallHandler
//                         }
//                         val intent = Intent(this, ForegroundService::class.java)
//                          intent.putExtra("DEVICE_ID", currentDeviceId)
//                         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//                             startForegroundService(intent)
//                         } else {
//                             startService(intent)
//                         }
//                         result.success("Service started with device: $currentDeviceId")
//                     }
//                     "stopForegroundService" -> {
//                         val intent = Intent(this, ForegroundService::class.java)
//                         stopService(intent)
//                         result.success("Service stopped")
//                     }
//                     "moveTaskToBack" -> {
//                         moveTaskToBack(true)
//                         result.success("Moved to background")
//                     }
//                     else -> {
//                         result.notImplemented()
//                     }
//                 }
//             }
//         // 🔹 Channel baru untuk ekspor CSV
//         MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "airfresh/csv")
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "exportCsv" -> {
//                         val db = AirQualityDatabase(this)
//                         db.exportPmDataToCsv(this)
//                         result.success("CSV berhasil diekspor")
//                     }
//                     else -> result.notImplemented()
//              }
//          }
//          MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.DLabs.air_fresh/air_quality")
//             .setMethodCallHandler { call, result ->
//                 if (call.method == "getPmDailyData") {
//                     val db = AirQualityDatabase(this)
//                     val results = db.getAveragePmPerDay(7)

//                     val jsonArray = org.json.JSONArray()
//                     for (day in results) {
//                         val obj = org.json.JSONObject()
//                         obj.put("timestamp", day.timestamp)
//                         obj.put("pm25", day.pm25)
//                         obj.put("pm10", day.pm10)
//                         jsonArray.put(obj)
//                     }
//                     result.success(jsonArray.toString())
//                 } else result.notImplemented()
//             }

//             MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.DLabs.air_fresh/device")
//             .setMethodCallHandler { call, result ->
//                 when (call.method) {
//                     "setDeviceId" -> {
//                         val deviceId = call.argument<String>("deviceId")
//                         if (deviceId != null && deviceId.isNotEmpty()) {
//                             currentDeviceId = deviceId
//                             result.success("Device ID updated: $deviceId")
//                         } else {
//                             result.error("INVALID_ID", "Device ID kosong atau null", null)
//                         }
//                     }
//                     "getDeviceId" -> {
//                         result.success(currentDeviceId)
//                     }
//                     else -> result.notImplemented()
//                 }
//             }

//     }
// }
