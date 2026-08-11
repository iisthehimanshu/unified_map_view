import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

/// Data for one rooftop overlay item, rendered by [Rooftop3DLabelOverlay].
///
/// If [imageUrl] and [boundary] (3+ points) are both provided, the roof
/// renders as that image draped flat across the polygon's real footprint,
/// at [roofHeightMeters]. Otherwise it falls back to a floating text pill
/// anchored at (lat, lng, roofHeightMeters).
class RoofLabelData {
  final String id;
  final double lng;
  final double lat;
  final double roofHeightMeters;
  final String text;

  /// Full boundary of the roof polygon (lat, lng), in order — required to
  /// drape [imageUrl] onto the roof's actual shape.
  final List<LatLng>? boundary;

  /// URL (http/https) or asset path of a photo to drape onto the roof.
  final String? imageUrl;

  const RoofLabelData({
    required this.id,
    required this.lng,
    required this.lat,
    required this.roofHeightMeters,
    required this.text,
    this.boundary,
    this.imageUrl,
  });
}

/// Transparent overlay stacked above the native MapLibre map that renders
/// floating labels and/or textured rooftop images in 3D.
///
/// Not WebGL/three.js: every item is projected every frame through a
/// perspective camera model matched to MapLibre/Mapbox's own camera (same
/// vertical FOV constant, same pitch/bearing/zoom -> distance formula), and
/// drawn with a single [CustomPainter] — text via [TextPainter], rooftop
/// images via [Canvas.drawVertices] + [ui.ImageShader] (a real
/// perspective-projected texture map onto the polygon's footprint, not just
/// a flat icon).
///
/// The native map pushes its camera into this overlay via [updateCamera]
/// (call this once as soon as the map/style is ready, AND continuously
/// during gestures) and content via [updateLabels].
class Rooftop3DLabelOverlay extends StatefulWidget {
  const Rooftop3DLabelOverlay({super.key});

  @override
  State<Rooftop3DLabelOverlay> createState() => Rooftop3DLabelOverlayState();
}

class Rooftop3DLabelOverlayState extends State<Rooftop3DLabelOverlay> {
  LatLng _target = const LatLng(0, 0);
  double _zoom = 0;
  double _bearing = 0;
  double _tilt = 0;
  Size _sizePx = Size.zero;
  LatLng? _origin;

  List<RoofLabelData> _labels = const [];

  final Map<String, ui.Image?> _imageCache = {};
  final Set<String> _imageLoading = {};

  static const double _fovRadians = 0.6435011087932844; // ~36.87°, matches MapLibre/Mapbox
  static const double _earthCircumferenceMeters = 40075016.6855785;

  // -----------------------------------------------------------------------
  // Public API — called from MaplibreMapProvider
  // -----------------------------------------------------------------------

  /// Pushes the native map's current camera into the overlay. Call this
  /// once right after the map/style is ready (so the overlay isn't blank
  /// until the user first pans), and continuously during gestures.
  void updateCamera({
    required LatLng target,
    required double zoom,
    required double bearing,
    required double tilt,
    required Size sizePx,
  }) {
    _origin ??= target;
    if (!mounted) return;
    setState(() {
      _target = target;
      _zoom = zoom;
      _bearing = bearing;
      _tilt = tilt;
      _sizePx = sizePx;
    });
  }

  /// Replaces the set of rooftop items currently shown.
  void updateLabels(List<RoofLabelData> labels) {
    _origin ??= _target;
    for (final l in labels) {
      final url = l.imageUrl;
      if (url != null && url.isNotEmpty) {
        _ensureImageLoaded(url);
      }
    }
    if (!mounted) return;
    setState(() {
      _labels = labels;
    });
  }

  // -----------------------------------------------------------------------
  // Image loading
  // -----------------------------------------------------------------------

  Future<void> _ensureImageLoaded(String url) async {
    if (_imageCache.containsKey(url) || _imageLoading.contains(url)) return;
    _imageLoading.add(url);
    try {
      Uint8List bytes;
      if (url.startsWith('http')) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode} loading $url');
        }
        bytes = response.bodyBytes;
      } else {
        final data = await rootBundle.load(url);
        bytes = data.buffer.asUint8List();
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _imageCache[url] = frame.image;
    } catch (e) {
      debugPrint('Rooftop3DLabelOverlay: failed to load roof image $url: $e');
      _imageCache[url] = null; // mark failed so we stop retrying, fall back to text
    } finally {
      _imageLoading.remove(url);
      if (mounted) setState(() {});
    }
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_labels.isEmpty || _sizePx.width <= 0 || _sizePx.height <= 0) {
      return const SizedBox.shrink();
    }

    final origin = _origin ?? _target;
    final basis = _cameraBasis(_tilt * math.pi / 180.0, _bearing * math.pi / 180.0);
    final distanceMeters = _cameraDistanceMeters();
    final camPos = basis.forward.scaled(-distanceMeters);
    final focalLengthPx = 0.5 * _sizePx.height / math.tan(_fovRadians / 2);

    return CustomPaint(
      size: _sizePx,
      painter: _RoofOverlayPainter(
        labels: _labels,
        origin: origin,
        basis: basis,
        camPos: camPos,
        focalLengthPx: focalLengthPx,
        distanceMeters: distanceMeters,
        sizePx: _sizePx,
        imageCache: _imageCache,
        localMeters: _localMeters,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Camera / projection math (shared with the painter)
  // -----------------------------------------------------------------------

  double _cameraDistanceMeters() {
    final latRad = _target.latitude * math.pi / 180.0;
    final metersPerPixel =
        _earthCircumferenceMeters * math.cos(latRad) / (256 * math.pow(2, _zoom));
    final cameraToCenterPx = 0.5 * _sizePx.height / math.tan(_fovRadians / 2);
    return cameraToCenterPx * metersPerPixel;
  }

  /// Converts a lat/lng into local (east, north) meters relative to
  /// [origin] — equirectangular approximation, accurate enough at the
  /// building/block scale this overlay operates at.
  Offset _localMeters(LatLng origin, double lat, double lng) {
    final latRad = origin.latitude * math.pi / 180.0;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(latRad);
    final east = (lng - origin.longitude) * metersPerDegLng;
    final north = (lat - origin.latitude) * metersPerDegLat;
    return Offset(east, north);
  }

  /// Camera (forward, up, right) basis in local (east, north, up) meters,
  /// from pitch and bearing. At pitch 0 / bearing 0 the camera looks
  /// straight down with screen-up = north — avoids the degenerate
  /// straight-down case a cross-product-with-world-up approach would hit.
  _Basis _cameraBasis(double pitchRad, double bearingRad) {
    const forward0 = _Vec3(0, 0, -1);
    const up0 = _Vec3(0, 1, 0);
    const right0 = _Vec3(1, 0, 0);

    final cosP = math.cos(pitchRad);
    final sinP = math.sin(pitchRad);
    final forwardP = forward0.scaled(cosP) + up0.scaled(sinP);
    final upP = forward0.scaled(-sinP) + up0.scaled(cosP);
    const rightP = right0;

    final cosB = math.cos(bearingRad);
    final sinB = math.sin(bearingRad);
    _Vec3 rotateBearing(_Vec3 v) {
      final e = v.e * cosB + v.n * sinB;
      final n = -v.e * sinB + v.n * cosB;
      return _Vec3(e, n, v.u);
    }

    return _Basis(
      forward: rotateBearing(forwardP),
      up: rotateBearing(upP),
      right: rotateBearing(rightP),
    );
  }
}

class _RoofOverlayPainter extends CustomPainter {
  final List<RoofLabelData> labels;
  final LatLng origin;
  final _Basis basis;
  final _Vec3 camPos;
  final double focalLengthPx;
  final double distanceMeters;
  final Size sizePx;
  final Map<String, ui.Image?> imageCache;
  final Offset Function(LatLng origin, double lat, double lng) localMeters;

  _RoofOverlayPainter({
    required this.labels,
    required this.origin,
    required this.basis,
    required this.camPos,
    required this.focalLengthPx,
    required this.distanceMeters,
    required this.sizePx,
    required this.imageCache,
    required this.localMeters,
  });

  /// Projects a real-world point (lat, lng, heightMeters) to screen space.
  /// Returns null if the point is behind the camera.
  Offset? _project(double lat, double lng, double heightMeters) {
    final local = localMeters(origin, lat, lng);
    final worldPos = _Vec3(local.dx, local.dy, heightMeters);
    final rel = worldPos - camPos;
    final depth = rel.dot(basis.forward);
    if (depth < 5.0) return null;

    final xCam = rel.dot(basis.right);
    final yCam = rel.dot(basis.up);
    final screenX = sizePx.width / 2 + xCam * focalLengthPx / depth;
    final screenY = sizePx.height / 2 - yCam * focalLengthPx / depth;
    return Offset(screenX, screenY);
  }

  double? _depthOf(double lat, double lng, double heightMeters) {
    final local = localMeters(origin, lat, lng);
    final worldPos = _Vec3(local.dx, local.dy, heightMeters);
    return (worldPos - camPos).dot(basis.forward);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Sort far-to-near so nearer roofs/labels draw on top of farther ones.
    final sorted = [...labels]..sort((a, b) {
      final da = _depthOf(a.lat, a.lng, a.roofHeightMeters) ?? double.infinity;
      final db = _depthOf(b.lat, b.lng, b.roofHeightMeters) ?? double.infinity;
      return db.compareTo(da);
    });

    for (final label in sorted) {
      final boundary = label.boundary;
      final image = label.imageUrl != null ? imageCache[label.imageUrl] : null;

      if (image != null && boundary != null && boundary.length >= 3) {
        _paintRoofImage(canvas, label, boundary, image);
      } else {
        _paintTextPill(canvas, label);
      }
    }
  }

  /// Drapes [image] across [boundary] at the roof's real height using
  /// fan-triangulated, texture-mapped triangles (correct perspective
  /// texture mapping via Canvas.drawVertices + ImageShader).
  ///
  /// Fan triangulation assumes a convex-ish polygon (true for most building
  /// footprints); a strongly concave/self-intersecting boundary may show
  /// minor triangulation artifacts.
  void _paintRoofImage(
      Canvas canvas,
      RoofLabelData label,
      List<LatLng> boundaryIn,
      ui.Image image,
      ) {
    // Drop a trailing point that just duplicates the first (common in
    // GeoJSON rings) to avoid a degenerate closing triangle.
    var boundary = boundaryIn;
    if (boundary.length > 3) {
      final first = boundary.first;
      final last = boundary.last;
      if ((first.latitude - last.latitude).abs() < 1e-9 &&
          (first.longitude - last.longitude).abs() < 1e-9) {
        boundary = boundary.sublist(0, boundary.length - 1);
      }
    }
    if (boundary.length < 3) return;

    // Local ENU meters for each boundary point, for UV bounding-box mapping.
    final localPts = boundary.map((p) => localMeters(origin, p.latitude, p.longitude)).toList();
    double minE = localPts.first.dx, maxE = localPts.first.dx;
    double minN = localPts.first.dy, maxN = localPts.first.dy;
    for (final p in localPts) {
      minE = math.min(minE, p.dx);
      maxE = math.max(maxE, p.dx);
      minN = math.min(minN, p.dy);
      maxN = math.max(maxN, p.dy);
    }
    final spanE = (maxE - minE).abs() < 1e-6 ? 1.0 : (maxE - minE);
    final spanN = (maxN - minN).abs() < 1e-6 ? 1.0 : (maxN - minN);

    // Project every boundary vertex; bail if any is behind the camera —
    // roofs are small enough on screen that partial-clipping isn't worth
    // the complexity.
    final screenPts = <Offset>[];
    for (final p in boundary) {
      final s = _project(p.latitude, p.longitude, label.roofHeightMeters);
      if (s == null) return;
      screenPts.add(s);
    }

    // UV per vertex, in image pixel space (top-down: north = image top).
    // If your photos come out mirrored/rotated, flip the (u) or (v) sign
    // here to match how the source photo was shot relative to north.
    final uvPts = <Offset>[];
    for (final p in localPts) {
      final u = (p.dx - minE) / spanE;
      final v = 1.0 - (p.dy - minN) / spanN;
      uvPts.add(Offset(u * image.width, v * image.height));
    }

    // Fan triangulation from vertex 0.
    final positions = <Offset>[];
    final uvs = <Offset>[];
    for (var i = 1; i < boundary.length - 1; i++) {
      positions.addAll([screenPts[0], screenPts[i], screenPts[i + 1]]);
      uvs.addAll([uvPts[0], uvPts[i], uvPts[i + 1]]);
    }
    if (positions.isEmpty) return;

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uvs,
    );

    final paint = Paint()
      ..shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      )
      ..filterQuality = FilterQuality.medium;

    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  void _paintTextPill(Canvas canvas, RoofLabelData label) {
    final screen = _project(label.lat, label.lng, label.roofHeightMeters);
    if (screen == null) return;
    final depth = _depthOf(label.lat, label.lng, label.roofHeightMeters) ?? distanceMeters;
    final scale = (distanceMeters / depth).clamp(0.4, 2.5);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140 * scale);

    const paddingH = 6.0, paddingV = 2.0;
    final pillWidth = textPainter.width + paddingH * 2;
    final pillHeight = textPainter.height + paddingV * 2;

    canvas.save();
    canvas.translate(screen.dx, screen.dy - 12 * scale);
    canvas.scale(scale.toDouble());

    final rect = Rect.fromCenter(center: Offset.zero, width: pillWidth, height: pillHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, Paint()..color = Colors.black.withOpacity(0.55));
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RoofOverlayPainter oldDelegate) => true;
}

class _Basis {
  final _Vec3 forward;
  final _Vec3 up;
  final _Vec3 right;

  const _Basis({required this.forward, required this.up, required this.right});
}

/// Minimal (east, north, up) vector — no dependency on any 3D/WebGL package.
class _Vec3 {
  final double e;
  final double n;
  final double u;

  const _Vec3(this.e, this.n, this.u);

  _Vec3 operator +(_Vec3 other) => _Vec3(e + other.e, n + other.n, u + other.u);
  _Vec3 operator -(_Vec3 other) => _Vec3(e - other.e, n - other.n, u - other.u);
  _Vec3 scaled(double s) => _Vec3(e * s, n * s, u * s);
  double dot(_Vec3 other) => e * other.e + n * other.n + u * other.u;
}