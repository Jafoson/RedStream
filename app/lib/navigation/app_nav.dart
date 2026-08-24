import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum NavScreen { home, serien, anime, filme, search, queue, library, watchlist, settings }

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
  bool _gridMode = false;
  String? _toast;

  // Remembers the last (row, col) for each screen so navigating back
  // restores the user's previous position.
  final _savedPositions = <NavScreen, (int, int)>{};

  // Per-row column memory within the current screen.
  // Cleared when switching screens so each screen starts fresh.
  final _rowCols = <int, int>{};

  static const _sidebarCount = 10; // 9 nav items + 1 profile tile
  static const _navScreens = [
    NavScreen.home,
    NavScreen.watchlist,
    NavScreen.serien,
    NavScreen.anime,
    NavScreen.filme,
    NavScreen.search,
    NavScreen.queue,
    NavScreen.library,
    NavScreen.settings,
  ];

  String? get toast => _toast;

  // ── Global key handler ───────────────────────────────────────────────────
  // Uses HardwareKeyboard so key events are captured before Flutter's own
  // focus/traversal system can redirect D-pad presses to a ListView.

  /// Called when the user presses Enter/A on the profile switch tile in the sidebar.
  VoidCallback? _profileSwitchCb;
  void setProfileSwitchCallback(VoidCallback cb) { _profileSwitchCb = cb; }

  bool _attached = false;

  /// When true the key handler returns false for everything, letting Flutter's
  /// built-in focus / text-editing handle all input (used while a TextField
  /// has focus on the search screen).
  bool textInputActive = false;

  /// When true AND textInputActive is also true, ALL key events (including
  /// UP/DOWN) pass through unchanged — used for the inline TV keyboard so
  /// arrow keys navigate between keyboard rows instead of exiting text mode.
  bool textInputFull = false;

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

    if (textInputActive) {
      // Full pass-through mode: inline TV keyboard handles ALL keys itself
      // (including UP/DOWN for row navigation). Don't intercept anything.
      if (textInputFull) return false;
      // Normal text-field mode: UP/Down escape back to D-pad navigation.
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        FocusManager.instance.primaryFocus?.unfocus();
        textInputActive = false;
        handleKeyEvent(event);
        return true;
      }
      return false; // left/right/enter/chars stay in the text field
    }

    // Only consume navigation keys — let letters/digits pass through (search).
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight &&
        !_isConfirm(key)) { return false; }

    // Don't consume nav keys when no content rows are registered and the
    // sidebar isn't focused — this lets text fields in unregistered screens
    // (settings) use arrow keys normally for cursor movement.
    if (!sidebarFocused && _rowLengths.isEmpty) { return false; }

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
  /// [gridMode] enables two grid-specific behaviours:
  /// - Down/Up keeps the current column instead of resetting to 0 on first visit.
  /// - Right at the last column wraps to the first item of the next row.
  void registerNav(
    List<int> rowLengths,
    void Function(int row, int col) onActivate, {
    bool gridMode = false,
  }) {
    _rowLengths = List.of(rowLengths);
    _activateCb = onActivate;
    _gridMode = gridMode;
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
        if (sidebarIndex < _navScreens.length) {
          final newScreen = _navScreens[sidebarIndex];
          screen = newScreen;
          _rowLengths = [];
          _rowCols.clear();
          _restorePosition(newScreen);
        }
      }
      notifyListeners();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      final newIdx = (sidebarIndex + 1).clamp(0, _sidebarCount - 1);
      if (newIdx != sidebarIndex) {
        _savePosition();
        sidebarIndex = newIdx;
        if (sidebarIndex < _navScreens.length) {
          final newScreen = _navScreens[sidebarIndex];
          screen = newScreen;
          _rowLengths = [];
          _rowCols.clear();
          _restorePosition(newScreen);
        }
      }
      notifyListeners();
    } else if (key == LogicalKeyboardKey.arrowRight || _isConfirm(key)) {
      if (sidebarIndex >= _navScreens.length) {
        // Profile switch tile — hand off to HomeScreen which handles detach/attach.
        _profileSwitchCb?.call();
      } else {
        sidebarFocused = false;
        notifyListeners();
      }
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
      } else if (_gridMode && contentRow < _rowLengths.length - 1) {
        // Grid mode: wrap to first item of next row
        _rowCols[contentRow] = contentCol;
        contentRow++;
        contentCol = 0;
        notifyListeners();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (contentRow > 0) {
        final prevCol = contentCol;
        _rowCols[contentRow] = contentCol;
        contentRow--;
        final max = (_rowLengths[contentRow] - 1).clamp(0, 9999);
        // Grid mode: keep same column; otherwise reset to 0 on first visit
        contentCol = (_rowCols[contentRow] ?? (_gridMode ? prevCol : 0)).clamp(0, max);
        notifyListeners();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (contentRow < _rowLengths.length - 1) {
        final prevCol = contentCol;
        _rowCols[contentRow] = contentCol;
        contentRow++;
        final max = (_rowLengths[contentRow] - 1).clamp(0, 9999);
        // Grid mode: keep same column; otherwise reset to 0 on first visit
        contentCol = (_rowCols[contentRow] ?? (_gridMode ? prevCol : 0)).clamp(0, max);
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
