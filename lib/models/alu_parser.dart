import 'alu.dart';

/// Defensive parsers for Gemma's pipe-colon output format.
/// Every parser returns null on failure — never throws.
///
/// Wire format:
///   WordCard:      WORD:negotiate|DEF:to discuss to reach agreement|EX:They negotiated.
///   Quiz:          Q:What means to discuss terms?|negotiate,admire,retreat|negotiate|definition text
///   Story:         STORY:Once upon a time...|WORDS:negotiate,admire
///   Dialogue line: A:Hello there.|B:Hi, how are you?|WORDS:hello,hi
///   Flashcard:     FRONT:negotiate|BACK:to discuss terms
///   Preview:       PREVIEW:Today we learn about negotiations and more.
class AluParser {
  // ── Public parsers ────────────────────────────────────────────────────────

  static WordCardAlu? parseWordCard(String raw, {required String captureId, required String id}) {
    try {
      final p = _pipe(raw);
      final word = _get(p, 'WORD');
      final def  = _get(p, 'DEF');
      final ex   = _get(p, 'EX');
      if (word.isEmpty || def.isEmpty) return null;
      return WordCardAlu(id: id, captureId: captureId, word: word, definition: def, example: ex);
    } catch (_) { return null; }
  }

  static QuizItemAlu? parseQuizItem(String raw, {required String captureId, required String id}) {
    try {
      final p = _pipe(raw);
      if (p.length < 3) return null;
      final question = p[0].startsWith('Q:') ? p[0].substring(2).trim() : p[0].trim();
      final options  = p[1].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final answer   = p[2].trim();
      final def      = p.length > 3 ? p[3].trim() : '';
      if (question.isEmpty || options.length < 2 || answer.isEmpty) return null;
      return QuizItemAlu(
        id: id, captureId: captureId,
        question: question, options: options,
        correctAnswer: answer, definition: def,
      );
    } catch (_) { return null; }
  }

  static MiniStoryAlu? parseStory(String raw, {required String captureId, required String id}) {
    try {
      final p = _pipe(raw);
      final story = _get(p, 'STORY');
      final translation = _get(p, 'TRANSLATION');
      if (story.isEmpty) return null;
      final wordsPart = _get(p, 'WORDS');
      final targetWords = <String>[];
      final wordMeanings = <String, String>{};
      final pairs = wordsPart.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      for (final pair in pairs) {
        if (pair.contains(':')) {
          final idx = pair.indexOf(':');
          final w = pair.substring(0, idx).trim();
          final m = pair.substring(idx + 1).trim();
          targetWords.add(w);
          wordMeanings[w.toLowerCase()] = m;
        } else {
          targetWords.add(pair);
        }
      }
      return MiniStoryAlu(
        id: id,
        captureId: captureId,
        story: story,
        translation: translation,
        targetWords: targetWords,
        wordMeanings: wordMeanings,
      );
    } catch (_) { return null; }
  }

  static DialogueAlu? parseDialogue(String raw, {required String captureId, required String id}) {
    try {
      final p = _pipe(raw);
      final lines = <DialogueLine>[];
      var targetWords = <String>[];
      for (final part in p) {
        if (part.startsWith('A:'))      { lines.add(DialogueLine(speaker: 'A', text: part.substring(2).trim())); }
        else if (part.startsWith('B:')) { lines.add(DialogueLine(speaker: 'B', text: part.substring(2).trim())); }
        else if (part.startsWith('WORDS:')) {
          targetWords = part.substring(6).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      }
      if (lines.isEmpty) return null;
      return DialogueAlu(id: id, captureId: captureId, lines: lines, targetWords: targetWords);
    } catch (_) { return null; }
  }

  static FlashcardSetAlu? parseFlashcardSet(String raw, {required String captureId, required String id}) {
    try {
      final cards = raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) {
            final p = _pipe(line);
            final front = _get(p, 'FRONT');
            final back  = _get(p, 'BACK');
            return (front.isNotEmpty && back.isNotEmpty) ? Flashcard(front: front, back: back) : null;
          })
          .whereType<Flashcard>()
          .toList();
      if (cards.isEmpty) return null;
      return FlashcardSetAlu(id: id, captureId: captureId, cards: cards);
    } catch (_) { return null; }
  }

  static VocabPreviewAlu? parseVocabPreview(String raw, {required String captureId, required String id}) {
    try {
      final p = _pipe(raw);
      final preview = _get(p, 'PREVIEW');
      return VocabPreviewAlu(id: id, captureId: captureId, summary: preview.isNotEmpty ? preview : raw.trim());
    } catch (_) { return null; }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<String> _pipe(String raw) => raw.split('|');

  static String _get(List<String> parts, String key) {
    for (final part in parts) {
      if (part.startsWith('$key:')) return part.substring(key.length + 1).trim();
    }
    return '';
  }
}
