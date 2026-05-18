import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ModelStatus {
  final bool isDownloaded;
  final bool isDownloading;
  final double progress;
  final String statusString;
  final String? error;
  final int? bytesDownloaded;
  final int? bytesTotal;
  final double? downloadSpeedBytesPerSec;

  ModelStatus({
    required this.isDownloaded,
    required this.isDownloading,
    required this.progress,
    required this.statusString,
    this.error,
    this.bytesDownloaded,
    this.bytesTotal,
    this.downloadSpeedBytesPerSec,
  });

  ModelStatus copyWith({
    bool? isDownloaded,
    bool? isDownloading,
    double? progress,
    String? statusString,
    String? error,
    int? bytesDownloaded,
    int? bytesTotal,
    double? downloadSpeedBytesPerSec,
  }) {
    return ModelStatus(
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      statusString: statusString ?? this.statusString,
      error: error ?? this.error,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      downloadSpeedBytesPerSec: downloadSpeedBytesPerSec ?? this.downloadSpeedBytesPerSec,
    );
  }
}

class ModelNotifier extends Notifier<ModelStatus> {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');
  static const _eventChannel = EventChannel('com.circadian_lingo/download_progress');
  StreamSubscription? _subscription;

  @override
  ModelStatus build() {
    // We don't want to dispose the subscription here as it's a long-running process.
    // However, Notifier doesn't have an easy 'dispose' like StateNotifier.
    // We'll check status on first build.
    Future.microtask(() => checkStatus());
    return ModelStatus(
      isDownloaded: false,
      isDownloading: false,
      progress: 0.0,
      statusString: 'UNKNOWN',
      bytesDownloaded: null,
      bytesTotal: null,
      downloadSpeedBytesPerSec: null,
    );
  }

  Future<void> checkStatus() async {
    try {
      final String status = await _channel.invokeMethod('checkModelStatus');
      state = state.copyWith(
        isDownloaded: status == 'DOWNLOADED',
        statusString: status,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> startDownload() async {
    if (state.isDownloading || state.isDownloaded) return;

    state = state.copyWith(
      isDownloading: true, 
      progress: 0.0, 
      error: null,
      bytesDownloaded: 0,
      bytesTotal: 0,
      downloadSpeedBytesPerSec: 0.0,
    );

    try {
      await _channel.invokeMethod('startDownload');
      _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
        final Map<dynamic, dynamic> map = event as Map<dynamic, dynamic>;
        final String status = map['status'] as String;

        if (status == 'downloading') {
          state = state.copyWith(
            progress: (map['progress'] as num).toDouble(),
            bytesDownloaded: map['bytesDownloaded'] != null ? (map['bytesDownloaded'] as num).toInt() : null,
            bytesTotal: map['bytesTotal'] != null ? (map['bytesTotal'] as num).toInt() : null,
            downloadSpeedBytesPerSec: map['speedBytesPerSec'] != null ? (map['speedBytesPerSec'] as num).toDouble() : null,
          );
        } else if (status == 'complete') {
          final bool success = map['success'] as bool;
          state = state.copyWith(
            isDownloading: false,
            isDownloaded: success,
            progress: success ? 1.0 : 0.0,
            statusString: success ? 'DOWNLOADED' : 'MISSING',
            error: success ? null : 'Download processing failed after completion.',
            bytesDownloaded: null,
            bytesTotal: null,
            downloadSpeedBytesPerSec: null,
          );
          _subscription?.cancel();
        }
      }, onError: (err) {
        state = state.copyWith(
          isDownloading: false, 
          error: err.toString(),
          bytesDownloaded: null,
          bytesTotal: null,
          downloadSpeedBytesPerSec: null,
        );
        _subscription?.cancel();
      });
    } catch (e) {
      state = state.copyWith(
        isDownloading: false, 
        error: e.toString(),
        bytesDownloaded: null,
        bytesTotal: null,
        downloadSpeedBytesPerSec: null,
      );
    }
  }
}

final modelProvider = NotifierProvider<ModelNotifier, ModelStatus>(() {
  return ModelNotifier();
});
