package com.example.circadian_lingo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i("BootReceiver", "Device rebooted. Re-scheduling context tasks.")
            
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean("flutter.smartContextSchedulingEnabled", false)
            
            if (isEnabled) {
                ScreenshotWorkManager.enqueueNextScreenshotWork(context)
                AudioWorkManager.enqueueNextAudioWork(context)
            } else {
                Log.i("BootReceiver", "Smart scheduling disabled. No work enqueued.")
            }
            // Schedule daily lesson generation at user-selected time (constrained programmatically in worker)
            LessonWorkManager.scheduleDailyLesson(context)
        }
    }
}