package com.example.circadian_lingo

/**
 * AudioProcessorJni — JNI stub for the native ONNX Runtime VAD pipeline.
 *
 * The native implementation in AudioProcessor.cpp:
 *   1. Reads the decoded 16kHz mono 16-bit PCM WAV from [inputWavPath].
 *   2. Loads silero_vad.onnx via ONNX Runtime (C++).
 *   3. Slides 512-sample (32ms) windows, running SileroVad::runWindow()
 *      with persistent LSTM h/c state across windows.
 *   4. Collects speech-positive windows (probability >= 0.5).
 *   5. Writes the silence-stripped PCM to [outputDir]/trimmed_<ts>.wav.
 *
 * Returns:
 *   - Absolute path to the trimmed WAV on success.
 *   - Empty string "" if VAD found no speech in the audio.
 *   - JSON error string {"error":"..."} on failure.
 *
 * Threading: Always call from a background coroutine (Dispatchers.IO).
 */
object AudioProcessorJni {

    init {
        System.loadLibrary("audio_pipeline")
    }

    external fun processWithVad(
        inputWavPath: String,
        modelPath: String,
        outputDir: String
    ): String
}
