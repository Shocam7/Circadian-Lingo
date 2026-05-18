import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../theme/lesson_theme.dart';
import 'word_bottom_sheet.dart';

class StoryWidget extends StatefulWidget {
  final MiniStoryAlu alu;
  final Map<String, WordCardAlu>? wordLookup;
  final bool flowMode;

  const StoryWidget({
    super.key,
    required this.alu,
    this.wordLookup,
    this.flowMode = false,
  });

  @override
  State<StoryWidget> createState() => _StoryWidgetState();
}

class _StoryWidgetState extends State<StoryWidget> {
  bool _showTranslation = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!widget.flowMode) {
      return _compactStory(theme, cs);
    }

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.surfaceContainerLow),
        boxShadow: [LessonTheme.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mini Story',
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'READING PRACTICE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showTranslation = !_showTranslation),
                icon: Icon(
                  Icons.translate,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                label: Text(
                  _showTranslation ? 'Hide' : 'Translate',
                  style: GoogleFonts.jetBrainsMono(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: cs.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRichText(context, cs),
          if (_showTranslation && widget.alu.translation.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.secondary.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                widget.alu.translation,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  height: 1.6,
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (widget.alu.targetWords.isNotEmpty) ...[
            const SizedBox(height: 28),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'KEY VOCABULARY',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 1,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.alu.targetWords.map((w) {
                return Material(
                  color: cs.secondary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () {
                      final clean = w.toLowerCase();
                      final lookup = widget.wordLookup?[clean];
                      final localMeaning = widget.alu.wordMeanings[clean];
                      WordBottomSheet.show(
                        context,
                        word: w,
                        definition: localMeaning ?? lookup?.definition,
                        example: lookup?.example,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            w,
                            style: GoogleFonts.manrope(
                              color: cs.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactStory(ThemeData theme, ColorScheme cs) {
    return Container(
      width: double.infinity,
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
              Icon(Icons.auto_stories, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Mini Story',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRichText(context, cs),
        ],
      ),
    );
  }

  Widget _buildRichText(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);
    final words = widget.alu.story.split(' ');
    final targetSet = widget.alu.targetWords
        .map((w) => w.toLowerCase())
        .where((w) =>
            widget.alu.wordMeanings.containsKey(w) ||
            widget.wordLookup == null ||
            widget.wordLookup!.containsKey(w))
        .toSet();
    final spans = <InlineSpan>[];

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^\w]'), '').toLowerCase();
      if (targetSet.contains(clean)) {
        spans.add(
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                final lookup = widget.wordLookup?[clean];
                final localMeaning = widget.alu.wordMeanings[clean];
                WordBottomSheet.show(
                  context,
                  word: clean,
                  definition: localMeaning ?? lookup?.definition,
                  example: lookup?.example,
                );
              },
              child: Text(
                '$word ',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  color: cs.secondary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: cs.secondary.withValues(alpha: 0.3),
                  height: 1.6,
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
              fontSize: 18,
              color: cs.onSurface,
              height: 1.6,
            ),
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(
        children: spans,
        style: theme.textTheme.bodyLarge,
      ),
    );
  }
}
