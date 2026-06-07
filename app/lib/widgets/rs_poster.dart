import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/rs_theme.dart';

/// Vertical poster card for series/anime items.
/// Shows [SeriesResult] with image, title, optional genre badges.
/// Highlights with accent ring when [focused].
class RsPosterCard extends StatelessWidget {
  final SeriesResult item;
  final bool focused;
  final VoidCallback? onTap;
  final bool inGrid;

  const RsPosterCard({
    super.key,
    required this.item,
    required this.focused,
    this.onTap,
    this.inGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: inGrid ? null : Rs.cardW,
        height: inGrid ? null : Rs.cardH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rs.radius),
          border: focused
              ? Border.all(color: Rs.accent, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: Rs.accent.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        transform: focused
            ? Matrix4.diagonal3Values(1.07, 1.07, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Rs.radius - 3),
          child: SizedBox(
            width: inGrid ? null : Rs.cardW,
            height: inGrid ? null : Rs.cardH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Artwork / poster image
                _PosterArt(posterUrl: item.posterUrl, title: item.title),
                // Subtle grain highlight
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.8, -0.8),
                      radius: 1.2,
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Bottom gradient + text
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: [0.0, 0.46, 0.7],
                      colors: [
                        Color(0xD0000000),
                        Color(0x26000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Title info at bottom
                Positioned(
                  left: 15,
                  right: 15,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                          height: 1.1,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 12),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Landscape "Continue Watching" card.
class RsContinueCard extends StatelessWidget {
  final SeriesResult item;
  final bool focused;
  final VoidCallback? onTap;
  final String? epLabel;
  final double progressFraction;
  /// Episode screenshot — shown as the main image.
  /// Falls back to [item.posterUrl] (series poster) while loading or if empty.
  final String? thumbnailUrl;

  const RsContinueCard({
    super.key,
    required this.item,
    required this.focused,
    this.onTap,
    this.epLabel,
    this.progressFraction = 0,
    this.thumbnailUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: Rs.cwW,
        height: Rs.cwH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Rs.radius),
          border: focused
              ? Border.all(color: Rs.accent, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: Rs.accent.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        transform: focused
            ? Matrix4.diagonal3Values(1.05, 1.05, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Rs.radius - 3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ContinueArt(
                thumbnailUrl: thumbnailUrl,
                posterUrl: item.posterUrl,
                title: item.title,
              ),
              // Gradient overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0.0, 0.55],
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
              // Play button when focused
              if (focused)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Rs.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
              // Title + episode chip + progress bar
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (epLabel != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Rs.accent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          epLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (progressFraction > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progressFraction,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Rs.accent),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Continue-watching artwork: shows episode screenshot (thumbnailUrl) as the
/// main image, with the series poster (posterUrl) as the placeholder while it loads.
class _ContinueArt extends StatelessWidget {
  final String? thumbnailUrl;
  final String posterUrl;
  final String title;
  const _ContinueArt({
    required this.thumbnailUrl,
    required this.posterUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        placeholder: (_, _) => _posterPlaceholder(),
        errorWidget: (_, _, _) => _posterPlaceholder(),
      );
    }
    return _posterPlaceholder();
  }

  Widget _posterPlaceholder() {
    if (posterUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: posterUrl,
        fit: BoxFit.cover,
        placeholder: (_, _) => _GradientPlaceholder(title),
        errorWidget: (_, _, _) => _GradientPlaceholder(title),
      );
    }
    return _GradientPlaceholder(title);
  }
}

/// Shared artwork widget — shows poster image or a gradient placeholder.
class _PosterArt extends StatelessWidget {
  final String posterUrl;
  final String title;
  const _PosterArt({required this.posterUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    if (posterUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: posterUrl,
        fit: BoxFit.cover,
        placeholder: (_, _) => _GradientPlaceholder(title),
        errorWidget: (_, _, _) => _GradientPlaceholder(title),
      );
    }
    return _GradientPlaceholder(title);
  }
}

/// Gradient placeholder generated from the title string.
class _GradientPlaceholder extends StatelessWidget {
  final String title;
  const _GradientPlaceholder(this.title);

  static const _palettes = [
    [Color(0xFF341812), Color(0xFFB15A3C)], // crimson
    [Color(0xFF2E1206), Color(0xFFC2651F)], // ember
    [Color(0xFF211A2A), Color(0xFF5A4A6E)], // indigo
    [Color(0xFF142420), Color(0xFF3F7E6E)], // teal
    [Color(0xFF271629), Color(0xFF7A4F74)], // plum
    [Color(0xFF221D18), Color(0xFF6A5F4F)], // steel
    [Color(0xFF2E1820), Color(0xFFAB6A70)], // rose
    [Color(0xFF1B2417), Color(0xFF5E7544)], // forest
    [Color(0xFF2F2206), Color(0xFFC8932F)], // gold
    [Color(0xFF201A24), Color(0xFF534A66)], // midnight
  ];

  @override
  Widget build(BuildContext context) {
    final idx = title.isEmpty ? 0 : title.codeUnitAt(0) % _palettes.length;
    final pal = _palettes[idx];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.3, -1.0),
          end: const Alignment(0.3, 1.0),
          colors: pal,
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.12),
            letterSpacing: -2,
          ),
        ),
      ),
    );
  }
}
