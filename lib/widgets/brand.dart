import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The brand assets of Discord Media Sender.
///
/// The mark is a geometric origami paper plane: folded wing planes, a centre
/// spine and a violet nose tip. It carries no letterforms, so the wordmark
/// stays a separate sans-serif type.
///
/// The four variants mirror the brand guide:
///
///  * `logo_paper_plane.svg`        — mark on the dark plate (circle)
///  * `logo_paper_plane_mark.svg`   — mark only, transparent background
///  * `logo_paper_plane_icon.svg`   — rounded tile, used as the launcher icon
///  * `logo_paper_plane_light.svg`  — light background variant
class BrandAssets {
  BrandAssets._();

  static const String plate = 'assets/brand/logo_paper_plane.svg';
  static const String mark = 'assets/brand/logo_paper_plane_mark.svg';
  static const String icon = 'assets/brand/logo_paper_plane_icon.svg';
  static const String light = 'assets/brand/logo_paper_plane_light.svg';

  /// The accent violet that is only ever used on the nose of the plane.
  static const Color accent = Color(0xFF8B5CF6);

  /// The light accent used by the launcher tile.
  static const Color accentLight = Color(0xFFA78BFA);

  /// The dark plate behind the mark.
  static const Color plateColor = Color(0xFF1C2030);
}

/// The origami paper plane without a background.
///
/// Use it on dark surfaces. On light surfaces use [BrandMark.light].
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 32,
    this.light = false,
    this.semanticLabel = 'Discord Media Sender',
  });

  /// The size of the square that holds the mark.
  final double size;

  /// Renders the variant that reads on a light background.
  final bool light;

  /// The accessibility label of the mark.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final String asset = light ? BrandAssets.light : BrandAssets.mark;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SvgPicture.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// The origami paper plane on its dark plate.
class BrandPlate extends StatelessWidget {
  const BrandPlate({
    super.key,
    this.size = 56,
    this.semanticLabel = 'Discord Media Sender',
  });

  /// The diameter of the plate.
  final double size;

  /// The accessibility label of the plate.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SvgPicture.asset(
          BrandAssets.plate,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// The full lockup: the mark next to the product name.
///
/// The wordmark is plain sans-serif type; the mark itself carries no letters.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.size = 44,
    this.title = 'Discord Media Sender',
    this.subtitle,
    this.light = false,
    this.alignment = MainAxisAlignment.start,
  });

  /// The diameter of the plate that holds the mark.
  final double size;

  /// The product name.
  final String title;

  /// An optional second line under the product name.
  final String? subtitle;

  /// Uses the light background variant of the mark.
  final bool light;

  /// How the mark and the type are placed next to each other.
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color muted = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Row(
      mainAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandMark(size: size, light: light),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
