import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/daily_lesson_screen.dart';
import 'screens/privacy_dashboard_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/storage_cleanup_service.dart';
import 'widgets/custom_bottom_nav.dart';
import 'providers/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: CircadianLingoApp()));
}

class CircadianLingoApp extends StatelessWidget {
  const CircadianLingoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circadian Lingo',
      theme: AppTheme.lightTheme,
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Best-effort cleanup on every launch
    StorageCleanupService.runOnLaunch();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      PrivacyDashboardScreen(
        onGenerateLesson: () => setState(() => _currentIndex = 2),
      ),
      const DailyLessonScreen(),
      const ProgressScreen(),
    ];

    final settingsAsync = ref.watch(userSettingsProvider);

    return settingsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (settings) {
        if (!settings.hasCompletedOnboarding) {
          return const OnboardingScreen();
        }

        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: screens[_currentIndex],
          bottomNavigationBar: CustomBottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }
}
