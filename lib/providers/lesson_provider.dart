import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alu.dart';
import '../models/alu_parser.dart';
import '../models/word_review_record.dart';
import '../services/fsrs_service.dart';
import 'daily_captures_provider.dart';

// ── Session model ─────────────────────────────────────────────────────────────

enum SessionType { captureLesson, quickReview, onboarding }

class LessonSession {
  final String id;
  final SessionType type;
  final bool isPartial;
  final List<Alu> items;
  final List<WordReviewRecord> dueReviews;
  final bool isSpecific;
  final bool isCompleted;
  final DateTime generatedAt;

  const LessonSession({
    required this.id,
    required this.type,
    required this.items,
    this.isPartial = false,
    this.dueReviews = const [],
    this.isSpecific = false,
    this.isCompleted = false,
    required this.generatedAt,
  });

  static final empty = LessonSession(
    id: '',
    type: SessionType.onboarding,
    items: [],
    generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  bool get hasContent => items.isNotEmpty || dueReviews.isNotEmpty;
}

class LessonsState {
  final List<LessonSession> sessions;
  final List<WordReviewRecord> dueReviews;

  const LessonsState({required this.sessions, this.dueReviews = const []});

  static const empty = LessonsState(sessions: [], dueReviews: []);

  bool get hasContent => sessions.isNotEmpty || dueReviews.isNotEmpty;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final lessonProvider = AsyncNotifierProvider<LessonNotifier, LessonsState>(
  LessonNotifier.new,
);

class LessonProgressPercent extends Notifier<double?> {
  @override
  double? build() => null;
  void update(double? v) => state = v;
}

final lessonProgressPercentProvider =
    NotifierProvider<LessonProgressPercent, double?>(LessonProgressPercent.new);

class LessonProgressMessage extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? v) => state = v;
}

final lessonProgressMessageProvider =
    NotifierProvider<LessonProgressMessage, String?>(LessonProgressMessage.new);

class LessonGenerationIsSpecific extends Notifier<bool> {
  @override
  bool build() => false;
  void update(bool v) => state = v;
}

final lessonGenerationIsSpecificProvider =
    NotifierProvider<LessonGenerationIsSpecific, bool>(
      LessonGenerationIsSpecific.new,
    );

class LessonProgressCounts {
  final Map<String, int> current;
  final Map<String, int> target;

  LessonProgressCounts({required this.current, required this.target});

  static LessonProgressCounts empty() => LessonProgressCounts(
    current: {},
    target: {1: 1}.map((k, v) => MapEntry('', 0)),
  ); // just a placeholder
}

class LessonProgressCountsNotifier extends Notifier<LessonProgressCounts?> {
  @override
  LessonProgressCounts? build() => null;
  void update(LessonProgressCounts? v) => state = v;
}

final lessonProgressCountsProvider =
    NotifierProvider<LessonProgressCountsNotifier, LessonProgressCounts?>(
      LessonProgressCountsNotifier.new,
    );

class LessonNotifier extends AsyncNotifier<LessonsState> {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');

  @override
  Future<LessonsState> build() => _assemble();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_assemble);
  }

  Future<void> generateLesson({CaptureItem? item}) async {
    final isSpecific = item != null;
    ref.read(lessonGenerationIsSpecificProvider.notifier).update(isSpecific);

    state = const AsyncLoading();
    try {
      await _channel.invokeMethod('generateLesson', {
        'isSpecific': isSpecific,
        'itemId': item?.id,
        'itemType': item?.type,
      });

      // Reset progress
      ref.read(lessonProgressPercentProvider.notifier).update(0.0);
      ref
          .read(lessonProgressMessageProvider.notifier)
          .update("Starting generation...");
      ref.read(lessonProgressCountsProvider.notifier).update(null);

      // Poll until ready
      bool ready = false;
      int attempts = 0;
      while (!ready && attempts < 240) {
        // Max 4 mins (at 1s polling)
        await Future.delayed(const Duration(seconds: 1));
        ready =
            await _channel.invokeMethod<bool>('getLessonReadyStatus') ?? false;

        if (!ready) {
          final progress = await _channel.invokeMapMethod<String, dynamic>(
            'getLessonProgress',
          );
          if (progress != null) {
            ref
                .read(lessonProgressPercentProvider.notifier)
                .update(progress['percent'] as double?);
            ref
                .read(lessonProgressMessageProvider.notifier)
                .update(progress['message'] as String?);

            // Handle counts if present
            final currentRaw = progress['current_counts'] as String?;
            final targetRaw = progress['target_counts'] as String?;

            if (currentRaw != null &&
                targetRaw != null &&
                currentRaw != '{}' &&
                targetRaw != '{}') {
              try {
                final current = (jsonDecode(currentRaw) as Map)
                    .cast<String, int>();
                final target = (jsonDecode(targetRaw) as Map)
                    .cast<String, int>();

                ref
                    .read(lessonProgressCountsProvider.notifier)
                    .update(
                      LessonProgressCounts(current: current, target: target),
                    );
              } catch (_) {}
            }
          }
        }
        attempts++;
      }

      if (ready) {
        ref.read(lessonProgressPercentProvider.notifier).update(1.0);
        ref
            .read(lessonProgressMessageProvider.notifier)
            .update("Finalizing lesson content…");
        await refresh();
      }

      ref.read(lessonProgressPercentProvider.notifier).update(null);
      ref.read(lessonProgressMessageProvider.notifier).update(null);

      if (ready) {
        await refresh();
      }
    } catch (e) {
      ref.read(lessonProgressPercentProvider.notifier).update(null);
      ref.read(lessonProgressMessageProvider.notifier).update(null);
      state = AsyncError(e, StackTrace.current);
    }
  }

  Future<void> cancelGeneration() async {
    try {
      await _channel.invokeMethod('cancelLessonGeneration');
    } catch (_) {}
  }

  DateTime _parseTimestamp(String folderName) {
    // folderName format: lesson_YYYYMMDD_HHMMSS_type
    try {
      final parts = folderName.split('_');
      if (parts.length >= 3) {
        final dateStr = parts[1]; // YYYYMMDD
        final timeStr = parts[2]; // HHMMSS
        if (dateStr.length == 8 && timeStr.length == 6) {
          final year = int.parse(dateStr.substring(0, 4));
          final month = int.parse(dateStr.substring(4, 6));
          final day = int.parse(dateStr.substring(6, 8));
          final hour = int.parse(timeStr.substring(0, 2));
          final minute = int.parse(timeStr.substring(2, 4));
          final second = int.parse(timeStr.substring(4, 6));
          return DateTime(year, month, day, hour, minute, second);
        }
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<LessonsState> _assemble() async {
    // Check if actively generating in background
    bool isGenerating =
        await _channel.invokeMethod<bool>('getLessonGeneratingStatus') ?? false;

    if (isGenerating) {
      // Loop and update progress while it generates
      while (isGenerating) {
        final progress = await _channel.invokeMapMethod<String, dynamic>(
          'getLessonProgress',
        );
        if (progress != null) {
          ref
              .read(lessonProgressPercentProvider.notifier)
              .update(progress['percent'] as double?);
          ref
              .read(lessonProgressMessageProvider.notifier)
              .update(progress['message'] as String?);

          final currentRaw = progress['current_counts'] as String?;
          final targetRaw = progress['target_counts'] as String?;
          if (currentRaw != null &&
              targetRaw != null &&
              currentRaw != '{}' &&
              targetRaw != '{}') {
            try {
              final current = (jsonDecode(currentRaw) as Map)
                  .cast<String, int>();
              final target = (jsonDecode(targetRaw) as Map).cast<String, int>();
              ref
                  .read(lessonProgressCountsProvider.notifier)
                  .update(
                    LessonProgressCounts(current: current, target: target),
                  );
            } catch (_) {}
          }
        }
        await Future.delayed(const Duration(seconds: 1));
        isGenerating =
            await _channel.invokeMethod<bool>('getLessonGeneratingStatus') ??
            false;
      }
      ref.read(lessonProgressPercentProvider.notifier).update(1.0);
      ref
          .read(lessonProgressMessageProvider.notifier)
          .update("Assembling lesson content…");
    }

    // 1. Get lesson cache directory
    final cacheDirPath = await _channel.invokeMethod<String>(
      'getLessonCacheDir',
    );
    final cacheDir = cacheDirPath != null ? Directory(cacheDirPath) : null;

    final sessions = <LessonSession>[];

    // 2. Scan lesson subdirectories inside cacheDir
    if (cacheDir != null && await cacheDir.exists()) {
      final list = cacheDir.listSync().whereType<Directory>().toList();
      for (final subDir in list) {
        final name = subDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith('lesson_')) {
          final isSpecificMarker = await File(
            '${subDir.path}/is_specific.tag',
          ).exists();
          final isCompleted = await File(
            '${subDir.path}/completed.tag',
          ).exists();
          final generatedAt = _parseTimestamp(name);
          final aluItems = await _parseAluFiles(subDir);

          if (aluItems.isNotEmpty) {
            sessions.add(
              LessonSession(
                id: name,
                type: SessionType.captureLesson,
                items: aluItems,
                isPartial: false,
                isSpecific: isSpecificMarker || aluItems.length <= 4,
                isCompleted: isCompleted,
                generatedAt: generatedAt,
              ),
            );
          }
        }
      }
    }

    // Sort sessions in reverse chronological order (newest first)
    sessions.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

    // Clear progress when done
    ref.read(lessonProgressPercentProvider.notifier).update(null);
    ref.read(lessonProgressMessageProvider.notifier).update(null);

    // 3. Get FSRS due words for Quick Review
    final dueWords = await FsrsService.instance.getDueWords();

    return LessonsState(sessions: sessions, dueReviews: dueWords);
  }

  /// Consume the current lesson — mark completed.
  Future<void> markConsumed(String lessonId) async {
    await _channel.invokeMethod('markLessonCompleted', {'lessonId': lessonId});
    await refresh();
  }

  // ── File parsing ─────────────────────────────────────────────────────────

  Future<List<Alu>> _parseAluFiles(Directory dir) async {
    final result = <Alu>[];
    // Ordered list: preview → word cards → dialogues → flashcards → stories → quiz
    final orderedPrefixes = [
      'preview',
      'word_card',
      'dialogue',
      'flashcards',
      'story',
      'quiz',
    ];

    final files = dir.listSync().whereType<File>().toList();

    for (final prefix in orderedPrefixes) {
      final matching =
          files.where((f) => f.uri.pathSegments.last.contains(prefix)).toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in matching) {
        final raw = await file.readAsString();
        final name = file.uri.pathSegments.last;
        final id = name.replaceAll('.json', '');
        final alu = _parse(prefix, raw, id);
        if (alu != null) result.add(alu);
      }
    }

    return result;
  }

  Alu? _parse(String prefix, String raw, String id) {
    switch (prefix) {
      case 'preview':
        return AluParser.parseVocabPreview(raw, captureId: id, id: id);
      case 'word_card':
        return AluParser.parseWordCard(raw, captureId: id, id: id);
      case 'story':
        return AluParser.parseStory(raw, captureId: id, id: id);
      case 'dialogue':
        return AluParser.parseDialogue(raw, captureId: id, id: id);
      case 'flashcards':
        return AluParser.parseFlashcardSet(raw, captureId: id, id: id);
      case 'quiz':
        return AluParser.parseQuizItem(raw, captureId: id, id: id);
      default:
        return null;
    }
  }
}
