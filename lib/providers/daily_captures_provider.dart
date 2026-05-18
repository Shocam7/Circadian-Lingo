import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_pipeline_provider.dart';
import 'settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Quality Threshold (architecture.txt §QUALITY THRESHOLD)
// ─────────────────────────────────────────────────────────────────────────────

enum CaptureQuality { unknown, usable, excludedTooShort, excludedTooFewWords }

const _minAudioSeconds = 10;
const _minTextWords    = 20;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a single captured context session.
class CaptureItem {
  final String id;
  final DateTime timestamp;
  final String type; // 'audio_raw' | 'screen_context'
  final String? filePath;   // .m4a audio path
  final String? imagePath;  // .jpg screenshot path
  final String? textPath;   // .txt scraped-text path
  final String? content;    // pre-loaded text content
  final CaptureQuality quality;
  final String? excludeReason; // e.g. "Audio too short: 6s / min 10s"

  const CaptureItem({
    required this.id,
    required this.timestamp,
    required this.type,
    this.filePath,
    this.imagePath,
    this.textPath,
    this.content,
    this.quality = CaptureQuality.unknown,
    this.excludeReason,
  });

  CaptureItem copyWith({
    CaptureQuality? quality,
    String? excludeReason,
    String? content,
  }) => CaptureItem(
        id: id, timestamp: timestamp, type: type,
        filePath: filePath, imagePath: imagePath,
        textPath: textPath,
        content: content ?? this.content,
        quality: quality ?? this.quality,
        excludeReason: excludeReason ?? this.excludeReason,
      );

  @override
  String toString() =>
      'CaptureItem(id=$id, type=$type, quality=$quality, excludeReason=$excludeReason)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class DailyCapturesNotifier extends Notifier<List<CaptureItem>> {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');

  // ── Quality computation ────────────────────────────────────────────────────

  /// Tags a capture as usable or excluded with a specific reason.
  Future<CaptureItem> _withQuality(CaptureItem item) async {
    if (item.type == 'audio_raw') {
      if (item.filePath == null) {
        return item.copyWith(quality: CaptureQuality.excludedTooShort, excludeReason: 'No audio file');
      }
      try {
        final ms = await _channel.invokeMethod<int>('getAudioDurationMs', {'filePath': item.filePath});
        final secs = (ms ?? 0) ~/ 1000;
        if (secs < _minAudioSeconds) {
          return item.copyWith(
            quality: CaptureQuality.excludedTooShort,
            excludeReason: 'Audio too short: ${secs}s / min ${_minAudioSeconds}s',
          );
        }
        return item.copyWith(quality: CaptureQuality.usable);
      } catch (_) {
        return item.copyWith(quality: CaptureQuality.unknown);
      }
    } else if (item.type == 'screen_context') {
      final text = item.content ?? '';
      final wordCount = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (wordCount < _minTextWords) {
        return item.copyWith(
          quality: CaptureQuality.excludedTooFewWords,
          excludeReason: 'Too few words: $wordCount / min $_minTextWords',
        );
      }
      return item.copyWith(quality: CaptureQuality.usable);
    }
    return item.copyWith(quality: CaptureQuality.unknown);
  }

  bool _isSyncing = false;

  @override
  List<CaptureItem> build() {
    // Listen to the audio pipeline. When a 'done' state arrives with a
    // non-empty transcript, automatically create and store a CaptureItem.
    ref.listen<AsyncValue<AudioPipelineState>>(audioPipelineProvider, (
      previous,
      next,
    ) {
      final pipelineState = next.asData?.value;
      if (pipelineState == null) return;

      if (pipelineState.isDone &&
          pipelineState.audioPath != null &&
          pipelineState.audioPath!.isNotEmpty) {
        // Only add if this is a genuinely new completion (not a re-watch).
        final prevState = previous?.asData?.value;
        final alreadySaved =
            prevState != null &&
            prevState.isDone &&
            prevState.audioPath == pipelineState.audioPath;
        if (alreadySaved) return;

        // NEW: Audio is now added as 'audio_raw' for playable deferred UI.
        addCapture(pipelineState.audioPath!, type: 'audio_raw');
      }
    });

    // Initial purge and sync - delayed slightly to avoid overlap with UI initialization
    Future.delayed(const Duration(milliseconds: 100), () => purgeStaleCaptures());

    return [];
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> syncAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await syncVisualCaptures();
      await syncAudioCaptures();
      _updateSettingsCounts();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> syncVisualCaptures() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getSavedScreenshots',
      );
      
      final List<CaptureItem> newItems = [];
      final existingIds = state.map((e) => e.id).toSet();

      for (final dynamic itemData in result) {
        final map = Map<String, dynamic>.from(itemData as Map);
        final String id = map['id'] as String;

        // Skip if already in state or already processed in this batch
        if (existingIds.contains(id)) continue;
        if (newItems.any((it) => it.id == id)) continue;

        final String? textPath = map['textPath'] as String?;
        final String? imagePath = map['imagePath'] as String?;

        String? content;
        DateTime ts = DateTime.now();

        if (textPath != null) {
          try {
            final file = File(textPath);
            if (await file.exists()) {
              content = await file.readAsString();
              ts = await file.lastModified();
            }
          } catch (_) {}
        } else if (imagePath != null) {
          try {
            final file = File(imagePath);
            if (await file.exists()) {
              ts = await file.lastModified();
            }
          } catch (_) {}
        }

        var item = CaptureItem(
          id: id,
          timestamp: ts,
          type: 'screen_context',
          textPath: textPath,
          imagePath: imagePath,
          content: content,
        );
        item = await _withQuality(item);
        newItems.add(item);
      }

      if (newItems.isNotEmpty) {
        // Final check against state just in case it changed during the loop
        final latestIds = state.map((e) => e.id).toSet();
        final filtered = newItems.where((it) => !latestIds.contains(it.id)).toList();
        
        if (filtered.isNotEmpty) {
          state = [...state, ...filtered]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> syncAudioCaptures() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getSavedAudioRecordings',
      );
      final List<String> savedPaths = result.cast<String>();

      final List<CaptureItem> newItems = [];
      final currentPaths = state.map((e) => e.filePath).toSet();

      for (final path in savedPaths) {
        if (currentPaths.contains(path)) continue;
        if (newItems.any((it) => it.filePath == path)) continue;
        if (!path.endsWith('.m4a')) continue;

        DateTime ts;
        try {
          ts = await File(path).lastModified();
        } catch (_) {
          ts = DateTime.now();
        }

        var item = CaptureItem(
          id: path, // Audio items use path as ID
          timestamp: ts,
          type: 'audio_raw',
          filePath: path,
        );
        item = await _withQuality(item);
        newItems.add(item);
      }

      if (newItems.isNotEmpty) {
        final latestPaths = state.map((e) => e.filePath).toSet();
        final filtered = newItems.where((it) => !latestPaths.contains(it.filePath)).toList();
        
        if (filtered.isNotEmpty) {
          state = [...state, ...filtered]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }
      }
    } catch (e) {
      // ignore
    }
  }

  /// Appends a new [CaptureItem] with [filePath] and the current time.
  void addCapture(String filePath, {String type = 'audio_raw'}) {
    // Deduplicate fresh additions too
    if (state.any((it) => it.filePath == filePath)) return;

    final item = CaptureItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: type,
      filePath: filePath,
    );
    state = [...state, item]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _updateSettingsCounts();
  }

  /// Removes the [CaptureItem] identified by [id].
  Future<void> removeCapture(String id) async {
    try {
      final item = state.firstWhere((element) => element.id == id);
      // All file-based captures (.m4a, .jpg, .txt) are deleted natively.
      if (item.filePath != null) {
        await _channel.invokeMethod('deleteScreenshot', {
          'filePath': item.filePath,
        });
      }
      if (item.imagePath != null) {
        await _channel.invokeMethod('deleteScreenshot', {
          'filePath': item.imagePath,
        });
      }
      if (item.textPath != null) {
        await _channel.invokeMethod('deleteScreenshot', {
          'filePath': item.textPath,
        });
      }
    } catch (_) {}
    state = state.where((item) => item.id != id).toList();
    _updateSettingsCounts();
  }

  void _updateSettingsCounts() {
    final screenCount = state.where((c) => c.type == 'screen_context').length;
    final audioCount =
        state.where((c) => c.type == 'audio_raw' || c.type == 'audio').length;
    ref.read(userSettingsProvider.notifier).updateCounts(screenCount, audioCount);
  }

  /// Clears current state and re-populates from storage.
  Future<void> refreshCaptures() async {
    await purgeStaleCaptures();
  }

  /// Clears all captures (e.g., after lesson generation).
  void clearAll() {
    state = [];
  }

  /// NEW: Identifies and deletes files from previous days.
  /// Returns true if this is the first launch of a new calendar day.
  Future<bool> purgeStaleCaptures() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    
    try {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      // 1. Get the files directory from native side
      String? filesDirPath;
      try {
        filesDirPath = await _channel.invokeMethod<String>('getFilesDir');
      } catch (e) {
        // fallback or ignore
      }

      if (filesDirPath == null) return false;

      // 2. Identify and Delete Stale Data
      final dirsToCleanup = ['recordings', 'captures'];

      for (final dirName in dirsToCleanup) {
        final dir = Directory('$filesDirPath/$dirName');
        if (await dir.exists()) {
          final List<FileSystemEntity> entities = dir.listSync();
          for (final entity in entities) {
            if (entity is File) {
              try {
                final lastModified = entity.lastModifiedSync();
                if (lastModified.isBefore(todayMidnight)) {
                  entity.deleteSync();
                }
              } catch (_) {
                // skip files in use
              }
            }
          }
        }
      }

      // 3. Date Logic for "First Launch of Day" notification
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getString('last_cleanup_day');
      final todayStr = "${now.year}-${now.month}-${now.day}";
      final bool isNewDay = lastCleanup != todayStr;

      if (isNewDay) {
        await prefs.setString('last_cleanup_day', todayStr);
      }

      // 4. Always Sync State (ensure state is up to date with disk)
      state = []; 
      
      // We are already inside _isSyncing lock, so we can't call syncAll().
      // We manually trigger the syncs here.
      await syncVisualCaptures();
      await syncAudioCaptures();
      _updateSettingsCounts();

      return isNewDay;
    } finally {
      _isSyncing = false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final dailyCapturesProvider =
    NotifierProvider<DailyCapturesNotifier, List<CaptureItem>>(
      DailyCapturesNotifier.new,
    );
