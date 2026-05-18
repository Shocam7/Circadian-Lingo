import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/audio_pipeline_provider.dart';
import '../providers/daily_captures_provider.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/organic_listening_button.dart';
import '../providers/model_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_strings_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NEW: Clean up stale data on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewDayAndCleanup();
    });
  }

  Future<void> _checkNewDayAndCleanup() async {
    final isNewDay = await ref
        .read(dailyCapturesProvider.notifier)
        .purgeStaleCaptures();
    if (isNewDay && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'A new day has begun. Your ambient context has been reset.',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNewDayAndCleanup(); // Cleanup on resume if it's a new day
      ref.read(dailyCapturesProvider.notifier).syncAll();
      ref.read(userSettingsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiStringsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Ensure dailyCapturesProvider is active so its listener captures done events.
    ref.watch(dailyCapturesProvider);
    final modelStatus = ref.watch(modelProvider);

    // Watch for error state and show a SnackBar (fire-and-forget, guarded by
    // a post-frame callback so we are not calling showSnackBar inside build).
    ref.listen<AsyncValue<AudioPipelineState>>(audioPipelineProvider, (
      _,
      next,
    ) {
      final state = next.asData?.value;
      if (state != null && state.hasError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'An error occurred.'),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        });
      }
    });

    ref.listen<ModelStatus>(modelProvider, (previous, next) {
      if (previous?.statusString != next.statusString) {
        String message = '';
        switch (next.statusString) {
          case 'DOWNLOADED':
            message = 'Using downloaded model (Internal)';
            break;
        }
        if (message.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      }
    });

    return AmbientBackground(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colorScheme.surface, colorScheme.primaryContainer],
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: const GlassAppBar(),
        body: RefreshIndicator(
          color: colorScheme.primary,
          onRefresh: () async {
            // Check for model file, sync captures, and refresh settings
            await ref.read(modelProvider.notifier).checkStatus();
            await ref.read(dailyCapturesProvider.notifier).syncAll();
            await ref.read(userSettingsProvider.notifier).refresh();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(
              left: 24.0,
              right: 24.0,
              top: 48.0,
              bottom: 120.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Greeting
                Text(
                  uiString(ui, 'greeting_title'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  uiString(ui, 'greeting_subtitle'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),

                // ── Model Download Progress ────────────────────────────────────
                if (!modelStatus.isDownloaded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48.0),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.download_for_offline,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Downloading Brain (1.5 GB)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (modelStatus.isDownloading) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: modelStatus.progress,
                                minHeight: 12,
                                backgroundColor:
                                    colorScheme.surfaceContainerHigh,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Please stay connected to Wi-Fi. ${(modelStatus.progress * 100).toInt()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ] else ...[
                            Text(
                              'Gemma-4 is required for local language intelligence. Start download to enable listening.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => ref
                                    .read(modelProvider.notifier)
                                    .startDownload(),
                                icon: const Icon(Icons.cloud_download),
                                label: const Text('Start Download'),
                              ),
                            ),
                          ],
                          if (modelStatus.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Text(
                                modelStatus.error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Core Interaction — fully self-contained (state + callbacks
                // are all handled internally by OrganicListeningButton).
                if (modelStatus.isDownloaded) const OrganicListeningButton(),
                const SizedBox(height: 64),

                // Insights Bento Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      children: [
                        // Card 1
                        SizedBox(
                          width: isWide
                              ? (constraints.maxWidth / 3) - 16
                              : constraints.maxWidth,
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.translate,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'New Patterns',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '12',
                                  style: theme.textTheme.displayLarge?.copyWith(
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Subtly absorbed today.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Card 2
                        SizedBox(
                          width: isWide
                              ? (constraints.maxWidth * 2 / 3) - 8
                              : constraints.maxWidth,
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color:
                                                colorScheme.tertiaryContainer,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.psychology,
                                            color:
                                                colorScheme.onTertiaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Cognitive Ease',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'High',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: 0.85,
                                    minHeight: 16,
                                    backgroundColor:
                                        colorScheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Your environment is optimal for passive retention.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
