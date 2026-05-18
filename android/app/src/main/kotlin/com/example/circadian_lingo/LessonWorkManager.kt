package com.example.circadian_lingo

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.Calendar
import java.util.concurrent.TimeUnit

object LessonWorkManager {
    private const val TAG       = "LessonWorkManager"
    private const val WORK_NAME = "daily_lesson_generation"

    /**
     * Schedules the automatic daily lesson generation at the user-selected time.
     * Calculates the time delay to the next occurrence and enqueues it.
     */
    fun scheduleDailyLesson(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.lessonAutoGenerationEnabled", true)

        if (!enabled) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.i(TAG, "scheduleDailyLesson: Automatic daily lesson generation is disabled.")
            return
        }

        val hour = prefs.getInt("flutter.lessonGenerationHour", 22) // default 10 PM
        val minute = prefs.getInt("flutter.lessonGenerationMinute", 0)

        val currentTime = Calendar.getInstance()
        val targetTime = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        // If target time has already passed today, schedule for tomorrow
        if (targetTime.before(currentTime)) {
            targetTime.add(Calendar.DAY_OF_YEAR, 1)
        }

        val initialDelayMs = targetTime.timeInMillis - currentTime.timeInMillis

        // Build request without WorkManager-level constraints because constraints check is handled programmatically in Worker
        val workRequest = OneTimeWorkRequestBuilder<DailyLessonWorker>()
            .setInitialDelay(initialDelayMs, TimeUnit.MILLISECONDS)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE, // REPLACE to cancel the previous schedule and apply the new time
            workRequest
        )
        
        val hourStr = hour.toString().padStart(2, '0')
        val minStr = minute.toString().padStart(2, '0')
        Log.i(TAG, "scheduleDailyLesson: Scheduled daily lesson generation at $hourStr:$minStr (delay: ${initialDelayMs / 1000} seconds)")
    }

    fun cancelLessonWork(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        Log.i(TAG, "cancelLessonWork: Cancelled daily lesson generation unique work.")
    }
}
