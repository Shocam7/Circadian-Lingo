import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word_review_record.dart';
import 'learned_words_service.dart';

/// FSRS spaced-repetition scheduler (Ye 2022).
/// Pure Dart, no AI, no network. Persisted to SharedPreferences.
///
/// Core model per word:
///   S (stability)      — days until retrievability drops to the target
///   D (difficulty)     — 0.0 easy … 1.0 hard
///   R (retrievability) — exp(-elapsed / S), probability of recall right now
class FsrsService {
  static const _prefsKey = 'fsrs_word_records';
  static const _retrievabilityTarget = 0.9;
  static const _knownThreshold = 0.9;
  static const _knownStreakRequired = 1;

  FsrsService._();
  static final FsrsService instance = FsrsService._();

  Map<String, WordReviewRecord> _records = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _records = map.map(
          (k, v) => MapEntry(k, WordReviewRecord.fromJson(v as Map<String, dynamic>)));
    }
    _loaded = true;
  }

  /// Ensure a word is tracked. Call before first review.
  Future<void> ensureWord(String word, String meaning) async {
    await _ensureLoaded();
    final key = word.trim().toLowerCase();
    if (!_records.containsKey(key)) {
      _records[key] = WordReviewRecord(word: word.trim(), meaning: meaning.trim());
      await _persist();
    }
  }

  /// Record a review outcome and update S, D, nextDue.
  Future<void> recordReview(String word, String meaning, bool correct) async {
    await _ensureLoaded();
    final key = word.trim().toLowerCase();
    final rec = _records[key] ?? WordReviewRecord(word: word.trim(), meaning: meaning.trim());

    final elapsed = DateTime.now().difference(rec.lastReviewed).inMinutes / 1440.0;
    final r = _retrievability(elapsed, rec.stability);

    if (correct) {
      rec.stability = _stabilityAfterCorrect(rec.stability, r, rec.difficulty);
      rec.difficulty = math.max(0.0, rec.difficulty - 0.05);
      rec.correctStreak += 1;
    } else {
      rec.stability = math.max(0.5, rec.stability * 0.5);
      rec.difficulty = math.min(1.0, rec.difficulty + 0.1);
      rec.correctStreak = 0;
    }

    rec.reviewCount += 1;
    rec.lastReviewed = DateTime.now();
    final intervalHours = (_nextIntervalDays(rec.stability) * 24).round();
    rec.nextDue = DateTime.now().add(Duration(hours: intervalHours));

    _records[key] = rec;

    // Promote to learned words store if mastered
    if (correct && rec.correctStreak >= _knownStreakRequired && _retrievability(0, rec.stability) >= _knownThreshold) {
      await LearnedWordsService.instance.addWord(rec.word, rec.meaning);
    }

    await _persist();
  }

  /// Words whose nextDue is in the past, sorted by most overdue first.
  Future<List<WordReviewRecord>> getDueWords() async {
    await _ensureLoaded();
    final now = DateTime.now();
    return _records.values
        .where((r) => r.nextDue.isBefore(now))
        .toList()
      ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
  }

  /// True if the word passes the mastery threshold.
  Future<bool> isKnown(String word) async {
    await _ensureLoaded();
    final rec = _records[word.trim().toLowerCase()];
    if (rec == null) return false;
    final elapsed = DateTime.now().difference(rec.lastReviewed).inMinutes / 1440.0;
    return _retrievability(elapsed, rec.stability) >= _knownThreshold &&
        rec.correctStreak >= _knownStreakRequired;
  }

  // ── FSRS maths ──────────────────────────────────────────────────────────

  /// Retrievability: R(t, S) = exp(-t / S)
  double _retrievability(double elapsedDays, double s) =>
      s > 0 ? math.exp(-elapsedDays / s) : 0.0;

  /// S after a correct review (simplified FSRS-4 update rule).
  double _stabilityAfterCorrect(double s, double r, double d) =>
      s * (1.0 + 0.9 * math.pow(1.0 - r, 0.1 * (11.0 - 10.0 * d)));

  /// Next interval in days so R drops to [_retrievabilityTarget].
  double _nextIntervalDays(double s) =>
      s * math.log(_retrievabilityTarget) / math.log(0.9);

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey,
        jsonEncode({for (final e in _records.entries) e.key: e.value.toJson()}));
  }
}
