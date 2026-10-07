import 'map_viewport_native.dart'
    if (dart.library.js_interop) 'map_viewport_web.dart' as impl;

/// How the map's DOM element currently relates to the map drawn in it.
enum MapViewportState {
  /// The map is laid out and sized to its element. Always the case on native.
  ready,

  /// The element is out of layout (0x0), e.g. behind another route.
  hidden,

  /// The element is laid out but the map has not been resized to it yet.
  stale,
}

/// Web only: reads the map element's size straight from the DOM, since the
/// MapLibre controller does not expose it. See the provider's
/// `_awaitWebViewport` for why camera updates need it.
MapViewportState mapViewportState() => impl.mapViewportState();
