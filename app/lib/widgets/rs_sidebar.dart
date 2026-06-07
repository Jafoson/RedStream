import 'package:flutter/material.dart';

import '../navigation/app_nav.dart';
import '../theme/rs_theme.dart';

class RsSidebar extends StatelessWidget {
  final AppNavController nav;
  const RsSidebar({super.key, required this.nav});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) => Container(
        width: Rs.sidebarW,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEB111315), Color(0xEB0B0C0E)],
          ),
          border: Border(right: BorderSide(color: Rs.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 34),
            _Brand(),
            const SizedBox(height: 30),
            _NavGroup(nav: nav, items: _menuItems),
            _SectionLabel('BIBLIOTHEK'),
            _NavGroup(nav: nav, items: _libItems),
            const Spacer(),
            _NavGroup(nav: nav, items: _genItems),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 0, 18, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Rs.accent,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Rs.accent.withValues(alpha: 0.5),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Red',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Rs.text,
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: 'Stream',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Rs.accent,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 18, 16, 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 2.0,
          color: Rs.muted2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavGroup extends StatelessWidget {
  final AppNavController nav;
  final List<_NavItem> items;
  const _NavGroup({required this.nav, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) => _NavTile(nav: nav, item: item)).toList(),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final NavScreen screen;
  final int index;
  const _NavItem(this.icon, this.label, this.screen, this.index);
}

const _menuItems = [
  _NavItem(Icons.home_rounded, 'Home', NavScreen.home, 0),
  _NavItem(Icons.tv_rounded, 'Serien', NavScreen.serien, 1),
  _NavItem(Icons.movie_filter_rounded, 'Anime', NavScreen.anime, 2),
  _NavItem(Icons.search_rounded, 'Suche', NavScreen.search, 3),
];

const _libItems = [
  _NavItem(Icons.download_rounded, 'Downloads', NavScreen.queue, 4),
  _NavItem(Icons.video_library_rounded, 'Bibliothek', NavScreen.library, 5),
];

const _genItems = [
  _NavItem(Icons.settings_rounded, 'Einstellungen', NavScreen.settings, 6),
];

class _NavTile extends StatelessWidget {
  final AppNavController nav;
  final _NavItem item;
  const _NavTile({required this.nav, required this.item});

  @override
  Widget build(BuildContext context) {
    final isFoc = nav.isSidebarFocused(item.index);
    final isActive = nav.screen == item.screen;

    return GestureDetector(
      onTap: () => nav.switchScreen(item.screen),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        padding: EdgeInsets.fromLTRB(isFoc ? 20 : 16, 13, 16, 13),
        decoration: BoxDecoration(
          color: isFoc
              ? Rs.accent
              : isActive
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: isFoc
              ? [
                  BoxShadow(
                    color: Rs.accent.withValues(alpha: 0.45),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 22,
              color: isFoc
                  ? Colors.white
                  : isActive
                      ? Rs.accent
                      : Rs.muted,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isFoc ? Colors.white : isActive ? Colors.white : Rs.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
