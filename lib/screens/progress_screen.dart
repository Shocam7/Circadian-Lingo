import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/learned_words_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_app_bar.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _learnedWordsProvider = FutureProvider.autoDispose<List<LearnedWord>>((
  ref,
) {
  return LearnedWordsService.instance.getAllWords();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wordsAsync = ref.watch(_learnedWordsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: const GlassAppBar(),
        body: wordsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (words) {
            final filtered = _query.isEmpty
                ? words
                : words
                      .where(
                        (w) =>
                            w.word.toLowerCase().contains(
                              _query.toLowerCase(),
                            ) ||
                            w.meaning.toLowerCase().contains(
                              _query.toLowerCase(),
                            ),
                      )
                      .toList();

            return CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Progress',
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CountBadge(count: words.length, cs: cs, theme: theme),
                        const SizedBox(height: 24),
                        _SearchBar(
                          controller: _searchController,
                          onChanged: (q) => setState(() => _query = q),
                          cs: cs,
                          theme: theme,
                        ),
                        const SizedBox(height: 24),
                        if (words.isEmpty)
                          _EmptyState(cs: cs, theme: theme)
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Center(
                              child: Text(
                                'No words match "$_query"',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ── Table header ─────────────────────────────────────────────
                if (filtered.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _TableHeader(cs: cs, theme: theme),
                    ),
                  ),

                // ── Word rows ─────────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _WordRow(
                        word: filtered[i],
                        theme: theme,
                        cs: cs,
                        isEven: i.isEven,
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final ColorScheme cs;
  final ThemeData theme;
  const _CountBadge({
    required this.count,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [cs.primaryContainer, cs.secondaryContainer],
      ),
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
    ),
    child: RichText(
      text: TextSpan(
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.onPrimaryContainer,
        ),
        children: [
          TextSpan(text: 'You have learned '),
          TextSpan(
            text: '$count',
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: count == 1 ? ' word' : ' words'),
        ],
      ),
    ),
  );
}

class _SearchBar extends ConsumerWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ColorScheme cs;
  final ThemeData theme;
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: 'Search words or meanings…',
      hintStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
      ),
      prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
      suffixIcon: controller.text.isNotEmpty
          ? IconButton(
              icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            )
          : null,
      filled: true,
      fillColor: cs.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  const _TableHeader({required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            'Word',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            'Meaning',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          'Learned',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _WordRow extends StatelessWidget {
  final LearnedWord word;
  final ThemeData theme;
  final ColorScheme cs;
  final bool isEven;
  const _WordRow({
    required this.word,
    required this.theme,
    required this.cs,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: isEven
          ? cs.surfaceContainerLow.withValues(alpha: 0.5)
          : Colors.transparent,
      border: Border(
        bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            word.word,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            word.meaning,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          _formatDate(word.learnedAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    return '${dt.day}/${dt.month}';
  }
}

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  const _EmptyState({required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.school_outlined,
            size: 40,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No words learned yet',
          style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Complete lessons and flashcards to build your word list.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
