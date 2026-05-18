import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/lesson_provider.dart';
import '../providers/ui_strings_provider.dart';
import '../theme/lesson_theme.dart';
import '../utils/lesson_flow_utils.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_app_bar.dart';
import 'lesson_flow_screen.dart';


class DailyLessonScreen extends ConsumerStatefulWidget {
  const DailyLessonScreen({super.key});

  @override
  ConsumerState<DailyLessonScreen> createState() => _DailyLessonScreenState();
}

class _DailyLessonScreenState extends ConsumerState<DailyLessonScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(lessonProvider);
    final theme = Theme.of(context);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: const GlassAppBar(),
        body: RefreshIndicator(
          color: theme.colorScheme.primary,
          onRefresh: () => ref.read(lessonProvider.notifier).refresh(),
          child: session.when(
            loading: () {
              final progressMsg = ref.watch(lessonProgressMessageProvider);
              final progressPct = ref.watch(lessonProgressPercentProvider);
              final counts = ref.watch(lessonProgressCountsProvider);
              final isSpecific = ref.watch(lessonGenerationIsSpecificProvider);
              return _LoadingView(
                message: progressMsg,
                percent: progressPct,
                counts: counts,
                isSpecific: isSpecific,
              );
            },
            error: (e, _) => _ErrorView(
              error: e,
              onRetry: () => ref.read(lessonProvider.notifier).refresh(),
            ),
            data: (s) => s.hasContent
                ? _LessonsHub(lessonsState: s)
                : _EmptyView(),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends ConsumerWidget {
  final String? message;
  final double? percent;
  final LessonProgressCounts? counts;
  final bool isSpecific;

  const _LoadingView({
    this.message,
    this.percent,
    this.counts,
    this.isSpecific = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = LessonTheme.scheme(isSpecific: isSpecific);
    final theme = Theme.of(context);
    final accent = cs.primary;
    final gradient = isSpecific
        ? LessonTheme.specificCardGradient()
        : LessonTheme.dailyCardGradient();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 120),
      children: [
        Center(
          child: Column(
            children: [
              Text(
                'COGNITIVE ASSEMBLY',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: accent,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Forging your curriculum…',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withValues(alpha: 0.2),
            ),
            boxShadow: [LessonTheme.cardShadow],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isSpecific ? Icons.camera_enhance : Icons.wb_sunny,
                    color: accent,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isSpecific ? 'Specific Capture Lesson' : 'Daily Lesson',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white38)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (percent != null) ...[
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: percent!),
                  builder: (context, value, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            backgroundColor: accent.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${(value * 100).toInt()}% Synthesized',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => ref.read(lessonProvider.notifier).cancelGeneration(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'CANCEL',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              message ?? 'Processing…',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              Divider(color: accent.withValues(alpha: 0.25)),
              const SizedBox(height: 24),
              if (counts != null)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _ModuleLoadingChip(
                      icon: Icons.view_carousel,
                      current: counts!.current['word_card'] ?? 0,
                      target: counts!.target['word_card'] ?? 0,
                      label: 'Word Card',
                      accent: accent,
                      onSurfaceVariant: cs.onSurfaceVariant,
                    ),
                    _ModuleLoadingChip(
                      icon: Icons.forum_outlined,
                      current: counts!.current['dialogue'] ?? 0,
                      target: counts!.target['dialogue'] ?? 0,
                      label: 'Dialogue',
                      accent: accent,
                      onSurfaceVariant: cs.onSurfaceVariant,
                    ),
                    _ModuleLoadingChip(
                      icon: Icons.style_outlined,
                      current: counts!.current['flashcards'] ?? 0,
                      target: counts!.target['flashcards'] ?? 0,
                      label: 'Flashcard',
                      accent: accent,
                      onSurfaceVariant: cs.onSurfaceVariant,
                    ),
                    _ModuleLoadingChip(
                      icon: Icons.auto_stories,
                      current: counts!.current['story'] ?? 0,
                      target: counts!.target['story'] ?? 0,
                      label: 'Story',
                      accent: accent,
                      onSurfaceVariant: cs.onSurfaceVariant,
                    ),
                    _ModuleLoadingChip(
                      icon: Icons.quiz_outlined,
                      current: counts!.current['quiz'] ?? 0,
                      target: counts!.target['quiz'] ?? 0,
                      label: 'Quiz',
                      accent: accent,
                      onSurfaceVariant: cs.onSurfaceVariant,
                    ),
                  ],
                )
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModuleLoadingChip extends StatelessWidget {
  final IconData icon;
  final int current;
  final int target;
  final String label;
  final Color accent;
  final Color onSurfaceVariant;

  const _ModuleLoadingChip({
    required this.icon,
    required this.current,
    required this.target,
    required this.label,
    required this.accent,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    final completed = target > 0 && current >= target;
    return Container(
      width: (MediaQuery.sizeOf(context).width - 88) / 2,
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [LessonTheme.cardShadow],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: completed ? Colors.green : accent.withValues(alpha: 0.6),
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            '$current/$target ${label}s',
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: completed ? Colors.green : onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 120),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: cs.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load lesson',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiStringsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 32, 32, bottomInset + 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.secondaryContainer],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.nights_stay_outlined,
                    size: 48,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  uiString(ui, 'no_lesson_yet'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  uiString(ui, 'empty_lesson_hint'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LessonsHub extends ConsumerWidget {
  final LessonsState lessonsState;

  const _LessonsHub({required this.lessonsState});

  Future<void> _openFlow(BuildContext context, WidgetRef ref, LessonSession session) async {
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonFlowScreen(session: session),
      ),
    );
    if (finished == true && context.mounted) {
      await ref.read(lessonProvider.notifier).markConsumed(session.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 120),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'CONTINUE JOURNEY',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: LessonTheme.dailyPrimary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Refine your cognitive pace',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: LessonTheme.scheme(isSpecific: false).onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your personalized curriculum is ready for today\'s cycle.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 16,
              color: LessonTheme.scheme(isSpecific: false).onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ...lessonsState.sessions.map((session) {
            final counts = countsFor(session);
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: _LessonHubCard(
                session: session,
                counts: counts,
                onStart: () => _openFlow(context, ref, session),
              ),
            );
          }),
          if (lessonsState.dueReviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReviewSection(count: lessonsState.dueReviews.length),
          ],
        ],
      ),
    );
  }
}

class _LessonHubCard extends ConsumerWidget {
  final LessonSession session;
  final LessonTypeCounts counts;
  final VoidCallback? onStart;

  const _LessonHubCard({
    required this.session,
    required this.counts,
    this.onStart,
  });

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSpecific = session.isSpecific;
    final isCompleted = session.isCompleted;
    final cs = LessonTheme.scheme(isSpecific: isSpecific);

    final accent = cs.primary;
    final gradient = isSpecific
        ? LessonTheme.specificCardGradient()
        : LessonTheme.dailyCardGradient();

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (isSpecific
                  ? LessonTheme.accentSecondaryFixed
                  : LessonTheme.dailyPrimaryFixed)
              .withValues(alpha: 0.2),
        ),
        boxShadow: [LessonTheme.cardShadow],
      ),
      padding: const EdgeInsets.all(28),
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
                    Row(
                      children: [
                        Icon(
                          isSpecific ? Icons.camera_enhance : Icons.wb_sunny,
                          color: accent,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isSpecific ? 'Specific Capture' : 'Daily Lesson',
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Generated at ${_formatTime(session.generatedAt)}',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Completed',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Available',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: accent.withValues(alpha: 0.25)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ModuleChip(
                icon: Icons.view_carousel,
                label: _countLabel(counts.wordCards, 'Word Card'),
                accent: accent,
              ),
              _ModuleChip(
                icon: Icons.forum_outlined,
                label: _countLabel(counts.dialogues, 'Dialogue'),
                accent: accent,
              ),
              _ModuleChip(
                icon: Icons.style_outlined,
                label: _countLabel(counts.flashcardSets, 'Flashcard'),
                accent: accent,
              ),
              _ModuleChip(
                icon: Icons.auto_stories,
                label: _countLabel(counts.stories, 'Story'),
                accent: accent,
              ),
              _ModuleChip(
                icon: Icons.quiz_outlined,
                label: _countLabel(counts.quizzes, 'Quiz'),
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: accent.withValues(alpha: 0.25)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: isCompleted ? Colors.white.withValues(alpha: 0.15) : accent,
              foregroundColor: isCompleted ? cs.onSurface : cs.onPrimary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isCompleted
                    ? BorderSide(color: cs.onSurface.withValues(alpha: 0.2))
                    : BorderSide.none,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isCompleted
                      ? (isSpecific ? 'Replay Deep Dive' : 'Replay Session')
                      : (isSpecific ? 'Deep Dive' : 'Start Session'),
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(isCompleted ? Icons.replay : (isSpecific ? Icons.layers : Icons.arrow_forward)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(int n, String singular) {
    if (n == 0) return '0 ${singular}s';
    final plural = n == 1 ? singular : '${singular}s';
    return '$n $plural';
  }
}

class _ModuleChip extends ConsumerWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _ModuleChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: (MediaQuery.sizeOf(context).width - 88) / 2,
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        boxShadow: [LessonTheme.cardShadow],
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: LessonTheme.scheme(isSpecific: false).onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartialBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your full lesson is still being prepared. Here\'s what\'s ready so far.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final int count;

  const _ReviewSection({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.replay, color: cs.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          '$count words due for review',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
