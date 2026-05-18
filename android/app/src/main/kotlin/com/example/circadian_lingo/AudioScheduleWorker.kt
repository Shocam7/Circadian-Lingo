package com.example.circadian_lingo

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.util.Calendar
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AudioScheduleWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // 1. Check if Smart Context Scheduling is enabled
        val isEnabled = prefs.getBoolean("flutter.smartContextSchedulingEnabled", false)
        if (!isEnabled) {
            Log.i("AudioWorker", "Smart scheduling disabled. Skipping.")
            return Result.success()
        }

        // 2. Check if already recording
        if (AudioCaptureService.isRunning) {
            Log.i("AudioWorker", "AudioCaptureService already running. Rescheduling.")
            AudioWorkManager.enqueueNextAudioWork(applicationContext)
            return Result.success()
        }

        // 3. Check Time Window
        val startHour = prefs.getInt("flutter.contextWindowStartHour", 9)
        val endHour = prefs.getInt("flutter.contextWindowEndHour", 17)
        val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

        if (currentHour < startHour || currentHour >= endHour) {
            Log.i("AudioWorker", "Outside time window ($startHour-$endHour). Current: $currentHour. Rescheduling.")
            AudioWorkManager.enqueueNextAudioWork(applicationContext)
            return Result.success()
        }

        // 4. Check Daily Limit
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val lastDate = prefs.getString("flutter.lastAudioCaptureDate", "")
        val limit = prefs.getLong("flutter.dailyAudioCaptureLimit", 5L).toInt()
        
        var count = 0L
        if (lastDate == today) {
            count = prefs.getLong("flutter.dailyAudioCaptureCount", 0L)
        }

        if (count >= limit) {
            Log.i("AudioWorker", "Daily limit reached ($count/$limit). Skipping.")
            return Result.success()
        }

        // 5. Trigger Notification via Receiver
        Log.i("AudioWorker", "Conditions met. Triggering notification.")
        AudioNotificationReceiver.showAudioRequest(applicationContext)

        // 6. Schedule Next
        AudioWorkManager.enqueueNextAudioWork(applicationContext)

        return Result.success()
    }
}