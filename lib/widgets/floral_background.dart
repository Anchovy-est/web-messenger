import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/floral_palette.dart';

/// One placed instance of the flower illustration — everything about it
/// (color, opacity, size, rotation, position) is independent of every
/// other instance, per the Floral theme's design brief.
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

  /// 0.0–1.0 of the available width/height — resolved to actual pixels
  /// at layout time, so the same composition scales sensibly across
  /// different screen sizes rather than being pinned to fixed pixel
  /// coordinates.
  final double leftFraction;
  final double topFraction;
}

/// The Floral theme's decorative backdrop: a soft pastel base color plus
/// several low-opacity, independently colored/sized/rotated copies of
/// `assets/flowers/flower.svg`, with [child] (the actual app content) on
/// top. Only ever mounted while the Floral theme is active — see
/// `MessengerApp`, which wraps the routed content in this widget
/// conditionally and nothing else, so switching away from Floral removes
/// every trace of it rather than leaving flowers bleeding into another
/// theme.
///
/// The flower composition (each instance's color/opacity/size/rotation/
/// position) is generated exactly once, in [State.initState], and cached
/// for this widget's lifetime — not recomputed on every rebuild, which
/// would make the background visibly jump around on every navigation.
/// Since `MessengerApp` mounts one `FloralBackground` instance behind the
/// whole app (not one per screen), this same composition also stays
/// stable across screens — a calm, consistent backdrop instead of a
/// different flower arrangement per route.
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
                        // Purely decorative — must never intercept taps
                        // meant for the real UI on top of it.
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
