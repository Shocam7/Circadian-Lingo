import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_pipeline_provider.dart';
import '../providers/ui_strings_provider.dart';

/// Organic, pulsing listening button wired to [audioPipelineProvider].
class OrganicListeningButton extends ConsumerStatefulWidget {
  const OrganicListeningButton({super.key});

  @override
  ConsumerState<OrganicListeningButton> createState() =>
      _OrganicListeningButtonState();
}

class _OrganicListeningButtonState extends ConsumerState<OrganicListeningButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _morphController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  void _syncAnimation(PipelineStatus status) {
    if (status == PipelineStatus.recording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.animateTo(0, duration: const Duration(milliseconds: 400));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final pipelineAsync = ref.watch(audioPipelineProvider);
    final pipeline = pipelineAsync.asData?.value ?? const AudioPipelineState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAnimation(pipeline.status);
    });

    final String statusLabel;
    final Color statusDotColor;
    final Color statusTextColor;

    switch (pipeline.status) {
      case PipelineStatus.recording:
        statusLabel = uiString(ui, 'listening_status');
        statusDotColor = colorScheme.primary;
        statusTextColor = colorScheme.primary;
        break;
      case PipelineStatus.processing:
        statusLabel = uiString(ui, 'processing_status');
        statusDotColor = colorScheme.tertiary;
        statusTextColor = colorScheme.tertiary;
        break;
      case PipelineStatus.done:
        statusLabel = uiString(ui, 'ambient_inactive_status');
        statusDotColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        statusTextColor = colorScheme.onSurfaceVariant;
        break;
      case PipelineStatus.error:
        statusLabel = pipeline.errorMessage ?? 'An error occurred.';
        statusDotColor = colorScheme.error;
        statusTextColor = colorScheme.error;
        break;
      case PipelineStatus.idle:
        statusLabel = uiString(ui, 'ambient_inactive_status');
        statusDotColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        statusTextColor = colorScheme.onSurfaceVariant;
    }

    final IconData buttonIcon = pipeline.isProcessing
        ? Icons.hourglass_top_rounded
        : pipeline.isRecording
        ? Icons.stop_rounded
        : Icons.hearing;

    Future<void> onTap() async {
      if (pipeline.isProcessing) return;
      if (pipeline.isRecording) {
        await ref.read(audioPipelineProvider.notifier).stopAndProcess();
      } else {
        await ref.read(audioPipelineProvider.notifier).startCapture();
      }
    }

    final caption = pipeline.isRecording
        ? uiString(ui, 'tap_pause_status')
        : pipeline.isProcessing
        ? uiString(ui, 'processing_capture')
        : uiString(ui, 'tap_start_status');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF3E8FF).withValues(alpha: 0.2),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              pipeline.isProcessing
                  ? SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusDotColor,
                      ),
                    )
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusDotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: Listenable.merge([_scaleAnimation, _morphController]),
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              );
            },
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          colorScheme.secondaryContainer.withValues(alpha: 0.5),
                          colorScheme.primaryContainer.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  if (pipeline.isRecording) ...[
                    _RippleRing(size: 88, opacity: 0.2),
                    _RippleRing(size: 132, opacity: 0.1, delay: 1),
                  ],
                  AnimatedBuilder(
                    animation: _morphController,
                    builder: (context, child) {
                      final t = _morphController.value * 2 * math.pi;
                      final radii = [
                        60 + 20 * math.sin(t),
                        40 + 20 * math.cos(t + 1),
                        30 + 20 * math.sin(t + 2),
                        70 + 20 * math.cos(t + 0.5),
                      ];
                      return ClipPath(
                        clipper: _OrganicClipper(radii),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: pipeline.isRecording
                              ? [
                                  colorScheme.errorContainer,
                                  colorScheme.error.withValues(alpha: 0.6),
                                ]
                              : [colorScheme.surface, colorScheme.surfaceContainerLow],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF3E8FF).withValues(alpha: 0.4),
                            blurRadius: 48,
                            offset: const Offset(0, 12),
                          ),
                        ],
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      child: Center(
                        child: pipeline.isProcessing
                            ? SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: colorScheme.primary,
                                ),
                              )
                            : Icon(
                                buttonIcon,
                                size: 64,
                                color: pipeline.isRecording
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.primary,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          caption,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (pipeline.hasError) ...[
          const SizedBox(height: 12),
          Text(
            pipeline.errorMessage ?? '',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _RippleRing extends StatefulWidget {
  final double size;
  final double opacity;
  final double delay;

  const _RippleRing({required this.size, required this.opacity, this.delay = 0});

  @override
  State<_RippleRing> createState() => _RippleRingState();
}

class _RippleRingState extends State<_RippleRing> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
      if (mounted) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1 + _controller.value * 0.4;
        final opacity = widget.opacity * (1 - _controller.value);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _OrganicClipper extends CustomClipper<Path> {
  final List<double> radii;

  _OrganicClipper(this.radii);

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.5, 0);
    path.cubicTo(w * 0.85, h * 0.05, w, h * 0.35, w * 0.9, h * 0.55);
    path.cubicTo(w, h * 0.85, w * 0.65, h, w * 0.5, h);
    path.cubicTo(w * 0.15, h, 0, h * 0.75, w * 0.08, h * 0.5);
    path.cubicTo(0, h * 0.2, w * 0.25, 0, w * 0.5, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _OrganicClipper oldClipper) =>
      oldClipper.radii != radii;
}
