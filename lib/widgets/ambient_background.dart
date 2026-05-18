import 'dart:ui';
import 'package:flutter/material.dart';

class AmbientBackground extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;

  const AmbientBackground({super.key, required this.child, this.gradient});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          if (gradient != null)
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: gradient!)),
            ),
          // Background Organic Blobs
          Positioned(
            top: -100,
            left: -150,
            child: _buildBlob(
              colorScheme.primaryContainer.withValues(alpha: 0.6),
              400,
            ),
          ),
          Positioned(
            bottom: 50,
            right: -100,
            child: _buildBlob(
              colorScheme.secondaryContainer.withValues(alpha: 0.5),
              350,
            ),
          ),
          Positioned(
            top: 300,
            left: 200,
            child: _buildBlob(
              colorScheme.tertiaryContainer.withValues(alpha: 0.5),
              200,
            ),
          ),
          // Main Content
          Positioned.fill(child: SafeArea(bottom: false, child: child)),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
