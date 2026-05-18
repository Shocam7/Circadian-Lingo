/// Per-word FSRS state record, persisted as JSON.
class WordReviewRecord {
  final String word;    // in target language
  final String meaning; // in native language
  double stability;     // S: how many days memory persists
  double difficulty;    // D: 0.0 (easy) – 1.0 (hard)
  int reviewCount;
  int correctStreak;
  DateTime lastReviewed;
  DateTime nextDue;

  WordReviewRecord({
    required this.word,
    required this.meaning,
    this.stability = 1.0,
    this.difficulty = 0.3,
    this.reviewCount = 0,
    this.correctStreak = 0,
    DateTime? lastReviewed,
    DateTime? nextDue,
  })  : lastReviewed = lastReviewed ?? DateTime.now(),
        nextDue = nextDue ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaning,
        'stability': stability,
        'difficulty': difficulty,
        'reviewCount': reviewCount,
        'correctStreak': correctStreak,
        'lastReviewed': lastReviewed.toIso8601String(),
        'nextDue': nextDue.toIso8601String(),
      };

  factory WordReviewRecord.fromJson(Map<String, dynamic> json) => WordReviewRecord(
        word: json['word'] as String,
        meaning: json['meaning'] as String,
        stability: (json['stability'] as num).toDouble(),
        difficulty: (json['difficulty'] as num).toDouble(),
        reviewCount: json['reviewCount'] as int,
        correctStreak: json['correctStreak'] as int,
        lastReviewed: DateTime.parse(json['lastReviewed'] as String),
        nextDue: DateTime.parse(json['nextDue'] as String),
      );
}
