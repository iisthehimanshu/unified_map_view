import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/models/map_layer.dart';
import 'package:unified_map_view/src/models/map_style_config.dart';

/// The two config files shipped in the repo are the format's documentation, and
/// a key that no longer parses documents the wrong thing. These read the real
/// files rather than a copy, so an edit that breaks one fails here.
void main() {
  for (final path in const [
    'example/assets/map_config.yaml',
    'docs/map_config.example.yaml',
  ]) {
    test('$path parses with no warnings', () {
      final config = MapStyleConfig.parse(File(path).readAsStringSync());
      expect(config.warnings, isEmpty,
          reason: '$path produced loader warnings');
      expect(config.isEmpty, isFalse);
    });
  }

  test('the example app config sets what its comments claim', () {
    final config = MapStyleConfig.parse(
        File('example/assets/map_config.yaml').readAsStringSync());

    expect(config.immersive, isTrue);
    expect(config.greyscale, isFalse);
    expect(config.fade, isTrue);
    expect(config.symbolsSpecified, isTrue);
    expect(config.symbolTypes, isNull); // mode: all

    // Group tier.
    expect(config.layers.states[MapLayer.markers]!.visible, isTrue);
    expect(config.layers.states[MapLayer.subSectionLabels]!.opacity, 0.9);

    // Layer tier, including one layer outside the group taxonomy.
    final rooms =
        config.layers.layers[MapStyleLayers.normalPolygons]!.properties;
    expect(rooms['fill-color'], '#ffe8cc');
    final basemap =
        config.layers.layers[MapStyleLayers.baseMapRaster]!.properties;
    expect(basemap['raster-opacity'], 0.85);

    // The sibling of normal-polygons-layer is deliberately NOT named, so it
    // resolves through `rooms` to `polygons` and keeps the renderer's colour.
    final sibling = config.layers
        .resolveLayer(MapStyleLayers.patternPolygons, MapLayer.rooms);
    expect(sibling.properties, isEmpty);
    expect(sibling.visible, isTrue);
  });
}
