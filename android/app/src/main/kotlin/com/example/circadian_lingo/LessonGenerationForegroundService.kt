package com.example.circadian_lingo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.io.File

/**
 * Foreground service for on-demand "Specific Capture Lesson" generation.
 *
 * Used when the user taps "Generate Daily Lesson" from the Privacy Dashboard
 * while the app is in the foreground. Shows a persistent notification while
 * Gemma is running, then auto-stops when done.
 *
 * Produces a reduced ALU set compared to overnight generation:
 *   1 VocabPreview, 1 WordCard, 1 Story/Dialogue, 2 QuizItems, 2 Flashcards
 */
class LessonGenerationForegroundService : Service() {

    companion object {
        private const val TAG            = "LessonGenFGService"
        private const val CHANNEL_ID     = "lesson_generation"
        private const val NOTIFICATION_ID = 1001

        private const val EXTRA_NATIVE_LANG = "nativeLang"
        private const val EXTRA_TARGET_LANG = "targetLang"
        private const val EXTRA_IS_SPECIFIC = "isSpecific"
        private const val EXTRA_ITEM_ID = "itemId"
        private const val EXTRA_ITEM_TYPE = "itemType"

        fun start(context: Context, nativeLang: String, targetLang: String, isSpecific: Boolean, itemId: String?, itemType: String?) {
            val intent = Intent(context, LessonGenerationForegroundService::class.java).apply {
                putExtra(EXTRA_NATIVE_LANG, nativeLang)
                putExtra(EXTRA_TARGET_LANG, targetLang)
                putExtra(EXTRA_IS_SPECIFIC, isSpecific)
                putExtra(EXTRA_ITEM_ID, itemId)
                putExtra(EXTRA_ITEM_TYPE, itemType)
            }
            context.startForegroundService(intent)
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Preparing your lesson…"))
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nativeLang = intent?.getStringExtra(EXTRA_NATIVE_LANG) ?: "Hindi"
        val targetLang = intent?.getStringExtra(EXTRA_TARGET_LANG) ?: "English"
        val isSpecific = intent?.getBooleanExtra(EXTRA_IS_SPECIFIC, false) ?: false
        val itemId = intent?.getStringExtra(EXTRA_ITEM_ID)
        val itemType = intent?.getStringExtra(EXTRA_ITEM_TYPE)

        Log.i(TAG, "onStartCommand: native=$nativeLang, target=$targetLang, isSpecific=$isSpecific, itemId=$itemId, itemType=$itemType")

        scope.launch {
            try {

                
                val audioPaths = if (isSpecific) {
                    if (itemType == "audio_raw") collectAudio(true, itemId) else emptyList()
                } else {
                    collectAudio(false, null)
                }
                
                val textCaptures = if (isSpecific) {
                    if (itemType == "screen_context") collectText(true, itemId) else emptyList()
                } else {
                    collectText(false, null)
                }
                

                
                val learnedWords = loadLearnedWords()


                val success = GemmaManager.generateLesson(
                    context        = applicationContext,
                    audioPaths     = audioPaths,
                    textCaptures   = textCaptures,
                    nativeLanguage = nativeLang,
                    targetLanguage = targetLang,
                    learnedWords   = learnedWords,
                    isSpecific     = isSpecific,
                    onProgress     = { msg ->
                        updateNotification(msg)
                    }
                )

                if (!success) {
                    Log.w(TAG, "Lesson generation failed (model likely missing).")
                    return@launch // Stop here, failure is already handled in GemmaManager or by previous log
                }

                Log.i(TAG, "Lesson generation complete. Type: ${if (isSpecific) "Specific Capture Lesson" else "Daily Lesson"}")

                // Tag this lesson as "Specific" for the Flutter UI colors
                val lessonDir = File(filesDir, "lesson_cache")
                if (!lessonDir.exists()) lessonDir.mkdirs()
                val markerFile = File(lessonDir, "is_specific.tag")
                if (isSpecific) {
                    markerFile.createNewFile()
                } else {
                    if (markerFile.exists()) markerFile.delete()
                }

                // Mark as ready so Flutter polling can finish
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.lesson_ready", true).apply()

                Log.i(TAG, "Lesson generation complete")
            } catch (e: Exception) {
                // If it fails, ensure the flag is false so the UI shows an error or empty state
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.lesson_ready", false).apply()
                Log.e(TAG, "Lesson generation error: ${e.message}", e)
            } finally {
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CircadianLingo:LessonGeneration")
            wakeLock?.acquire(60 * 60 * 1000L) // 1 hour max safety limit
            Log.i(TAG, "WakeLock acquired for lesson generation.")
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            Log.i(TAG, "WakeLock released for lesson generation.")
        }
        wakeLock = null
    }

    private fun collectAudio(isSpecific: Boolean, itemId: String?): List<String> {
        val dir = File(filesDir, "recordings")
        if (!dir.exists()) {
            Log.w(TAG, "Recordings directory does not exist.")
            return emptyList()
        }
        
        return if (isSpecific && itemId != null) {
            // Check if itemId is already a full path
            if (itemId.startsWith("/")) {
                val file = File(itemId)
                if (file.exists()) {
                    Log.i(TAG, "Found specific audio via path: ${file.absolutePath}")
                    return listOf(file.absolutePath)
                }
            }
            
            // Search for file containing the itemId (timestamp) and matching extension
            val matches = dir.listFiles()?.filter { it.name.contains(itemId) && it.extension == "m4a" }
            if (!matches.isNullOrEmpty()) {
                Log.i(TAG, "Found specific audio via ID match: ${matches[0].absolutePath}")
                listOf(matches[0].absolutePath)
            } else {
                Log.w(TAG, "Specific audio file not found for ID: $itemId")
                emptyList()
            }
        } else {
            val files = dir.listFiles()?.filter { it.extension == "m4a" }?.map { it.absolutePath } ?: emptyList()
            Log.i(TAG, "Found ${files.size} daily audio files.")
            files
        }
    }

    private fun collectText(isSpecific: Boolean, itemId: String?): List<String> {
        val dir = File(filesDir, "captures")
        if (!dir.exists()) {
            Log.w(TAG, "Captures directory does not exist.")
            return emptyList()
        }
        
        return if (isSpecific && itemId != null) {
            // Search for file containing the itemId (timestamp) and matching extension
            val matches = dir.listFiles()?.filter { it.name.contains(itemId) && it.extension == "txt" }
            if (!matches.isNullOrEmpty()) {
                Log.i(TAG, "Found specific text via ID match: ${matches[0].absolutePath}")
                val text = matches[0].readText()
                listOf(text) // bypass word count threshold for specific lessons
            } else {
                Log.w(TAG, "Specific text file not found for ID: $itemId")
                emptyList()
            }
        } else {
            val texts = dir.listFiles()?.filter { it.extension == "txt" }
                ?.mapNotNull { f ->
                    try {
                        val text = f.readText()
                        val words = text.trim().split(Regex("\\s+")).count { it.isNotBlank() }
                        if (words >= 20) text else null
                    } catch (_: Exception) { null }
                } ?: emptyList()
            Log.i(TAG, "Found ${texts.size} usable daily text files.")
            texts
        }
    }

    private fun loadLearnedWords(): List<String> {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.learned_words_store", null) ?: return emptyList()
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it).getString("word") }
        } catch (_: Exception) { emptyList() }
    }

    private fun updateNotification(message: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(message))
    }

    private fun buildNotification(contentText: String): Notification {
        val cancelIntent = Intent(this, NotificationCancelReceiver::class.java)
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this, 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Generating lesson…")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setProgress(0, 0, true)  // indeterminate
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Lesson Generation",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shown while Gemma is generating your daily lesson"
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }
}
