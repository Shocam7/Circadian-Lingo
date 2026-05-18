package com.example.circadian_lingo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import android.util.Log

class ScreenshotReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ALLOW = "com.example.circadian_lingo.ACTION_ALLOW_SCREENSHOT"
        const val ACTION_DENY = "com.example.circadian_lingo.ACTION_DENY_SCREENSHOT"
        const val NOTIFICATION_ID = 2001
        private const val CHANNEL_ID = "screenshot_request_channel"

        fun showScreenshotRequest(context: Context) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Screenshot Requests",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Used to approve background screenshots"
                }
                notificationManager.createNotificationChannel(channel)
            }

            val allowIntent = Intent(context, ScreenshotReceiver::class.java).apply {
                action = ACTION_ALLOW
            }
            val allowPendingIntent = PendingIntent.getBroadcast(
                context, 0, allowIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val denyIntent = Intent(context, ScreenshotReceiver::class.java).apply {
                action = ACTION_DENY
            }
            val denyPendingIntent = PendingIntent.getBroadcast(
                context, 1, denyIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("Snapshot Request")
                .setContentText("Circadian Lingo wants to capture your screen context.")
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
            ACTION_ALLOW -> {
                Log.i("ScreenshotReceiver", "User ALLOWED screenshot")
                val service = CircadianAccessibilityService.instance
                if (service != null) {
                    service.captureScreen()
                } else {
                    Log.e("ScreenshotReceiver", "AccessibilityService not running")
                }
            }
            ACTION_DENY -> {
                Log.i("ScreenshotReceiver", "User DENIED screenshot")
            }
        }
    }
}