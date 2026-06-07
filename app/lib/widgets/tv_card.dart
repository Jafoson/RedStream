import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'tv_focusable.dart';

/// Poster card used in browse rows and search results.
/// Width × height ratio follows the standard 2:3 poster format.
class TvCard extends StatelessWidget {
  final String title;
  final String posterUrl;
  final VoidCallback? onActivate;
  final bool autofocus;
  final double width;

  const TvCard({
    super.key,
    required this.title,
    required this.posterUrl,
    this.onActivate,
    this.autofocus = false,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final textTheme = Theme.of(context).textTheme;

    return TvFocusable(
      onActivate: onActivate,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(width, height),
                      errorWidget: (_, __, ___) => _placeholder(width, height),
                    )
                  : _placeholder(width, height),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(double w, double h) => Container(
        width: w,
        height: h,
        color: const Color(0xFF2A2A2A),
        child: const Center(
          child: Icon(Icons.movie, color: Color(0xFF555555), size: 40),
        ),
      );
}
