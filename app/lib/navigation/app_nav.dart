import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NavScreen { home, serien, anime, search, queue, library, settings }

/// Central D-Pad navigation controller — mirrors the HTML prototype's
/// custom focus engine (region/row/col model).
class AppNavController extends ChangeNotifier {
  bool sidebarFocused = false;
  NavScreen screen = NavScreen.home;
  int sidebarIndex = 0;
  int contentRow = 0;
  int contentCol = 0;

  List<int> _rowLengths = [];
  void Function(int row, int col)? _activateCb;
  String? _toast;

  // Remembers the last (row, col) for each screen so navigating back
  // restores the user's previous position.
  final _savedPositions = <NavScreen, (int, int)>{};

  // Per-row column memory within the current screen.
  // Cleared when switching screens so each screen starts fresh.
  final _rowCols = <int, int>{};

  static const _sidebarCount = 7;
  static const _navScreens = [
    NavScreen.home,
    NavScreen.serien,
    NavScreen.anime,
    NavScreen.search,
    NavScreen.queue,
    NavScreen.library,
    NavScreen.settings,
  ];

  String? get toast => _toast;

  // ── Global key handler ───────────────────────────────────────────────────
  // Uses HardwareKeyboard so key events are captured before Flutter's own
  // focus/traversal system can redirect D-pad presses to a ListView.

  bool _attached = false;

  void attach() {
    if (_attached) { return; }
    _attached = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void detach() {
    if (!_attached) { return; }
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (!_attached) { return false; }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) { return false; }
    final key = event.logicalKey;
    // Only consume navigation keys — let letters/digits pass through (search).
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight &&
        !_isConfirm(key)) { return false; }
    handleKeyEvent(event);
    return true; // consumed — prevents ListView scroll / focus traversal
  }

  // ── Position memory ──────────────────────────────────────────────────────

  void _savePosition() {
    _savedPositions[screen] = (contentRow, contentCol);
  }

  void _restorePosition(NavScreen toScreen) {
    final saved = _savedPositions[toScreen];
    if (saved != null) {
      contentRow = saved.$1;
      contentCol = saved.$2;
    } else {
      contentRow = 0;
      contentCol = 0;
    }
  }

  // ── Screen registration ──────────────────────────────────────────────────

  /// Called by each screen to register row lengths and the activate callback.
  /// Clamps the current (possibly restored) position to valid bounds and
  /// notifies listeners so screens can auto-scroll to the restored row.
  void registerNav(List<int> rowLengths, void Function(int row, int col) onActivate) {
    _rowLengths = List.of(rowLengths);
    _activateCb = onActivate;
    if (_rowLengths.isNotEmpty) {
      contentRow = contentRow.clamp(0, _rowLengths.length - 1);
      final maxCol = (_rowLengths[contentRow] - 1).clamp(0, 9999);
      contentCol = contentCol.clamp(0, maxCol);
    }
    // Do NOT call notifyListeners here — screens trigger their own scroll
    // after registerNav via the addPostFrameCallback in their build method.
  }

  // ── Query helpers ────────────────────────────────────────────────────────

  bool isItemFocused(int row, int col) =>
      !sidebarFocused && contentRow == row && contentCol == col;

  bool isSidebarFocused(int index) =>
      sidebarFocused && sidebarIndex == index;

  // ── Imperative navigation ────────────────────────────────────────────────

  void showToast(String msg) {
    _toast = msg;
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (_toast == msg) {
        _toast = null;
        notifyListeners();
      }
    });
  }

  void goToContent() {
    sidebarFocused = false;
    contentRow = 0;
    contentCol = 0;
    notifyListeners();
  }

  /// Switch screen programmatically (e.g. from a touch tap on the sidebar).
  void switchScreen(NavScreen newScreen) {
    _savePosition();
    final idx = _navScreens.indexOf(newScreen);
    if (idx >= 0) { sidebarIndex = idx; }
    screen = newScreen;
    sidebarFocused = false;
    _rowLengths = [];
    _rowCols.clear();
    _restorePosition(newScreen);
    notifyListeners();
  }

  // ── Key event dispatch ───────────────────────────────────────────────────

  void handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) { return; }
    final key = event.logicalKey;
    if (sidebarFocused) {
      _sidebar(key);
    } else {
      _content(key);
    }
  }

  void _sidebar(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      final newIdx = (sidebarIndex - 1).clamp(0, _sidebarCount - 1);
      if (newIdx != sidebarIndex) {
        _savePosition();
        sidebarIndex = newIdx;
        final newScreen = _navScreens[sidebarIndex];
        screen = newScreen;
        _rowLengths = [];
        _rowCols.clear();
        _restorePosition(newScreen);
      }
      notifyListeners();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final newIdx = (sidebarIndex + 1).clamp(0, _sidebarCount - 1);
      if (newIdx != sidebarIndex) {
        _savePosition();
        sidebarIndex = newIdx;
        final newScreen = _navScreens[sidebarIndex];
        screen = newScreen;
        _rowLengths = [];
        _rowCols.clear();
        _restorePosition(newScreen);
      }
      notifyListeners();
    } else if (key == LogicalKeyboardKey.arrowRight || _isConfirm(key)) {
      sidebarFocused = false;
      notifyListeners();
    }
  }

  void _content(LogicalKeyboardKey key) {
    if (_rowLengths.isEmpty) { return; }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (contentCol > 0) {
        contentCol--;
        notifyListeners();
      } else {
        sidebarFocused = true;
        notifyListeners();
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final max = (_rowLengths[contentRow] - 1).clamp(0, 9999);
      if (contentCol < max) {
        contentCol++;
        notifyListeners();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (contentRow > 0) {
        _rowCols[contentRow] = contentCol; // save current row's col
        contentRow--;
        final max = (_rowLengths[contentRow] - 1).clamp(0, 9999);
        contentCol = (_rowCols[contentRow] ?? 0).clamp(0, max);
        notifyListeners();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (contentRow < _rowLengths.length - 1) {
        _rowCols[contentRow] = contentCol; // save current row's col
        contentRow++;
        final max = (_rowLengths[contentRow] - 1).clamp(0, 9999);
        contentCol = (_rowCols[contentRow] ?? 0).clamp(0, max);
        notifyListeners();
      }
    } else if (_isConfirm(key)) {
      _activateCb?.call(contentRow, contentCol);
    }
  }

  static bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;
}
