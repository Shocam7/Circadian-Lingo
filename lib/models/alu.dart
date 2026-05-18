// Atomic Lesson Units — the smallest independently useful pieces of lesson content.
// Format produced by GemmaManager.generateLesson() and parsed by AluParser.

abstract class Alu {
  final String id;
  final String captureId;
  const Alu({required this.id, required this.captureId});
}

// ── ALU types ────────────────────────────────────────────────────────────────

class VocabPreviewAlu extends Alu {
  final String summary;
  const VocabPreviewAlu({
    required super.id,
    required super.captureId,
    required this.summary,
  });
}

class WordCardAlu extends Alu {
  final String word;
  final String definition;
  final String example;
  const WordCardAlu({
    required super.id,
    required super.captureId,
    required this.word,
    required this.definition,
    required this.example,
  });
}

class DialogueLine {
  final String speaker; // 'A' or 'B'
  final String text;
  const DialogueLine({required this.speaker, required this.text});
}

class MiniStoryAlu extends Alu {
  final String story;
  final String translation;
  final List<String> targetWords;
  final Map<String, String> wordMeanings;
  const MiniStoryAlu({
    required super.id,
    required super.captureId,
    required this.story,
    required this.translation,
    required this.targetWords,
    this.wordMeanings = const {},
  });
}

class DialogueAlu extends Alu {
  final List<DialogueLine> lines;
  final List<String> targetWords;
  const DialogueAlu({
    required super.id,
    required super.captureId,
    required this.lines,
    required this.targetWords,
  });
}

class Flashcard {
  final String front; // word in target language
  final String back;  // meaning in native language
  const Flashcard({required this.front, required this.back});
}

class FlashcardSetAlu extends Alu {
  final List<Flashcard> cards;
  const FlashcardSetAlu({
    required super.id,
    required super.captureId,
    required this.cards,
  });
}

class QuizItemAlu extends Alu {
  final String question;
  final List<String> options; // exactly 3
  final String correctAnswer;
  final String definition;    // shown after answer regardless of result
  const QuizItemAlu({
    required super.id,
    required super.captureId,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.definition,
  });
}
