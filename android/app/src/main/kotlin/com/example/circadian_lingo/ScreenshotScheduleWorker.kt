package com.example.circadian_lingo

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.util.Calendar
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenshotScheduleWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // 1. Check if Smart Context Scheduling is enabled
        val isEnabled = prefs.getBoolean("flutter.smartContextSchedulingEnabled", false)
        if (!isEnabled) {
            Log.i("ScreenshotWorker", "Smart scheduling disabled. Skipping.")
            return Result.success()
        }

        // 2. Check Time Window
        val startHour = prefs.getInt("flutter.contextWindowStartHour", 9)
        val endHour = prefs.getInt("flutter.contextWindowEndHour", 17)
        val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

        if (currentHour < startHour || currentHour >= endHour) {
            Log.i("ScreenshotWorker", "Outside time window ($startHour-$endHour). Current: $currentHour. Rescheduling.")
            ScreenshotWorkManager.enqueueNextScreenshotWork(applicationContext)
            return Result.success()
        }

        // 3. Check Daily Limit
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val lastDate = prefs.getString("flutter.lastCaptureDate", "")
        val limit = prefs.getLong("flutter.dailyScreenCaptureLimit", 5L).toInt()
        
        var count = 0L
        if (lastDate == today) {
            count = prefs.getLong("flutter.dailyScreenCaptureCount", 0L)
        }

        if (count >= limit) {
            Log.i("ScreenshotWorker", "Daily limit reached ($count/$limit). Skipping.")
            return Result.success()
        }

        // 4. Trigger Notification via Receiver
        Log.i("ScreenshotWorker", "Conditions met. Triggering notification.")
        ScreenshotReceiver.showScreenshotRequest(applicationContext)

        // 5. Schedule Next
        ScreenshotWorkManager.enqueueNextScreenshotWork(applicationContext)

        return Result.success()
    }
}