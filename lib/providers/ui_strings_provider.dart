import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/language_names.dart';
import 'settings_provider.dart';

/// Default English UI dictionary — source of truth for translation input.
const Map<String, String> kDefaultEnglishUiStrings = {
  'sync_complete': 'Synchronization complete',
  'settings_title': 'Settings',
  'settings_native_language': 'My Native Language',
  'settings_target_language': 'I want to master...',
  'settings_language_disclaimer':
      'We can support 99 languages with exact contextual accuracy in the major languages. ',
  'settings_smart_scheduling': 'Smart Context Scheduling',
  'settings_context_window': 'Context Time Window',
  'settings_ambient_duration': 'Ambient Capture Duration',
  'settings_screen_limit': 'Daily Screen Capture Limit',
  'settings_audio_limit': 'Daily Audio Capture Limit',
  'cancel_btn': 'Cancel',
  'save_btn': 'Save',
  'sync_tooltip': 'Sync and Reload',
  'new_day_reset': 'A new day has begun. Your ambient context has been reset.',
  'error_occurred': 'An error occurred.',
  'using_downloaded_model': 'Using downloaded model (Internal)',
  'downloading_brain': 'Downloading Brain (1.5 GB)',
  'gemma_requirement':
      'Gemma-4 is required for local language intelligence. Start download to enable listening.',
  'start_download_btn': 'Start Download',
  'new_patterns_title': 'New Patterns',
  'subtly_absorbed': 'Subtly absorbed today.',
  'cognitive_ease_title': 'Cognitive Ease',
  'cognitive_ease_high': 'High',
  'optimal_environment': 'Your environment is optimal for passive retention.',
  'auth_reason': 'Please authenticate to view your raw captures',
  'onboarding_title_1': 'The Brain',
  'onboarding_title_2': 'Identity',
  'onboarding_title_3': 'Power Up',
  'onboarding_subtitle_1': 'Downloading your personal AI companion',
  'onboarding_subtitle_2': 'Tell us about your language journey',
  'onboarding_subtitle_3': 'Granting necessary permissions',
  'back_btn': 'Back',
  'continue_btn': 'Continue',
  'get_started_btn': 'Get Started',
  'gemma_ready': 'Gemma 2B is ready',
  'awakening_gemma': 'Awakening Gemma...',
  'local_ai_init': 'Local AI initialization',
  'download_model_btn': 'Download Model (1.5 GB)',
  'native_language_title': 'Native Language',
  'target_language_title': 'Target Language',
  'mic_permission_title': 'Microphone',
  'mic_permission_subtitle': 'For ambient listening & lessons',
  'notif_permission_title': 'Notifications',
  'notif_permission_subtitle': 'For learning reminders',
  'allow_btn': 'Allow',
  'generating_lesson_snackbar': 'Generating lesson from today\'s captures…',
  'no_captures_category': 'No captures in this category.',
  'extracted_context_title': 'Extracted Context',
  'no_content_available': 'No content available.',
  'ready_for_lesson': 'Ready for lesson',
  'excluded_badge': 'Excluded',
  'screen_snapshot': 'Screen snapshot',
  'ambient_audio_capture': 'Ambient audio capture',
  'words_extracted_suffix': ' words extracted',
  'visual_context': 'Visual context',
  'audio_recording': 'Audio recording',
  'audio_preview': 'Audio preview',
  'learn_from_this': 'Learn from this',
  'view_screen_context_btn': 'View Screen Reader Context',
  'lesson_dialogue': 'Dialogue',
  'lesson_flashcard': 'Flashcard',
  'lesson_quiz': 'Quiz',
  'lesson_story': 'Story',
  'try_again_btn': 'Try again',
  'lesson_word_card': 'Word Card',
  'lesson_title': 'Lesson',
  'no_lesson_steps': 'No lesson steps available.',
  'search_hint': 'Search words or meanings…',
  'generate_btn': 'Generate Daily Lesson',
  'listening_status': 'Listening silently...',
  'ambient_inactive_status': 'Ambient capture inactive',
  'tap_start_status': 'Tap to start ambient immersion.',
  'privacy_tab': 'Privacy',
  'home_tab': 'Home',
  'lessons_tab': 'Lessons',
  'progress_tab': 'Progress',
  'greeting_title': 'Good morning, Learner',
  'greeting_subtitle': "The world is quiet. We're listening gently.",
  'privacy_screen_title': 'Your Morning Capture',
  'privacy_screen_subtitle':
      "Review the ambient audio and interactions captured today. "
      "Remove anything you'd prefer to keep private before generating your personalized lesson.",
  'no_captures': 'No captures yet today.',
  'visual_captures_section': 'Visual captures',
  'audio_captures_section': 'Audio captures',
  'lesson_consume_hint': "This will consume today's captures.",
  'localizing_overlay': 'Localizing interface using edge AI...',
  'ui_localize_checkbox': 'Translate app interface to my native language',
  'processing_status': 'Trimming silence and preparing audio...',
  'tap_pause_status': 'Tap to pause ambient immersion.',
  'processing_capture': 'Processing your capture…',
  'no_lesson_yet': 'No lesson yet',
  'empty_lesson_hint':
      'Capture some context today — ambient audio or screen content — '
      'then tap Generate Daily Lesson to start learning.',
  'settings_auto_gen_title': 'Daily Lesson Auto-Generation',
  'settings_auto_gen_enable': 'Enable Auto-Generation',
  'settings_auto_gen_subtitle':
      'Automatically generate a new lesson daily using your on-device Gemma LLM.',
  'settings_scheduled_time': 'Scheduled Time',
  'settings_recommendation_title': 'Important Recommendation',
  'settings_recommendation_body':
      'To ensure battery efficiency, the automatic background generation will only proceed if the device is idle (screen off) and battery is charging or >= 15% at the chosen time. Please keep your device locked and plugged in at this time. If constraints are not met, you will receive a notification to manually start generation with a single tap.',
};

String uiString(Map<String, String> strings, String key, [String? fallback]) =>
    strings[key] ?? fallback ?? kDefaultEnglishUiStrings[key] ?? key;

class UiStringsNotifier extends Notifier<Map<String, String>> {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');

  static const _uiTranslationEventsChannel = EventChannel(
    'com.circadian_lingo/ui_translation_events',
  );

  @override
  Map<String, String> build() {
    Future.microtask(_loadFromPrefs);
    _listenForTranslationEvents();
    return Map<String, String>.from(kDefaultEnglishUiStrings);
  }

  void _listenForTranslationEvents() {
    _uiTranslationEventsChannel.receiveBroadcastStream().listen(
      (event) {
        if (event == "complete") {
          _loadFromPrefs();
        }
      },
      onError: (error) {},
    );
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final localized = prefs.getBool('isUiLocalized') ?? false;

    if (!localized) return;

    final json = prefs.getString('uiStringsJson');
    if (json == null) return;

    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      // Corrupt cache — fall back to English.
    }
  }

  Future<void> setUiLocalized(
    BuildContext context,
    bool enabled, {
    required String nativeLanguageCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      state = Map<String, String>.from(kDefaultEnglishUiStrings);
      await prefs.setBool('isUiLocalized', false);
      await prefs.remove('uiStringsJson');
      await ref.read(userSettingsProvider.notifier).setIsUiLocalized(false);
      try {
        await _channel.invokeMethod('cancelUITranslation');
      } catch (_) {}
      return;
    }

    if (!context.mounted) return;

    // Optimistically update the UI to show the switch as enabled.
    await prefs.setBool('isUiLocalized', true);
    await ref.read(userSettingsProvider.notifier).setIsUiLocalized(true);

    try {
      final targetLanguage = languageDisplayName(nativeLanguageCode);
      final success = await _channel.invokeMethod<bool>('translateUI', {
        'uiElements': kDefaultEnglishUiStrings,
        'targetLanguage': targetLanguage,
      });

      if (success == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'UI localization started in background. Check notifications for progress.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        // If it failed to start, revert the switch
        await prefs.setBool('isUiLocalized', false);
        await ref.read(userSettingsProvider.notifier).setIsUiLocalized(false);
      }
    } catch (e) {
      // If it failed to start, revert the switch
      await prefs.setBool('isUiLocalized', false);
      await ref.read(userSettingsProvider.notifier).setIsUiLocalized(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start UI localization: $e')),
        );
      }
    }
  }
}

final uiStringsProvider =
    NotifierProvider<UiStringsNotifier, Map<String, String>>(
      UiStringsNotifier.new,
    );
