package com.example.circadian_lingo

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * ModelManager — APK Asset Extraction Utility
 *
 * Copies model files from `assets/models/` into `filesDir/models/` on first launch.
 * Both whisper.cpp (`whisper_init_from_file`) and ONNX Runtime (`Ort::Session`)
 * require POSIX filesystem paths — they cannot read from the compressed APK stream.
 *
 * Models managed:
 *   - silero_vad.onnx      (~2 MB)  — Silero VAD v4/v5 ONNX model
 */
object ModelManager {

    private const val TAG              = "ModelManager"
    private const val PREFS_NAME       = "circadian_model_prefs"
    private const val PREF_MODELS_READY = "models_extracted_v3"

    private val MODEL_FILES = listOf(
        "silero_vad.onnx"
    )

    /**
     * Ensures all model files are present in [filesDir]/models/.
     * Safe to call on every launch; skips copy if files already exist.
     * Run on [Dispatchers.IO].
     */
    suspend fun ensureModelsReady(context: Context): Boolean =
        withContext(Dispatchers.IO) {
            val prefs     = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val modelsDir = File(context.filesDir, "models")

            if (prefs.getBoolean(PREF_MODELS_READY, false)) {
                val allPresent = MODEL_FILES.all { File(modelsDir, it).let { f -> f.exists() && f.length() > 0 } }
                if (allPresent) {
                    Log.i(TAG, "Models already extracted — skipping.")
                    return@withContext true
                }
                Log.w(TAG, "Pref flag set but files missing — re-extracting.")
                prefs.edit().remove(PREF_MODELS_READY).apply()
            }

            modelsDir.mkdirs()
            var allOk = true

            for (name in MODEL_FILES) {
                val dest = File(modelsDir, name)
                try {
                    context.assets.open("models/$name").use { input ->
                        FileOutputStream(dest).use { output ->
                            val buf = ByteArray(8 * 1024)
                            var read: Int
                            var total = 0L
                            while (input.read(buf).also { read = it } != -1) {
                                output.write(buf, 0, read)
                                total += read
                            }
                            output.flush()
                            Log.i(TAG, "Extracted $name (${total / 1024} KB)")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to extract $name: ${e.message}", e)
                    dest.delete()
                    allOk = false
                }
            }

            if (allOk) prefs.edit().putBoolean(PREF_MODELS_READY, true).apply()
            allOk
        }

    /** Returns the absolute path to a model file in [filesDir]/models/. */
    fun modelPath(context: Context, modelName: String): String =
        File(File(context.filesDir, "models"), modelName).absolutePath

    /** Returns the absolute path to the recordings directory. */
    fun recordingsDir(context: Context): String =
        File(context.filesDir, "recordings").also { it.mkdirs() }.absolutePath
}
