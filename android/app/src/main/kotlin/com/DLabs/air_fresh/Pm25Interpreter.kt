package com.DLabs.air_fresh
import android.content.Context
import org.tensorflow.lite.Interpreter
import org.json.JSONArray
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

class Pm25Interpreter(context: Context) {
    private val interpreter: Interpreter
    private val labels: List<String>

    init {
        // Load model .tflite
        val assetFileDescriptor = context.assets.openFd("pm25_model.tflite")
        val fileInputStream = FileInputStream(assetFileDescriptor.fileDescriptor)
        val fileChannel = fileInputStream.channel
        val startOffset = assetFileDescriptor.startOffset
        val declaredLength = assetFileDescriptor.declaredLength
        val modelBuffer = fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
        interpreter = Interpreter(modelBuffer)

        // Load labels.json
        val jsonText = context.assets.open("labels.json").bufferedReader().use { it.readText() }
        val jsonArray = JSONArray(jsonText)
        labels = List(jsonArray.length()) { i -> jsonArray.getString(i) }
    }

    fun predict(pm25: Float): String {
        val input = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder()).putFloat(pm25)
        val output = ByteBuffer.allocateDirect(4 * labels.size).order(ByteOrder.nativeOrder())
        input.rewind()
        output.rewind()

        interpreter.run(input, output)

        output.rewind()
        val results = FloatArray(labels.size)
        output.asFloatBuffer().get(results)

        val maxIdx = results.indices.maxByOrNull { results[it] } ?: 0
        return labels[maxIdx]
    }
}
