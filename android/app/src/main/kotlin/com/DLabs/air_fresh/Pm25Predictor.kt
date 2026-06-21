
import android.content.Context
import com.DLabs.air_fresh.Pm25Interpreter

object Pm25Predictor {
    fun predictStatus(context: Context, pm25: Float): String {
        val interpreter = Pm25Interpreter(context)
        val label = interpreter.predict(pm25)

        return when (label) {
            "BAIK" -> "🙂 BAIK"
            "SEDANG" -> "😌 SEDANG"
            "TIDAK SEHAT BAGI SENSITIF" -> "😐 TIDAK SEHAT BAGI SENSITIF"
            "TIDAK SEHAT" -> "😷 TIDAK SEHAT"
            "SANGAT TIDAK SEHAT" -> "🤢 SANGAT TIDAK SEHAT"
            "BERBAHAYA" -> " BERBAHAYA"
            else -> label
        }
    }
}
