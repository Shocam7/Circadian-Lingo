import '../models/alu.dart';
import '../providers/lesson_provider.dart';
import '../providers/ui_strings_provider.dart';

/// Ordered lesson flow: word cards → dialogues → flashcards → stories → quizzes.
List<Alu> buildFlowSteps(List<Alu> items) {
  final result = <Alu>[];
  void addType<T extends Alu>() {
    result.addAll(items.whereType<T>());
  }

  addType<WordCardAlu>();
  addType<DialogueAlu>();
  addType<FlashcardSetAlu>();
  addType<MiniStoryAlu>();
  addType<QuizItemAlu>();
  return result;
}

class LessonTypeCounts {
  final int wordCards;
  final int dialogues;
  final int flashcardSets;
  final int stories;
  final int quizzes;

  const LessonTypeCounts({
    this.wordCards = 0,
    this.dialogues = 0,
    this.flashcardSets = 0,
    this.stories = 0,
    this.quizzes = 0,
  });

  int get flashcardItems => flashcardSets;
  bool get isEmpty =>
      wordCards + dialogues + flashcardSets + stories + quizzes == 0;
}

LessonTypeCounts countLessonTypes(List<Alu> items) {
  var cards = 0;
  var flashcardCount = 0;
  for (final alu in items) {
    if (alu is WordCardAlu) cards++;
    if (alu is FlashcardSetAlu) flashcardCount += alu.cards.length;
  }
  return LessonTypeCounts(
    wordCards: cards,
    dialogues: items.whereType<DialogueAlu>().length,
    flashcardSets: flashcardCount,
    stories: items.whereType<MiniStoryAlu>().length,
    quizzes: items.whereType<QuizItemAlu>().length,
  );
}

String stepLabel(Alu alu, Map<String, String> ui, {int? index, int? total}) {
  final prefix = switch (alu) {
    WordCardAlu() => 'Word Card',
    DialogueAlu() => 'Dialogue',
    FlashcardSetAlu() => 'Flashcards',
    MiniStoryAlu() => 'Story',
    QuizItemAlu() => 'Quiz',
    _ => 'Lesson',
  };
  if (index != null && total != null && total > 1) {
    return '$prefix ${index + 1} of $total';
  }
  return prefix;
}

int countStepsOfType(List<Alu> steps, Type type) {
  if (type == WordCardAlu) return steps.whereType<WordCardAlu>().length;
  if (type == DialogueAlu) return steps.whereType<DialogueAlu>().length;
  if (type == FlashcardSetAlu) return steps.whereType<FlashcardSetAlu>().length;
  if (type == MiniStoryAlu) return steps.whereType<MiniStoryAlu>().length;
  if (type == QuizItemAlu) return steps.whereType<QuizItemAlu>().length;
  return 0;
}

int indexWithinType(List<Alu> steps, int globalIndex) {
  final alu = steps[globalIndex];
  final type = alu.runtimeType;
  var idx = 0;
  for (var i = 0; i <= globalIndex; i++) {
    if (steps[i].runtimeType == type) idx++;
  }
  return idx - 1;
}

LessonTypeCounts countsFor(LessonSession session) =>
    countLessonTypes(session.items);
