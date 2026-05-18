import 'package:flutter/material.dart';

/// Bottom sheet shown when a user taps a target word in a story or dialogue.
class WordBottomSheet {
  static void show(BuildContext context, {required String word, String? definition, String? example}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WordSheet(word: word, definition: definition, example: example),
    );
  }
}

class _WordSheet extends StatelessWidget {
  final String word;
  final String? definition;
  final String? example;
  const _WordSheet({required this.word, this.definition, this.example});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(word,
              style: theme.textTheme.displaySmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 16),
          if (definition != null) ...[
            Text('Meaning', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(definition!, style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface, height: 1.5)),
            const SizedBox(height: 16),
          ],
          if (example != null) ...[
            Text('Example', style: theme.textTheme.labelMedium?.copyWith(color: cs.secondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: cs.secondary, width: 3)),
              ),
              child: Text(example!, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
