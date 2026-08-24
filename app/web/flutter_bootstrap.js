{{flutter_js}}
{{flutter_build_config}}

// The Flutter web build has no HTML renderer anymore (removed in Flutter
// 3.29) — every build runs on CanvasKit, which is itself WebAssembly and
// normally wants WebGL2. Smart TV browsers (this app's /app/ target
// includes older embedded Chromium engines, e.g. Titan OS TVs) often have
// weak or buggy GPU drivers that only surface as a blank white screen with
// no console. These two options trade some performance for compatibility:
//   - canvasKitVariant: 'full' — the universally-compatible CanvasKit
//     binary, instead of 'auto' which may pick a smaller build assuming
//     newer browser features are present.
//   - canvasKitForceCpuOnly: true — skip WebGL entirely and rasterize on
//     the CPU, sidestepping broken/limited GPU drivers.
_flutter.loader.load({
  config: {
    canvasKitVariant: 'full',
    canvasKitForceCpuOnly: true,
  },
});
