package com.DLabs.air_fresh
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class AirQualityDatabase(context: Context) :
    SQLiteOpenHelper(context, "air_quality.db", null, 1) {

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
                filterLife INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS air_quality")
        onCreate(db)
    }

    fun insertData(pm25: Int, co2: Int, tvoc: Int, pm10: Int, filterLife: Int) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put("timestamp", System.currentTimeMillis())
            put("pm25", pm25)
            put("co2", co2)
            put("tvoc", tvoc)
            put("pm10", pm10)
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
                "SELECT AVG(pm25), AVG(co2), AVG(tvoc), AVG(pm10) FROM air_quality WHERE timestamp BETWEEN ? AND ?",
                arrayOf(start.toString(), end.toString())
            )
            if (cursor.moveToFirst()) {
                val pm25 = cursor.getDouble(0).toFloat()
                val co2 = cursor.getDouble(1).toFloat()
                val tvoc = cursor.getDouble(2).toFloat()
                val pm10 = cursor.getDouble(3).toFloat()
                results.add(DailyPmData(calendar.timeInMillis, pm25, co2, tvoc, pm10))
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

    fun exportPmDataToCsv(context: Context) {
        val fileName = "pm25_data.csv"
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        val file = File(dir, fileName)

        val db = readableDatabase
        val cursor = db.rawQuery("SELECT timestamp, pm25 FROM air_quality", null)

        file.bufferedWriter().use { writer ->
            writer.write("timestamp,pm25,status\n")
            while (cursor.moveToNext()) {
                val timestamp = cursor.getLong(0)
                val pm25 = cursor.getInt(1)
                val status = getStatusFromPm25(pm25)
                val date = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(timestamp))
                writer.write("$date,$pm25,$status\n")
            }
        }

        cursor.close()
        db.close()

        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, "CSV disimpan di: ${file.absolutePath}", Toast.LENGTH_LONG).show()
        }

        // Log.d("AirQualityDB", "CSV exported to ${file.absolutePath}")
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
        pm25 in 0..12 -> "🙂 BAIK"
        pm25 in 13..35 -> "😐 SEDANG"
        pm25 in 36..55 -> "😌 TIDAK SEHAT BAGI YANG SENSITIF"
        pm25 in 56..150 -> "😷 TIDAK SEHAT"
        pm25 in 151..250 -> "🤢 SANGAT TIDAK SEHAT"
        pm25 > 250 -> "BERBAHAYA"
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
