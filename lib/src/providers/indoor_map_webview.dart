import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hosts the full indoor map (base tiles + rooms + roof-anchored labels)
/// inside a single WebView running maplibre-gl.js + Three.js
/// (see map_labels.html). Everything is driven by ONE camera inside the
/// WebView, which is what removes the flicker you were seeing from
/// stacking a separate native MapLibre layer under a separate Three.js
/// overlay — two unsynced render loops can never agree on the same frame.
///
/// Setup required in your Flutter project:
/// 1. Copy map_labels.html into assets/, e.g. assets/map/map_labels.html
/// 2. Register it in pubspec.yaml:
///      flutter:
///        assets:
///          - assets/map/map_labels.html
/// 3. Make sure webview_flutter is in pubspec.yaml (it already is, per
///    your existing MaplibreMapProvider imports).
class IndoorMapWebView extends StatefulWidget {
  /// GeoJSON FeatureCollection of room/section polygons — same shape you
  /// already build in MaplibreMapProvider._updatePolygonSource (id,
  /// fillColor, height, base_height, etc. as properties).
  final Map<String, dynamic> roomPolygons;

  /// GeoJSON FeatureCollection of point features carrying imageFile /
  /// associatedPolygons / name — same shape your web app's
  /// buildPointImagePlanes already consumes.
  final Map<String, dynamic> roomLabels;

  /// Base URL prepended to any relative imageFile value (e.g.
  /// "https://your-cdn.example.com/images/"). Pass "" if imageFile values
  /// are already absolute URLs.
  final String assetBaseUrl;

  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final double initialBearing;
  final double initialPitch;

  /// Optional: pass your own MapLibre style JSON (as a Dart Map) if you
  /// don't want the default dark raster style baked into the HTML file.
  final Map<String, dynamic>? styleJson;
  final VoidCallback? onWebViewReady;
  const IndoorMapWebView({
    super.key,
    required this.roomPolygons,
    required this.roomLabels,
    required this.assetBaseUrl,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 18.0,
    this.initialBearing = 0.0,
    this.initialPitch = 45.0,
    this.styleJson,
    this.onWebViewReady,
  });

  @override
  State<IndoorMapWebView> createState() => IndoorMapWebViewState();
}

class IndoorMapWebViewState extends State<IndoorMapWebView> {
  late final WebViewController _controller;
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        // Prints real WebView console output to your `flutter run` terminal
        // instead of the useless "[object Object]" Android normally shows.
        // eslint-disable-next-line
        // ignore: avoid_print
        print('WEBVIEW[${message.level.name}]: ${message.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            await _pushConfig();
            await _controller.runJavaScript("window.initMap();");
            await _pushRoomPolygons(widget.roomPolygons);
            await _pushRoomLabels(widget.roomLabels);
            if (mounted) setState(() => _pageReady = true);
            widget.onWebViewReady?.call();
          },
        ),
      )
      ..loadFlutterAsset('packages/unified_map_view/assets/map/map_labels.html');
  }

  @override
  void didUpdateWidget(covariant IndoorMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.roomPolygons, widget.roomPolygons)) {
      updateRoomPolygons(widget.roomPolygons);
    }
    if (!identical(oldWidget.roomLabels, widget.roomLabels)) {
      updateRoomLabels(widget.roomLabels);
    }
  }

  Future<void> _pushConfig() async {
    // window.ASSET_BASE_URL / INITIAL_CAMERA / MAP_STYLE_JSON must be set
    // BEFORE the HTML's own initMap() call runs at the bottom of the file —
    // since loadFlutterAsset already ran the whole <script type="module">
    // by the time onPageFinished fires, initMap() has already used whatever
    // defaults were baked in. If you need Dart-provided initial camera or
    // style values respected on first load (not just on subsequent calls),
    // move `initMap();` out of the module body and instead expose
    // `window.initMap = initMap;`, then call it here via runJavaScript
    // AFTER pushing config. That one-line change in map_labels.html is
    // recommended if styleJson/asset base URL differ per building.
    final camera = {
      'lng': widget.initialLng,
      'lat': widget.initialLat,
      'zoom': widget.initialZoom,
      'bearing': widget.initialBearing,
      'pitch': widget.initialPitch,
    };
    await _controller.runJavaScript(
      "window.ASSET_BASE_URL = ${jsonEncode(widget.assetBaseUrl)};",
    );
    await _controller.runJavaScript(
      "window.INITIAL_CAMERA = ${jsonEncode(camera)};",
    );
    if (widget.styleJson != null) {
      await _controller.runJavaScript(
        "window.MAP_STYLE_JSON = ${jsonEncode(widget.styleJson)};",
      );
    }
  }

  Future<void> _pushRoomPolygons(Map<String, dynamic> featureCollection) {
    return _controller.runJavaScript(
      "window.setRoomPolygons(${jsonEncode(featureCollection)});",
    );
  }

  Future<void> _pushRoomLabels(Map<String, dynamic> featureCollection) {
    return _controller.runJavaScript(
      "window.setRoomLabels(${jsonEncode(featureCollection)});",
    );
  }

  /// Call this whenever your Dart-side room polygon data changes (e.g. after
  /// fetching a new floor from your API) to re-render the base fill-extrusion
  /// layer and update what buildPointImagePlanes can attach labels to.
  Future<void> updateRoomPolygons(Map<String, dynamic> featureCollection) {
    if (!_pageReady) return Future.value();
    return _pushRoomPolygons(featureCollection);
  }

  /// Call this whenever your label/point data changes. Cheap enough to call
  /// on data refresh; do not call this every frame.
  Future<void> updateRoomLabels(Map<String, dynamic> featureCollection) {
    if (!_pageReady) return Future.value();
    return _pushRoomLabels(featureCollection);
  }

  Future<void> flyTo({
    required double lng,
    required double lat,
    double? zoom,
    double? bearing,
    double? pitch,
  }) {
    if (!_pageReady) return Future.value();
    return _controller.runJavaScript(
      "window.flyTo(${jsonEncode(lng)}, ${jsonEncode(lat)}, "
          "${jsonEncode(zoom ?? widget.initialZoom)}, "
          "${jsonEncode(bearing ?? widget.initialBearing)}, "
          "${jsonEncode(pitch ?? widget.initialPitch)});",
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}