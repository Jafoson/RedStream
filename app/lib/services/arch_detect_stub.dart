// dart:ffi has no web implementation. The updater is desktop/Android-only
// (see `_supportsUpdate` in settings_screen.dart), so this path is never
// actually called on web — it just has to compile.
bool isArm32() => false;
