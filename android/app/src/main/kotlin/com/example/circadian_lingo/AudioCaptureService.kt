package com.example.circadian_lingo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaRecorder
import android.os.*
import android.util.Log
import java.io.File
import kotlinx.coroutines.*

/**
 * AudioCaptureService — Android 14 Compliant Foreground Recording Service
 *
 * Records compressed AAC audio (.m4a) to the app's internal filesDir/recordings/.
 * The recording runs continuously until [stopRecording] is called — aligned with
 * the Idle-Shift Pipeline's "Silent Collector" phase.
 *
 * Android 14 compliance:
 *   - Uses FOREGROUND_SERVICE_TYPE_MICROPHONE for the startForeground() call.
 *   - Declares the matching <service android:foregroundServiceType="microphone"> in
 *     AndroidManifest.xml.
 *   - POST_NOTIFICATIONS permission is declared for the required notification.
 *
 * Lifecycle:
 *   1. MainActivity binds this service via Intent.
 *   2. Calls [startRecording] — service starts foreground + MediaRecorder.
 *   3. App may be backgrounded; service keeps recording.
 *   4. Calls [stopRecording] — MediaRecorder is stopped and the .m4a path returned.
 *   5. MainActivity unbinds; service stops itself.
 */
class AudioCaptureService : Service() {

    companion object {
        private const val TAG                 = "AudioCaptureService"
        private const val NOTIFICATION_ID     = 1001
        private const val CHANNEL_ID          = "circadian_audio_capture"
        private const val CHANNEL_NAME        = "Audio Context Capture"
        
        var isRunning = false
            private set
    }

    // ── Local Binder for same-process communication ───────────────────────────
    inner class LocalBinder : Binder() {
        fun getService(): AudioCaptureService = this@AudioCaptureService
    }

    private val binder = LocalBinder()

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null
    private var _isRecording = false
    
    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    private var isAmbient = false
    private var filePrefix = "recording"

    val isRecording: Boolean get() = _isRecording

    // ─────────────────────────────────────────────────────────────────────────
    // Service lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Handle direct start (from AudioNotificationReceiver or manual startService)
        isAmbient = intent?.getBooleanExtra("is_ambient", false) ?: false
        filePrefix = if (isAmbient) "ambient" else "manual"
        
        if (!isRunning && !_isRecording) {
            startRecording()
        }
        
        return START_STICKY
    }

    override fun onDestroy() {
        if (_isRecording) {
            Log.w(TAG, "Service destroyed while recording — releasing MediaRecorder.")
            stopRecording()
        }
        serviceJob.cancel()
        releaseWakeLock()
        isRunning = false
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public API (called via Binder from MainActivity)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Starts the foreground service with a persistent notification and begins
     * recording compressed AAC audio to [filesDir]/recordings/.
     *
     * Must be called from the main thread (Service binding callback).
     * The recording runs continuously until [stopRecording] is called.
     */
    fun startRecording() {
        if (_isRecording) {
            Log.w(TAG, "startRecording() called while already recording — ignored.")
            return
        }

        // ── Promote to foreground with MICROPHONE type ────────────────────
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        isRunning = true

        // ── Prepare output file ───────────────────────────────────────────
        val recordingsDir = File(filesDir, "recordings")
        recordingsDir.mkdirs()
        val outputFile = File(recordingsDir, "${filePrefix}_${System.currentTimeMillis()}.m4a")
        currentRecordingPath = outputFile.absolutePath

        // ── Initialise MediaRecorder ──────────────────────────────────────
        // Use the context-aware constructor (API 31+) where available;
        // fall back to the deprecated no-arg constructor for API 26–30.
        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        recorder.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(16000)   // Strictly 16kHz for Whisper
            setAudioChannels(1)           // Mono
            setAudioEncodingBitRate(256_000)
            setOutputFile(currentRecordingPath)
            prepare()
            start()
        }

        mediaRecorder = recorder
        _isRecording = true

        Log.i(TAG, "Recording started → ${currentRecordingPath} (isAmbient=$isAmbient)")

        if (isAmbient) {
            scheduleAmbientTimeout()
        }
    }

    /**
     * Stops the active recording and returns the absolute path to the .m4a file.
     *
     * MediaRecorder.stop() finalises the MPEG-4 container, so even if the
     * process was briefly paused, the file should be readable. If stop() throws
     * (e.g., recording started but no data was written), the partial file is
     * deleted and null is returned.
     *
     * @return Absolute path to the completed .m4a, or null on failure.
     */
    fun stopRecording(): String? {
        if (!_isRecording || mediaRecorder == null) {
            Log.w(TAG, "stopRecording() called but not recording — returning null.")
            return null
        }

        val path = currentRecordingPath

        try {
            mediaRecorder?.stop()
            Log.i(TAG, "Recording stopped. File: $path")
        } catch (e: IllegalStateException) {
            // Can happen if stop() is called before any audio frames were written.
            Log.e(TAG, "MediaRecorder.stop() threw IllegalStateException: ${e.message}")
            path?.let { File(it).delete() }
            releaseRecorder()
            stopForeground(STOP_FOREGROUND_REMOVE)
            return null
        } finally {
            releaseRecorder()
        }

        stopForeground(STOP_FOREGROUND_REMOVE)
        releaseWakeLock()
        return path
    }

    private fun scheduleAmbientTimeout() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // Flutter saves as Long in SharedPreferences for some reason sometimes, or Int. 
        // Our settings_provider uses prefs.setInt, but let's be safe.
        val durationMins = prefs.getLong("flutter.ambientAudioDuration", 30L).toInt()
        val durationMs = durationMins * 60 * 1000L
        
        Log.i(TAG, "Scheduling ambient timeout in $durationMins minutes.")
        
        serviceScope.launch {
            delay(durationMs)
            if (_isRecording && isAmbient) {
                Log.i(TAG, "Ambient timeout reached. Stopping recording.")
                stopRecording()
                stopSelf() // Stop service if it was started ambiently
            }
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CircadianLingo:AudioCapture")
            wakeLock?.acquire(120 * 60 * 1000L) // 2 hour max safety limit
            Log.i(TAG, "WakeLock acquired.")
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            Log.i(TAG, "WakeLock released.")
        }
        wakeLock = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun releaseRecorder() {
        try {
            mediaRecorder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "MediaRecorder.release() threw: ${e.message}")
        }
        mediaRecorder = null
        _isRecording = false
        currentRecordingPath = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW  // IMPORTANCE_LOW = no sound, stays quiet
            ).apply {
                description = "Used while Circadian Lingo captures ambient context"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val contentText = if (isAmbient) {
            "Circadian Lingo is capturing ambient context"
        } else {
            "Circadian Lingo is recording audio"
        }

        return builder
            .setContentTitle("Circadian Lingo")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)       // Cannot be swiped away
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }
}
