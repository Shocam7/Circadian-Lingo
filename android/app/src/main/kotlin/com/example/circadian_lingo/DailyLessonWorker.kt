package com.example.circadian_lingo

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaMetadataRetriever
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File

/**
 * Daily scheduled lesson generation worker.
 *
 * Runs at the user-specified time daily.
 * Programmatically checks device-idle and battery constraints before running.
 * If constraints fail, shows a high-priority notification to let the user manual-start or dismiss.
 * Always schedules the next daily run before exiting.
 */
class DailyLessonWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "DailyLessonWorker"
        private const val ALERT_NOTIFICATION_ID = 1004
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        Log.i(TAG, "doWork started")

        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )

        // ── 1. Check if automatic generation is enabled ──────────────────────────
        val enabled = prefs.getBoolean("flutter.lessonAutoGenerationEnabled", true)
        if (!enabled) {
            Log.i(TAG, "Automatic daily lesson generation is disabled. Aborting.")
            return@withContext Result.success()
        }

        // ── 2. Check programmatic constraints ───────────────────────────────────
        val isIdle = isDeviceIdle(applicationContext)
        val isBatteryOk = isBatteryNotLow(applicationContext)
        
        Log.i(TAG, "Constraint check: isIdle=$isIdle  isBatteryOk=$isBatteryOk")
        if (!isIdle || !isBatteryOk) {
            Log.w(TAG, "Constraints failed. Postponing automatic generation and notifying user.")
            
            // Reschedule for tomorrow
            LessonWorkManager.scheduleDailyLesson(applicationContext)
            
            // Show alert notification with actions
            showConstraintsAlertNotification(applicationContext)
            return@withContext Result.success()
        }

        // ── 3. Read language settings ─────────────────────────────────────────
        val nativeLang = prefs.getString("flutter.nativeLanguage", "Hindi") ?: "Hindi"
        val targetLang = prefs.getString("flutter.targetLanguage", "English") ?: "English"
        Log.i(TAG, "Languages: native=$nativeLang  target=$targetLang")

        // ── 4. Collect usable audio captures (.m4a files in recordings/) ──────
        val recordingsDir = File(applicationContext.filesDir, "recordings")
        val audioPaths = if (recordingsDir.exists()) {
            recordingsDir.listFiles()
                ?.filter { it.extension == "m4a" && isAudioUsable(it) }
                ?.map { it.absolutePath }
                ?: emptyList()
        } else emptyList()
        Log.i(TAG, "Usable audio captures: ${audioPaths.size}")

        // ── 5. Collect usable text captures (.txt files in captures/) ─────────
        val capturesDir = File(applicationContext.filesDir, "captures")
        val textCaptures = if (capturesDir.exists()) {
            capturesDir.listFiles()
                ?.filter { it.extension == "txt" }
                ?.mapNotNull { file ->
                    try {
                        val text = file.readText()
                        val wordCount = text.trim().split(Regex("\\s+")).count { it.isNotBlank() }
                        if (wordCount >= 20) text else null  // quality threshold
                    } catch (_: Exception) { null }
                }
                ?: emptyList()
        } else emptyList()
        Log.i(TAG, "Usable text captures: ${textCaptures.size}")

        // ── 6. Abort if no usable captures ───────────────────────────────────
        if (audioPaths.isEmpty() && textCaptures.isEmpty()) {
            Log.w(TAG, "No usable captures — skipping generation (Quick Review mode)")
            prefs.edit().putBoolean("flutter.lesson_ready", false).apply()
            
            // Reschedule for tomorrow
            LessonWorkManager.scheduleDailyLesson(applicationContext)
            return@withContext Result.success()
        }

        // ── 7. Read learned words for prompt injection ─────────────────────
        val learnedWords = loadLearnedWords()

        // ── 8. Setup Notification for progress ─────────────────────────────
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channelId = "daily_lesson_channel"
        val notificationId = 1002

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Overnight Lesson Generation",
                android.app.NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress for daily lesson generation"
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        val cancelIntent = Intent(applicationContext, NotificationCancelReceiver::class.java)
        val cancelPendingIntent = android.app.PendingIntent.getBroadcast(
            applicationContext, 0, cancelIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        // ── 9. Generate lesson (single Engine) ─────────────────────────────
        val success = GemmaManager.generateLesson(
            context        = applicationContext,
            audioPaths     = audioPaths,
            textCaptures   = textCaptures,
            nativeLanguage = nativeLang,
            targetLanguage = targetLang,
            learnedWords   = learnedWords,
            onProgress     = { msg -> 
                val notification = androidx.core.app.NotificationCompat.Builder(applicationContext, channelId)
                    .setSmallIcon(android.R.drawable.ic_popup_sync)
                    .setContentTitle("Generating Daily Lesson")
                    .setContentText(msg)
                    .setProgress(0, 0, true)
                    .setOngoing(true)
                    .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
                    .build()
                notificationManager.notify(notificationId, notification)
            }
        )

        notificationManager.cancel(notificationId)

        Log.i(TAG, "doWork complete — success=$success")
        if (success) {
            prefs.edit().putBoolean("flutter.lesson_ready", true).apply()
            
            // Reschedule for tomorrow
            LessonWorkManager.scheduleDailyLesson(applicationContext)
            return@withContext Result.success()
        } else {
            return@withContext Result.retry()
        }
    }

    // ── Constraints Programmatic Check Helpers ─────────────────────────────────

    private fun isBatteryNotLow(context: Context): Boolean {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent != null) {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            if (isCharging) return true
            
            if (level >= 0 && scale > 0) {
                val pct = level * 100 / scale.toFloat()
                return pct >= 15f // Standard battery low boundary
            }
        }
        return true
    }

    private fun isDeviceIdle(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val isScreenOff = !pm.isInteractive
        val isDozeIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isDeviceIdleMode
        } else {
            false
        }
        return isScreenOff || isDozeIdle
    }

    private fun showConstraintsAlertNotification(context: Context) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channelId = "daily_lesson_alert_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Daily Lesson Alert",
                android.app.NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies when daily scheduled lesson could not auto-generate due to device state."
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Action: Start Now
        val startIntent = Intent(context, LessonScheduleReceiver::class.java).apply {
            action = LessonScheduleReceiver.ACTION_START_GENERATION
        }
        val startPendingIntent = android.app.PendingIntent.getBroadcast(
            context, 1, startIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Dismiss
        val cancelIntent = Intent(context, LessonScheduleReceiver::class.java).apply {
            action = LessonScheduleReceiver.ACTION_CANCEL_GENERATION
        }
        val cancelPendingIntent = android.app.PendingIntent.getBroadcast(
            context, 2, cancelIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = androidx.core.app.NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Daily Lesson Ready")
            .setContentText("Tap Start Now to generate, or dismiss to skip.")
            .setStyle(androidx.core.app.NotificationCompat.BigTextStyle()
                .bigText("Your scheduled daily lesson is ready to generate, but your device is active or battery is low. Tap Start Now to generate anyway, or dismiss to skip today."))
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setCategory(androidx.core.app.NotificationCompat.CATEGORY_ALARM)
            .addAction(android.R.drawable.ic_media_play, "Start Now", startPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", cancelPendingIntent)
            .build()

        notificationManager.notify(ALERT_NOTIFICATION_ID, notification)
    }

    // ── Quality Helpers ───────────────────────────────────────────────────────

    /** Quality threshold: audio must be at least 10 seconds. */
    private fun isAudioUsable(file: File): Boolean {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(file.absolutePath)
            val durationMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            retriever.release()
            durationMs >= 10_000L
        } catch (_: Exception) { false }
    }

    /** Load personal learned words from SharedPreferences (same store as Dart). */
    private fun loadLearnedWords(): List<String> {
        return try {
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val raw = prefs.getString("flutter.learned_words_store", null) ?: return emptyList()
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it).getString("word") }
        } catch (_: Exception) { emptyList() }
    }
}
