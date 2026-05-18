import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/alu.dart';
import '../services/fsrs_service.dart';
import '../theme/lesson_theme.dart';

class FlashcardSwiperWidget extends StatefulWidget {
  final FlashcardSetAlu alu;
  final VoidCallback? onComplete;
  final bool flowMode;

  const FlashcardSwiperWidget({
    super.key,
    required this.alu,
    this.onComplete,
    this.flowMode = false,
  });

  @override
  State<FlashcardSwiperWidget> createState() => _FlashcardSwiperWidgetState();
}

class _FlashcardSwiperWidgetState extends State<FlashcardSwiperWidget> {
  final CardSwiperController _controller = CardSwiperController();
  final Map<int, bool> _revealed = {};
  int _remaining = 0;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _remaining = widget.alu.cards.length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _onSwipe(int prev, int? next, CardSwiperDirection dir) async {
    final card = widget.alu.cards[prev];
    final correct = dir == CardSwiperDirection.right;
    await FsrsService.instance.recordReview(card.front, card.back, correct);
    setState(() {
      _remaining = (_remaining - 1).clamp(0, widget.alu.cards.length);
      _currentIndex = (next ?? prev + 1).clamp(0, widget.alu.cards.length - 1);
      _revealed.remove(prev);
    });
    if (_remaining == 0) widget.onComplete?.call();
    return true;
  }

  Future<void> _rateCard(bool gotIt) async {
    if (_remaining <= 0) return;
    final dir = gotIt ? CardSwiperDirection.right : CardSwiperDirection.left;
    if (widget.flowMode) {
      await _onSwipe(_currentIndex, _currentIndex + 1, dir);
    } else {
      _controller.swipe(dir);
    }
  }

  void _toggleReveal(int index) {
    setState(() => _revealed[index] = !(_revealed[index] ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!widget.flowMode) {
      return _legacyLayout(theme, cs);
    }

    final card = widget.alu.cards.isNotEmpty
        ? widget.alu.cards[_currentIndex.clamp(0, widget.alu.cards.length - 1)]
        : null;
    final revealed = _revealed[_currentIndex] ?? false;
    final progress = widget.alu.cards.isEmpty
        ? 0.0
        : (_currentIndex + 1) / widget.alu.cards.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'VOCABULARY SESSION',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${_currentIndex + 1} of ${widget.alu.cards.length}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: cs.surfaceContainer,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 24),
        if (card != null)
          GestureDetector(
            onTap: () => _toggleReveal(_currentIndex),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) {
                  final rotateAnim = Tween<double>(begin: 3.14159, end: 0).animate(anim);
                  return AnimatedBuilder(
                    animation: rotateAnim,
                    child: child,
                    builder: (context, child) {
                      final isBack = child?.key == const ValueKey('back');
                      final value = isBack ? rotateAnim.value : -rotateAnim.value;
                      final isFacingAway = isBack ? (value > 1.5708) : (value < -1.5708);
                      
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(value),
                        child: isFacingAway ? const SizedBox() : child,
                      );
                    },
                  );
                },
                child: revealed
                    ? _FlowCardBack(
                        key: const ValueKey('back'),
                        card: card,
                        cs: cs,
                      )
                    : _FlowCardFront(
                        key: const ValueKey('front'),
                        card: card,
                        cs: cs,
                      ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: card == null
              ? null
              : () => _toggleReveal(_currentIndex),
          icon: Icon(
            revealed ? Icons.visibility_off : Icons.rotate_right,
          ),
          label: Text(revealed ? 'Hide Answer' : 'Show Answer'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: cs.surfaceContainerHighest,
            foregroundColor: cs.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: card == null ? null : () => _rateCard(true),
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Next',
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legacyLayout(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.style_outlined, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Flashcards',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '$_remaining left',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: CardSwiper(
            controller: _controller,
            cardsCount: widget.alu.cards.length,
            onSwipe: _onSwipe,
            allowedSwipeDirection: const AllowedSwipeDirection.only(
              left: true,
              right: true,
            ),
            cardBuilder: (ctx, index, h, v) {
              final card = widget.alu.cards[index];
              final revealed = _revealed[index] ?? false;
              return GestureDetector(
                onTap: () => setState(() => _revealed[index] = true),
                child: _LegacyCard(
                  card: card,
                  revealed: revealed,
                  cs: cs,
                  theme: theme,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FlowCardFront extends StatelessWidget {
  final Flashcard card;
  final ColorScheme cs;

  const _FlowCardFront({super.key, required this.card, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LessonTheme.dailyPrimaryFixed.withValues(alpha: 0.15),
            cs.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [LessonTheme.cardShadow],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: LessonTheme.dailyPrimaryFixed,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'TARGET WORD',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: LessonTheme.dailyPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            card.front,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 32),
          Icon(Icons.light_mode_outlined, color: cs.primary.withValues(alpha: 0.4), size: 40),
        ],
      ),
    );
  }
}

class _FlowCardBack extends StatelessWidget {
  final Flashcard card;
  final ColorScheme cs;

  const _FlowCardBack({super.key, required this.card, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LessonTheme.accentSecondaryFixed.withValues(alpha: 0.15),
            cs.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [LessonTheme.cardShadow],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: LessonTheme.accentSecondaryFixed,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'DEFINITION',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: LessonTheme.accentSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            card.back,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyCard extends StatelessWidget {
  final Flashcard card;
  final bool revealed;
  final ColorScheme cs;
  final ThemeData theme;

  const _LegacyCard({
    required this.card,
    required this.revealed,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: revealed
                ? [cs.tertiaryContainer, cs.secondaryContainer]
                : [cs.primaryContainer, cs.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  revealed ? card.back : card.front,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!revealed) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tap to reveal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
