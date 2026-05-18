package com.example.circadian_lingo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NotificationCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("NotificationCancel", "Cancellation requested via notification")
        GemmaManager.cancelGeneration(context)
    }
}
