import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A word the user has mastered, stored in target + native language pair.
class LearnedWord {
  final String word;    // target language
  final String meaning; // native language
  final DateTime learnedAt;

  const LearnedWord({
    required this.word,
    required this.meaning,
    required this.learnedAt,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
        'learnedAt': learnedAt.toIso8601String(),
      };

  factory LearnedWord.fromJson(Map<String, dynamic> json) => LearnedWord(
        word: json['word'] as String,
        meaning: json['meaning'] as String,
        learnedAt: DateTime.parse(json['learnedAt'] as String),
      );
}

/// Singleton service: personal learned-words store.
/// Starts empty on day 1. Grows as the user masters words via FSRS.
/// Used for: (1) progress screen, (2) prompt injection ("do not teach these").
class LearnedWordsService {
  static const _prefsKey = 'learned_words_store';
  static const _promptLimit = 100;

  LearnedWordsService._();
  static final LearnedWordsService instance = LearnedWordsService._();

  List<LearnedWord> _cache = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _cache = list.map((e) => LearnedWord.fromJson(e as Map<String, dynamic>)).toList();
    }
    _loaded = true;
  }

  /// Add a newly mastered word. Silently skips duplicates (case-insensitive).
  Future<void> addWord(String word, String meaning) async {
    await _ensureLoaded();
    final normalised = word.trim().toLowerCase();
    if (_cache.any((w) => w.word.toLowerCase() == normalised)) return;
    _cache.add(LearnedWord(word: word.trim(), meaning: meaning.trim(), learnedAt: DateTime.now()));
    await _persist();
  }

  /// Full list for the progress screen.
  Future<List<LearnedWord>> getAllWords() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  }

  /// Last [_promptLimit] target-language word strings for prompt injection.
  Future<List<String>> getForPrompt() async {
    await _ensureLoaded();
    final slice = _cache.length > _promptLimit
        ? _cache.sublist(_cache.length - _promptLimit)
        : _cache;
    return slice.map((w) => w.word).toList();
  }

  Future<int> getTotalCount() async {
    await _ensureLoaded();
    return _cache.length;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_cache.map((w) => w.toJson()).toList()));
  }
}
