import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/rs_theme.dart';

/// App logo: SVG icon + "RedStream" wordmark.
/// [iconSize] controls the SVG height (width is calculated from 430:282 aspect ratio).
/// Set [showText] to false to render only the icon (e.g. collapsed sidebar).
class RsLogo extends StatelessWidget {
  final double iconSize;
  final bool showText;
  final double textSize;

  const RsLogo({
    super.key,
    this.iconSize = 30,
    this.showText = true,
    this.textSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidth = iconSize * (430 / 282);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/rs_logo.svg',
          width: iconWidth,
          height: iconSize,
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          RichText(
            overflow: TextOverflow.clip,
            maxLines: 1,
            text: TextSpan(children: [
              TextSpan(
                text: 'Red',
                style: TextStyle(
                  fontSize: textSize,
                  fontWeight: FontWeight.w800,
                  color: Rs.text,
                  letterSpacing: -0.4,
                ),
              ),
              TextSpan(
                text: 'Stream',
                style: TextStyle(
                  fontSize: textSize,
                  fontWeight: FontWeight.w800,
                  color: Rs.accent,
                  letterSpacing: -0.4,
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}
