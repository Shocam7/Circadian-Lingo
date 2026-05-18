import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_pipeline_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State model
// ─────────────────────────────────────────────────────────────────────────────

/// The complete state of the offline audio pipeline.
enum PipelineStatus {
  /// No recording or processing is active.
  idle,

  /// [AudioCaptureService] is running; microphone is active.
  recording,

  /// VAD + Whisper pipeline is running. UI should show a progress indicator.
  processing,

  /// Pipeline completed successfully. [transcript] contains the result.
  done,

  /// A recoverable error occurred. [errorMessage] contains details.
  error,
}

/// Immutable snapshot of the audio pipeline state.
class AudioPipelineState {
  final PipelineStatus status;

  /// Absolute path to the trimmed 16kHz mono WAV file.
  /// Non-null when [status] is [PipelineStatus.done].
  /// Empty string means VAD found no speech in the audio.
  final String? audioPath;

  /// Non-null when [status] is [PipelineStatus.error].
  final String? errorMessage;

  /// The native error code from [AudioPipelineException.code].
  final String? errorCode;

  const AudioPipelineState({
    this.status = PipelineStatus.idle,
    this.audioPath,
    this.errorMessage,
    this.errorCode,
  });

  AudioPipelineState copyWith({
    PipelineStatus? status,
    String? audioPath,
    String? errorMessage,
    String? errorCode,
  }) {
    return AudioPipelineState(
      status: status ?? this.status,
      audioPath: audioPath ?? this.audioPath,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
    );
  }

  bool get isIdle => status == PipelineStatus.idle;
  bool get isRecording => status == PipelineStatus.recording;
  bool get isProcessing => status == PipelineStatus.processing;
  bool get isDone => status == PipelineStatus.done;
  bool get hasError => status == PipelineStatus.error;

  @override
  String toString() =>
      'AudioPipelineState(status=$status, '
      'audioPath=$audioPath, error=$errorMessage)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

/// The singleton [AudioPipelineService] — created once and reused across
/// the provider so the MethodChannel is not re-created on every rebuild.
final audioPipelineServiceProvider = Provider<AudioPipelineService>(
  (ref) => AudioPipelineService(),
);

/// Provides the full audio pipeline as an [AsyncNotifier].
///
/// Usage in a widget:
/// ```dart
/// final state = ref.watch(audioPipelineProvider);
/// // or: await ref.read(audioPipelineProvider.notifier).startCapture();
/// ```
final audioPipelineProvider =
    AsyncNotifierProvider<AudioPipelineNotifier, AudioPipelineState>(
      AudioPipelineNotifier.new,
    );

/// [AsyncNotifier] that owns the [AudioPipelineState] and exposes the
/// audio pipeline's public actions to the Flutter UI.
class AudioPipelineNotifier extends AsyncNotifier<AudioPipelineState> {
  late final AudioPipelineService _service;

  @override
  Future<AudioPipelineState> build() async {
    _service = ref.read(audioPipelineServiceProvider);

    // Kick off model readiness check on first build, non-blocking.
    _ensureModels();

    return const AudioPipelineState();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Requests RECORD_AUDIO permission (via native) and starts the
  /// [AudioCaptureService] foreground service.
  Future<void> startCapture() async {
    state = const AsyncValue.loading();
    try {
      await _service.startCapture();
      state = AsyncValue.data(
        const AudioPipelineState(status: PipelineStatus.recording),
      );
    } on AudioPipelineException catch (e) {
      state = AsyncValue.data(
        AudioPipelineState(
          status: PipelineStatus.error,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    }
  }

  /// Stops the recording and stores the raw .m4a path in state.
  /// No automatic processing occurs; the UI will handle playback.
  Future<void> stopAndProcess() async {
    state = AsyncValue.data(
      const AudioPipelineState(status: PipelineStatus.processing),
    );
    try {
      final rawPath = await _service.stopCapture();
      state = AsyncValue.data(
        AudioPipelineState(status: PipelineStatus.done, audioPath: rawPath),
      );
    } on AudioPipelineException catch (e) {
      state = AsyncValue.data(
        AudioPipelineState(
          status: PipelineStatus.error,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    }
  }

  /// Resets the state back to [PipelineStatus.idle].
  /// Call after consuming the transcript (e.g., after sending to Gemma).
  void reset() {
    state = const AsyncValue.data(AudioPipelineState());
  }

  /// Runs [AudioPipelineService.processAudio] on an already-recorded file.
  /// Useful for the README's "Force Night-Shift" debug button.
  Future<void> processAudio(String filePath) async {
    state = AsyncValue.data(
      const AudioPipelineState(status: PipelineStatus.processing),
    );
    try {
      final audioPath = await _service.processAudio(filePath);
      state = AsyncValue.data(
        AudioPipelineState(status: PipelineStatus.done, audioPath: audioPath),
      );
    } on AudioPipelineException catch (e) {
      state = AsyncValue.data(
        AudioPipelineState(
          status: PipelineStatus.error,
          errorCode: e.code,
          errorMessage: e.message,
        ),
      );
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _ensureModels() async {
    try {
      final ready = await _service.ensureModels();
      if (!ready) {
        // Models failed to extract — surface an error so the user is informed.
        state = AsyncValue.data(
          const AudioPipelineState(
            status: PipelineStatus.error,
            errorCode: 'MODELS_NOT_READY',
            errorMessage:
                'AI models could not be prepared. '
                'Please ensure silero_vad.onnx is bundled in assets/models/.',
          ),
        );
      }
    } on AudioPipelineException catch (_) {
      // Non-fatal — UI will surface the error when the user tries to record.
    }
  }
}
