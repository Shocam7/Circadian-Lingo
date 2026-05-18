package com.example.circadian_lingo

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.content.Intent
import android.app.PendingIntent
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class CircadianTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val service = CircadianAccessibilityService.instance
        
        if (service != null) {
            unlockAndRun { service.captureScreen() }
        } else {
            // Service is disabled: Route to Settings and show Toast
            val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            // Handle API 34 deprecation gracefully
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pendingIntent = android.app.PendingIntent.getActivity(this, 0, intent, android.app.PendingIntent.FLAG_IMMUTABLE)
                startActivityAndCollapse(pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
            
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(applicationContext, "Please enable Circadian Lingo to take snapshots", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }
}