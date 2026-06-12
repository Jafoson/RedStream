import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../theme/rs_theme.dart';
import 'rs_poster.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

class _MouseDragBehavior extends MaterialScrollBehavior {
  const _MouseDragBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

/// Horizontal scrolling rail with a section title bar.
/// [rowIndex] maps to AppNavController.contentRow.
/// Automatically scrolls to keep the focused card visible.
class RsRail extends StatefulWidget {
  final String title;
  final String? linkLabel;
  final int rowIndex;
  final List<SeriesResult> items;
  final AppNavController nav;
  final void Function(SeriesResult item) onSelect;
  final bool isContinue;

  const RsRail({
    super.key,
    required this.title,
    this.linkLabel,
    required this.rowIndex,
    required this.items,
    required this.nav,
    required this.onSelect,
    this.isContinue = false,
  });

  @override
  State<RsRail> createState() => _RsRailState();
}

class _RsRailState extends State<RsRail> {
  final _scrollCtrl = ScrollController();

  static const _hPad = 44.0;
  static const _gap = 20.0;

  double get _itemW => widget.isContinue ? Rs.cwW : Rs.cardW;
  double get _step => _itemW + _gap;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCol(int col) {
    if (!_scrollCtrl.hasClients) return;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    final target = ((col - 1) * _step).clamp(0.0, maxScroll);
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.nav,
      builder: (context, _) {
        final rowFocused = !widget.nav.sidebarFocused &&
            widget.nav.contentRow == widget.rowIndex;
        final focusedCol = rowFocused ? widget.nav.contentCol : -1;

        // Auto-scroll when focus changes within this row
        if (rowFocused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToCol(focusedCol);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(_hPad, 30, _hPad, 18),
              child: Row(
                children: [
                  // Accent bar
                  Container(
                    width: 5,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Rs.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Rs.text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (widget.linkLabel != null) ...[
                    const Spacer(),
                    Text(
                      '${widget.linkLabel} ›',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Rs.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Scrollable card track
            // Extra vertical padding (18px each side) absorbs the 1.05–1.07× focus
            // scale so the enlarged card doesn't overflow the SizedBox.
            // clipBehavior: none lets the border/shadow render past the list edges.
            SizedBox(
              height: widget.isContinue ? Rs.cwH + 36 : Rs.cardH + 36,
              child: ScrollConfiguration(
                behavior: _isDesktop
                    ? const _MouseDragBehavior()
                    : const MaterialScrollBehavior(),
                child: ListView.builder(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.fromLTRB(_hPad, 18, _hPad, 18),
                itemCount: widget.items.length,
                itemBuilder: (context, i) {
                  final focused = focusedCol == i;
                  final item = widget.items[i];
                  return Padding(
                    padding: EdgeInsets.only(right: i < widget.items.length - 1 ? _gap : 0),
                    child: widget.isContinue
                        ? RsContinueCard(
                            item: item,
                            focused: focused,
                            onTap: () => widget.onSelect(item),
                          )
                        : RsPosterCard(
                            item: item,
                            focused: focused,
                            onTap: () => widget.onSelect(item),
                          ),
                  );
                },
              ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Section title used outside of a rail (e.g. in detail screen).
class RsSectionTitle extends StatelessWidget {
  final String title;
  const RsSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 28, 44, 16),
      child: Row(
        children: [
          Container(
            width: 5, height: 24,
            decoration: BoxDecoration(
              color: Rs.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 13),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Rs.text,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
