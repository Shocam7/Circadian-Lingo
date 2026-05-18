import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../providers/lesson_provider.dart';
import '../theme/lesson_theme.dart';
import '../utils/lesson_flow_utils.dart';
import '../widgets/dialogue_widget.dart';
import '../widgets/flashcard_swiper_widget.dart';
import '../widgets/lesson_progress_header.dart';
import '../widgets/quiz_widget.dart';
import '../widgets/story_widget.dart';
import '../widgets/word_card_widget.dart';
import '../providers/ui_strings_provider.dart';

class LessonFlowScreen extends ConsumerStatefulWidget {
  final LessonSession session;

  const LessonFlowScreen({super.key, required this.session});

  @override
  ConsumerState<LessonFlowScreen> createState() => _LessonFlowScreenState();
}

class _LessonFlowScreenState extends ConsumerState<LessonFlowScreen> {
  late List<Alu> _steps;
  int _index = 0;
  bool _flashcardsDone = false;
  bool _quizAnswered = false;
  late Map<String, WordCardAlu> _wordLookup;

  @override
  void initState() {
    super.initState();
    _steps = buildFlowSteps(widget.session.items);
    _wordLookup = _buildWordLookup(widget.session.items);
  }

  Map<String, WordCardAlu> _buildWordLookup(List<Alu> items) {
    final lookup = <String, WordCardAlu>{};
    for (final item in items) {
      if (item is WordCardAlu) {
        lookup[item.word.toLowerCase()] = item;
      }
    }
    return lookup;
  }

  double get _progress => _steps.isEmpty ? 0 : (_index + 1) / _steps.length;

  void _advance() {
    if (_index < _steps.length - 1) {
      setState(() {
        _index++;
        _flashcardsDone = false;
        _quizAnswered = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  String _headerLabel() {
    final ui = ref.read(uiStringsProvider);
    final alu = _steps[_index];
    final typeCount = countStepsOfType(_steps, alu.runtimeType);
    final typeIndex = indexWithinType(_steps, _index);
    return stepLabel(alu, ui, index: typeIndex, total: typeCount);
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiStringsProvider);
    if (_steps.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lesson')),
        body: const Center(child: Text('No lesson steps available.')),
      );
    }

    final cs = LessonTheme.scheme(isSpecific: widget.session.isSpecific);
    final alu = _steps[_index];
    final canContinue = switch (alu) {
      FlashcardSetAlu() => _flashcardsDone,
      QuizItemAlu() => _quizAnswered,
      _ => true,
    };

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(colorScheme: cs, textTheme: _lessonTextTheme(cs)),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface.withValues(alpha: 0.8),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: cs.primary),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: Text(
            widget.session.isSpecific ? 'Specific Lesson' : 'Daily Lesson',
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: LessonProgressHeader(
                  label: _headerLabel(),
                  progress: _progress,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey(_index),
                      child: _buildStep(context, alu),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: FilledButton(
              onPressed: canContinue ? _advance : null,
              style: FilledButton.styleFrom(
                backgroundColor: cs.secondary,
                foregroundColor: cs.onSecondary,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _index < _steps.length - 1 ? 'Continue' : 'Finish Lesson',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _index < _steps.length - 1
                        ? Icons.arrow_forward
                        : Icons.check,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, Alu alu) {
    if (alu is WordCardAlu) {
      return WordCardWidget(alu: alu, flowMode: true);
    }
    if (alu is DialogueAlu) {
      return DialogueWidget(alu: alu, flowMode: true, wordLookup: _wordLookup);
    }
    if (alu is FlashcardSetAlu) {
      return FlashcardSwiperWidget(
        alu: alu,
        flowMode: true,
        onComplete: () => setState(() => _flashcardsDone = true),
      );
    }
    if (alu is MiniStoryAlu) {
      return StoryWidget(alu: alu, flowMode: true, wordLookup: _wordLookup);
    }
    if (alu is QuizItemAlu) {
      return QuizWidget(
        alu: alu,
        flowMode: true,
        onAnswered: () => setState(() => _quizAnswered = true),
      );
    }
    return const SizedBox.shrink();
  }

  TextTheme _lessonTextTheme(ColorScheme cs) {
    final base = Theme.of(context).textTheme;
    return base.copyWith(
      displayLarge: GoogleFonts.manrope(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: cs.onSurface,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
        height: 1.4,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
        height: 1.55,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: cs.onSurfaceVariant,
        height: 1.5,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: cs.outline,
      ),
    );
  }
}
