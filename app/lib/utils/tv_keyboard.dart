import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// On Android TV / Chromecast the soft keyboard does not open automatically
/// when a TextField receives D-pad focus. These helpers request the IME
/// explicitly via the platform channel.

extension TvKeyboardFocus on FocusNode {
  /// Show the soft keyboard whenever this node gains focus.
  /// Call once in [State.initState] right after creating the [FocusNode].
  void showKeyboardOnFocus() {
    addListener(() {
      if (hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }
}

/// Show the soft keyboard on the next frame.
/// Use in [State.initState] for TextFields that rely on [autofocus: true]
/// (where no explicit [FocusNode] is available to attach a listener).
void showKeyboardOnNextFrame() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  });
}
