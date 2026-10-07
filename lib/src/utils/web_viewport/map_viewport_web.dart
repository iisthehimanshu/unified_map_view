import 'dart:js_interop';

import 'map_viewport.dart';

@JS('document')
external _ParentNode get _document;

extension type _ParentNode(JSObject _) implements JSObject {
  external _Element? querySelector(String selectors);
}

extension type _Element(JSObject _) implements _ParentNode {
  external int get clientWidth;
  external int get clientHeight;
}

MapViewportState mapViewportState() {
  // MapLibre GL JS puts these classes on its container and canvas.
  final container = _document.querySelector('.maplibregl-map');
  // No map element to measure: never hold a camera update on a guess.
  if (container == null) return MapViewportState.ready;
  if (container.clientWidth == 0 || container.clientHeight == 0) {
    return MapViewportState.hidden;
  }
  final canvas = container.querySelector('.maplibregl-canvas');
  if (canvas == null) return MapViewportState.ready;
  return canvas.clientWidth == container.clientWidth &&
          canvas.clientHeight == container.clientHeight
      ? MapViewportState.ready
      : MapViewportState.stale;
}
