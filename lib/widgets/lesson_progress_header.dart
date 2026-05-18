import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LessonProgressHeader extends StatelessWidget {
  final String label;
  final String? trailing;
  final double progress;

  const LessonProgressHeader({
    super.key,
    required this.label,
    this.trailing,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (progress.clamp(0.0, 1.0) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.primary,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              trailing ?? '$pct% Complete',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: cs.surfaceContainer,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}
