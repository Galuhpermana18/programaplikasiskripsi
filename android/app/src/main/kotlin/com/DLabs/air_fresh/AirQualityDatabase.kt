package com.DLabs.air_fresh
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.widget.Toast
import java.io.BufferedWriter
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class AirQualityDatabase(context: Context) :
    SQLiteOpenHelper(context, "air_quality.db", null, 2) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE air_quality (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                pm25 INTEGER NOT NULL,
                co2 INTEGER NOT NULL,
                tvoc INTEGER NOT NULL,
                pm10 INTEGER NOT NULL,
                temperature REAL NOT NULL DEFAULT 0,
                humidity REAL NOT NULL DEFAULT 0,
                filterLife INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE air_quality ADD COLUMN temperature REAL NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE air_quality ADD COLUMN humidity REAL NOT NULL DEFAULT 0")
        }
    }

    fun insertData(
        pm25: Int,
        co2: Int,
        tvoc: Int,
        pm10: Int,
        temperature: Double,
        humidity: Double,
        filterLife: Int
    ) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put("timestamp", System.currentTimeMillis())
            put("pm25", pm25)
            put("co2", co2)
            put("tvoc", tvoc)
            put("pm10", pm10)
            put("temperature", temperature)
            put("humidity", humidity)
            put("filterLife", filterLife)
        }
        db.insert("air_quality", null, values)
        db.close()
    }

    fun deleteOlderThan(days: Int) {
        val cutoff = Calendar.getInstance().apply {
            add(Calendar.DATE, -days)
        }.timeInMillis

        val db = writableDatabase
        val deletedRows = db.delete("air_quality", "timestamp < ?", arrayOf(cutoff.toString()))
        db.close()
        Log.d("AirQualityDB", "Deleted $deletedRows old rows")
    }

    fun getAveragePm25Today(): Int {
        val todayStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val now = System.currentTimeMillis()
        return getAveragePm25Between(todayStart, now)
    }

    fun getAveragePm25Yesterday(): Int {
        val (start, end) = getYesterdayRange()
        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        Log.d("AirQualityDB", "Yesterday range: ${sdf.format(Date(start))} to ${sdf.format(Date(end))}")
        return getAveragePm25Between(start, end)
    }

    fun getDominantStatusYesterday(): String {
        val (start, end) = getYesterdayRange()
        val db = readableDatabase
        val cursor = db.rawQuery(
            "SELECT pm25 FROM air_quality WHERE timestamp BETWEEN ? AND ?",
            arrayOf(start.toString(), end.toString())
        )

        val totalData = cursor.count
        Log.d("AirQualityDB", "Total data kemarin: $totalData")

        if (totalData == 0) {
            cursor.close()
            db.close()
            return "Tidak ada data"
        }

        val statusCounts = mutableMapOf<String, Int>()
        while (cursor.moveToNext()) {
            val pm25 = cursor.getInt(0)
            val status = getStatusFromPm25(pm25)
            statusCounts[status] = statusCounts.getOrDefault(status, 0) + 1
            Log.d("AirQualityDB", "PM2.5: $pm25 -> Status: $status")
        }

        cursor.close()
        db.close()

        statusCounts.forEach { (status, count) ->
            Log.d("AirQualityDB", "Status '$status': $count kali")
        }

        return statusCounts.maxByOrNull { it.value }?.key ?: "Tidak diketahui"
    }

    fun getAveragePmPerDay(lastDays: Int = 7): List<DailyPmData> {
        val db = readableDatabase
        val results = mutableListOf<DailyPmData>()

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        for (i in lastDays downTo 1) {
            val end = calendar.timeInMillis
            calendar.add(Calendar.DATE, -1)
            val start = calendar.timeInMillis

            val cursor = db.rawQuery(
                "SELECT AVG(pm25), AVG(co2), AVG(tvoc), AVG(pm10), COUNT(*) FROM air_quality WHERE timestamp BETWEEN ? AND ?",
                arrayOf(start.toString(), end.toString())
            )
            if (cursor.moveToFirst()) {
                val totalData = cursor.getInt(4)
                if (totalData > 0) {
                    val pm25 = cursor.getDouble(0).toFloat()
                    val co2 = cursor.getDouble(1).toFloat()
                    val tvoc = cursor.getDouble(2).toFloat()
                    val pm10 = cursor.getDouble(3).toFloat()
                    results.add(DailyPmData(calendar.timeInMillis, pm25, co2, tvoc, pm10))
                }
            }
            cursor.close()
        }

        db.close()
        return results.asReversed()
    }

    private fun getAveragePm25Between(start: Long, end: Long): Int {
        val db = readableDatabase
        val cursor = db.rawQuery(
            "SELECT AVG(pm25), COUNT(*) FROM air_quality WHERE timestamp BETWEEN ? AND ?",
            arrayOf(start.toString(), end.toString())
        )

        var avg = 0
        var count = 0
        if (cursor.moveToFirst()) {
            avg = cursor.getDouble(0).toInt()
            count = cursor.getInt(1)
        }
        cursor.close()
        db.close()

        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        // Log.d("AirQualityDB", "Query range: ${sdf.format(Date(start))} to ${sdf.format(Date(end))}")
        // Log.d("AirQualityDB", "Found $count records, average PM2.5: $avg")

        return avg
    }

    fun countAll(): Int {
        val db = readableDatabase
        val cursor = db.rawQuery("SELECT COUNT(*) FROM air_quality", null)
        var count = 0
        if (cursor.moveToFirst()) {
            count = cursor.getInt(0)
        }
        cursor.close()
        db.close()
        return count
    }
    fun getLastDataTimestamp(): Long? {
        val db = readableDatabase

        val cursor = db.rawQuery(
            "SELECT MAX(timestamp) FROM air_quality",
            null
        )

        var timestamp: Long? = null

        if (cursor.moveToFirst() && !cursor.isNull(0)) {
            timestamp = cursor.getLong(0)
        }

        cursor.close()
        db.close()

        return timestamp
    }
    fun exportPmDataToCsv(context: Context): String {
        val fileName = "air_quality_data.csv"
        val db = readableDatabase
        val cursor = db.rawQuery(
            """
            SELECT timestamp, pm25, pm10, co2, tvoc, temperature, humidity, filterLife
            FROM air_quality
            ORDER BY timestamp ASC
            """.trimIndent(),
            null
        )

        fun writeRows(writer: BufferedWriter) {
            writer.write(
                "timestamp,pm25_ug_m3,pm10_ug_m3,eco2_ppm,tvoc_ppb," +
                    "temperature_c,humidity_percent,filter_life_percent,pm25_status\n"
            )
            while (cursor.moveToNext()) {
                val timestamp = cursor.getLong(0)
                val pm25 = cursor.getInt(1)
                val pm10 = cursor.getInt(2)
                val co2 = cursor.getInt(3)
                val tvoc = cursor.getInt(4)
                val temperature = cursor.getDouble(5)
                val humidity = cursor.getDouble(6)
                val filterLife = cursor.getInt(7)
                val status = getStatusFromPm25(pm25)
                val date = SimpleDateFormat(
                    "yyyy-MM-dd HH:mm:ss",
                    Locale.getDefault()
                ).format(Date(timestamp))
                writer.write(
                    "$date,$pm25,$pm10,$co2,$tvoc,$temperature,$humidity," +
                        "$filterLife,$status\n"
                )
            }
        }

        val savedLocation: String
        try {
            savedLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "text/csv")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values
                ) ?: error("Gagal membuat file CSV di folder Download")

                resolver.openOutputStream(uri)?.bufferedWriter()?.use(::writeRows)
                    ?: error("Gagal membuka file CSV untuk ditulis")

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                "Download/$fileName"
            } else {
                @Suppress("DEPRECATION")
                val downloadDir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                )
                if (!downloadDir.exists() && !downloadDir.mkdirs()) {
                    error("Folder Download tidak dapat dibuat")
                }
                val file = File(downloadDir, fileName)
                file.bufferedWriter().use(::writeRows)
                file.absolutePath
            }
        } finally {
            cursor.close()
            db.close()
        }

        Handler(Looper.getMainLooper()).post {
            Toast.makeText(
                context,
                "CSV disimpan di: $savedLocation",
                Toast.LENGTH_LONG
            ).show()
        }

        return savedLocation
    }
    fun hasFreshDataYesterday(): Boolean {
        val (start, end) = getYesterdayRange()
        val db = readableDatabase
        val cursor = db.rawQuery(
            "SELECT COUNT(*) FROM air_quality WHERE timestamp BETWEEN ? AND ?",
            arrayOf(start.toString(), end.toString())
        )

        var totalData = 0
        if (cursor.moveToFirst()) {
            totalData = cursor.getInt(0)
        }

        cursor.close()
        db.close()

        Log.d(
            "AirQualityDB",
            "Data kemarin: $totalData (${Date(start)} - ${Date(end)})"
        )

        return totalData > 0
    }
    fun debugYesterdayData(): String {
        val (start, end) = getYesterdayRange()
        val db = readableDatabase
        val cursor = db.rawQuery(
            "SELECT pm25, timestamp FROM air_quality WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
            arrayOf(start.toString(), end.toString())
        )

        val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
        val debugInfo = StringBuilder("Data kemarin:\n")

        val pm25Values = mutableListOf<Int>()
        while (cursor.moveToNext()) {
            val pm25 = cursor.getInt(0)
            val timestamp = cursor.getLong(1)
            pm25Values.add(pm25)
            debugInfo.append("${sdf.format(Date(timestamp))}: $pm25\n")
        }

        cursor.close()
        db.close()

        if (pm25Values.isNotEmpty()) {
            val average = pm25Values.average().toInt()
            debugInfo.append("Rata-rata: $average\nTotal data: ${pm25Values.size}")
        } else {
            debugInfo.append("Tidak ada data kemarin")
        }

        return debugInfo.toString()
    }

    private fun getYesterdayRange(): Pair<Long, Long> {
        val start = Calendar.getInstance().apply {
            add(Calendar.DATE, -1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val end = Calendar.getInstance().apply {
            add(Calendar.DATE, -1)
            set(Calendar.HOUR_OF_DAY, 23)
            set(Calendar.MINUTE, 59)
            set(Calendar.SECOND, 59)
            set(Calendar.MILLISECOND, 999)
        }.timeInMillis

        return Pair(start, end)
    }

    private fun getStatusFromPm25(pm25: Int): String {
    return when {
        pm25 in 0..9 -> "🙂 BAIK"
        pm25 in 10..35 -> "😐 SEDANG"
        pm25 in 36..55 -> "😌 TIDAK SEHAT UNTUK KELOMPOK SENSITIF"
        pm25 in 56..125 -> "😷 TIDAK SEHAT"
        pm25 in 126..225 -> "🤢 SANGAT TIDAK SEHAT"
        pm25 >= 226 -> "BERBAHAYA"
        else -> "Tidak diketahui"
    }
}

data class DailyPmData(
    val timestamp: Long,
    val pm25: Float,
    val co2: Float,
    val tvoc: Float,
    val pm10: Float
)
    // data class DailyPmData(val timestamp: Long, val pm25: Float, val pm10: Float)
}
