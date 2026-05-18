import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/model_provider.dart';
import '../providers/daily_captures_provider.dart';
import '../providers/ui_strings_provider.dart';
import 'searchable_language_selector.dart';

class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiStringsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF3E8FF).withValues(alpha: 0.3),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Stack(
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9999),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32.0,
                            vertical: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            'Circadian Lingo',
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 24, // Adapting to app bar size
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: colorScheme.primary,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.refresh, color: colorScheme.primary),
                          tooltip: uiString(ui, 'sync_tooltip'),
                          onPressed: () async {
                            // Global Sync: Model, Captures, Settings
                            await Future.wait<void>([
                              ref.read(modelProvider.notifier).checkStatus(),
                              ref
                                  .read(dailyCapturesProvider.notifier)
                                  .syncAll(),
                              ref.read(userSettingsProvider.notifier).refresh(),
                            ]);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(uiString(ui, 'sync_complete')),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: colorScheme.primary,
                          ),
                          onPressed: () => _showSettings(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 32);

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SettingsModal(),
    );
  }
}

class _SettingsModal extends ConsumerWidget {
  const _SettingsModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiStringsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settingsAsync = ref.watch(userSettingsProvider);
    final captures = ref.watch(dailyCapturesProvider);

    final screenCount =
        captures.where((c) => c.type == 'screen_context').length;
    final audioCount =
        captures.where((c) => c.type == 'audio_raw' || c.type == 'audio').length;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: settingsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, stack) => Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text('Error: $err')),
        ),
        data: (settings) => SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uiString(ui, 'settings_title'),
                style: theme.textTheme.displayLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
              Text(uiString(ui, 'settings_native_language'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _buildLanguageDropdown(
                context,
                ref,
                settings.nativeLanguage,
                (val) => ref
                    .read(userSettingsProvider.notifier)
                    .setNativeLanguage(val!),
                excludedLanguage: settings.targetLanguage,
              ),
              const SizedBox(height: 16),
              Text(uiString(ui, 'settings_target_language'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _buildLanguageDropdown(
                context,
                ref,
                settings.targetLanguage,
                (val) => ref
                    .read(userSettingsProvider.notifier)
                    .setTargetLanguage(val!),
                excludedLanguage: settings.nativeLanguage,
                showSections: true,
              ),
              const SizedBox(height: 4),
              Text(
                uiString(ui, 'settings_language_disclaimer'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  uiString(ui, 'ui_localize_checkbox'),
                  style: theme.textTheme.labelLarge,
                ),
                value: settings.isUiLocalized,
                onChanged: (enabled) async {
                  await ref.read(uiStringsProvider.notifier).setUiLocalized(
                        context,
                        enabled,
                        nativeLanguageCode: settings.nativeLanguage,
                      );
                },
                activeThumbColor: colorScheme.primary,
              ),
              const Divider(height: 32),
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    uiString(ui, 'settings_auto_gen_title'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  uiString(ui, 'settings_auto_gen_enable'),
                  style: theme.textTheme.labelLarge,
                ),
                subtitle: Text(
                  uiString(ui, 'settings_auto_gen_subtitle'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings.lessonAutoGenerationEnabled,
                onChanged: (enabled) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setLessonAutoGenerationSchedule(
                        enabled,
                        settings.lessonGenerationHour,
                        settings.lessonGenerationMinute,
                      );
                },
                activeThumbColor: colorScheme.primary,
              ),
              if (settings.lessonAutoGenerationEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      uiString(ui, 'settings_scheduled_time'),
                      style: theme.textTheme.labelLarge,
                    ),
                    InkWell(
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: settings.lessonGenerationHour,
                            minute: settings.lessonGenerationMinute,
                          ),
                        );
                        if (picked != null) {
                          ref
                              .read(userSettingsProvider.notifier)
                              .setLessonAutoGenerationSchedule(
                                true,
                                picked.hour,
                                picked.minute,
                              );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: colorScheme.primary, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              TimeOfDay(
                                hour: settings.lessonGenerationHour,
                                minute: settings.lessonGenerationMinute,
                              ).format(context),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: colorScheme.onSurfaceVariant,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            uiString(ui, 'settings_recommendation_title'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        uiString(ui, 'settings_recommendation_body'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    uiString(ui, 'settings_smart_scheduling'),
                    style: theme.textTheme.labelLarge,
                  ),
                  Switch(
                    value: settings.smartContextSchedulingEnabled,
                    onChanged: (val) {
                      ref
                          .read(userSettingsProvider.notifier)
                          .setSmartScheduling(val);
                    },
                    activeThumbColor: colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(uiString(ui, 'settings_context_window'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              RangeSlider(
                values: RangeValues(
                  settings.contextWindowStartHour.toDouble(),
                  settings.contextWindowEndHour.toDouble(),
                ),
                min: 0,
                max: 24,
                divisions: 24,
                activeColor: colorScheme.primary,
                inactiveColor: colorScheme.surfaceContainerHighest,
                labels: RangeLabels(
                  '${settings.contextWindowStartHour}:00',
                  '${settings.contextWindowEndHour}:00',
                ),
                onChanged: (RangeValues values) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setContextWindow(
                        values.start.round(),
                        values.end.round(),
                      );
                },
              ),
              const SizedBox(height: 16),
              Text(
                uiString(ui, 'settings_ambient_duration'),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Slider(
                value: settings.ambientAudioDuration.toDouble(),
                min: 5,
                max: 60,
                divisions: 11, // 5, 10, 15, ..., 60
                activeColor: colorScheme.primary,
                inactiveColor: colorScheme.surfaceContainerHighest,
                label: '${settings.ambientAudioDuration} mins',
                onChanged: (double value) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setAmbientAudioDuration(value.round());
                },
              ),
              const SizedBox(height: 16),
              Text(
                uiString(ui, 'settings_screen_limit'),
                style: theme.textTheme.labelLarge,
              ),
              Slider(
                value: settings.dailyScreenCaptureLimit.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: colorScheme.primary,
                label: '${settings.dailyScreenCaptureLimit}',
                onChanged: (val) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setDailyLimits(
                        val.round(),
                        settings.dailyAudioCaptureLimit,
                      );
                },
              ),
              const SizedBox(height: 8),
              Text(
                uiString(ui, 'settings_audio_limit'),
                style: theme.textTheme.labelLarge,
              ),
              Slider(
                value: settings.dailyAudioCaptureLimit.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: colorScheme.primary,
                label: '${settings.dailyAudioCaptureLimit}',
                onChanged: (val) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setDailyLimits(
                        settings.dailyScreenCaptureLimit,
                        val.round(),
                      );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Visual: $screenCount / ${settings.dailyScreenCaptureLimit}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Audio: $audioCount / ${settings.dailyAudioCaptureLimit}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(uiString(ui, 'cancel_btn')),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        // Persist or just close? 
                        // The current implementation seems to trigger setters immediately.
                        // Assuming setters trigger persistence.
                        Navigator.of(context).pop();
                      },
                      child: Text(uiString(ui, 'save_btn')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageDropdown(
    BuildContext context,
    WidgetRef ref,
    String value,
    ValueChanged<String?> onChanged, {
    List<String>? availableLanguages,
    String? excludedLanguage,
    bool showSections = false,
  }) {
    return SearchableLanguageSelector(
      selectedLanguage: value,
      onChanged: (val) => onChanged(val),
      availableLanguages: availableLanguages,
      excludedLanguage: excludedLanguage,
      showSections: showSections,
    );
  }
}
