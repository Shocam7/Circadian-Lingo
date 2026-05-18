import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../theme/lesson_theme.dart';
import 'word_bottom_sheet.dart';

class DialogueWidget extends ConsumerWidget {
  final DialogueAlu alu;
  final Map<String, WordCardAlu>? wordLookup;
  final bool flowMode;

  const DialogueWidget({
    super.key,
    required this.alu,
    this.wordLookup,
    this.flowMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final targetSet = alu.targetWords
        .map((w) => w.toLowerCase())
        .where((w) => wordLookup == null || wordLookup!.containsKey(w))
        .toSet();

    if (!flowMode) {
      return _compactDialogue(context, theme, cs, targetSet);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
            boxShadow: [LessonTheme.cardShadow],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: LessonTheme.dailyPrimaryFixed,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.forum, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dialogue',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'PRACTICE CONVERSATION',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ...alu.lines.map(
          (line) => _FlowBubble(
            line: line,
            targetSet: targetSet,
            wordLookup: wordLookup,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _compactDialogue(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    Set<String> targetSet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Dialogue',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...alu.lines.map((line) {
          final isA = line.speaker == 'A';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: isA
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isA) _Avatar(label: 'A', cs: cs),
                if (isA) const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isA
                          ? cs.surfaceContainerLowest
                          : cs.primaryContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isA ? 4 : 16),
                        bottomRight: Radius.circular(isA ? 16 : 4),
                      ),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: _buildBubbleText(context, line.text, targetSet),
                  ),
                ),
                if (!isA) const SizedBox(width: 8),
                if (!isA) _Avatar(label: 'B', cs: cs),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBubbleText(
    BuildContext context,
    String text,
    Set<String> targetSet,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final words = text.split(' ');
    final spans = <InlineSpan>[];

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
      if (targetSet.contains(clean)) {
        spans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                final lookup = wordLookup?[clean];
                WordBottomSheet.show(
                  context,
                  word: clean,
                  definition: lookup?.definition,
                  example: lookup?.example,
                );
              },
              child: Text(
                '$word ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.secondary,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: '$word ',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: spans));
  }
}

class _FlowBubble extends StatelessWidget {
  final DialogueLine line;
  final Set<String> targetSet;
  final Map<String, WordCardAlu>? wordLookup;

  const _FlowBubble({
    required this.line,
    required this.targetSet,
    this.wordLookup,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isA = line.speaker == 'A';
    final speaker = isA ? 'Alex' : 'Maria';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isA
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (isA) ...[
            _SpeakerAvatar(label: line.speaker, cs: cs, isA: true),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isA
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: isA ? 8 : 0,
                    right: isA ? 0 : 8,
                    bottom: 4,
                  ),
                  child: Text(
                    speaker,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isA
                        ? cs.surfaceContainerLowest
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isA ? 4 : 16),
                      bottomRight: Radius.circular(isA ? 16 : 4),
                    ),
                    border: isA
                        ? Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          )
                        : null,
                    boxShadow: isA
                        ? [LessonTheme.cardShadow]
                        : [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: _BubbleText(
                    text: line.text,
                    targetSet: targetSet,
                    wordLookup: wordLookup,
                  ),
                ),
              ],
            ),
          ),
          if (!isA) ...[
            const SizedBox(width: 10),
            _SpeakerAvatar(label: line.speaker, cs: cs, isA: false),
          ],
        ],
      ),
    );
  }
}

class _BubbleText extends StatelessWidget {
  final String text;
  final Set<String> targetSet;
  final Map<String, WordCardAlu>? wordLookup;

  const _BubbleText({
    required this.text,
    required this.targetSet,
    this.wordLookup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final words = text.split(' ');
    final spans = <InlineSpan>[];

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
      if (targetSet.contains(clean)) {
        spans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                final lookup = wordLookup?[clean];
                WordBottomSheet.show(
                  context,
                  word: clean,
                  definition: lookup?.definition,
                  example: lookup?.example,
                );
              },
              child: Text(
                '$word ',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  color: cs.secondary,
                ),
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: '$word ',
            style: GoogleFonts.manrope(
              fontSize: 16,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: spans));
  }
}

class _SpeakerAvatar extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  final bool isA;

  const _SpeakerAvatar({
    required this.label,
    required this.cs,
    required this.isA,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: isA
          ? LessonTheme.accentSecondaryFixed
          : LessonTheme.dailyPrimaryFixed,
      child: Text(
        label,
        style: TextStyle(
          color: isA ? cs.secondary : cs.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _Avatar({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 14,
    backgroundColor: cs.primary,
    child: Text(
      label,
      style: TextStyle(
        color: cs.onPrimary,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
