package com.example.circadian_lingo

import android.content.Context
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingWorkPolicy
import java.util.concurrent.TimeUnit
import kotlin.random.Random

object AudioWorkManager {
    private const val WORK_NAME = "AudioSchedulerWork"

    fun enqueueNextAudioWork(context: Context) {
        // Random delay between 45 and 90 minutes
        val delayMinutes = Random.nextLong(45, 91)
        
        val workRequest = OneTimeWorkRequestBuilder<AudioScheduleWorker>()
            .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest
        )
    }

    fun cancelAudioWork(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }
}