import 'package:flutter/material.dart';

import '../navigation/app_nav.dart';
import '../screens/profile_screen.dart';
import '../theme/rs_theme.dart';
import 'rs_logo.dart';

class RsSidebar extends StatelessWidget {
  final AppNavController nav;
  const RsSidebar({super.key, required this.nav});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) {
        final expanded = nav.sidebarFocused;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: expanded ? Rs.sidebarW : Rs.sidebarCollapsed,
          height: double.infinity,
          clipBehavior: Clip.hardEdge,
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
              const SizedBox(height: 24),
              _Brand(expanded: expanded),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NavGroup(nav: nav, items: _menuItems, expanded: expanded),
                      _SectionLabel(expanded: expanded),
                      _NavGroup(nav: nav, items: _libItems, expanded: expanded),
                    ],
                  ),
                ),
              ),
              _NavGroup(nav: nav, items: _genItems, expanded: expanded),
              _ProfileSwitchTile(nav: nav, expanded: expanded),
              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
  }
}

// ── Brand ────────────────────────────────────────────────────────────────────

class _Brand extends StatelessWidget {
  final bool expanded;
  const _Brand({required this.expanded});

  @override
  Widget build(BuildContext context) {
    // collapsed: center icon only; expanded: icon + wordmark
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 8 : 4, vertical: 0),
      child: expanded
          ? const RsLogo(iconSize: 26, textSize: 16)
          : const RsLogo(iconSize: 26, showText: false),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final bool expanded;
  const _SectionLabel({required this.expanded});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: expanded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 120),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(24, 14, 12, 8),
        child: Text(
          'BIBLIOTHEK',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.8,
            color: Rs.muted2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Nav group / tile ──────────────────────────────────────────────────────────

class _NavGroup extends StatelessWidget {
  final AppNavController nav;
  final List<_NavItem> items;
  final bool expanded;
  const _NavGroup(
      {required this.nav, required this.items, required this.expanded});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map((item) => _NavTile(nav: nav, item: item, expanded: expanded))
          .toList(),
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
  _NavItem(Icons.bookmark_rounded, 'Watchlist', NavScreen.watchlist, 1),
  _NavItem(Icons.tv_rounded, 'Serien', NavScreen.serien, 2),
  _NavItem(Icons.movie_filter_rounded, 'Anime', NavScreen.anime, 3),
  _NavItem(Icons.search_rounded, 'Suche', NavScreen.search, 4),
];

const _libItems = [
  _NavItem(Icons.download_rounded, 'Downloads', NavScreen.queue, 5),
  _NavItem(Icons.video_library_rounded, 'Bibliothek', NavScreen.library, 6),
];

const _genItems = [
  _NavItem(Icons.settings_rounded, 'Einstellungen', NavScreen.settings, 7),
];

class _NavTile extends StatelessWidget {
  final AppNavController nav;
  final _NavItem item;
  final bool expanded;
  const _NavTile(
      {required this.nav, required this.item, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final isFoc = nav.isSidebarFocused(item.index);
    final isActive = nav.screen == item.screen;

    final iconColor = isFoc
        ? Colors.white
        : isActive
            ? Rs.accent
            : Rs.muted;

    return GestureDetector(
      onTap: () => nav.switchScreen(item.screen),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: expanded
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 1)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: expanded
            ? EdgeInsets.fromLTRB(isFoc ? 16 : 12, 9, 12, 9)
            // (tile_w - icon_w) / 2 = (40 - 17) / 2 = 11.5 → centres icon
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: isFoc
              ? Rs.accent
              : isActive
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isFoc
              ? [
                  BoxShadow(
                    color: Rs.accent.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 17, color: iconColor),
            Flexible(
              child: AnimatedOpacity(
                opacity: expanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isFoc
                          ? Colors.white
                          : isActive
                              ? Colors.white
                              : Rs.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile switch tile ───────────────────────────────────────────────────────

class _ProfileSwitchTile extends StatelessWidget {
  final AppNavController nav;
  final bool expanded;
  const _ProfileSwitchTile({required this.nav, required this.expanded});

  static const _index = 8;

  @override
  Widget build(BuildContext context) {
    final isFoc = nav.isSidebarFocused(_index);

    return GestureDetector(
      onTap: () async {
        nav.detach();
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const ProfileScreen(canPop: true)),
        );
        nav.attach();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: expanded
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 1)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: expanded
            ? EdgeInsets.fromLTRB(isFoc ? 16 : 12, 9, 12, 9)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: isFoc ? Rs.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isFoc
              ? [
                  BoxShadow(
                      color: Rs.accent.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6))
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.switch_account_rounded,
                size: 17, color: isFoc ? Colors.white : Rs.muted),
            Flexible(
              child: AnimatedOpacity(
                opacity: expanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Text(
                    'Profil wechseln',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isFoc ? Colors.white : Rs.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
