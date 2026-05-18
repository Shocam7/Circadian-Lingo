import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cleans up lesson ALU files from native cache that are older than [maxAgeDays].
/// Called once on app launch. Never purges FSRS or learned-words data.
class StorageCleanupService {
  static const _prefsKey   = 'consumed_lesson_dates';
  static const _maxAgeDays = 7;
  static const _channel    = MethodChannel('com.circadian_lingo/audio_pipeline');

  /// Run on every app launch. Deletes ALU JSON files older than 7 days.
  static Future<void> runOnLaunch() async {
    try {
      final cacheDirPath = await _channel.invokeMethod<String>('getLessonCacheDir');
      if (cacheDirPath == null) return;

      final cacheDir = Directory(cacheDirPath);
      if (!await cacheDir.exists()) return;

      final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
      final prefs  = await SharedPreferences.getInstance();

      // Load previously consumed lesson date strings
      final raw = prefs.getString(_prefsKey);
      final consumed = raw != null
          ? (jsonDecode(raw) as List).cast<String>()
          : <String>[];

      final entities = cacheDir.listSync().whereType<File>();

      for (final file in entities) {
        final modified = file.lastModifiedSync();
        if (modified.isBefore(cutoff)) {
          // Only delete if this lesson date was fully consumed
          final dateKey = _dateKey(modified);
          if (consumed.contains(dateKey)) {
            await file.delete();
          }
        }
      }


    } catch (e) {
      // Non-fatal — cleanup is best-effort
    }
  }

  /// Call after a lesson session is fully completed by the user.
  static Future<void> markLessonConsumed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final consumed = raw != null
        ? (jsonDecode(raw) as List).cast<String>()
        : <String>[];

    final today = _dateKey(DateTime.now());
    if (!consumed.contains(today)) {
      consumed.add(today);
      // Keep last 14 entries
      final trimmed = consumed.length > 14
          ? consumed.sublist(consumed.length - 14)
          : consumed;
      await prefs.setString(_prefsKey, jsonEncode(trimmed));
    }
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
