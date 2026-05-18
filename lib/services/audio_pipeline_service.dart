import 'package:flutter/services.dart';

/// AudioPipelineService — Clean Dart API over the native MethodChannel.
///
/// Wraps all calls to 'com.circadian_lingo/audio_pipeline' and provides
/// meaningful typed exceptions in place of raw [PlatformException]s.
///
/// Typical Idle-Shift usage:
/// ```dart
/// final service = AudioPipelineService();
///
/// // Step 1 – morning: start the Silent Collector.
/// await service.startCapture();
///
/// // ... device is used throughout the day ...
///
/// // Step 2–3 – at idle time: stop recording, run VAD.
/// final audioPath = await service.stopAndProcess();
/// ```
class AudioPipelineService {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');

  // ── Core pipeline methods ───────────────────────────────────────────────

  /// Starts the [AudioCaptureService] foreground service and begins
  /// recording compressed AAC audio to the app's internal storage.
  ///
  /// Throws [AudioPipelineException] if:
  ///   - RECORD_AUDIO permission has not been granted.
  ///   - A recording is already in progress.
  Future<void> startCapture() async {
    try {
      await _channel.invokeMethod<void>('startCapture');
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'startCapture failed');
    }
  }

  /// Stops the active recording.
  ///
  /// Returns the absolute path to the raw `.m4a` file in internal storage.
  /// Use this path as the argument to [processAudio].
  ///
  /// Throws [AudioPipelineException] if no recording was active.
  Future<String> stopCapture() async {
    try {
      final path = await _channel.invokeMethod<String>('stopCapture');
      return path ??
          (throw AudioPipelineException(
            'NULL_PATH',
            'stopCapture returned null',
          ));
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'stopCapture failed');
    }
  }

  ///   1. Decodes `.m4a` → 16kHz mono PCM WAV  (Kotlin MediaCodec)
  ///   2. Strips silence  (ONNX Runtime Silero VAD)
  ///
  /// Returns the absolute path to the trimmed `.wav` file. Returns an
  /// **empty string** if VAD found no speech in the audio.
  ///
  /// Throws [AudioPipelineException] on decode or VAD failure.
  Future<String> processAudio(String filePath) async {
    try {
      final audioPath = await _channel.invokeMethod<String>('processAudio', {
        'filePath': filePath,
      });
      return audioPath ?? '';
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'processAudio failed');
    }
  }

  /// Returns the current pipeline status.
  ///
  /// Possible values: `'idle'`, `'recording'`, `'processing'`
  Future<String> getStatus() async {
    try {
      return await _channel.invokeMethod<String>('getStatus') ?? 'idle';
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'getStatus failed');
    }
  }

  /// Ensures the `silero_vad.onnx` model file has
  /// been extracted from the APK's assets to [filesDir]/models/.
  ///
  /// Returns `true` if the model is ready.
  Future<bool> ensureModels() async {
    try {
      return await _channel.invokeMethod<bool>('ensureModels') ?? false;
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'ensureModels failed');
    }
  }

  /// Notifies the native side to stop any in-flight processing.
  ///
  /// Note: whisper.cpp inference is synchronous — this call is a no-op until
  /// async cancellation is implemented in a future version.
  Future<void> cancelProcessing() async {
    try {
      await _channel.invokeMethod<void>('cancelProcessing');
    } on PlatformException catch (e) {
      throw AudioPipelineException(
        e.code,
        e.message ?? 'cancelProcessing failed',
      );
    }
  }

  /// Batch processes multiple `.m4a` files:
  ///   1. Decodes each `.m4a` -> 16kHz mono PCM WAV.
  ///   2. Trims silence using Silero VAD.
  ///   3. Transcribes all speech segments using Gemma.
  ///
  /// Returns the final concatenated transcript.
  /// Intermediate `.wav` files are cleaned up automatically.
  Future<String> processRawAudioBatch(List<String> m4aPaths) async {
    try {
      final transcript = await _channel.invokeMethod<String>(
        'processRawAudioBatch',
        {'m4aPaths': m4aPaths},
      );
      return transcript ?? '';
    } on PlatformException catch (e) {
      throw AudioPipelineException(
        e.code,
        e.message ?? 'processRawAudioBatch failed',
      );
    }
  }

  /// Convenience wrapper: stops the current recording, then runs the
  /// VAD pipeline and returns the final trimmed WAV path.
  ///
  /// Throws [AudioPipelineException] on any step failure.
  Future<String> stopAndProcess() async {
    final m4aPath = await stopCapture();
    return processAudio(m4aPath);
  }

  // ── Gemma Model Download ───────────────────────────────────────────────

  static const _downloadChannel = EventChannel(
    'com.circadian_lingo/download_progress',
  );

  /// Checks the status of the Gemma model (internal, side-loaded, or missing).
  Future<String> checkModelStatus() async {
    try {
      return await _channel.invokeMethod<String>('checkModelStatus') ??
          'MISSING_USE_DEMO';
    } on PlatformException catch (e) {
      throw AudioPipelineException(
        e.code,
        e.message ?? 'checkModelStatus failed',
      );
    }
  }

  /// Initiates the background download of the Gemma model via DownloadManager.
  Future<void> startDownload() async {
    try {
      await _channel.invokeMethod<void>('startModelDownload');
    } on PlatformException catch (e) {
      throw AudioPipelineException(e.code, e.message ?? 'startDownload failed');
    }
  }

  /// Returns a stream of progress updates from the active model download.
  ///
  /// Stream events are [Map<String, dynamic>] containing:
  ///   - `status`: 'downloading' | 'complete'
  ///   - `progress`: 0.0 to 1.0 (only if downloading)
  ///   - `success`: bool (only if complete)
  Stream<Map<dynamic, dynamic>> get downloadProgress {
    return _downloadChannel.receiveBroadcastStream().map(
      (event) => event as Map<dynamic, dynamic>,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed exception for clean error handling in the UI layer.
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown by [AudioPipelineService] when the native layer returns a
/// [PlatformException]. The [code] maps directly to the error code returned
/// by the Kotlin MethodChannel handler.
///
/// Known error codes:
///   - `ALREADY_RECORDING`   — [startCapture] called while recording
///   - `PERMISSION_DENIED`   — RECORD_AUDIO not granted
///   - `NOT_RECORDING`       — [stopCapture] called when not recording
///   - `STOP_FAILED`         — MediaRecorder.stop() failed
///   - `ALREADY_PROCESSING`  — [processAudio] called while processing
///   - `INVALID_ARGUMENT`    — filePath missing or blank
///   - `PIPELINE_ERROR`      — unexpected exception during decode/VAD
///   - `GEMMA_ERROR`         — error during Gemma model inference or setup
class AudioPipelineException implements Exception {
  final String code;
  final String message;

  const AudioPipelineException(this.code, this.message);

  @override
  String toString() => 'AudioPipelineException($code): $message';
}
