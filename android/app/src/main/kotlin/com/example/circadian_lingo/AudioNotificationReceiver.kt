package com.example.circadian_lingo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AudioNotificationReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ALLOW_AUDIO = "com.example.circadian_lingo.ACTION_ALLOW_AUDIO"
        const val ACTION_DENY_AUDIO = "com.example.circadian_lingo.ACTION_DENY_AUDIO"
        private const val NOTIFICATION_ID = 3001
        private const val CHANNEL_ID = "audio_request_channel"

        fun showAudioRequest(context: Context) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Audio Requests",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Used to approve ambient audio recording"
                }
                notificationManager.createNotificationChannel(channel)
            }

            val allowIntent = Intent(context, AudioNotificationReceiver::class.java).apply {
                action = ACTION_ALLOW_AUDIO
            }
            val allowPendingIntent = PendingIntent.getBroadcast(
                context, 0, allowIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val denyIntent = Intent(context, AudioNotificationReceiver::class.java).apply {
                action = ACTION_DENY_AUDIO
            }
            val denyPendingIntent = PendingIntent.getBroadcast(
                context, 1, denyIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle("Ambient Audio Request")
                .setContentText("Circadian Lingo wants to record ambient context.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .addAction(android.R.drawable.ic_menu_save, "Allow", allowPendingIntent)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Deny", denyPendingIntent)

            notificationManager.notify(NOTIFICATION_ID, builder.build())
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)

        when (intent.action) {
            ACTION_ALLOW_AUDIO -> {
                Log.i("AudioReceiver", "User ALLOWED audio capture")
                
                // Increment capture count
                incrementAudioCaptureCount(context)
                
                // Start AudioCaptureService in ambient mode
                val serviceIntent = Intent(context, AudioCaptureService::class.java).apply {
                    putExtra("is_ambient", true)
                }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
            ACTION_DENY_AUDIO -> {
                Log.i("AudioReceiver", "User DENIED audio capture")
            }
        }
    }

    private fun incrementAudioCaptureCount(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val lastDate = prefs.getString("flutter.lastAudioCaptureDate", "")
        
        var count = 0L
        if (lastDate == today) {
            count = prefs.getLong("flutter.dailyAudioCaptureCount", 0L)
        }
        
        prefs.edit().apply {
            putLong("flutter.dailyAudioCaptureCount", count + 1)
            putString("flutter.lastAudioCaptureDate", today)
            apply()
        }
        Log.i("AudioReceiver", "Incremented audio capture count: ${count + 1}")
    }
}