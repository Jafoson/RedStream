import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/rs_theme.dart';

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const _kLetterRows = <List<String>>[
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
  ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', '.'],
  ['Z', 'X', 'C', 'V', 'B', 'N', 'M', '-', '/', '⌫'],
];

// Action row — SPACE gets flex 3, others flex 1
const _kActionRow = <String>['⇧', 'SPACE', '@', '_', ':', '✓'];

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class TvKeyboardDialog extends StatefulWidget {
  final String title;
  final String initialText;
  final bool obscureText;

  const TvKeyboardDialog({
    super.key,
    required this.title,
    this.initialText = '',
    this.obscureText = false,
  });

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  late String _text;
  bool _shifted = false;

  // 2D grid of FocusNodes  [row][col]
  // rows 0..3 = _kLetterRows, row 4 = _kActionRow
  late final List<List<FocusNode>> _grid;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _grid = [
      ..._kLetterRows.map((r) => List.generate(r.length, (_) => FocusNode())),
      List.generate(_kActionRow.length, (_) => FocusNode()),
    ];
    // Start on 'A'
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _grid[2][0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final row in _grid) {
      for (final n in row) {
        n.dispose();
      }
    }
    super.dispose();
  }

  // ── Key press ─────────────────────────────────────────────────────────────

  void _press(String key) {
    setState(() {
      switch (key) {
        case '⇧':
          _shifted = !_shifted;
          return;
        case 'SPACE':
          _text += ' ';
          return;
        case '⌫':
          if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
          return;
        case '✓':
          Navigator.of(context).pop(_text);
          return;
      }
      // Single character — apply shift for A-Z
      if (key.length == 1 && RegExp(r'^[A-Z]$').hasMatch(key)) {
        _text += _shifted ? key : key.toLowerCase();
        _shifted = false;
      } else {
        _text += key;
      }
    });
  }

  // ── D-pad navigation ──────────────────────────────────────────────────────

  KeyEventResult _onKey(int row, int col, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      final key = row < _kLetterRows.length ? _kLetterRows[row][col] : _kActionRow[col];
      _press(key);
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowRight) {
      _moveTo(row, col + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _moveTo(row, col - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _moveTo(row + 1, col);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _moveTo(row - 1, col);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveTo(int row, int col) {
    final r = row.clamp(0, _grid.length - 1);
    final rowLen = _grid[r].length;
    final c = col.clamp(0, rowLen - 1);
    _grid[r][c].requestFocus();
  }

  // ── Key widget ────────────────────────────────────────────────────────────

  Widget _key(String raw, int row, int col) {
    final node = _grid[row][col];
    final isSpace = raw == 'SPACE';
    final isDone = raw == '✓';
    final isBack = raw == '⌫';
    final isShift = raw == '⇧';

    String label(bool shifted) {
      if (isSpace) return 'SPACE';
      if (raw.length == 1 && RegExp(r'^[A-Z]$').hasMatch(raw)) {
        return shifted ? raw : raw.toLowerCase();
      }
      return raw;
    }

    return Expanded(
      flex: isSpace ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: AnimatedBuilder(
          animation: node,
          builder: (_, _) {
            final focused = node.hasFocus;
            final active = isShift && _shifted;
            return Focus(
              focusNode: node,
              onKeyEvent: (_, e) => _onKey(row, col, e),
              child: GestureDetector(
                onTap: () => _press(raw),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: focused
                        ? Rs.accent
                        : active
                            ? Rs.accent.withValues(alpha: 0.4)
                            : isDone
                                ? Rs.accent.withValues(alpha: 0.18)
                                : isBack
                                    ? Colors.red.withValues(alpha: 0.18)
                                    : Rs.panel,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: focused ? Rs.accentLight : Rs.line,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: node,
                    builder: (_, _) => Text(
                      label(_shifted),
                      style: TextStyle(
                        color: focused ? Colors.white : Rs.text,
                        fontSize: isSpace ? 13 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(int rowIdx, List<String> keys) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            for (var c = 0; c < keys.length; c++) _key(keys[c], rowIdx, c),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final display = widget.obscureText ? '•' * _text.length : _text;

    return Dialog(
      backgroundColor: Rs.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 780,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(color: Rs.muted, fontSize: 13, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              // Display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Rs.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Rs.accent, width: 2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        display.isEmpty ? '…' : display,
                        style: TextStyle(
                          color: display.isEmpty ? Rs.muted : Rs.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          fontFamily: widget.obscureText ? 'monospace' : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard, color: Rs.accent, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Letter rows
              for (var r = 0; r < _kLetterRows.length; r++) _row(r, _kLetterRows[r]),
              // Action row
              _row(_kLetterRows.length, _kActionRow),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Future<String?> showTvKeyboard(
  BuildContext context, {
  required String title,
  String initialText = '',
  bool obscureText = false,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TvKeyboardDialog(
        title: title,
        initialText: initialText,
        obscureText: obscureText,
      ),
    );

// ---------------------------------------------------------------------------
// TvKeyboardInline — embedded keyboard for the search page (no dialog)
// ---------------------------------------------------------------------------

class TvKeyboardInline extends StatefulWidget {
  final String initialText;
  final void Function(String text) onChanged;
  /// Called when ✓ is pressed, ↓ from bottom row, or Back/ESC.
  final VoidCallback onExitKeyboard;

  const TvKeyboardInline({
    super.key,
    this.initialText = '',
    required this.onChanged,
    required this.onExitKeyboard,
  });

  @override
  State<TvKeyboardInline> createState() => TvKeyboardInlineState();
}

class TvKeyboardInlineState extends State<TvKeyboardInline> {
  late String _text;
  bool _shifted = false;
  late final List<List<FocusNode>> _grid;

  /// Focuses the 'A' key — call this when re-entering keyboard mode.
  void requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _grid[2][0].requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _grid = [
      ..._kLetterRows.map((r) => List.generate(r.length, (_) => FocusNode())),
      List.generate(_kActionRow.length, (_) => FocusNode()),
    ];
    requestFocus();
  }

  @override
  void dispose() {
    for (final row in _grid) {
      for (final n in row) n.dispose();
    }
    super.dispose();
  }

  void _press(String key) {
    if (key == '⇧') { setState(() => _shifted = !_shifted); return; }
    if (key == '✓') { widget.onExitKeyboard(); return; }

    String next = _text;
    bool nextShift = _shifted;

    switch (key) {
      case 'SPACE': next += ' ';
      case '⌫': if (next.isNotEmpty) next = next.substring(0, next.length - 1);
      default:
        if (key.length == 1 && RegExp(r'^[A-Z]$').hasMatch(key)) {
          next += _shifted ? key : key.toLowerCase();
          nextShift = false;
        } else {
          next += key;
        }
    }
    setState(() { _text = next; _shifted = nextShift; });
    widget.onChanged(_text);
  }

  KeyEventResult _onKey(int row, int col, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.gameButtonA) {
      _press(row < _kLetterRows.length ? _kLetterRows[row][col] : _kActionRow[col]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) { _moveTo(row, col + 1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowLeft)  { _moveTo(row, col - 1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowUp)    { _moveTo(row - 1, col); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (row == _grid.length - 1) { widget.onExitKeyboard(); return KeyEventResult.handled; }
      _moveTo(row + 1, col);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.goBack) {
      widget.onExitKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveTo(int row, int col) {
    final r = row.clamp(0, _grid.length - 1);
    final c = col.clamp(0, _grid[r].length - 1);
    _grid[r][c].requestFocus();
  }

  Widget _key(String raw, int row, int col) {
    final node = _grid[row][col];
    final isSpace = raw == 'SPACE';
    final isDone  = raw == '✓';
    final isBack  = raw == '⌫';
    final isShift = raw == '⇧';

    String label(bool sh) {
      if (isSpace) return 'SPACE';
      if (raw.length == 1 && RegExp(r'^[A-Z]$').hasMatch(raw)) return sh ? raw : raw.toLowerCase();
      return raw;
    }

    return Expanded(
      flex: isSpace ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: AnimatedBuilder(
          animation: node,
          builder: (_, _) {
            final focused = node.hasFocus;
            final active  = isShift && _shifted;
            return Focus(
              focusNode: node,
              onKeyEvent: (_, e) => _onKey(row, col, e),
              child: GestureDetector(
                onTap: () => _press(raw),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: focused
                        ? Rs.accent
                        : active
                            ? Rs.accent.withValues(alpha: 0.4)
                            : isDone
                                ? Rs.accent.withValues(alpha: 0.18)
                                : isBack
                                    ? Colors.red.withValues(alpha: 0.18)
                                    : Rs.panel,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: focused ? Rs.accentLight : Rs.line,
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: node,
                    builder: (_, _) => Text(
                      label(_shifted),
                      style: TextStyle(
                        color: focused ? Colors.white : Rs.text,
                        fontSize: isSpace ? 12 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _keyRow(int ri, List<String> keys) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            for (var c = 0; c < keys.length; c++) _key(keys[c], ri, c),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < _kLetterRows.length; r++) _keyRow(r, _kLetterRows[r]),
          _keyRow(_kLetterRows.length, _kActionRow),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TvTextInput — drop-in TextField replacement for Android TV
// ---------------------------------------------------------------------------

class TvTextInput extends StatefulWidget {
  final String label;
  final String value;
  final bool obscureText;
  final void Function(String) onChanged;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;

  const TvTextInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.obscureText = false,
    this.focusNode,
    this.keyboardType,
  });

  @override
  State<TvTextInput> createState() => _TvTextInputState();
}

class _TvTextInputState extends State<TvTextInput> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final result = await showTvKeyboard(
      context,
      title: widget.label,
      initialText: widget.value,
      obscureText: widget.obscureText,
    );
    if (result != null) widget.onChanged(result);
    // Re-focus the field after dialog closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final display =
        widget.obscureText ? '•' * widget.value.length : widget.value;

    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA) {
          _open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Rs.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? Rs.accent : Rs.line,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: display.isEmpty
                    ? Text(widget.label,
                        style: const TextStyle(color: Rs.muted2, fontSize: 17))
                    : Text(display,
                        style: const TextStyle(color: Rs.text, fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.keyboard_alt_outlined,
                color: _focused ? Rs.accent : Rs.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
