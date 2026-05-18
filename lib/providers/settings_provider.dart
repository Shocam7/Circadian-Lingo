import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSettings {
  final String nativeLanguage;
  final String targetLanguage;
  final int contextWindowStartHour;
  final int contextWindowEndHour;
  final int dailyScreenCaptureCount;
  final int dailyAudioCaptureCount;
  final int dailyScreenCaptureLimit;
  final int dailyAudioCaptureLimit;
  final int ambientAudioDuration; // In minutes
  final DateTime? lastCaptureDate;
  final bool smartContextSchedulingEnabled;
  final bool hasCompletedOnboarding;
  final bool isUiLocalized;
  final bool lessonAutoGenerationEnabled;
  final int lessonGenerationHour;
  final int lessonGenerationMinute;

  const UserSettings({
    this.nativeLanguage = 'Hindi', // Default to Hindi
    this.targetLanguage = 'English', // Default to English
    this.contextWindowStartHour = 9, // 9 AM
    this.contextWindowEndHour = 17, // 5 PM
    this.dailyScreenCaptureCount = 0,
    this.dailyAudioCaptureCount = 0,
    this.dailyScreenCaptureLimit = 5,
    this.dailyAudioCaptureLimit = 5,
    this.ambientAudioDuration = 30, // 30 minutes default
    this.lastCaptureDate,
    this.smartContextSchedulingEnabled = false,
    this.hasCompletedOnboarding = false,
    this.isUiLocalized = false,
    this.lessonAutoGenerationEnabled = true,
    this.lessonGenerationHour = 22, // 10 PM
    this.lessonGenerationMinute = 0,
  });

  UserSettings copyWith({
    String? nativeLanguage,
    String? targetLanguage,
    int? contextWindowStartHour,
    int? contextWindowEndHour,
    int? dailyScreenCaptureCount,
    int? dailyAudioCaptureCount,
    int? dailyScreenCaptureLimit,
    int? dailyAudioCaptureLimit,
    int? ambientAudioDuration,
    DateTime? lastCaptureDate,
    bool? smartContextSchedulingEnabled,
    bool? hasCompletedOnboarding,
    bool? isUiLocalized,
    bool? lessonAutoGenerationEnabled,
    int? lessonGenerationHour,
    int? lessonGenerationMinute,
  }) {
    return UserSettings(
      nativeLanguage: nativeLanguage ?? this.nativeLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      contextWindowStartHour:
          contextWindowStartHour ?? this.contextWindowStartHour,
      contextWindowEndHour: contextWindowEndHour ?? this.contextWindowEndHour,
      dailyScreenCaptureCount:
          dailyScreenCaptureCount ?? this.dailyScreenCaptureCount,
      dailyAudioCaptureCount:
          dailyAudioCaptureCount ?? this.dailyAudioCaptureCount,
      dailyScreenCaptureLimit:
          dailyScreenCaptureLimit ?? this.dailyScreenCaptureLimit,
      dailyAudioCaptureLimit:
          dailyAudioCaptureLimit ?? this.dailyAudioCaptureLimit,
      ambientAudioDuration: ambientAudioDuration ?? this.ambientAudioDuration,
      lastCaptureDate: lastCaptureDate ?? this.lastCaptureDate,
      smartContextSchedulingEnabled:
          smartContextSchedulingEnabled ?? this.smartContextSchedulingEnabled,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      isUiLocalized: isUiLocalized ?? this.isUiLocalized,
      lessonAutoGenerationEnabled:
          lessonAutoGenerationEnabled ?? this.lessonAutoGenerationEnabled,
      lessonGenerationHour: lessonGenerationHour ?? this.lessonGenerationHour,
      lessonGenerationMinute:
          lessonGenerationMinute ?? this.lessonGenerationMinute,
    );
  }
}

class UserSettingsNotifier extends AsyncNotifier<UserSettings> {
  static const _channel = MethodChannel('com.circadian_lingo/audio_pipeline');

  @override
  Future<UserSettings> build() async {
    final prefs = await SharedPreferences.getInstance();

    final startHour = prefs.getInt('contextWindowStartHour') ?? 9;
    final endHour = prefs.getInt('contextWindowEndHour') ?? 17;
    final count = prefs.getInt('dailyScreenCaptureCount') ?? 0;
    final audioCount = prefs.getInt('dailyAudioCaptureCount') ?? 0;
    final screenLimit = prefs.getInt('dailyScreenCaptureLimit') ?? 5;
    final audioLimit = prefs.getInt('dailyAudioCaptureLimit') ?? 5;
    final ambientDuration = prefs.getInt('ambientAudioDuration') ?? 30;
    final enabled = prefs.getBool('smartContextSchedulingEnabled') ?? false;
    final lastDateStr = prefs.getString('lastCaptureDate');
    final nativeLang = prefs.getString('nativeLanguage') ?? 'Hindi';
    final targetLang = prefs.getString('targetLanguage') ?? 'English';
    final completedOnboarding =
        prefs.getBool('hasCompletedOnboarding') ?? false;
    final isUiLocalized = prefs.getBool('isUiLocalized') ?? false;
    final lessonAutoEnabled = prefs.getBool('lessonAutoGenerationEnabled') ?? true;
    final lessonHour = prefs.getInt('lessonGenerationHour') ?? 22;
    final lessonMinute = prefs.getInt('lessonGenerationMinute') ?? 0;

    DateTime? lastDate;
    if (lastDateStr != null) {
      final parts = lastDateStr.split('-');
      if (parts.length == 3) {
        lastDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    }

    return UserSettings(
      contextWindowStartHour: startHour,
      contextWindowEndHour: endHour,
      dailyScreenCaptureCount: count,
      dailyAudioCaptureCount: audioCount,
      dailyScreenCaptureLimit: screenLimit,
      dailyAudioCaptureLimit: audioLimit,
      ambientAudioDuration: ambientDuration,
      smartContextSchedulingEnabled: enabled,
      lastCaptureDate: lastDate,
      nativeLanguage: nativeLang,
      targetLanguage: targetLang,
      hasCompletedOnboarding: completedOnboarding,
      isUiLocalized: isUiLocalized,
      lessonAutoGenerationEnabled: lessonAutoEnabled,
      lessonGenerationHour: lessonHour,
      lessonGenerationMinute: lessonMinute,
    );
  }

  Future<void> setIsUiLocalized(bool localized) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isUiLocalized', localized);
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(isUiLocalized: localized));
    }
  }

  Future<void> setNativeLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nativeLanguage', lang);

    // Sync to native
    try {
      await _channel.invokeMethod('saveUserLanguages', {
        'nativeLanguage': lang,
        'targetLanguage': state.value?.targetLanguage ?? 'en',
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(nativeLanguage: lang));
    }
  }

  Future<void> setTargetLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('targetLanguage', lang);

    // Sync to native
    try {
      await _channel.invokeMethod('saveUserLanguages', {
        'nativeLanguage': state.value?.nativeLanguage ?? 'hi',
        'targetLanguage': lang,
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(targetLanguage: lang));
    }
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCompletedOnboarding', completed);
    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(hasCompletedOnboarding: completed),
      );
    }
  }

  Future<void> completeOnboarding() async {
    await syncAllToNative();
    await setOnboardingCompleted(true);
  }

  Future<void> setContextWindow(int startHour, int endHour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contextWindowStartHour', startHour);
    await prefs.setInt('contextWindowEndHour', endHour);

    // Save settings back to Native to update WorkManager
    try {
      await _channel.invokeMethod('saveSettings', {
        'startHour': startHour,
        'endHour': endHour,
        'ambientAudioDuration': state.value?.ambientAudioDuration ?? 30,
        'dailyScreenCaptureLimit': state.value?.dailyScreenCaptureLimit ?? 5,
        'dailyAudioCaptureLimit': state.value?.dailyAudioCaptureLimit ?? 5,
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(
          contextWindowStartHour: startHour,
          contextWindowEndHour: endHour,
        ),
      );
    }
  }

  Future<void> setSmartScheduling(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smartContextSchedulingEnabled', enabled);

    try {
      if (enabled) {
        await _channel.invokeMethod('startScreenshotScheduler');
        await _channel.invokeMethod('startAudioScheduler');
      } else {
        await _channel.invokeMethod('stopScreenshotScheduler');
        await _channel.invokeMethod('stopAudioScheduler');
      }
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(smartContextSchedulingEnabled: enabled),
      );
    }
  }

  Future<void> setAmbientAudioDuration(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ambientAudioDuration', minutes);

    try {
      await _channel.invokeMethod('saveSettings', {
        'startHour': state.value?.contextWindowStartHour ?? 9,
        'endHour': state.value?.contextWindowEndHour ?? 17,
        'ambientAudioDuration': minutes,
        'dailyScreenCaptureLimit': state.value?.dailyScreenCaptureLimit ?? 5,
        'dailyAudioCaptureLimit': state.value?.dailyAudioCaptureLimit ?? 5,
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(ambientAudioDuration: minutes),
      );
    }
  }

  Future<void> setDailyLimits(int screenLimit, int audioLimit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dailyScreenCaptureLimit', screenLimit);
    await prefs.setInt('dailyAudioCaptureLimit', audioLimit);

    try {
      await _channel.invokeMethod('saveSettings', {
        'startHour': state.value?.contextWindowStartHour ?? 9,
        'endHour': state.value?.contextWindowEndHour ?? 17,
        'ambientAudioDuration': state.value?.ambientAudioDuration ?? 30,
        'dailyScreenCaptureLimit': screenLimit,
        'dailyAudioCaptureLimit': audioLimit,
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(
          dailyScreenCaptureLimit: screenLimit,
          dailyAudioCaptureLimit: audioLimit,
        ),
      );
    }
  }

  Future<void> updateCounts(int screenCount, int audioCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dailyScreenCaptureCount', screenCount);
    await prefs.setInt('dailyAudioCaptureCount', audioCount);

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(
          dailyScreenCaptureCount: screenCount,
          dailyAudioCaptureCount: audioCount,
        ),
      );
    }
  }

  Future<void> setLessonAutoGenerationSchedule(bool enabled, int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lessonAutoGenerationEnabled', enabled);
    await prefs.setInt('lessonGenerationHour', hour);
    await prefs.setInt('lessonGenerationMinute', minute);

    try {
      await _channel.invokeMethod('updateLessonSchedule', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      });
    } catch (e) {
      // ignore
    }

    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(
          lessonAutoGenerationEnabled: enabled,
          lessonGenerationHour: hour,
          lessonGenerationMinute: minute,
        ),
      );
    }
  }

  Future<void> syncAllToNative() async {
    final settings = state.value;
    if (settings == null) return;

    try {
      await _channel.invokeMethod('saveUserLanguages', {
        'nativeLanguage': settings.nativeLanguage,
        'targetLanguage': settings.targetLanguage,
      });

      await _channel.invokeMethod('saveSettings', {
        'startHour': settings.contextWindowStartHour,
        'endHour': settings.contextWindowEndHour,
        'ambientAudioDuration': settings.ambientAudioDuration,
        'dailyScreenCaptureLimit': settings.dailyScreenCaptureLimit,
        'dailyAudioCaptureLimit': settings.dailyAudioCaptureLimit,
      });

      await _channel.invokeMethod('updateLessonSchedule', {
        'enabled': settings.lessonAutoGenerationEnabled,
        'hour': settings.lessonGenerationHour,
        'minute': settings.lessonGenerationMinute,
      });

      if (settings.smartContextSchedulingEnabled) {
        await _channel.invokeMethod('startScreenshotScheduler');
        await _channel.invokeMethod('startAudioScheduler');
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> refresh() async {
    final updated = await build();
    state = AsyncValue.data(updated);
  }
}

final userSettingsProvider =
    AsyncNotifierProvider<UserSettingsNotifier, UserSettings>(
      UserSettingsNotifier.new,
    );
