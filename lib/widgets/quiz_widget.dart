import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../services/fsrs_service.dart';
import '../theme/lesson_theme.dart';

class QuizWidget extends StatefulWidget {
  final QuizItemAlu alu;
  final bool flowMode;
  final VoidCallback? onAnswered;

  const QuizWidget({
    super.key,
    required this.alu,
    this.flowMode = false,
    this.onAnswered,
  });

  @override
  State<QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<QuizWidget> {
  String? _selected;
  bool get _answered => _selected != null;

  Future<void> _onTap(String option) async {
    if (_answered) return;
    setState(() => _selected = option);
    final correct = option == widget.alu.correctAnswer;
    await FsrsService.instance.recordReview(
      widget.alu.correctAnswer,
      widget.alu.definition,
      correct,
    );
    widget.onAnswered?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!widget.flowMode) {
      return _compactQuiz(theme, cs);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.surfaceContainerHigh),
            boxShadow: [LessonTheme.cardShadow],
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: LessonTheme.dailyPrimaryFixed,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.translate, color: cs.primary, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'CONTEXTUAL SCENARIO',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: cs.outline,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.alu.question,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...widget.alu.options.asMap().entries.map((entry) {
          final letter = String.fromCharCode(65 + entry.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FlowOption(
              letter: letter,
              option: entry.value,
              selected: _selected == entry.value,
              correct: widget.alu.correctAnswer,
              answered: _answered,
              onTap: () => _onTap(entry.value),
            ),
          );
        }),
        if (_answered && widget.alu.definition.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: cs.secondary, width: 3)),
            ),
            child: Text(
              widget.alu.definition,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _compactQuiz(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Quick Quiz',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.alu.question,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ...widget.alu.options.map(
            (option) => _OptionButton(
              option: option,
              selected: _selected == option,
              correct: widget.alu.correctAnswer,
              answered: _answered,
              onTap: () => _onTap(option),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowOption extends StatelessWidget {
  final String letter;
  final String option;
  final bool selected;
  final String correct;
  final bool answered;
  final VoidCallback onTap;

  const _FlowOption({
    required this.letter,
    required this.option,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color? bg = cs.surfaceContainerLowest;
    Color border = Colors.transparent;

    if (answered) {
      if (option == correct) {
        bg = Colors.green.withValues(alpha: 0.12);
        border = Colors.green;
      } else if (selected) {
        bg = cs.error.withValues(alpha: 0.1);
        border = cs.error;
      }
    } else if (selected) {
      border = cs.primary;
      bg = cs.primary.withValues(alpha: 0.08);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: answered ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 2),
            boxShadow: [LessonTheme.cardShadow],
          ),
          child: Row(
            children: [
              Text(
                letter,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: cs.outline,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  option,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (answered && option == correct)
                Icon(Icons.check_circle, color: cs.primary, size: 22)
              else if (answered && selected)
                Icon(Icons.cancel, color: cs.error, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String option;
  final bool selected;
  final String correct;
  final bool answered;
  final VoidCallback onTap;

  const _OptionButton({
    required this.option,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color? bg;
    Color? border;

    if (answered) {
      if (option == correct) {
        bg = Colors.green.withValues(alpha: 0.15);
        border = Colors.green;
      } else if (selected) {
        bg = cs.error.withValues(alpha: 0.12);
        border = cs.error;
      } else {
        bg = cs.surfaceContainerHighest.withValues(alpha: 0.4);
        border = cs.outlineVariant.withValues(alpha: 0.3);
      }
    } else {
      bg = selected ? cs.primaryContainer : cs.surfaceContainerHigh;
      border = selected ? cs.primary : cs.outlineVariant;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (answered && option == correct)
                const Icon(Icons.check_circle, color: Colors.green, size: 20)
              else if (answered && selected)
                Icon(Icons.cancel, color: cs.error, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
