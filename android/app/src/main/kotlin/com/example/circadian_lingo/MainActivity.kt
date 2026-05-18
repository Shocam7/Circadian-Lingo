package com.example.circadian_lingo

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.app.DownloadManager
import android.content.BroadcastReceiver
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import org.json.JSONObject
import java.io.File
import android.net.Uri
import android.content.IntentFilter
import android.provider.Settings
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat

/**
 * MainActivity — Flutter host + MethodChannel for the audio pipeline.
 *
 * MethodChannel: "com.circadian_lingo/audio_pipeline"
 *
 * Supported methods:
 * ┌──────────────────┬────────────────────┬──────────────────────────────────┐
 * │ Method           │ Arguments          │ Returns                          │
 * ├──────────────────┼────────────────────┼──────────────────────────────────┤
 * │ startCapture     │ —                  │ void                             │
 * │ stopCapture      │ —                  │ String (.m4a path)               │
 * │ processAudio     │ filePath: String   │ String (transcript)              │
 * │ getStatus        │ —                  │ String (idle|recording|processing│
 * │ cancelProcessing │ —                  │ void                             │
 * │ ensureModels     │ —                  │ Boolean                          │
 * └──────────────────┴────────────────────┴──────────────────────────────────┘
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG           = "MainActivity"
        private const val CHANNEL_NAME  = "com.circadian_lingo/audio_pipeline"
        private const val RC_RECORD     = 100
        private const val RC_NOTIFY     = 101
        
        // Let the Service poke the Activity if it happens to be open when translation finishes
        var uiTranslationEventSink: EventChannel.EventSink? = null
        
        fun notifyUITranslationComplete() {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                uiTranslationEventSink?.success("complete")
            }
        }
    }

    // ── Coroutine scope — cancelled in onDestroy ─────────────────────────────
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── AudioCaptureService binding ──────────────────────────────────────────
    private var audioCaptureService: AudioCaptureService? = null
    private var serviceConnected     = false
    private var pendingStartResult: MethodChannel.Result? = null

    // ── Pipeline status ───────────────────────────────────────────────────────
    enum class PipelineStatus { IDLE, RECORDING, PROCESSING }
    private var pipelineStatus = PipelineStatus.IDLE

    // ── Model Download ───────────────────────────────────────────────────────
    private var downloadId: Long = -1
    private var progressEventSink: EventChannel.EventSink? = null
    private val DOWNLOAD_CHANNEL = "com.circadian_lingo/download_progress"

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            if (id == downloadId && id != -1L) {
                Log.i(TAG, "DownloadManager signaled completion for ID: $id")
                ioScope.launch {
                    val success = GemmaManager.moveModelToInternal(applicationContext, id)
                    withContext(Dispatchers.Main) {
                        cancelDownloadProgressNotification()
                        progressEventSink?.success(mapOf(
                            "status" to "complete",
                            "success" to success
                        ))
                        downloadId = -1
                    }
                }
            }
        }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            audioCaptureService = (binder as? AudioCaptureService.LocalBinder)?.getService()
            serviceConnected    = true
            Log.i(TAG, "AudioCaptureService connected.")

            // If startCapture was waiting for the service to bind, execute now.
            pendingStartResult?.let { result ->
                pendingStartResult = null
                audioCaptureService?.startRecording()
                pipelineStatus = PipelineStatus.RECORDING
                result.success(null)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            audioCaptureService = null
            serviceConnected    = false
            Log.w(TAG, "AudioCaptureService disconnected unexpectedly.")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flutter engine + MethodChannel setup
    // ─────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        // ── Download Progress EventChannel ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressEventSink = null
                }
            })
            
        // ── UI Translation EventChannel ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.circadian_lingo/ui_translation_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    uiTranslationEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    uiTranslationEventSink = null
                }
            })

        // Register download receiver
        ContextCompat.registerReceiver(
            this, downloadReceiver, 
            IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), 
            ContextCompat.RECEIVER_EXPORTED
        )

        // Kick off model extraction in the background immediately on launch,
        // so models are ready before any processAudio() call arrives.
        ioScope.launch {
            val ready = ModelManager.ensureModelsReady(applicationContext)
            Log.i(TAG, "ModelManager.ensureModelsReady → $ready")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MethodChannel dispatcher
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {

        when (call.method) {
            "startCapture"        -> handleStartCapture(result)
            "stopCapture"         -> handleStopCapture(result)
            "processAudio"        -> handleProcessAudio(call, result)
            "transcribeWithGemma" -> handleTranscribeWithGemma(call, result)
            "getStatus"           -> result.success(pipelineStatus.name.lowercase())
            "cancelProcessing"    -> handleCancelProcessing(result)
            "ensureModels"        -> handleEnsureModels(result)
            
            // New Download Methods
            "checkModelStatus"    -> result.success(GemmaManager.checkModelStatus(applicationContext))
            "startDownload"       -> {
                downloadId = GemmaManager.startDownload(applicationContext)
                startProgressPolling()
                result.success(downloadId)
            }
            
            // New Screenshot Methods
            "requestAccessibilityPermission" -> {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(null)
            }
            "triggerScreenshotNotification" -> handleTriggerScreenshotNotification(result)
            "getSavedScreenshots" -> handleGetSavedScreenshots(result)
            "getSavedAudioRecordings" -> handleGetSavedAudioRecordings(result)
            "deleteScreenshot"    -> handleDeleteScreenshot(call, result)
            "isAccessibilityEnabled" -> result.success(CircadianAccessibilityService.instance != null)
            
            "saveSettings" -> handleSaveSettings(call, result)
            "startScreenshotScheduler" -> {
                ScreenshotWorkManager.enqueueNextScreenshotWork(applicationContext)
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.smartContextSchedulingEnabled", true).apply()
                result.success(null)
            }
            "stopScreenshotScheduler" -> {
                ScreenshotWorkManager.cancelScreenshotWork(applicationContext)
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.smartContextSchedulingEnabled", false).apply()
                result.success(null)
            }
            "startAudioScheduler" -> {
                AudioWorkManager.enqueueNextAudioWork(applicationContext)
                result.success(null)
            }
            "stopAudioScheduler" -> {
                AudioWorkManager.cancelAudioWork(applicationContext)
                result.success(null)
            }
            "getAudioDurationMs"   -> handleGetAudioDurationMs(call, result)
            "generateLesson"       -> handleGenerateLesson(call, result)
            "updateLessonSchedule" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                val hour = call.argument<Int>("hour") ?: 22
                val minute = call.argument<Int>("minute") ?: 0
                
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("flutter.lessonAutoGenerationEnabled", enabled)
                    .putInt("flutter.lessonGenerationHour", hour)
                    .putInt("flutter.lessonGenerationMinute", minute)
                    .apply()
                    
                LessonWorkManager.scheduleDailyLesson(applicationContext)
                result.success(null)
            }
            "getLessonReadyStatus" -> {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                result.success(prefs.getBoolean("flutter.lesson_ready", false))
            }
            "getLessonProgress" -> {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val percent = prefs.getFloat("flutter.lesson_progress_percent", 0f)
                val msg = prefs.getString("flutter.lesson_progress_message", "")
                val current = prefs.getString("flutter.lesson_current_counts", "{}")
                val target = prefs.getString("flutter.lesson_target_counts", "{}")
                result.success(mapOf(
                    "percent" to percent.toDouble(),
                    "message" to msg,
                    "current_counts" to current,
                    "target_counts" to target
                ))
            }
            "getLessonGeneratingStatus" -> {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                result.success(prefs.getBoolean("flutter.lesson_generating", false))
            }
            "cancelLessonGeneration" -> {
                GemmaManager.cancelGeneration(this)
                result.success(null)
            }
            "getLessonCacheDir" -> {
                purgeOldLessons(applicationContext)
                val dir = java.io.File(filesDir, "lesson_cache")
                dir.mkdirs()
                result.success(dir.absolutePath)
            }
            "clearLessonCache" -> {
                val dir = java.io.File(filesDir, "lesson_cache")
                dir.listFiles()?.forEach { file ->
                    if (!file.isDirectory) {
                        file.delete()
                    }
                }
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .edit().putBoolean("flutter.lesson_ready", false).apply()
                result.success(null)
            }
            "markLessonCompleted" -> {
                val lessonId = call.argument<String>("lessonId")
                if (lessonId != null) {
                    val lessonDir = java.io.File(java.io.File(filesDir, "lesson_cache"), lessonId)
                    if (lessonDir.exists() && lessonDir.isDirectory) {
                        java.io.File(lessonDir, "completed.tag").createNewFile()
                        Log.i(TAG, "Marked lesson $lessonId as completed")
                    }
                }
                result.success(null)
            }
            "translateUI" -> handleTranslateUI(call, result)
            "cancelUITranslation" -> handleCancelUITranslation(result)

            "getFilesDir" -> result.success(filesDir.absolutePath)
            else                  -> result.notImplemented()
        }
    }

    private fun purgeOldLessons(context: Context) {
        val dir = java.io.File(context.filesDir, "lesson_cache")
        if (!dir.exists()) return
        val todayStr = java.text.SimpleDateFormat("yyyyMMdd", java.util.Locale.US).format(java.util.Date())
        dir.listFiles()?.forEach { file ->
            if (file.isDirectory && file.name.startsWith("lesson_")) {
                if (!file.name.contains(todayStr)) {
                    Log.i(TAG, "Purging old lesson folder: ${file.name}")
                    file.deleteRecursively()
                }
            } else {
                // Delete legacy/unknown files in root to avoid messing up namespacing
                Log.i(TAG, "Deleting legacy/unknown cache file: ${file.name}")
                file.deleteRecursively()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Handler implementations
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleStartCapture(result: MethodChannel.Result) {
        if (pipelineStatus == PipelineStatus.RECORDING) {
            result.error("ALREADY_RECORDING", "A recording is already in progress.", null)
            return
        }

        if (!hasRecordPermission()) {
            requestRecordPermission()
            result.error("PERMISSION_DENIED",
                "RECORD_AUDIO permission is required. Request sent to user.", null)
            return
        }

        if (serviceConnected && audioCaptureService != null) {
            audioCaptureService!!.startRecording()
            pipelineStatus = PipelineStatus.RECORDING
            result.success(null)
        } else {
            // Service not yet bound — bind it, start recording in onServiceConnected.
            pendingStartResult = result
            
            // Start as foreground service immediately to ensure it's robust
            val serviceIntent = Intent(this, AudioCaptureService::class.java).apply {
                putExtra("is_ambient", false)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            bindAudioService()
        }
    }

    private fun handleStopCapture(result: MethodChannel.Result) {
        if (pipelineStatus != PipelineStatus.RECORDING) {
            result.error("NOT_RECORDING", "No active recording to stop.", null)
            return
        }

        val path = audioCaptureService?.stopRecording()
        unbindAudioService()
        pipelineStatus = PipelineStatus.IDLE

        if (path != null) {
            result.success(path)
        } else {
            result.error("STOP_FAILED", "MediaRecorder failed to stop cleanly.", null)
        }
    }

    /**
     * Batch processing: [m4aPaths] -> decode -> VAD -> pack -> transcribe all.
     */
    private fun handleProcessRawAudioBatch(call: MethodCall, result: MethodChannel.Result) {
        val m4aPaths = call.argument<List<String>>("m4aPaths")
        if (m4aPaths.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "m4aPaths argument is required and must not be empty.", null)
            return
        }

        if (pipelineStatus == PipelineStatus.PROCESSING) {
            result.error("ALREADY_PROCESSING", "A processing job is already running.", null)
            return
        }

        pipelineStatus = PipelineStatus.PROCESSING

        ioScope.launch {
            try {
                val ctx = applicationContext
                val vadModelPath = ModelManager.modelPath(ctx, "silero_vad.onnx")
                val recordingsDir = ModelManager.recordingsDir(ctx)
                
                val allPacketPaths = mutableListOf<String>()

                for (m4aPath in m4aPaths) {
                    Log.i(TAG, "Batch: Processing $m4aPath")
                    
                    // 1. Decode
                    val decodedPath = AudioDecoderHelper.decode(ctx, m4aPath)
                        ?: continue

                    // 2. VAD
                    val jsonTimestamps = AudioProcessorJni.processWithVad(
                        decodedPath, vadModelPath, recordingsDir)

                    if (jsonTimestamps.isEmpty() || jsonTimestamps == "[]" || jsonTimestamps.startsWith("{\"error\"")) {
                        File(decodedPath).delete()
                        continue
                    }

                    // 3. Pack
                    // Use the filename (without extension) as prefix to avoid collisions
                    val prefix = File(m4aPath).nameWithoutExtension
                    val packetPaths = SmartAudioPacker.pack(ctx, decodedPath, jsonTimestamps, prefix)
                    
                    // Cleanup decoded WAV
                    File(decodedPath).delete()
                    
                    allPacketPaths.addAll(packetPaths)
                }

                if (allPacketPaths.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        pipelineStatus = PipelineStatus.IDLE
                        result.success("")
                    }
                    return@launch
                }

                // 4. Transcribe all packets in one session
                Log.i(TAG, "Batch: Transcribing ${allPacketPaths.size} total segments")
                val finalTranscript = GemmaManager.transcribePackets(ctx, allPacketPaths) { msg ->
                    showTranscriptionProgressNotification(msg)
                }

                // 5. Cleanup all packets
                for (path in allPacketPaths) {
                    File(path).delete()
                }

                cancelTranscriptionProgressNotification()

                withContext(Dispatchers.Main) {
                    pipelineStatus = PipelineStatus.IDLE
                    result.success(finalTranscript)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Batch processing failed: ${e.message}", e)
                cancelTranscriptionProgressNotification()
                withContext(Dispatchers.Main) {
                    pipelineStatus = PipelineStatus.IDLE
                    result.error("BATCH_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Full pipeline: M4A → decode → VAD → Whisper → transcript.
     * Runs entirely on [Dispatchers.IO]. Result returned on main thread.
     */
    private fun handleProcessAudio(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "filePath argument is required.", null)
            return
        }

        if (pipelineStatus == PipelineStatus.PROCESSING) {
            result.error("ALREADY_PROCESSING", "A processing job is already running.", null)
            return
        }

        pipelineStatus = PipelineStatus.PROCESSING

        ioScope.launch {
            try {
                val ctx = applicationContext

                // ── Step 1: Decode M4A → 16kHz mono PCM WAV ──────────────
                Log.i(TAG, "Step 1: Decoding M4A...")
                val decodedPath = AudioDecoderHelper.decode(ctx, filePath)
                    ?: throw RuntimeException("AudioDecoderHelper returned null for $filePath")

                // ── Step 2: Silero VAD (C++ ONNX Runtime) — get timestamps ───
                Log.i(TAG, "Step 2: Running Silero VAD (ONNX Runtime C++)...")
                val vadModelPath  = ModelManager.modelPath(ctx, "silero_vad.onnx")
                val recordingsDir = ModelManager.recordingsDir(ctx)
                val jsonTimestamps = AudioProcessorJni.processWithVad(
                                        decodedPath, vadModelPath, recordingsDir)

                // AudioProcessorJni returns: "[{...}]" | "" (no speech) | {"error":...}
                if (jsonTimestamps.isEmpty() || jsonTimestamps == "[]") {
                    java.io.File(decodedPath).delete()
                    Log.i(TAG, "VAD found no speech.")
                    withContext(Dispatchers.Main) {
                        pipelineStatus = PipelineStatus.IDLE
                        result.success("")  // Empty string = no speech detected
                    }
                    return@launch
                }

                if (jsonTimestamps.startsWith("{\"error\"")) {
                    java.io.File(decodedPath).delete()
                    Log.e(TAG, "VAD C++ error: $jsonTimestamps")
                    throw RuntimeException("VAD failed: $jsonTimestamps")
                }

                // ── Step 3: Smart Audio Packer ─────────────────────────────
                Log.i(TAG, "Step 3: Packing audio into 28s segments")
                val packetPaths = SmartAudioPacker.pack(ctx, decodedPath, jsonTimestamps)
                
                // Clean up the full decoded WAV — it can be large.
                java.io.File(decodedPath).delete()
                Log.i(TAG, "Decoded WAV deleted after packing.")

                if (packetPaths.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        pipelineStatus = PipelineStatus.IDLE
                        result.success("")
                    }
                    return@launch
                }

                // ── Step 4: Gemma Transcription ────────────────────────────
                Log.i(TAG, "Step 4: Transcribing ${packetPaths.size} packets with Gemma")
                val transcript = GemmaManager.transcribePackets(ctx, packetPaths) { msg ->
                    showTranscriptionProgressNotification(msg)
                }

                // ── Step 5: Cleanup temporary packet files ─────────────────
                for (path in packetPaths) {
                    java.io.File(path).delete()
                }
                Log.i(TAG, "Cleanup: Deleted all temporary packet WAV files.")

                cancelTranscriptionProgressNotification()

                withContext(Dispatchers.Main) {
                    pipelineStatus = PipelineStatus.IDLE
                    result.success(transcript)
                }

            } catch (e: Exception) {
                Log.e(TAG, "processAudio pipeline failed: ${e.message}", e)
                cancelTranscriptionProgressNotification()
                withContext(Dispatchers.Main) {
                    pipelineStatus = PipelineStatus.IDLE
                    result.error("PIPELINE_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleTranscribeWithGemma(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "filePath argument is required.", null)
            return
        }

        ioScope.launch {
            try {
                val transcript = GemmaManager.transcribePackets(applicationContext, listOf(filePath)) { msg ->
                    showTranscriptionProgressNotification(msg)
                }
                cancelTranscriptionProgressNotification()
                withContext(Dispatchers.Main) {
                    result.success(transcript)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Gemma transcription failed", e)
                cancelTranscriptionProgressNotification()
                withContext(Dispatchers.Main) {
                    result.error("GEMMA_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleGetAudioDurationMs(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
            result.success(0)
            return
        }
        ioScope.launch {
            val durationMs = try {
                val retriever = android.media.MediaMetadataRetriever()
                retriever.setDataSource(filePath)
                val dur = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                retriever.release()
                dur
            } catch (e: Exception) {
                Log.e(TAG, "getAudioDurationMs failed: ${e.message}")
                0L
            }
            withContext(Dispatchers.Main) { result.success(durationMs) }
        }
    }

    private fun handleGenerateLesson(call: MethodCall, result: MethodChannel.Result) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val nativeLang = prefs.getString("flutter.nativeLanguage", "Hindi") ?: "Hindi"
        val targetLang = prefs.getString("flutter.targetLanguage", "English") ?: "English"
        
        val isSpecific = call.argument<Boolean>("isSpecific") ?: false
        val itemId = call.argument<String>("itemId")
        val itemType = call.argument<String>("itemType")
        
        Log.i(TAG, "Starting on-demand lesson: native=$nativeLang target=$targetLang isSpecific=$isSpecific itemId=$itemId type=$itemType")
        LessonGenerationForegroundService.start(applicationContext, nativeLang, targetLang, isSpecific, itemId, itemType)
        result.success(null)
    }

    private fun handleTranslateUI(call: MethodCall, result: MethodChannel.Result) {
        val uiElements = call.argument<Map<String, String>>("uiElements")
        val targetLanguage = call.argument<String>("targetLanguage")
        
        if (uiElements == null || targetLanguage == null) {
            result.error("INVALID_ARGUMENT", "uiElements and targetLanguage are required.", null)
            return
        }

        try {
            val jsonStr = JSONObject(uiElements as Map<*, *>).toString()
            UITranslationForegroundService.start(applicationContext, targetLanguage, jsonStr)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start UI translation service: ${e.message}", e)
            result.error("TRANSLATION_ERROR", e.message, null)
        }
    }

    private fun handleCancelUITranslation(result: MethodChannel.Result) {
        try {
            UITranslationForegroundService.stop(applicationContext)
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_translating_ui", false).apply()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel UI translation: ${e.message}", e)
            result.error("CANCEL_ERROR", e.message, null)
        }
    }



    private fun handleCancelProcessing(result: MethodChannel.Result) {
        // The current implementation does not support mid-inference cancellation
        // (whisper.cpp is synchronous). Status will reset to IDLE when inference
        // completes. This is a no-op placeholder for future async cancellation.
        Log.w(TAG, "cancelProcessing() called — inference cannot be interrupted mid-flight.")
        result.success(null)
    }

    private fun handleEnsureModels(result: MethodChannel.Result) {
        ioScope.launch {
            val ready = ModelManager.ensureModelsReady(applicationContext)
            withContext(Dispatchers.Main) { result.success(ready) }
        }
    }

    private fun handleTriggerScreenshotNotification(result: MethodChannel.Result) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "screenshot_channel",
                "Screenshot Requests",
                NotificationManager.IMPORTANCE_HIGH
            )
            notificationManager.createNotificationChannel(channel)
        }

        val allowIntent = Intent(this, ScreenshotReceiver::class.java).apply {
            action = ScreenshotReceiver.ACTION_ALLOW
        }
        val allowPendingIntent = PendingIntent.getBroadcast(
            this, 0, allowIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val denyIntent = Intent(this, ScreenshotReceiver::class.java).apply {
            action = ScreenshotReceiver.ACTION_DENY
        }
        val denyPendingIntent = PendingIntent.getBroadcast(
            this, 1, denyIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, "screenshot_channel")
            .setSmallIcon(android.R.drawable.ic_menu_camera) // using a built-in icon
            .setContentTitle("Screenshot Request")
            .setContentText("Circadian Lingo wants a snapshot of your screen for lesson context")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .addAction(0, "Allow", allowPendingIntent)
            .addAction(0, "Deny", denyPendingIntent)
            .setAutoCancel(true)

        notificationManager.notify(ScreenshotReceiver.NOTIFICATION_ID, builder.build())
        result.success(null)
    }

    private fun handleGetSavedAudioRecordings(result: MethodChannel.Result) {
        val recordingsDir = File(filesDir, "recordings")
        val files = if (recordingsDir.exists()) {
            recordingsDir.listFiles()?.map { it.absolutePath } ?: emptyList()
        } else {
            emptyList()
        }
        result.success(files)
    }

    private fun handleGetSavedScreenshots(result: MethodChannel.Result) {
        val capturesDir = File(filesDir, "captures")
        if (!capturesDir.exists()) {
            result.success(emptyList<Map<String, String?>>())
            return
        }

        val files = capturesDir.listFiles() ?: emptyArray()
        val events = mutableMapOf<String, MutableMap<String, String?>>()

        for (file in files) {
            val name = file.name
            val timestamp = when {
                name.startsWith("img_") -> name.substringAfter("img_").substringBeforeLast(".jpg")
                name.startsWith("ctx_") -> name.substringAfter("ctx_").substringBeforeLast(".txt")
                name.startsWith("screenshot_") -> name.substringAfter("screenshot_").substringBeforeLast(".jpg")
                name.startsWith("text_context_") -> name.substringAfter("text_context_").substringBeforeLast(".txt")
                else -> null
            }

            if (timestamp != null) {
                val event = events.getOrPut(timestamp) { mutableMapOf("id" to timestamp, "imagePath" to null, "textPath" to null) }
                if (name.endsWith(".jpg")) {
                    event["imagePath"] = file.absolutePath
                } else if (name.endsWith(".txt")) {
                    event["textPath"] = file.absolutePath
                }
            }
        }

        result.success(events.values.toList())
    }

    private fun handleDeleteScreenshot(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        if (filePath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "filePath argument is required.", null)
            return
        }
        val file = File(filePath)
        if (file.exists()) {
            if (file.delete()) {
                result.success(true)
            } else {
                result.error("DELETE_FAILED", "Could not delete file.", null)
            }
        } else {
            result.success(true)
        }
    }

    private fun handleSaveSettings(call: MethodCall, result: MethodChannel.Result) {
        val startHour = call.argument<Int>("startHour") ?: 9
        val endHour = call.argument<Int>("endHour") ?: 17
        val ambientAudioDuration = call.argument<Int>("ambientAudioDuration") ?: 30
        val screenLimit = call.argument<Int>("dailyScreenCaptureLimit") ?: 5
        val audioLimit = call.argument<Int>("dailyAudioCaptureLimit") ?: 5
        
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("flutter.contextWindowStartHour", startHour.toLong())
            .putLong("flutter.contextWindowEndHour", endHour.toLong())
            .putLong("flutter.ambientAudioDuration", ambientAudioDuration.toLong())
            .putLong("flutter.dailyScreenCaptureLimit", screenLimit.toLong())
            .putLong("flutter.dailyAudioCaptureLimit", audioLimit.toLong())
            .apply()
            
        // Re-enqueue WorkManager so it picks up the new time window immediately
        val isEnabled = prefs.getBoolean("flutter.smartContextSchedulingEnabled", false)
        if (isEnabled) {
            ScreenshotWorkManager.enqueueNextScreenshotWork(applicationContext)
            AudioWorkManager.enqueueNextAudioWork(applicationContext)
        }
        
        result.success(null)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Service binding
    // ─────────────────────────────────────────────────────────────────────────

    private fun bindAudioService() {
        val intent = Intent(this, AudioCaptureService::class.java)
        // BIND_AUTO_CREATE starts the service if it isn't running.
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        Log.i(TAG, "Binding AudioCaptureService...")
    }

    private fun unbindAudioService() {
        if (serviceConnected) {
            unbindService(serviceConnection)
            serviceConnected = false
            audioCaptureService = null
            Log.i(TAG, "AudioCaptureService unbound.")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Permission handling
    // ─────────────────────────────────────────────────────────────────────────

    private fun hasRecordPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

    private fun requestRecordPermission() {
        val perms = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // POST_NOTIFICATIONS required for the foreground service notification on API 33+
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        requestPermissions(perms.toTypedArray(), RC_RECORD)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    private fun showTranscriptionProgressNotification(message: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "transcription_progress_channel"
        val notificationId = 1003
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Transcription Progress",
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }
        
        val cancelIntent = Intent(this, NotificationCancelReceiver::class.java)
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this, 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle("Transcribing Audio")
            .setContentText(message)
            .setProgress(0, 0, true)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
            .build()
            
        nm.notify(notificationId, notification)
    }
    
    private fun cancelTranscriptionProgressNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(1003)
    }

    private fun showDownloadProgressNotification(progress: Double, bytesDownloaded: Long, bytesTotal: Long, speedBytesPerSec: Double) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "download_progress_channel"
        val notificationId = 1004
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Model Download Progress",
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }
        
        val mbDownloaded = bytesDownloaded.toDouble() / (1024.0 * 1024.0)
        val mbTotal = bytesTotal.toDouble() / (1024.0 * 1024.0)
        val speedMb = speedBytesPerSec / (1024.0 * 1024.0)
        
        val progressPercent = if (progress >= 0.0) (progress * 100.0).toInt() else 0
        
        val contentText = if (bytesTotal > 0) {
            String.format(
                "%.1f MB / %.1f MB (%.1f%%) • %.2f MB/s",
                mbDownloaded, mbTotal, progress * 100.0, speedMb
            )
        } else {
            String.format(
                "%.1f MB • %.2f MB/s",
                mbDownloaded, speedMb
            )
        }
        
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading Circadian Lingo Brain")
            .setContentText(contentText)
            .setProgress(100, progressPercent, false)
            .setOngoing(true)
            
        nm.notify(notificationId, builder.build())
    }
    
    private fun cancelDownloadProgressNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(1004)
    }

    private fun startProgressPolling() {
        ioScope.launch {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            var lastBytes = -1L
            var lastTime = System.currentTimeMillis()
            while (isActive && downloadId != -1L) {
                val query = DownloadManager.Query().setFilterById(downloadId)
                val cursor = dm.query(query)
                if (cursor != null && cursor.moveToFirst()) {
                    val bytesDownloaded = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val bytesTotal = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    val status = cursor.getInt(cursor.getColumnIndex(DownloadManager.COLUMN_STATUS))
                    
                    val progress = if (bytesTotal > 0) (bytesDownloaded.toDouble() / bytesTotal.toDouble()) else 0.0
                    
                    val currentTime = System.currentTimeMillis()
                    val speedBytesPerSec = if (lastBytes >= 0L && bytesDownloaded >= lastBytes) {
                        val timeDiffMs = currentTime - lastTime
                        if (timeDiffMs > 0) {
                            ((bytesDownloaded - lastBytes) * 1000.0) / timeDiffMs
                        } else {
                            0.0
                        }
                    } else {
                        0.0
                    }
                    lastBytes = bytesDownloaded
                    lastTime = currentTime
                    
                    withContext(Dispatchers.Main) {
                        progressEventSink?.success(mapOf(
                            "status" to "downloading",
                            "progress" to progress,
                            "bytesDownloaded" to bytesDownloaded,
                            "bytesTotal" to bytesTotal,
                            "speedBytesPerSec" to speedBytesPerSec
                        ))
                        showDownloadProgressNotification(progress, bytesDownloaded, bytesTotal, speedBytesPerSec)
                    }
                    
                    if (status == DownloadManager.STATUS_SUCCESSFUL || status == DownloadManager.STATUS_FAILED) {
                        withContext(Dispatchers.Main) {
                            cancelDownloadProgressNotification()
                        }
                        cursor.close()
                        break
                    }
                }
                cursor?.close()
                delay(1000)
            }
        }
    }

    override fun onDestroy() {
        cancelDownloadProgressNotification()
        unregisterReceiver(downloadReceiver)
        unbindAudioService()
        ioScope.cancel()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
}
