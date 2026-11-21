// Wall-image demo for the maplibre_gl fork in third_party/maplibre_gl.
//
// Run with:  flutter run -t lib/wall_image_demo.dart
//
// Draws two buildings (fill-extrusions) and two wall images:
//  * "poster" on the south face of the big building, partly hidden by the
//    small building in front of it (checks depth against extrusions);
//  * "sign", a free-standing single-sided wall (seen from behind it should
//    disappear).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() => runApp(const MaterialApp(home: WallImageDemo()));

const _origin = LatLng(28.6139, 77.2090);

/// Offset from [_origin] in metres east and north.
LatLng _at(double east, double north) {
  const mPerDegLat = 111320.0;
  final mPerDegLng = mPerDegLat * math.cos(_origin.latitude * math.pi / 180);
  return LatLng(_origin.latitude + north / mPerDegLat, _origin.longitude + east / mPerDegLng);
}

List<List<double>> _box(double w, double s, double e, double n) {
  final ring = [_at(w, s), _at(e, s), _at(e, n), _at(w, n), _at(w, s)];
  return [for (final p in ring) [p.longitude, p.latitude]];
}

Map<String, dynamic> _building(String id, List<List<double>> ring, double height, String color) => {
      'type': 'Feature',
      'id': id,
      'properties': {'height': height, 'color': color},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
    };

final _style = jsonEncode({
  'version': 8,
  'sources': {
    'buildings': {
      'type': 'geojson',
      'data': {
        'type': 'FeatureCollection',
        'features': [
          _building('big', _box(-10, 0, 10, 12), 15, '#aab4c3'),
          _building('front', _box(-6, -10, -1, -7), 10, '#d08a5a'),
        ],
      },
    },
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#e9efe6'},
    },
    {
      'id': 'buildings',
      'type': 'fill-extrusion',
      'source': 'buildings',
      'paint': {
        'fill-extrusion-color': ['get', 'color'],
        'fill-extrusion-height': ['get', 'height'],
        'fill-extrusion-opacity': 1.0,
      },
    },
  ],
});

class WallImageDemo extends StatefulWidget {
  const WallImageDemo({super.key});

  @override
  State<WallImageDemo> createState() => _WallImageDemoState();
}

class _WallImageDemoState extends State<WallImageDemo> {
  MapLibreMapController? _controller;
  String _status = 'Loading…';

  Future<void> _addWalls() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final poster = await _renderImage('POSTER', const Color(0xFF1E6FD9), const Color(0xFFF2B33D));
      final sign = await _renderImage('SIGN', const Color(0xFF2E9E5B), const Color(0xFFFFFFFF));

      // Big building's south face is at north = 0; sit 30 cm in front of it.
      // West → east, so from the south `start` is on the left.
      await controller.addWallImage(
        id: 'poster',
        start: _at(-8, -0.3),
        end: _at(8, -0.3),
        baseMeters: 3,
        heightMeters: 8,
        imageBytes: poster,
      );
      await controller.addWallImage(
        id: 'sign',
        start: _at(16, -4),
        end: _at(26, -4),
        heightMeters: 5,
        imageBytes: sign,
        doubleSided: false,
        opacity: 0.9,
      );
      setState(() => _status = 'Walls added');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    }
  }

  Future<void> _view(double bearing) async {
    await _controller?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: _at(4, -2),
      zoom: 18.6,
      tilt: 60,
      bearing: bearing,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _style,
            initialCameraPosition: CameraPosition(target: _at(4, -2), zoom: 18.6, tilt: 60),
            onMapCreated: (c) => _controller = c,
            onStyleLoadedCallback: _addWalls,
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_status, key: const Key('wall-status')),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: () => _view(0), child: const Text('Front')),
                        FilledButton(onPressed: () => _view(70), child: const Text('Side')),
                        FilledButton(onPressed: () => _view(180), child: const Text('Back')),
                        OutlinedButton(
                          onPressed: () async {
                            await _controller?.removeWallImage('poster');
                            setState(() => _status = 'Poster removed');
                          },
                          child: const Text('Remove'),
                        ),
                        OutlinedButton(onPressed: _addWalls, child: const Text('Add')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 2:1 test image with a label, an arrow pointing to the start edge, and a
/// transparent hole in one corner to check alpha.
Future<Uint8List> _renderImage(String label, Color background, Color accent) async {
  const w = 1024.0, h = 512.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(w, h), [background, background.withValues(alpha: 0.7)]),
  );
  canvas.drawRect(
    const Rect.fromLTWH(12, 12, w - 24, h - 24),
    Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24,
  );
  final text = TextPainter(
    text: TextSpan(
      text: '◀ START   $label',
      style: TextStyle(color: accent, fontSize: 120, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w - 80);
  text.paint(canvas, Offset((w - text.width) / 2, (h - text.height) / 2));
  canvas.drawCircle(const Offset(w - 90, 90), 50, Paint()..blendMode = BlendMode.clear);
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
