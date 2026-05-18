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
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Foreground service for translating the UI into the user's native language.
 * Runs independently of the Flutter app lifecycle so the user can background/close the app.
 */
class UITranslationForegroundService : Service() {

    companion object {
        private const val TAG = "UITranslationService"
        private const val CHANNEL_ID = "ui_translation_channel"
        private const val NOTIFICATION_ID = 2002

        private const val EXTRA_TARGET_LANG = "targetLang"
        private const val EXTRA_UI_ELEMENTS_JSON = "uiElementsJson"

        fun start(context: Context, targetLang: String, uiElementsJson: String) {
            val intent = Intent(context, UITranslationForegroundService::class.java).apply {
                putExtra(EXTRA_TARGET_LANG, targetLang)
                putExtra(EXTRA_UI_ELEMENTS_JSON, uiElementsJson)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, UITranslationForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Preparing translation...", 0, 100))
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val targetLang = intent?.getStringExtra(EXTRA_TARGET_LANG) ?: return START_NOT_STICKY
        val uiElementsJsonStr = intent.getStringExtra(EXTRA_UI_ELEMENTS_JSON) ?: return START_NOT_STICKY

        scope.launch {
            try {
                // Parse UI elements
                val uiElementsObj = JSONObject(uiElementsJsonStr)
                val uiElements = mutableMapOf<String, String>()
                uiElementsObj.keys().forEach { key ->
                    uiElements[key] = uiElementsObj.getString(key)
                }

                Log.i(TAG, "Starting UI translation for ${uiElements.size} items to $targetLang")

                // Let flutter know we're busy
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.is_translating_ui", true).apply()

                val translatedMap = GemmaManager.translateUIElements(
                    context = applicationContext,
                    uiElements = uiElements,
                    targetLanguage = targetLang,
                    onProgress = { current, total ->
                        updateNotification("Translating UI: $current / $total", current, total)
                    }
                )

                if (translatedMap.isNotEmpty()) {
                    Log.i(TAG, "UI translation complete! Saving to SharedPreferences.")
                    val editor = prefs.edit()
                    val resultJson = JSONObject(translatedMap as Map<*, *>)
                    
                    // Direct save so app uses it next launch/resume
                    editor.putString("flutter.uiStringsJson", resultJson.toString())
                    editor.putBoolean("flutter.isUiLocalized", true)
                    editor.putBoolean("flutter.is_translating_ui", false)
                    
                    editor.apply()

                    // Signal event channel if app is currently open
                    MainActivity.notifyUITranslationComplete()
                } else {
                    Log.w(TAG, "Translation returned empty map.")
                    prefs.edit().putBoolean("flutter.is_translating_ui", false).apply()
                }

            } catch (e: Exception) {
                Log.e(TAG, "UI translation error: ${e.message}", e)
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.is_translating_ui", false).apply()
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

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CircadianLingo:UITranslation")
            wakeLock?.acquire(30 * 60 * 1000L) // 30 minutes max safety limit
            Log.i(TAG, "WakeLock acquired for UI translation.")
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            Log.i(TAG, "WakeLock released for UI translation.")
        }
        wakeLock = null
    }

    private fun updateNotification(message: String, progress: Int, max: Int) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(message, progress, max))
    }

    private fun buildNotification(contentText: String, progress: Int, max: Int): Notification {
        val cancelIntent = Intent(this, NotificationCancelReceiver::class.java)
        val cancelPendingIntent = PendingIntent.getBroadcast(
            this, 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Translating Interface")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setProgress(max, progress, max == 0 || progress == 0)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "UI Translation",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shown while Gemma is translating the app interface"
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }
}
