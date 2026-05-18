package com.example.circadian_lingo

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive

import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.SamplerConfig

object GemmaManager {
    private const val TAG           = "GemmaManager"
    private const val MODEL_URL     = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
    private const val MODEL_FILENAME = "gemma-4-E2B-it.litertlm"
    
    @Volatile
    private var isCancelled = false

    // Single-threaded dispatcher whose priority is adjusted dynamically depending on execution mode.
    private val inferenceDispatcher = Executors.newSingleThreadExecutor { runnable ->
        Thread(
            {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
                runnable.run()
            },
            "gemma-inference"
        ).also { it.priority = Thread.MIN_PRIORITY }
    }.asCoroutineDispatcher()

    @Volatile
    private var hasGpuOrNpuCache: Boolean? = null

    private fun isGpuOrNpuPresent(context: Context): Boolean {
        hasGpuOrNpuCache?.let { return it }
        val result = checkGpuOrNpu(context)
        hasGpuOrNpuCache = result
        return result
    }

    private fun checkGpuOrNpu(context: Context): Boolean {
        if (isEmulator()) {
            Log.i(TAG, "checkGpuOrNpu: Device is emulator (no physical GPU/NPU).")
            return false
        }
        
        // 1. Check for Vulkan hardware support (Vulkan is standard on modern GPUs)
        val hasVulkan = context.packageManager.hasSystemFeature("android.hardware.vulkan.version")
        if (hasVulkan) {
            Log.i(TAG, "checkGpuOrNpu: Vulkan hardware detected (GPU is present).")
            return true
        }
        
        // 2. Check for OpenCL library presence in common locations
        val openCLPaths = arrayOf(
            "/system/lib64/libOpenCL.so",
            "/system/vendor/lib64/libOpenCL.so",
            "/vendor/lib64/libOpenCL.so",
            "/system/lib/libOpenCL.so",
            "/system/vendor/lib/libOpenCL.so",
            "/vendor/lib/libOpenCL.so"
        )
        for (path in openCLPaths) {
            if (File(path).exists()) {
                Log.i(TAG, "checkGpuOrNpu: OpenCL library found at $path (GPU is present).")
                return true
            }
        }

        // 3. Check SoC hardware / board names for modern chips (which all have capable GPU/NPU)
        val hardware = android.os.Build.HARDWARE.lowercase()
        val board = android.os.Build.BOARD.lowercase()
        val socManufacturer = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            android.os.Build.SOC_MANUFACTURER.lowercase()
        } else ""
        val socModel = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            android.os.Build.SOC_MODEL.lowercase()
        } else ""

        val modernSoCKeywords = listOf(
            "qcom", "snapdragon", "mediatek", "mt6", "mt8", "exynos", "tensor", "kirin", 
            "hisilicon", "adreno", "mali", "bionic", "geforce", "nvidia", "tegra"
        )

        for (keyword in modernSoCKeywords) {
            if (hardware.contains(keyword) || board.contains(keyword) || socManufacturer.contains(keyword) || socModel.contains(keyword)) {
                Log.i(TAG, "checkGpuOrNpu: Modern SoC detected via keyword '$keyword' (GPU/NPU present).")
                return true
            }
        }

        // 4. Check for dedicated NPU/TPU/Hexagon libraries
        val npuLibPaths = arrayOf(
            "/vendor/lib64/libqnn_hexagon.so",
            "/vendor/lib64/libhexagon_nn_skel.so",
            "/vendor/lib64/libneuron_adapter.so",
            "/vendor/lib64/libaimet.so",
            "/vendor/lib/libqnn_hexagon.so",
            "/vendor/lib/libhexagon_nn_skel.so",
            "/vendor/lib/libneuron_adapter.so"
        )
        for (path in npuLibPaths) {
            if (File(path).exists()) {
                Log.i(TAG, "checkGpuOrNpu: Dedicated NPU library found at $path.")
                return true
            }
        }

        Log.w(TAG, "checkGpuOrNpu: No Vulkan, OpenCL, NPU libraries, or modern SoC keyword detected. Assuming no capable GPU/NPU.")
        return false
    }

    private fun isEmulator(): Boolean {
        val brand = android.os.Build.BRAND
        val device = android.os.Build.DEVICE
        val fingerprint = android.os.Build.FINGERPRINT
        val hardware = android.os.Build.HARDWARE
        val model = android.os.Build.MODEL
        val product = android.os.Build.PRODUCT
        val manufacturer = android.os.Build.MANUFACTURER

        return (brand.startsWith("generic") && device.startsWith("generic"))
                || fingerprint.startsWith("generic")
                || fingerprint.startsWith("unknown")
                || hardware.contains("goldfish")
                || hardware.contains("ranchu")
                || model.contains("google_sdk")
                || model.contains("Emulator")
                || model.contains("Android SDK built for x86")
                || manufacturer.contains("Genymotion")
                || product.contains("sdk_google")
                || product.contains("google_sdk")
                || product.contains("sdk")
                || product.contains("sdk_x86")
                || product.contains("vbox86p")
                || product.contains("emulator")
                || product.contains("simulator")
    }

    // ── Model management ──────────────────────────────────────────────────────

    fun checkModelStatus(context: Context): String {
        val internalFile = File(context.filesDir, "models/$MODEL_FILENAME")
        return if (internalFile.exists()) "DOWNLOADED" else "MISSING"
    }

    fun startDownload(context: Context): Long {
        Log.i(TAG, "Starting download of Gemma model from $MODEL_URL")
        
        // Clean up any existing file in external files dir to prevent DownloadManager from renaming it (e.g. gemma-4-E2B-it-1.litertlm)
        val externalFile = File(context.getExternalFilesDir(null), MODEL_FILENAME)
        if (externalFile.exists()) {
            try {
                externalFile.delete()
            } catch (e: Exception) {
                Log.w(TAG, "Could not delete existing external file: ${e.message}")
            }
        }

        val request = DownloadManager.Request(Uri.parse(MODEL_URL))
            .setTitle("Downloading Circadian Lingo Brain")
            .setDescription("Optimizing local language intelligence (1.5 GB)")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN)
            .setMimeType("application/octet-stream")
            .setDestinationInExternalFilesDir(context, null, MODEL_FILENAME)
            
        val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return dm.enqueue(request)
    }

    fun moveModelToInternal(context: Context, downloadId: Long): Boolean {
        val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = dm.query(query)
        var success = false
        if (cursor.moveToFirst()) {
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                val uriString = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                val uri = Uri.parse(uriString)
                val targetDir = File(context.filesDir, "models")
                if (!targetDir.exists()) targetDir.mkdirs()
                val targetFile = File(targetDir, MODEL_FILENAME)
                try {
                    // Check if URI is a file path and handle it directly for efficiency & immediate cleanup
                    val file = if (uri.scheme == "file") {
                        File(uri.path ?: "")
                    } else {
                        null
                    }
                    
                    if (file != null && file.exists()) {
                        file.inputStream().use { input ->
                            targetFile.outputStream().use { output -> input.copyTo(output) }
                        }
                        try {
                            file.delete()
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to delete temp download file: ${e.message}")
                        }
                    } else {
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            targetFile.outputStream().use { output -> input.copyTo(output) }
                        }
                    }
                    success = true
                    Log.i(TAG, "Model copied successfully.")
                    dm.remove(downloadId)
                } catch (e: Exception) {
                    Log.e(TAG, "Copy failed: ${e.message}", e)
                }
            } else {
                val reason = try {
                    cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                } catch (e: Exception) {
                    -1
                }
                Log.e(TAG, "Download failed. Status: $status, Reason: $reason")
            }
        }
        cursor.close()
        return success
    }

    // ── Engine lifecycle helpers ──────────────────────────────────────────────

    private fun buildEngine(context: Context, useAudio: Boolean = true, isSpecific: Boolean = false, maxNumTokens: Int? = null): Engine {
        if (!android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
            throw UnsupportedOperationException("LiteRT requires a 64-bit (arm64-v8a) architecture. This device only supports 32-bit (${android.os.Build.SUPPORTED_ABIS.joinToString()}).")
        }
        val modelPath = File(context.filesDir, "models/$MODEL_FILENAME").absolutePath
        val threadCount = if (isSpecific) {
            Runtime.getRuntime().availableProcessors()
        } else {
            2 // Low-resource overnight/daily execution
        }
        Log.i(TAG, "buildEngine: Configuring LiteRT with $threadCount CPU threads (isSpecific=$isSpecific, maxNumTokens=$maxNumTokens).")
        val config = EngineConfig(
            modelPath   = modelPath,
            backend     = Backend.CPU(numOfThreads = threadCount),
            audioBackend = if (useAudio) Backend.CPU(numOfThreads = threadCount) else null,
            maxNumTokens = maxNumTokens,
            cacheDir    = context.cacheDir.path
        )
        return Engine(config)
    }

    /** Run one inference turn using [engine]. Engine must already be initialized. */
    private fun inferText(engine: Engine, prompt: String, enableReasoning: Boolean = false): String {
        val config = if (enableReasoning) {
            ConversationConfig(
                systemInstruction = Contents.of(Content.Text("<|think|>")),
                samplerConfig = SamplerConfig(temperature = 0.0, topK = 1, topP = 1.0)
            )
        } else {
            ConversationConfig(samplerConfig = SamplerConfig(temperature = 0.0, topK = 1, topP = 1.0))
        }

        engine.createConversation(config).use { conversation ->
            val rawResponse = conversation.sendMessage(Contents.of(Content.Text(prompt))).toString()
            

            
            if (enableReasoning) {
                // Parse out the thought channel
                return rawResponse.replace(Regex("<\\|channel>thought.*?<channel\\|>", RegexOption.DOT_MATCHES_ALL), "").trim()
            }
            
            return rawResponse.trim()
        }
    }

    /** Transcribe one audio file using [engine]. Engine must already be initialized. */
    private suspend fun transcribeAudio(
        context: Context,
        engine: Engine,
        audioPath: String,
        nativeLang: String,
        targetLang: String
    ): String {
        // 1. Decode AAC/M4A to 16kHz Mono PCM WAV
        val wavPath = AudioDecoderHelper.decode(context, audioPath) ?: return ""
        val wavFile = File(wavPath)
        
        try {
            val audioBytes = wavFile.readBytes()
            val prompt = buildTranscriptionPrompt(nativeLang, targetLang)
            
            engine.createConversation(
                ConversationConfig(samplerConfig = SamplerConfig(temperature = 0.0, topK = 1, topP = 1.0))
            ).use { conversation ->
                val response = conversation.sendMessage(
                    Contents.of(Content.AudioBytes(audioBytes), Content.Text(prompt))
                ).toString().trim()
                

                
                return response
            }
        } catch (e: Exception) {
            Log.e(TAG, "Transcription failed: ${e.message}")
            return ""
        } finally {
            // Clean up temporary WAV
            if (wavFile.exists()) wavFile.delete()
        }
    }

    // ── Dynamic prompt builders ───────────────────────────────────────────────

    private fun buildTranscriptionPrompt(nativeLang: String, targetLang: String) =
        "Listen to the attached audio. The user is speaking $nativeLang or possibly $targetLang. " +
        "Transcribe exactly what they say using standard romanisation if needed. Output ONLY the transcription."

    private fun getLanguageInstruction(nativeLang: String, targetLang: String) =
        "CRITICAL INSTRUCTION: The words, sentences, stories, and dialogues to be taught MUST be in $targetLang. " +
        "All explanations, summaries, translations, definitions, questions, and meanings MUST be in $nativeLang (written in native script)."

    private fun buildContextExtractionPrompt(captureText: String, nativeLang: String, targetLang: String) =
        "You are an expert language teacher analyzing a real-world text/conversation in $nativeLang (possibly mixed with $targetLang). " +
        "Note that the input could consist of only a few words, and these words could be nonsensical and malformed. " +
        "Read the following text and extract two distinct things:\n" +
        "1. 'context': A 2-3 sentence summary of the specific situation, theme, and scenario. You can reasonably incorporate descriptions of any notable idioms, phrases, or conversational context present in the text here.\n" +
        "2. 'vocabulary': A comma-separated list of exactly 5 to 8 of the most useful, practical individual vocabulary words present in the text that a student learning $targetLang would benefit from.\n" +
        "   CRITICAL RULES FOR VOCABULARY SELECTION:\n" +
        "   - EXTRACT ONLY SINGLE WORDS. Do NOT include phrases, idioms, sentences, multi-word expressions, or anything containing more than one word. Any multi-word expressions or idioms must be left out of the vocabulary list and instead described in the 'context' summary.\n" +
        "   - STRICTLY LIMIT the list to a maximum of 5 to 8 single words total. Do not bloat this section.\n" +
        "   - Do NOT include proper nouns (e.g., names of people, politicians, channels, websites, countries, cities, or actors like 'Will Ferrell', 'Modi', 'Sweden', 'Dhruv Rathee').\n" +
        "   - Do NOT include app UI labels, buttons, platform terminology, or navigation controls (e.g., 'Expand Mini Player', 'Shorts', 'Notifications', 'Search', 'filters', 'YouTube').\n" +
        "   - Do NOT include hashtags, raw hyperlinks, numbers, or technical metadata/acronyms.\n" +
        "   - Select ONLY actual, high-quality individual dictionary words (nouns, verbs, adjectives, adverbs) in $targetLang that are contextually relevant.\n\n" +
        "You MUST output your response as valid JSON in the exact format below. Output ONLY the JSON.\n" +
        "{\n" +
        "  \"context\": \"<your 1-2 sentence summary>\",\n" +
        "  \"vocabulary\": \"<comma separated list of 5-8 high-quality single words>\"\n" +
        "}\n\n" +
        "Text to analyze:\n$captureText"

    private fun buildVocabPreviewPrompt(
        vocabularyList: String, contextSummary: String, nativeLang: String, targetLang: String, knownWords: String
    ) = "You are a language teacher. Based on this key vocabulary list: '$vocabularyList' (extracted from this theme: '$contextSummary'), " +
        "identify 3-5 key $targetLang words a $nativeLang speaker would benefit from learning. $knownWords " +
        "Write a single engaging summary sentence for a lesson card (max 40 words). " +
        "${getLanguageInstruction(nativeLang, targetLang)}\n" +
        "CRITICAL: Output ONLY the result in the format specified below. Do NOT write any introduction, preamble, conversational filler, markdown, or commentary. Start immediately with 'PREVIEW:'.\n" +
        "Output format: PREVIEW:<your summary>\n\nVocabulary to consider:\n$vocabularyList"

    private fun buildWordCardPrompt(
        vocabularyList: String, contextSummary: String, nativeLang: String, targetLang: String, knownWords: String
    ) = "You are a language teacher. From this key vocabulary list: '$vocabularyList' (Theme: '$contextSummary'), " +
        "pick ONE key $targetLang word a $nativeLang speaker should learn. $knownWords " +
        "${getLanguageInstruction(nativeLang, targetLang)}\n" +
        "CRITICAL: Output ONLY the result in the format specified below. Do NOT write any introduction, preamble, conversational filler, markdown formatting, or commentary. Start immediately with 'WORD:'.\n" +
        "Output format: WORD:<word>|DEF:<definition in $nativeLang>|EX:<example sentence in $targetLang>"

    private fun buildStoryPrompt(
        contextSummary: String, vocabularyList: String, nativeLang: String, targetLang: String, knownWords: String
    ) = "You are a language teacher. Write a short 4-5 sentence story in $targetLang inspired by " +
        "this scenario: '$contextSummary'. Try to naturally incorporate some of these words if they fit: '$vocabularyList'. " +
        "Use simple vocabulary. $knownWords " +
        "After the story, provide a full translation of the entire story into $nativeLang. " +
        "Include a comma-separated list of the key target words used, along with their meaning in $nativeLang in the format word:meaning (e.g. negotiate:discuss to agree).\n" +
        "${getLanguageInstruction(nativeLang, targetLang)}\n" +
        "CRITICAL: Output ONLY the result in the format specified below. Do NOT write any introduction, preamble, conversational filler, markdown formatting, or commentary. Start immediately with 'STORY:'.\n" +
        "Output format: STORY:<story in $targetLang>|TRANSLATION:<full translation in $nativeLang>|WORDS:<word1>:<meaning1 in $nativeLang>,<word2>:<meaning2 in $nativeLang>,..."

    private fun buildDialoguePrompt(
        contextSummary: String, vocabularyList: String, nativeLang: String, targetLang: String, knownWords: String
    ) = "You are a language teacher. Write a realistic 4-6 line dialogue in $targetLang taking place " +
        "in this situation: '$contextSummary'. Try to naturally incorporate some of these words if they fit: '$vocabularyList'. " +
        "$knownWords Include a comma-separated list of key target words.\n" +
        "${getLanguageInstruction(nativeLang, targetLang)}\n" +
        "CRITICAL: Output ONLY the result in the format specified below. Do NOT write any introduction, preamble, conversational filler, markdown formatting, or commentary. Start immediately with the first line of dialogue (e.g. 'A:').\n" +
        "Output format: A:<line>|B:<line>|A:<line>|...|WORDS:<word1,word2,...>"

    private fun buildFlashcardsPrompt(
        vocabularyList: String, nativeLang: String, targetLang: String, knownWords: String
    ) = "You are a language teacher. Create 3 flashcards focusing on these key terms: '$vocabularyList'. $knownWords " +
        "Each flashcard: front = $targetLang word, back = $nativeLang meaning.\n" +
        "${getLanguageInstruction(nativeLang, targetLang)}\n" +
        "CRITICAL: Output ONLY the raw flashcard lines. Do NOT write any introduction, preamble, conversational filler, markdown formatting (such as list symbols or bolding), or commentary. Start immediately with the first FRONT:<word>|BACK:<meaning> line.\n" +
        "Output: one flashcard per line, format FRONT:<word>|BACK:<meaning>"

    private fun buildQuizPrompt(
        contextSummary: String, vocabList: String, nativeLang: String, targetLang: String
    ) = "You are an expert language teacher. Create exactly one multiple-choice quiz question to test a student's understanding of one of these target $targetLang words: '$vocabList'.\n" +
        "CRITICAL RULES:\n" +
        "1. The question (following 'Q:') MUST be written entirely in $nativeLang (written in native script, e.g., Devanagari for Hindi). The question should describe the meaning or context of one of the target $targetLang words in $nativeLang, and ask which target word is the correct match.\n" +
        "2. The options MUST be exactly 3 candidate $targetLang words (comma-separated, e.g., Word1,Word2,Word3).\n" +
        "3. The correct answer MUST be one of those target $targetLang words.\n" +
        "4. The explanation/definition MUST be written in $nativeLang (written in native script, e.g., Devanagari for Hindi).\n" +
        "5. Output must be on EXACTLY ONE SINGLE LINE. Do NOT output multiple lines, do NOT use markdown bold/asterisks, do NOT write text like '**सही उत्तर:**', and do NOT output template placeholders.\n" +
        "6. Do NOT write any preamble, introduction, conversational filler, or commentary. Start immediately with 'Q:'.\n\n" +
        "Output format (strict single line):\n" +
        "Q:<question in $nativeLang script>|<option1 in $targetLang>,<option2 in $targetLang>,<option3 in $targetLang>|<correct target word>|<brief definition in $nativeLang script>"

    // ── ALU file I/O ──────────────────────────────────────────────────────────

    private fun saveLessonFile(cacheDir: File, filename: String, content: String) {
        File(cacheDir, filename).writeText(content)
        Log.i(TAG, "Saved ALU: $filename")
    }

    private fun aluFileExists(cacheDir: File, filename: String) = File(cacheDir, filename).exists()

    private fun updateProgress(
        prefs: android.content.SharedPreferences,
        message: String,
        step: Int,
        total: Int,
        currentCounts: Map<String, Int>? = null,
        targetCounts: Map<String, Int>? = null,
        onProgress: ((String) -> Unit)?
    ) {
        val percent = if (total > 0) (step.toFloat() / total.toFloat()) else 0f
        val editor = prefs.edit()
            .putString("flutter.lesson_progress_message", message)
            .putFloat("flutter.lesson_progress_percent", percent)
        
        currentCounts?.let {
            val obj = org.json.JSONObject()
            for ((k, v) in it) obj.put(k, v)
            editor.putString("flutter.lesson_current_counts", obj.toString())
        }
        targetCounts?.let {
            val obj = org.json.JSONObject()
            for ((k, v) in it) obj.put(k, v)
            editor.putString("flutter.lesson_target_counts", obj.toString())
        }
        
        editor.apply()
        onProgress?.invoke(message)
    }

    // Data class to hold parsed summary
    data class ParsedSummary(val context: String, val vocabulary: String)

    fun cancelGeneration(context: Context) {
        isCancelled = true
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.lesson_progress_message", "Cancelling…").apply()
        Log.i(TAG, "Cancellation requested for lesson generation")
    }

    // ── Main lesson generation function ───────────────────────────────────────
    //
    // CRITICAL: Gemma is instantiated EXACTLY ONCE here.
    // The same Engine instance: transcribes all audio → generates all ALUs.
    // engine.close() and System.gc() happen ONLY in the finally block.

    suspend fun generateLesson(
        context: Context,
        audioPaths: List<String>,    // usable .m4a paths
        textCaptures: List<String>,  // usable scraped text content
        nativeLanguage: String,
        targetLanguage: String,
        learnedWords: List<String>,
        isSpecific: Boolean = false,
        onProgress: ((String) -> Unit)? = null
    ): Boolean = withContext(inferenceDispatcher) {
        isCancelled = false

        // Dynamically adjust thread priority of the current dispatcher thread
        if (isSpecific) {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_FOREGROUND)
            Thread.currentThread().priority = Thread.MAX_PRIORITY
            Log.i(TAG, "generateLesson: Promoted thread to FOREGROUND priority for Specific Capture lesson.")
        } else {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            Thread.currentThread().priority = Thread.MIN_PRIORITY
            Log.i(TAG, "generateLesson: Restricted thread to BACKGROUND priority for Daily lesson.")
        }

        if (checkModelStatus(context) != "DOWNLOADED") {
            Log.e(TAG, "generateLesson: model missing — aborting")
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.lesson_progress_message", "Model missing. Please download it.").apply()
            return@withContext false
        }
        val timestamp = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
        val lessonDirName = "lesson_${timestamp}_${if (isSpecific) "specific" else "daily"}"
        val lessonCache = File(File(context.filesDir, "lesson_cache"), lessonDirName).also { it.mkdirs() }
        
        if (isSpecific) {
            File(lessonCache, "is_specific.tag").createNewFile()
        }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val knownWordsInstruction = if (learnedWords.isNotEmpty())
            "Words the user already knows — do not teach these: ${learnedWords.takeLast(100).joinToString(", ")}."
        else ""

        // Setup tracking
        var currentStep = 0
        val initialCaptureCount = audioPaths.size + textCaptures.size
        
        // Reduced numbers for specific captures
        val storyCount = if (isSpecific) 1 else minOf(4, maxOf(3, initialCaptureCount))
        val dialogueCount = if (isSpecific) 0 else minOf(3, maxOf(2, initialCaptureCount))
        val targetWordCardCount = if (isSpecific) 1 else initialCaptureCount
        val targetFlashcardCount = if (isSpecific) 2 else 3
        val targetQuizCount = if (isSpecific) 2 else 5

        val totalSteps = audioPaths.size + initialCaptureCount + 1 + targetWordCardCount + storyCount + dialogueCount + targetFlashcardCount + targetQuizCount

        val targetCounts = mutableMapOf(
            "preview" to 1,
            "word_card" to targetWordCardCount,
            "story" to storyCount,
            "dialogue" to dialogueCount,
            "flashcards" to targetFlashcardCount,
            "quiz" to targetQuizCount
        )
        val currentCounts = mutableMapOf(
            "preview" to 0,
            "word_card" to 0,
            "story" to 0,
            "dialogue" to 0,
            "flashcards" to 0,
            "quiz" to 0
        )

        var currentEngine: Engine? = null
        var currentMaxTokens: Int? = null
        var currentUseAudio = false

        fun acquireEngine(maxTokens: Int? = null, useAudio: Boolean = false): Engine {
            val engine = currentEngine
            if (engine != null && currentMaxTokens == maxTokens && currentUseAudio == useAudio) {
                return engine
            }
            if (engine != null) {
                try {
                    engine.close()
                } catch (e: Exception) {
                    Log.e(TAG, "Error closing engine: ${e.message}")
                }
                System.gc()
            }
            Log.i(TAG, "acquireEngine: Initializing engine with maxNumTokens = $maxTokens, useAudio = $useAudio")
            
            // Show model is loading in notifications and Flutter UI
            val previousMessage = prefs.getString("flutter.lesson_progress_message", null) ?: "Processing…"
            updateProgress(prefs, "Loading AI model…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
            
            val newEngine = buildEngine(context, useAudio = useAudio, isSpecific = isSpecific, maxNumTokens = maxTokens)
            try {
                // Ensure device supports 64-bit architecture before attempting to initialize LiteRT
                if (!android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
                    throw UnsupportedOperationException("LiteRT requires a 64-bit (arm64-v8a) architecture. This device only supports 32-bit (${android.os.Build.SUPPORTED_ABIS.joinToString()}), which cannot run local LLM inference.")
                }
                newEngine.initialize()
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to initialize LiteRT engine: ${t.message}", t)
                updateProgress(prefs, "Error: Device architecture unsupported or model failed to load.", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                throw t
            }
            
            // Restore previous specific progress message
            updateProgress(prefs, previousMessage, currentStep, totalSteps, currentCounts, targetCounts, onProgress)
            
            currentEngine = newEngine
            currentMaxTokens = maxTokens
            currentUseAudio = useAudio
            return newEngine
        }

        try {
            prefs.edit().putBoolean("flutter.lesson_generating", true).apply()
            val shouldEnableReasoning = !isSpecific && isGpuOrNpuPresent(context)

            // ── Phase 1: Transcribe audio captures ───────────────────────────
            val transcripts = mutableListOf<String>()
            for ((index, path) in audioPaths.withIndex()) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Transcribing audio ${index + 1}/${audioPaths.size}…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                Log.i(TAG, "Transcribing audio: $path")
                
                var decodedPath: String? = null
                val packetPaths = mutableListOf<String>()
                
                try {
                    // 1. Decode
                    decodedPath = AudioDecoderHelper.decode(context, path)
                    if (decodedPath == null) {
                        Log.e(TAG, "Failed to decode audio: $path")
                        continue
                    }

                    // 2. VAD
                    val vadModelPath = ModelManager.modelPath(context, "silero_vad.onnx")
                    val recordingsDir = ModelManager.recordingsDir(context)
                    val jsonTimestamps = AudioProcessorJni.processWithVad(decodedPath!!, vadModelPath, recordingsDir)

                    if (jsonTimestamps.isEmpty() || jsonTimestamps == "[]" || jsonTimestamps.startsWith("{\"error\"")) {
                        Log.w(TAG, "VAD found no speech or failed: $jsonTimestamps")
                        continue
                    }

                    // 3. Pack
                    val packed = SmartAudioPacker.pack(context, decodedPath!!, jsonTimestamps, "capture_${index}_chunk")
                    packetPaths.addAll(packed)

                    if (packetPaths.isEmpty()) {
                        Log.w(TAG, "SmartAudioPacker produced no packets for $path")
                        continue
                    }

                    // 4. Transcribe chunks
                    val activeEngine = acquireEngine(useAudio = true)
                    val sb = StringBuilder()
                    for ((pktIndex, pktPath) in packetPaths.withIndex()) {
                        if (isCancelled) break
                        val chunkTranscript = transcribeAudio(context, activeEngine, pktPath, nativeLanguage, targetLanguage)
                        if (sb.isNotEmpty()) sb.append(" ")
                        sb.append(chunkTranscript)
                        System.gc()
                    }

                    var transcript = sb.toString()
                    if (transcript.isNotBlank()) {
                        transcripts.add(transcript.trim())
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "Audio processing failed for $path: ${e.message}", e)
                } finally {
                    // Clean up decoded WAV
                    decodedPath?.let { p ->
                        try { val f = File(p); if (f.exists()) f.delete() } catch (ex: Exception) { Log.e(TAG, "Failed to clean up decoded WAV: ${ex.message}") }
                    }
                    // Clean up packet WAVs
                    for (p in packetPaths) {
                        try { val f = File(p); if (f.exists()) f.delete() } catch (ex: Exception) { Log.e(TAG, "Failed to clean up packet WAV: ${ex.message}") }
                    }
                }
                
                System.gc() // shed intermediate tensors between calls
            }

            // ── Phase 2: Build capture pool & Extract Context ──────────────────────────────────
            val capturePool = (transcripts + textCaptures)
                .filter { it.isNotBlank() }
                .map { capture ->
                    if (capture.length > 3000) {
                        capture.substring(0, 3000) + "..."
                    } else {
                        capture
                    }
                }
            if (capturePool.isEmpty()) {
                Log.w(TAG, "generateLesson: capture pool empty after quality check — no lesson")
                prefs.edit().putBoolean("flutter.lesson_ready", false).apply()
                return@withContext false
            }

            // Phase 2.5: Extract context and vocabulary from each capture
            val summarizedCaptures = mutableListOf<ParsedSummary>()
            for ((index, capture) in capturePool.withIndex()) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Analyzing context ${index + 1}/${capturePool.size}…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                
                val activeEngine = acquireEngine()
                val rawExtraction = inferText(activeEngine, buildContextExtractionPrompt(capture, nativeLanguage, targetLanguage), enableReasoning = shouldEnableReasoning)
                
                // Clean markdown tags that LLMs sometimes add
                val cleanedExtraction = rawExtraction.replace(Regex("```json\\s*"), "").replace(Regex("```\\s*"), "").trim()
                
                var parsed = ParsedSummary(context = capture, vocabulary = capture) // Fallback is raw capture
                try {
                    val json = org.json.JSONObject(cleanedExtraction)
                    val ctx = json.optString("context", capture)
                    val vocab = json.optString("vocabulary", capture)
                    parsed = ParsedSummary(context = ctx, vocabulary = vocab)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse context extraction JSON, using fallback. Error: ${e.message}")
                }
                summarizedCaptures.add(parsed)
                System.gc()
            }

            // Adjust final counts dynamically
            val finalStoryCount = if (isSpecific) 1 else minOf(4, maxOf(3, summarizedCaptures.size))
            val finalDialogueCount = if (isSpecific) 0 else minOf(3, maxOf(2, summarizedCaptures.size))
            val finalWordCardCount = if (isSpecific) 1 else summarizedCaptures.size

            targetCounts["word_card"] = finalWordCardCount
            targetCounts["story"] = finalStoryCount
            targetCounts["dialogue"] = finalDialogueCount

            // ── Phase 3: Generate ALUs sequentially ──────────────────────────
            // Each ALU is saved to disk immediately. If the worker is killed,
            // all previously saved files survive. On restart, existing files
            // are skipped (checked via aluFileExists).

            if (isCancelled) return@withContext false

            // Build an aggregate of all summaries for the preview
            val aggregateContext = summarizedCaptures.joinToString(" ") { it.context }
            val aggregateVocab = summarizedCaptures.joinToString(", ") { it.vocabulary }

            // Step 1: VocabPreview
            currentStep++
            updateProgress(prefs, "Building vocab preview…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
            if (!aluFileExists(lessonCache, "preview.json")) {
                val activeEngine = acquireEngine()
                val raw = inferText(activeEngine, buildVocabPreviewPrompt(aggregateVocab, aggregateContext, nativeLanguage, targetLanguage, knownWordsInstruction), enableReasoning = shouldEnableReasoning)
                saveLessonFile(lessonCache, "preview.json", raw)
            }
            currentCounts["preview"] = 1

            // Step 2: Word Cards — one per capture
            val collectedVocab = mutableListOf<String>()
            val captureLimit = if (isSpecific) 1 else summarizedCaptures.size
            val finalSummarizedPool = summarizedCaptures.take(captureLimit)
            for (i in finalSummarizedPool.indices) {
                if (isCancelled) break
                val summary = finalSummarizedPool[i]
                currentStep++
                updateProgress(prefs, "Word card ${i + 1}/${finalSummarizedPool.size}…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                val filename = "word_card_$i.json"
                if (!aluFileExists(lessonCache, filename)) {
                    val activeEngine = acquireEngine()
                    val raw = inferText(activeEngine, buildWordCardPrompt(summary.vocabulary, summary.context, nativeLanguage, targetLanguage, knownWordsInstruction), enableReasoning = shouldEnableReasoning)
                    saveLessonFile(lessonCache, filename, raw)
                    // Extract word for later quiz generation
                    raw.split("|").firstOrNull { it.startsWith("WORD:") }
                        ?.removePrefix("WORD:")?.trim()
                        ?.let { collectedVocab.add(it) }
                }
                currentCounts["word_card"] = i + 1
                System.gc()
            }

            // Step 3: Mini Stories
            for (i in 0 until finalStoryCount) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Story ${i + 1}/$finalStoryCount…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                val filename = "story_$i.json"
                if (!aluFileExists(lessonCache, filename)) {
                    val summary = finalSummarizedPool[i % finalSummarizedPool.size]
                    val activeEngine = acquireEngine()
                    val raw = inferText(activeEngine, buildStoryPrompt(summary.context, summary.vocabulary, nativeLanguage, targetLanguage, knownWordsInstruction), enableReasoning = shouldEnableReasoning)
                    saveLessonFile(lessonCache, filename, raw)
                }
                currentCounts["story"] = i + 1
                System.gc()
            }

            // Step 4: Dialogues
            for (i in 0 until finalDialogueCount) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Dialogue ${i + 1}/$finalDialogueCount…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                val filename = "dialogue_$i.json"
                if (!aluFileExists(lessonCache, filename)) {
                    val summary = finalSummarizedPool[(i + 1) % finalSummarizedPool.size]
                    val activeEngine = acquireEngine()
                    val raw = inferText(activeEngine, buildDialoguePrompt(summary.context, summary.vocabulary, nativeLanguage, targetLanguage, knownWordsInstruction), enableReasoning = shouldEnableReasoning)
                    saveLessonFile(lessonCache, filename, raw)
                }
                currentCounts["dialogue"] = i + 1
                System.gc()
            }

            // Step 5: Flashcard Sets (2 or 3)
            for (i in 0 until targetFlashcardCount) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Flashcards ${i + 1}/$targetFlashcardCount…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                val filename = "flashcards_$i.json"
                if (!aluFileExists(lessonCache, filename)) {
                    val summary = finalSummarizedPool[i % finalSummarizedPool.size]
                    val activeEngine = acquireEngine()
                    val raw = inferText(activeEngine, buildFlashcardsPrompt(summary.vocabulary, nativeLanguage, targetLanguage, knownWordsInstruction), enableReasoning = shouldEnableReasoning)
                    saveLessonFile(lessonCache, filename, raw)
                }
                currentCounts["flashcards"] = i + 1
                System.gc()
            }

            // Step 6: Quiz Items (2 or 5) — drawn from accumulated vocabulary
            val vocabForQuiz = collectedVocab.joinToString(", ").ifBlank { aggregateVocab.take(200) }
            for (i in 0 until targetQuizCount) {
                if (isCancelled) break
                currentStep++
                updateProgress(prefs, "Quiz ${i + 1}/$targetQuizCount…", currentStep, totalSteps, currentCounts, targetCounts, onProgress)
                val filename = "quiz_$i.json"
                if (!aluFileExists(lessonCache, filename)) {
                    val summary = finalSummarizedPool[i % finalSummarizedPool.size]
                    val activeEngine = acquireEngine()
                    val raw = inferText(activeEngine, buildQuizPrompt(summary.context, vocabForQuiz, nativeLanguage, targetLanguage), enableReasoning = shouldEnableReasoning)
                    saveLessonFile(lessonCache, filename, raw)
                }
                currentCounts["quiz"] = i + 1
                System.gc()
            }

            // ── Final: mark lesson ready ─────────────────────────────────────
            if (isCancelled) {
                 prefs.edit().putBoolean("flutter.lesson_ready", true).apply() // Allow partial lesson
                 return@withContext true
            }
            prefs.edit().putBoolean("flutter.lesson_ready", true).apply()
            Log.i(TAG, "generateLesson complete — lesson_ready=true")
            return@withContext true

        } catch (e: Exception) {
            Log.e(TAG, "generateLesson failed: ${e.message}", e)
            // Partial lesson — leave lesson_ready=false; UI will show what's ready
            prefs.edit().putBoolean("flutter.lesson_ready", false).apply()
            return@withContext false

        } finally {
            try {
                currentEngine?.close() // ← ONLY HERE
            } catch (e: Exception) {
                Log.e(TAG, "generateLesson close error: ${e.message}")
            }
            System.gc()
            prefs.edit().putBoolean("flutter.lesson_generating", false).apply()
        }
    }



    // ── Legacy: audio-only transcription (used by existing pipeline) ──────────

    suspend fun transcribePackets(context: Context, packetPaths: List<String>, onProgress: ((String) -> Unit)? = null): String =
        withContext(inferenceDispatcher) {
            isCancelled = false
            if (checkModelStatus(context) != "DOWNLOADED") return@withContext "[Error: Gemma model missing]"

            Log.i(TAG, "transcribePackets: waking engine for ${packetPaths.size} packets")
            var engine: Engine? = null
            try {
                val activeEngine = buildEngine(context, useAudio = true, maxNumTokens = null)
                engine = activeEngine
                activeEngine.initialize()
                val sb = StringBuilder()
                // Read language settings (default to Hinglish if not set)
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val nativeLang = prefs.getString("flutter.nativeLanguage", "Hindi") ?: "Hindi"
                val targetLang = prefs.getString("flutter.targetLanguage", "English") ?: "English"

                for ((index, path) in packetPaths.withIndex()) {
                    if (isCancelled) {
                        Log.i(TAG, "transcribePackets: Cancellation requested, breaking.")
                        break
                    }
                    onProgress?.invoke("Transcribing audio segment ${index + 1} of ${packetPaths.size}...")
                    val transcript = transcribeAudio(context, activeEngine, path, nativeLang, targetLang)
                    if (sb.isNotEmpty()) sb.append(" ")
                    sb.append(transcript)
                    System.gc()
                }

                if (isCancelled) return@withContext "[Cancelled]"

                val raw = sb.toString()
                return@withContext raw.trim()

            } catch (e: Exception) {
                Log.e(TAG, "transcribePackets error: ${e.message}", e)
                return@withContext "[Error: Transcription failed]"
            } finally {
                try {
                    engine?.close()
                } catch (e: Exception) {
                    Log.e(TAG, "transcribePackets close error: ${e.message}")
                }
                System.gc()
            }
        }

    /** Translates a map of UI strings sequentially using a dedicated small-context engine. */
    suspend fun translateUIElements(
        context: Context,
        uiElements: Map<String, String>,
        targetLanguage: String,
        onProgress: ((Int, Int) -> Unit)? = null
    ): Map<String, String> = withContext(inferenceDispatcher) {
        isCancelled = false
        if (checkModelStatus(context) != "DOWNLOADED") {
            Log.e(TAG, "translateUIElements: model missing — aborting")
            return@withContext emptyMap()
        }

        // Give maximum priority for UI translation to make it as fast as possible
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_FOREGROUND)
        Thread.currentThread().priority = Thread.MAX_PRIORITY

        if (!android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
            Log.e(TAG, "translateUIElements: device is not 64-bit arm (arm64-v8a). It is ${android.os.Build.SUPPORTED_ABIS.joinToString()}")
            return@withContext emptyMap()
        }

        val modelPath = File(context.filesDir, "models/$MODEL_FILENAME").absolutePath
        val threadCount = maxOf(4, Runtime.getRuntime().availableProcessors())
        
        Log.i(TAG, "translateUIElements: Using $threadCount threads for max compute.")
        
        val config = EngineConfig(
            modelPath   = modelPath,
            backend     = Backend.CPU(numOfThreads = threadCount), 
            audioBackend = null, 
            maxNumTokens = null,                       
            cacheDir    = context.cacheDir.path
        )
        val engine = Engine(config)
        val translatedMap = mutableMapOf<String, String>()

        try {
            engine.initialize()
            var count = 0
            val total = uiElements.size
            
            for ((key, englishText) in uiElements) {
                if (isCancelled) {
                    Log.i(TAG, "translateUIElements: Cancellation requested, breaking.")
                    break
                }
                ensureActive() // Throw CancellationException if job is cancelled
                
                // Report progress
                onProgress?.invoke(count, total)
                
                val prompt = "You are an expert UX localization translator. Translate the following app interface text into $targetLanguage. " +
                             "CRITICAL INSTRUCTION: You MUST use the official native script and alphabet of $targetLanguage (For example, if the language is Hindi, you must write in Devanagari script. Do NOT use Romanized/English alphabets). " +
                             "Output ONLY the translated text. Do not add quotes, punctuation, or conversational filler. " +
                             "Text to translate: '$englishText'"
                
                val response = inferText(engine, prompt)
                translatedMap[key] = response.trim()
                
                count++
                if (count % 5 == 0) {
                    System.gc() // keep KV cache clean
                }
            }
            // Final progress update
            onProgress?.invoke(total, total)
        } catch (e: kotlinx.coroutines.CancellationException) {
            Log.i(TAG, "UI translation cancelled, nuking model from RAM.")
            translatedMap.clear()
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "UI translation failed: ${e.message}", e)
        } finally {
            try {
                engine.close()
            } catch (e: Exception) {
                Log.e(TAG, "UI translation close error: ${e.message}")
            }
            System.gc() // nuke from RAM
            
            // Restore background priority
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            Thread.currentThread().priority = Thread.MIN_PRIORITY
        }

        return@withContext translatedMap
    }
}