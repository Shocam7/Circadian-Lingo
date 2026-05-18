import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/daily_captures_provider.dart';
import '../providers/lesson_provider.dart';
import '../providers/ui_strings_provider.dart';
import '../theme/colors.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_app_bar.dart';

class PrivacyDashboardScreen extends ConsumerWidget {
  final VoidCallback? onGenerateLesson;

  const PrivacyDashboardScreen({super.key, this.onGenerateLesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiStringsProvider);
    final captures = ref.watch(dailyCapturesProvider);
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: const GlassAppBar(),
        body: RefreshIndicator(
          color: colorScheme.primary,
          onRefresh: () async {
            await ref.read(dailyCapturesProvider.notifier).refreshCaptures();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    children: [
                      Text(
                        uiString(ui, 'privacy_screen_title'),
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        uiString(ui, 'privacy_screen_subtitle'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              if (captures.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      uiString(ui, 'no_captures'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _CollapsibleCaptureSection(
                        title: uiString(ui, 'visual_captures_section'),
                        icon: Icons.smartphone,
                        captures: captures
                            .where((c) => c.type == 'screen_context')
                            .toList(),
                        onDelete: (id) => ref
                            .read(dailyCapturesProvider.notifier)
                            .removeCapture(id),
                        onGenerateLesson: onGenerateLesson,
                      ),
                      const SizedBox(height: 16),
                      _CollapsibleCaptureSection(
                        title: uiString(ui, 'audio_captures_section'),
                        icon: Icons.mic,
                        captures: captures
                            .where(
                              (c) =>
                                  c.type == 'audio_raw' ||
                                  c.type.startsWith('audio'),
                            )
                            .toList(),
                        onDelete: (id) => ref
                            .read(dailyCapturesProvider.notifier)
                            .removeCapture(id),
                        onGenerateLesson: onGenerateLesson,
                      ),
                    ]),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                  child: Column(
                    children: [
                      _GenerateLessonButton(
                        hasUsable: captures.any(
                          (c) => c.quality == CaptureQuality.usable,
                        ),
                        onPressed: () async {
                          ref.read(lessonProvider.notifier).generateLesson();
                          onGenerateLesson?.call();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Generating lesson from today\'s captures…',
                                ),
                                backgroundColor: colorScheme.primary,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        uiString(ui, 'lesson_consume_hint'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleCaptureSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<CaptureItem> captures;
  final void Function(String id) onDelete;
  final VoidCallback? onGenerateLesson;

  const _CollapsibleCaptureSection({
    required this.title,
    required this.icon,
    required this.captures,
    required this.onDelete,
    this.onGenerateLesson,
  });

  @override
  State<_CollapsibleCaptureSection> createState() =>
      _CollapsibleCaptureSectionState();
}

class _CollapsibleCaptureSectionState
    extends State<_CollapsibleCaptureSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.captures.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: widget.captures.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'No captures in this category.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      for (var i = 0; i < widget.captures.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _CaptureTimelineCard(
                          item: widget.captures[i],
                          onDelete: () =>
                              widget.onDelete(widget.captures[i].id),
                          onGenerateLesson: widget.onGenerateLesson,
                        ),
                      ],
                    ],
                  ),
                ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

class _GenerateLessonButton extends ConsumerWidget {
  final bool hasUsable;
  final VoidCallback? onPressed;

  const _GenerateLessonButton({required this.hasUsable, this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiStringsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasUsable ? onPressed : null,
        borderRadius: BorderRadius.circular(9999),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.secondaryContainer,
                colorScheme.primaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF3E8FF).withValues(alpha: 0.4),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  uiString(ui, 'generate_btn'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.auto_awesome, color: colorScheme.onSurface, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureTimelineCard extends ConsumerStatefulWidget {
  final CaptureItem item;
  final VoidCallback onDelete;
  final VoidCallback? onGenerateLesson;

  const _CaptureTimelineCard({
    required this.item,
    required this.onDelete,
    this.onGenerateLesson,
  });

  @override
  ConsumerState<_CaptureTimelineCard> createState() =>
      _CaptureTimelineCardState();
}

class _CaptureTimelineCardState extends ConsumerState<_CaptureTimelineCard> {
  bool get _isScreenContext => widget.item.type == 'screen_context';
  bool get _isAudio => widget.item.type.startsWith('audio');


  void _showExtractedContext(
    BuildContext context,
    String? textPath,
    String? content,
  ) async {
    String textToShow = content ?? 'No content available.';
    if (textPath != null) {
      try {
        final file = File(textPath);
        if (await file.exists()) {
          textToShow = await file.readAsString();
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extracted Context',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  textToShow,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final audioFile = widget.item.filePath != null
        ? File(widget.item.filePath!)
        : null;
    final audioExists = audioFile?.existsSync() ?? false;

    final imageFile = widget.item.imagePath != null
        ? File(widget.item.imagePath!)
        : null;
    final imageExists = imageFile?.existsSync() ?? false;

    // Quality badge
    Widget? qualityBadge;
    if (widget.item.quality == CaptureQuality.usable) {
      qualityBadge = _QualityChip(
        label: 'Ready for lesson',
        color: Colors.green,
      );
    } else if (widget.item.quality == CaptureQuality.excludedTooShort ||
        widget.item.quality == CaptureQuality.excludedTooFewWords) {
      qualityBadge = _QualityChip(
        label: widget.item.excludeReason ?? 'Excluded',
        color: Colors.amber,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.background, width: 4),
          ),
          child: Icon(
            _isScreenContext ? Icons.smartphone : Icons.mic,
            color: colorScheme.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatTime(widget.item.timestamp),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _titleFor(widget.item),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitleFor(widget.item),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          if (qualityBadge != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                qualityBadge,
                                if (widget.item.quality ==
                                    CaptureQuality.usable)
                                  _LearnButton(
                                    onPressed: () async {
                                      // Start generation
                                      ref
                                          .read(lessonProvider.notifier)
                                          .generateLesson(item: widget.item);
                                      // Redirect to lesson screen immediately
                                      widget.onGenerateLesson?.call();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    _DeleteButton(onPressed: widget.onDelete),
                  ],
                ),
                if (_isScreenContext) ...[
                  if (imageExists) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Image.file(
                          imageFile!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _previewPlaceholder(colorScheme),
                        ),
                      ),
                    ),
                  ],
                  if (widget.item.textPath != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _showExtractedContext(
                          context,
                          widget.item.textPath,
                          widget.item.content,
                        ),
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Screen Reader Context'),
                      ),
                    ),
                  ],
                ],
                if (_isAudio && audioExists) ...[
                  const SizedBox(height: 16),
                  _AudioPreview(filePath: widget.item.filePath!),

                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewPlaceholder(ColorScheme colorScheme) {
    return Container(
      height: 120,
      color: colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  String _titleFor(CaptureItem item) {
    if (item.type == 'screen_context') {
      if (item.content != null && item.content!.trim().isNotEmpty) {
        final firstLine = item.content!.split('\n').first.trim();
        if (firstLine.isNotEmpty) return firstLine;
      }
      return 'Screen snapshot';
    }
    return 'Ambient audio capture';
  }

  String _subtitleFor(CaptureItem item) {
    if (item.type == 'screen_context') {
      if (item.content != null) {
        final words = item.content!
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        return '$words words extracted';
      }
      return 'Visual context';
    }
    return 'Audio recording';
  }
}

class _QualityChip extends StatelessWidget {
  final String label;
  final Color color;
  const _QualityChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _DeleteButton extends ConsumerWidget {
  final VoidCallback onPressed;

  const _DeleteButton({required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.errorContainer,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            Icons.delete_outline,
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _AudioPreview extends StatefulWidget {
  final String filePath;

  const _AudioPreview({required this.filePath});

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final duration = await _player.setFilePath(widget.filePath);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _duration = duration ?? Duration.zero;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = false);
    }

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });

    _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });

    _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => _duration = duration);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _seek(double value) async {
    if (_duration == Duration.zero) return;
    await _player.seek(Duration(milliseconds: value.round()));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final progressMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Audio preview',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _loaded ? _togglePlayback : null,
                icon: Icon(
                  _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: colorScheme.primary,
                  size: 36,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: progressMs,
                        max: maxMs,
                        onChanged: _loaded ? _seek : null,
                        activeColor: colorScheme.primary,
                        inactiveColor: colorScheme.surfaceContainerHigh,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LearnButton extends ConsumerWidget {
  final VoidCallback onPressed;
  const _LearnButton({required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 12, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                'Learn from this',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
