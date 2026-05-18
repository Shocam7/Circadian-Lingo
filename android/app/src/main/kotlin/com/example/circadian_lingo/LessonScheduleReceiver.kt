package com.example.circadian_lingo

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class LessonScheduleReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LessonScheduleReceiver"
        const val ACTION_START_GENERATION = "com.example.circadian_lingo.ACTION_START_GENERATION"
        const val ACTION_CANCEL_GENERATION = "com.example.circadian_lingo.ACTION_CANCEL_GENERATION"
        private const val ALERT_NOTIFICATION_ID = 1004
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "onReceive: action=$action")

        // Cancel the alert notification in all cases
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ALERT_NOTIFICATION_ID)

        if (action == ACTION_START_GENERATION) {
            Log.i(TAG, "Force-start daily lesson generation requested by user.")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val nativeLang = prefs.getString("flutter.nativeLanguage", "Hindi") ?: "Hindi"
            val targetLang = prefs.getString("flutter.targetLanguage", "English") ?: "English"

            // Start the foreground service immediately
            LessonGenerationForegroundService.start(
                context = context,
                nativeLang = nativeLang,
                targetLang = targetLang,
                isSpecific = false,
                itemId = null,
                itemType = null
            )
        } else if (action == ACTION_CANCEL_GENERATION) {
            Log.i(TAG, "Daily lesson generation alert dismissed/skipped by user.")
        }
    }
}
