import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/model_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_strings_provider.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/searchable_language_selector.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _localizeUi = false;

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: () async {
                  await ref.read(userSettingsProvider.notifier).completeOnboarding();
                },
                icon: const Icon(Icons.skip_next_rounded, color: Colors.black54, size: 20),
                label: const Text(
                  'Skip Onboarding',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildHeader(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) => setState(() => _currentStep = index),
              children: [
                const _Step1Brain(),
                _Step2Identity(
                  localizeUi: _localizeUi,
                  onLocalizeUiChanged: (v) => setState(() => _localizeUi = v),
                ),
                const _Step3Power(),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final titles = ['The Brain', 'Identity', 'Power Up'];
    final subtitles = [
      'Downloading your personal AI companion',
      'Tell us about your language journey',
      'Granting necessary permissions',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            titles[_currentStep],
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitles[_currentStep],
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final modelStatus = ref.watch(modelProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
              },
              child: const Text(
                'Back',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else if (_currentStep == 0 && !modelStatus.isDownloaded)
            TextButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
              },
              child: const Text(
                'Skip Download',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            const SizedBox.shrink(),

          _buildNextButton(),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    final modelStatus = ref.watch(modelProvider);

    bool canGoNext = false;
    if (_currentStep == 0) canGoNext = modelStatus.isDownloaded;
    if (_currentStep == 1) canGoNext = true;
    if (_currentStep == 2) canGoNext = true;

    return ElevatedButton(
      onPressed: canGoNext ? _handleNext : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(_currentStep == 2 ? 'Get Started' : 'Continue'),
    );
  }

  void _handleNext() async {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      final settings = ref.read(userSettingsProvider).value;
      final nativeLang = settings?.nativeLanguage ?? 'Hindi';

      if (_localizeUi && mounted) {
        await ref
            .read(uiStringsProvider.notifier)
            .setUiLocalized(context, true, nativeLanguageCode: nativeLang);
      }

      await ref.read(userSettingsProvider.notifier).completeOnboarding();
    }
  }
}

class _Step1Brain extends ConsumerStatefulWidget {
  const _Step1Brain();

  @override
  ConsumerState<_Step1Brain> createState() => _Step1BrainState();
}

class _Step1BrainState extends ConsumerState<_Step1Brain> {
  @override
  Widget build(BuildContext context) {
    final modelStatus = ref.watch(modelProvider);

    return GlassCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                modelStatus.isDownloaded
                    ? Icons.psychology_rounded
                    : Icons.cloud_download_rounded,
                size: 80,
                color: modelStatus.isDownloaded
                    ? Colors.green
                    : Colors.blueAccent,
              ),
              const SizedBox(height: 24),
              Text(
                modelStatus.isDownloaded
                    ? 'AI Companion is Ready'
                    : 'Personal AI Companion',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                modelStatus.isDownloaded
                    ? 'Your personal Gemma LLM model is fully installed on this device. All translations and lesson generations will happen locally and securely.'
                    : 'Circadian Lingo runs a powerful language model (Gemma) entirely offline on your device, ensuring maximum privacy and zero latency. We need to download this companion first.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              if (modelStatus.isDownloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: modelStatus.progress,
                    minHeight: 8,
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloading... ${(modelStatus.progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (modelStatus.downloadSpeedBytesPerSec != null && modelStatus.downloadSpeedBytesPerSec! > 0)
                      Text(
                        '${(modelStatus.downloadSpeedBytesPerSec! / (1024 * 1024)).toStringAsFixed(2)} MB/s',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (modelStatus.bytesDownloaded != null && modelStatus.bytesTotal != null && modelStatus.bytesTotal! > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${(modelStatus.bytesDownloaded! / (1024 * 1024)).toStringAsFixed(1)} MB of ${(modelStatus.bytesTotal! / (1024 * 1024)).toStringAsFixed(1)} MB',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ] else if (modelStatus.isDownloaded) ...[
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.green,
                  size: 36,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ready to Proceed!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ] else ...[
                if (modelStatus.error != null) ...[
                  Text(
                    'Error: ${modelStatus.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(modelProvider.notifier).startDownload();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download AI Model (2.59 GB)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Step2Identity extends ConsumerWidget {
  final bool localizeUi;
  final ValueChanged<bool> onLocalizeUiChanged;

  const _Step2Identity({
    required this.localizeUi,
    required this.onLocalizeUiChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(userSettingsProvider);
    final settings = settingsAsync.value ?? const UserSettings();

    return GlassCard(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NATIVE LANGUAGE',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The language you speak fluently:',
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 12),
              SearchableLanguageSelector(
                selectedLanguage: settings.nativeLanguage,
                onChanged: (lang) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setNativeLanguage(lang);
                },
                title: 'Select Native Language',
              ),
              const SizedBox(height: 28),
              const Text(
                'TARGET LANGUAGE',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The language you want to practice:',
                style: TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 12),
              SearchableLanguageSelector(
                selectedLanguage: settings.targetLanguage,
                onChanged: (lang) {
                  ref
                      .read(userSettingsProvider.notifier)
                      .setTargetLanguage(lang);
                },
                title: 'Select Target Language',
              ),
              const SizedBox(height: 28),
              const Divider(color: Colors.black12),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                title: const Text(
                  'Localize Interface',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                subtitle: const Text(
                  'Use on-device Gemma AI to translate the entire app UI (buttons, headings, menus) into your native language.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                value: localizeUi,
                onChanged: onLocalizeUiChanged,
                activeThumbColor: Colors.blueAccent,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step3Power extends StatelessWidget {
  const _Step3Power();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PermissionTile(
              icon: Icons.mic_rounded,
              title: 'Microphone',
              subtitle: 'For ambient listening & lessons',
              permission: Permission.microphone,
            ),
            const SizedBox(height: 16),
            _PermissionTile(
              icon: Icons.notification_important_rounded,
              title: 'Notifications',
              subtitle: 'For learning reminders',
              permission: Permission.notification,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Permission permission;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.permission,
  });

  @override
  State<_PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends State<_PermissionTile> {
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  void _check() async {
    final status = await widget.permission.status;
    if (mounted) setState(() => _granted = status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: ListTile(
        leading: Icon(widget.icon, color: Colors.blueAccent),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          widget.subtitle,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        trailing: _granted
            ? const Icon(Icons.check_circle_rounded, color: Colors.green)
            : ElevatedButton(
                onPressed: () async {
                  await widget.permission.request();
                  _check();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Allow'),
              ),
      ),
    );
  }
}
