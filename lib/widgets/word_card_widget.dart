import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../theme/lesson_theme.dart';

/// Word card — Stitch layout with definition and example from [WordCardAlu].
class WordCardWidget extends StatelessWidget {
  final WordCardAlu alu;
  final bool flowMode;

  const WordCardWidget({super.key, required this.alu, this.flowMode = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!flowMode) {
      return _LegacyFlipCard(alu: alu);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LessonTheme.wordCardGradient(cs),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            boxShadow: [LessonTheme.cardShadow],
          ),
          child: Column(
            children: [
              Icon(Icons.menu_book, color: cs.primary, size: 36),
              const SizedBox(height: 16),
              Text(
                alu.word,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 1,
                width: 48,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                alu.definition,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (alu.example.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: cs.secondary, width: 4),
                    ),
                  ),
                  child: Text(
                    alu.example,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? cs.primary;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Legacy flip card for non-flow contexts (e.g. review list).
class _LegacyFlipCard extends StatefulWidget {
  final WordCardAlu alu;
  const _LegacyFlipCard({required this.alu});

  @override
  State<_LegacyFlipCard> createState() => _LegacyFlipCardState();
}

class _LegacyFlipCardState extends State<_LegacyFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flipAnim;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_showBack) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
    setState(() => _showBack = !_showBack);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _flipAnim,
        builder: (context, child) {
          final angle = _flipAnim.value * 3.14159;
          final isBack = angle > 1.5708;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159),
                    child: _Back(alu: widget.alu, cs: cs, theme: theme),
                  )
                : _Front(alu: widget.alu, cs: cs, theme: theme),
          );
        },
      ),
    );
  }
}

class _Front extends StatelessWidget {
  final WordCardAlu alu;
  final ColorScheme cs;
  final ThemeData theme;
  const _Front({required this.alu, required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [cs.primaryContainer, cs.secondaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      boxShadow: [
        BoxShadow(
          color: cs.primary.withValues(alpha: 0.2),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          alu.word,
          style: theme.textTheme.displayMedium?.copyWith(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tap to reveal',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onPrimaryContainer.withValues(alpha: 0.6),
          ),
        ),
      ],
    ),
  );
}

class _Back extends StatelessWidget {
  final WordCardAlu alu;
  final ColorScheme cs;
  final ThemeData theme;
  const _Back({required this.alu, required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      boxShadow: [
        BoxShadow(
          color: cs.primary.withValues(alpha: 0.15),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          alu.word,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Divider(height: 24),
        Text(
          alu.definition,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurface,
            height: 1.5,
          ),
        ),
        if (alu.example.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
            ),
            child: Text(
              alu.example,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
