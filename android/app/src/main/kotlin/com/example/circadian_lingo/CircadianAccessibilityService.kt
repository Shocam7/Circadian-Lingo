package com.example.circadian_lingo

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.annotation.RequiresApi
import android.view.Display
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class CircadianAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "CircadianAccessibility"
        var instance: CircadianAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "CircadianAccessibilityService Connected")
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not needed for manual capture, but required to override
    }

    override fun onInterrupt() {
        Log.i(TAG, "CircadianAccessibilityService Interrupted")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    /**
     * Captures the current screen.
     * Android 11+ (API 30+) uses takeScreenshot().
     * Android 8-10 (API 26-29) fallbacks to text extraction.
     */
    fun captureScreen() {
        Log.i(TAG, "captureScreen() triggered. SDK_INT: ${Build.VERSION.SDK_INT}")
        // Programmatically collapse the Quick Settings panel to reveal the underlying app
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
        } else {
            @Suppress("DEPRECATION")
            sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
        }
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            collapsePanelAndCapture()
        }, 800)
    }

    private fun collapsePanelAndCapture() {
        val timestamp = System.currentTimeMillis()

        // Step A: Text Scrape
        extractTextContext(timestamp)

        // Step B: Pixel Capture
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        Log.i(TAG, "takeScreenshot onSuccess")
                        val bitmap = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
                        if (bitmap != null) {
                            saveBitmap(bitmap, timestamp)
                        } else {
                            Log.e(TAG, "HardwareBuffer to Bitmap conversion failed")
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "takeScreenshot onFailure: $errorCode")
                    }
                }
            )
        }
        
        // Increment capture count once for the combined event
        incrementCaptureCount()
    }

    private fun saveBitmap(bitmap: Bitmap, timestamp: Long) {
        CoroutineScope(Dispatchers.IO).launch {
            val capturesDir = File(filesDir, "captures")
            if (!capturesDir.exists()) capturesDir.mkdirs()

            val file = File(capturesDir, "img_$timestamp.jpg")

            try {
                FileOutputStream(file).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }
                Log.i(TAG, "Screenshot saved: ${file.absolutePath}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save screenshot", e)
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun extractTextContext(timestamp: Long) {
        var rootNode: AccessibilityNodeInfo? = null

        // Try to find the actual application window first to bypass the notification shade/system window
        try {
            val windowsList = windows
            if (!windowsList.isNullOrEmpty()) {
                val appWindow = windowsList.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                if (appWindow != null) {
                    rootNode = appWindow.root
                    Log.i(TAG, "Successfully found TYPE_APPLICATION window to extract text from.")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error looking up application window", e)
        }

        // Fall back to active window if application window was not found
        if (rootNode == null) {
            rootNode = rootInActiveWindow
            Log.i(TAG, "Fallback to rootInActiveWindow for text extraction.")
        }

        if (rootNode == null) {
            Log.e(TAG, "No root node found, cannot extract text.")
            return
        }

        val extractedTextSet = LinkedHashSet<String>()
        traverseNodes(rootNode, extractedTextSet)
        
        val extractedText = StringBuilder()
        for (item in extractedTextSet) {
            extractedText.append(item).append("\n")
        }

        val capturesDir = File(filesDir, "captures")
        if (!capturesDir.exists()) capturesDir.mkdirs()

        val file = File(capturesDir, "ctx_$timestamp.txt")
        val textToSave = extractedText.toString()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                file.writeText(textToSave)
                Log.i(TAG, "Text context saved: ${file.absolutePath}")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    android.widget.Toast.makeText(
                        applicationContext,
                        "Circadian Lingo: Snapshot saved successfully!",
                        android.widget.Toast.LENGTH_SHORT
                    ).show()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save text context", e)
            }
        }
    }

    private fun traverseNodes(node: AccessibilityNodeInfo, set: MutableSet<String>) {
        val rawTexts = mutableListOf<CharSequence?>()
        rawTexts.add(node.text)
        rawTexts.add(node.contentDescription)

        for (text in rawTexts) {
            text?.let {
                val str = it.toString().trim()
                if (str.isNotBlank() && countVowels(str) >= 2) {
                    set.add(str)
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                traverseNodes(child, set)
            }
        }
    }

    private fun countVowels(str: String): Int {
        val vowels = "aeiouAEIOU"
        return str.count { it in vowels }
    }

    private fun incrementCaptureCount() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val lastDate = prefs.getString("flutter.lastCaptureDate", "")
        
        var count = 0L
        if (lastDate == today) {
            count = prefs.getLong("flutter.dailyScreenCaptureCount", 0L)
        }
        
        prefs.edit().apply {
            putLong("flutter.dailyScreenCaptureCount", count + 1)
            putString("flutter.lastCaptureDate", today)
            apply()
        }
        Log.i(TAG, "Incremented screen capture count: ${count + 1}")
    }
}