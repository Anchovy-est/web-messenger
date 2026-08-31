import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/floral_palette.dart';

/// One placed instance of the flower illustration.
@immutable
class _FlowerSpec {
  const _FlowerSpec({
    required this.color,
    required this.opacity,
    required this.size,
    required this.rotation,
    required this.leftFraction,
    required this.topFraction,
  });

  final Color color;
  final double opacity;
  final double size;

  /// Radians.
  final double rotation;

  /// 0.0–1.0 of the available width/height, resolved at layout time.
  final double leftFraction;
  final double topFraction;
}

/// The Floral theme's decorative backdrop: a pastel base plus several
/// low-opacity flower copies, with [child] on top. Only mounted while
/// Floral is active. The composition is generated once and cached, so
/// it stays stable across navigation instead of jumping around.
class FloralBackground extends StatefulWidget {
  const FloralBackground({super.key, required this.child});

  final Widget child;

  @override
  State<FloralBackground> createState() => _FloralBackgroundState();
}

class _FloralBackgroundState extends State<FloralBackground> {
  late final List<_FlowerSpec> _flowers = _generateFlowers();

  static List<_FlowerSpec> _generateFlowers() {
    final random = Random();
    final palette = FloralPalette.flowerColors;
    return List.generate(FloralFlowerConfig.count, (_) {
      return _FlowerSpec(
        color: palette[random.nextInt(palette.length)],
        opacity: _lerpRandom(
          random,
          FloralFlowerConfig.minOpacity,
          FloralFlowerConfig.maxOpacity,
        ),
        size: _lerpRandom(
          random,
          FloralFlowerConfig.minSize,
          FloralFlowerConfig.maxSize,
        ),
        rotation:
            _lerpRandom(
              random,
              FloralFlowerConfig.minRotationDegrees,
              FloralFlowerConfig.maxRotationDegrees,
            ) *
            pi /
            180,
        leftFraction: random.nextDouble(),
        topFraction: random.nextDouble(),
      );
    });
  }

  static double _lerpRandom(Random random, double min, double max) =>
      min + random.nextDouble() * (max - min);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FloralPalette.cream,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  for (final flower in _flowers)
                    Positioned(
                      left:
                          flower.leftFraction * constraints.maxWidth -
                          flower.size / 2,
                      top:
                          flower.topFraction * constraints.maxHeight -
                          flower.size / 2,
                      child: IgnorePointer(
                        // Purely decorative — never intercepts taps.
                        child: Opacity(
                          opacity: flower.opacity,
                          child: Transform.rotate(
                            angle: flower.rotation,
                            child: SvgPicture.asset(
                              'assets/flowers/flower.svg',
                              width: flower.size,
                              height: flower.size,
                              colorFilter: ColorFilter.mode(
                                flower.color,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
