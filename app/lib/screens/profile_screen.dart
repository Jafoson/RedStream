import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';

// Available avatar background colors
const _kAvatarColors = [
  Color(0xFFE50914),
  Color(0xFF0071EB),
  Color(0xFFE87C03),
  Color(0xFF54B9C5),
  Color(0xFF2CB67D),
  Color(0xFFA259FF),
];

Color _parseColor(String hex) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return _kAvatarColors[0];
  }
}

String _nextColor(List<Profile> profiles) {
  if (profiles.isEmpty) return '#E50914';
  final usedColors = profiles.map((p) => p.avatarColor.toUpperCase()).toSet();
  for (final c in _kAvatarColors) {
    final hex = '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    if (!usedColors.contains(hex)) return hex;
  }
  return '#${_kAvatarColors[profiles.length % _kAvatarColors.length].toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

class ProfileScreen extends ConsumerStatefulWidget {
  /// When true the screen was pushed from HomeScreen — pop on profile select.
  /// When false (app launch) we replace navigation with HomeScreen.
  final bool canPop;
  const ProfileScreen({super.key, this.canPop = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  List<Profile> _profiles = [];
  bool _loading = true;
  bool _editMode = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Handle B/back via HardwareKeyboard (same pattern as AppNavController)
    // so no FocusNode is injected into the focus tree that could swallow focus.
    if (widget.canPop) {
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
         event.logicalKey == LogicalKeyboardKey.gameButtonB) &&
        mounted &&
        widget.canPop) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiServiceProvider);
      final profiles = await api.getProfiles();
      if (mounted) {
        setState(() { _profiles = profiles; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectProfile(Profile p) async {
    await ref.read(activeProfileIdProvider.notifier).setProfile(p.id);
    if (!mounted) return;
    // Defer navigation to post-frame to avoid !_debugLocked when Riverpod
    // triggers provider rebuilds synchronously during the same tap frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.canPop) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  Future<void> _showAddDialog() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final nameCtrl = TextEditingController();
    String selectedColor = _nextColor(_profiles);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => _ProfileEditDialog(
          title: 'Profil hinzufügen',
          nameController: nameCtrl,
          initialColor: selectedColor,
          onColorChanged: (c) => selectedColor = c,
          canDelete: false,
          onDelete: null,
        ),
      );
      if (result == 'save' && nameCtrl.text.trim().isNotEmpty) {
        final api = ref.read(apiServiceProvider);
        await api.createProfile(nameCtrl.text.trim(), selectedColor);
        await _load();
      }
    } catch (_) {
    } finally {
      if (mounted) _dialogOpen = false;
    }
  }

  Future<void> _showEditDialog(Profile p) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final nameCtrl = TextEditingController(text: p.name);
    String selectedColor = p.avatarColor;
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => _ProfileEditDialog(
          title: 'Profil bearbeiten',
          nameController: nameCtrl,
          initialColor: selectedColor,
          onColorChanged: (c) => selectedColor = c,
          canDelete: _profiles.length > 1,
          onDelete: () => Navigator.of(ctx).pop('delete'),
        ),
      );
      if (result == 'delete') {
        final api = ref.read(apiServiceProvider);
        await api.deleteProfile(p.id);
        await _load();
      } else if (result == 'save' && nameCtrl.text.trim().isNotEmpty) {
        final api = ref.read(apiServiceProvider);
        await api.updateProfileData(p.id,
            name: nameCtrl.text.trim(), avatarColor: selectedColor);
        await _load();
      }
    } catch (_) {
    } finally {
      if (mounted) _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rs.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ProfileBody(
              profiles: _profiles,
              editMode: _editMode,
              onSelect: _selectProfile,
              onAdd: _showAddDialog,
              onEdit: _showEditDialog,
              onToggleEdit: () => setState(() => _editMode = !_editMode),
            ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final List<Profile> profiles;
  final bool editMode;
  final void Function(Profile) onSelect;
  final VoidCallback onAdd;
  final void Function(Profile) onEdit;
  final VoidCallback onToggleEdit;

  const _ProfileBody({
    required this.profiles,
    required this.editMode,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context) {
    // FocusTraversalGroup with WidgetOrderTraversalPolicy ensures D-pad
    // left/right moves through profiles → add card → manage button in order.
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Wer schaut?',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 64),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in profiles) ...[
                  _ProfileCard(
                    profile: p,
                    editMode: editMode,
                    onTap: () => editMode ? onEdit(p) : onSelect(p),
                    autofocus: p == profiles.first && !editMode,
                  ),
                  const SizedBox(width: 40),
                ],
                _AddProfileCard(onTap: onAdd),
              ],
            ),
            const SizedBox(height: 56),
            TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onActivate: onToggleEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: Text(
                  editMode ? 'Fertig' : 'Profile verwalten',
                  style: TextStyle(
                    color: editMode ? Rs.accent : Rs.muted,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
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

class _ProfileCard extends StatefulWidget {
  final Profile profile;
  final bool editMode;
  final VoidCallback onTap;
  final bool autofocus;

  const _ProfileCard({
    required this.profile,
    required this.editMode,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> with SingleTickerProviderStateMixin {
  bool _focused = false;
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(widget.profile.avatarColor);
    final initial = widget.profile.name.isNotEmpty
        ? widget.profile.name[0].toUpperCase()
        : '?';

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) { _anim.forward(); } else { _anim.reverse(); }
      },
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ScaleTransition(
          scale: _scale,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: _focused ? Colors.white : Colors.transparent,
                    width: 4,
                  ),
                  boxShadow: _focused
                      ? [BoxShadow(color: color.withValues(alpha: 0.65), blurRadius: 32, spreadRadius: 6)]
                      : [],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (widget.editMode)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          child: const Icon(Icons.edit, color: Colors.white, size: 44),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.profile.name,
                style: const TextStyle(
                  color: Rs.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _AddProfileCard extends StatefulWidget {
  final VoidCallback onTap;
  const _AddProfileCard({required this.onTap});

  @override
  State<_AddProfileCard> createState() => _AddProfileCardState();
}

class _AddProfileCardState extends State<_AddProfileCard> with SingleTickerProviderStateMixin {
  bool _focused = false;
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) { _anim.forward(); } else { _anim.reverse(); }
      },
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ScaleTransition(
          scale: _scale,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Rs.panel2,
                  border: Border.all(
                    color: _focused ? Rs.accent : Rs.line2,
                    width: 4,
                  ),
                  boxShadow: _focused
                      ? [BoxShadow(color: Rs.accent.withValues(alpha: 0.4), blurRadius: 28, spreadRadius: 4)]
                      : [],
                ),
                child: const Icon(Icons.add, color: Rs.muted, size: 60),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hinzufügen',
                style: TextStyle(color: Rs.muted, fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
    );
  }
}

class _ProfileEditDialog extends StatefulWidget {
  final String title;
  final TextEditingController nameController;
  final String initialColor;
  final void Function(String) onColorChanged;
  final bool canDelete;
  final VoidCallback? onDelete;

  const _ProfileEditDialog({
    required this.title,
    required this.nameController,
    required this.initialColor,
    required this.onColorChanged,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  void _selectColor(String hex) {
    setState(() => _selectedColor = hex);
    widget.onColorChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    // Use Dialog (not AlertDialog) so all focusable elements — text field,
    // color swatches, and buttons — live in a single FocusTraversalGroup and
    // D-pad traversal flows top-to-bottom without jumping to a separate
    // "actions" layer.
    return Dialog(
      backgroundColor: Rs.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rs.radius)),
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Rs.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 28),
                // D-pad down while in the text field moves focus to the
                // first color swatch instead of doing nothing (single-line
                // fields don't consume vertical arrow keys).
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      node.nextFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Rs.text, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: const TextStyle(color: Rs.muted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Rs.line2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Rs.accent, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Farbe',
                  style: TextStyle(color: Rs.muted, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Row(
                  children: _kAvatarColors.map((c) {
                    final hex =
                        '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: _TvColorSwatch(
                        color: c,
                        selected: _selectedColor.toUpperCase() == hex,
                        onSelect: () => _selectColor(hex),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 36),
                Row(
                  children: [
                    if (widget.canDelete && widget.onDelete != null) ...[
                      _TvDialogButton(
                        label: 'Löschen',
                        textColor: Colors.redAccent,
                        onPressed: widget.onDelete!,
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    _TvDialogButton(
                      label: 'Abbrechen',
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                    const SizedBox(width: 12),
                    _TvDialogButton(
                      label: 'Speichern',
                      isPrimary: true,
                      onPressed: () => Navigator.of(context).pop('save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Focusable color circle for gamepad navigation inside the dialog.
class _TvColorSwatch extends StatefulWidget {
  final Color color;
  final bool selected;
  final VoidCallback onSelect;
  const _TvColorSwatch({
    required this.color,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_TvColorSwatch> createState() => _TvColorSwatchState();
}

class _TvColorSwatchState extends State<_TvColorSwatch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          border: Border.all(
            color: _focused
                ? Colors.white
                : widget.selected
                    ? Colors.white
                    : Colors.transparent,
            width: _focused ? 4 : 3,
          ),
          boxShadow: _focused
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.65), blurRadius: 18, spreadRadius: 3)]
              : null,
        ),
        child: widget.selected
            ? const Icon(Icons.check, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

// Focusable button for gamepad navigation inside dialogs.
class _TvDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? textColor;
  final bool isPrimary;
  const _TvDialogButton({
    required this.label,
    required this.onPressed,
    this.textColor,
    this.isPrimary = false,
  });

  @override
  State<_TvDialogButton> createState() => _TvDialogButtonState();
}

class _TvDialogButtonState extends State<_TvDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isPrimary
        ? (_focused ? Rs.accentLight : Rs.accent)
        : (_focused ? Rs.accent : Rs.line2);

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_focused ? Rs.accentLight : Rs.accent)
                : (_focused ? Rs.panel3 : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: _focused && widget.isPrimary
                ? [BoxShadow(color: Rs.accent.withValues(alpha: 0.45), blurRadius: 14)]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isPrimary ? Colors.white : (widget.textColor ?? Rs.muted),
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
    );
  }
}
