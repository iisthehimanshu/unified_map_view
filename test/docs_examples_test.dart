import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/unified_map_view.dart';

/// Compile-checks the Dart snippets in `docs/map_layers.md` §4 (Recipes).
///
/// Documentation that names a method which no longer exists is worse than no
/// documentation, and nothing else in the suite would catch that — the recipes
/// are prose. So each one is transcribed here as real code.
///
/// [_recipes] is never called: these need a live map, and the point is that the
/// file COMPILES. `flutter test` compiles the whole file, so a renamed
/// parameter or a deleted method fails the suite even though no assertion runs.
/// The snippets that build plain values are exercised for real in [main].
// ignore: unused_element
Future<void> _recipes(UnifiedMapController controller) async {
  // 1. Repaint one layer, keep everything else it draws.
  await controller.setStyleLayer(
    MapStyleLayers.normalPolygons,
    properties: {
      'fill-color': '#ffe8cc',
      'fill-outline-color': '#d9a441',
    },
  );

  // 2. Dim a whole category.
  await controller.setLayer(MapLayer.polygons, opacity: 0.5);

  // 3. Category-wide, with one exception.
  await controller.setLayer(MapLayer.polygons, opacity: 0.5);
  await controller.setStyleLayer(
    MapStyleLayers.normalPolygons,
    opacity: 0.7,
    properties: {'fill-color': 'red'},
  );
  await controller.setLayer(MapLayer.extrusions, visible: false);

  // 4. Hide something, or make it ignore taps.
  await controller.setLayer(MapLayer.furniture, visible: false);
  await controller.setLayer(MapLayer.polygons, tappable: false);

  // 5. Restyle text and the basemap.
  await controller.setStyleLayer(
    MapStyleLayers.sectionMarkers,
    properties: {'text-size': 15, 'text-halo-width': 1.5},
  );
  await controller.setStyleLayer(
    MapStyleLayers.baseMapRaster,
    properties: {'raster-opacity': 0.85},
  );

  // 6. Raw properties on a whole group, from Dart.
  await controller.updateLayers(const MapLayerPolicy({
    MapLayer.polygons: MapLayerState(
      properties: {'fill-outline-color': '#333333'},
    ),
  }));

  // 7. Values can be expressions, not just literals.
  await controller.setStyleLayer(
    MapStyleLayers.normalPolygons,
    properties: {
      'fill-color': ['get', 'fillColor']
    },
  );

  // 8. Undo.
  await controller.setStyleLayer(
    MapStyleLayers.normalPolygons,
    clearProperties: true,
    clearOpacity: true,
  );
  await controller.resetLayers();

  // 10. Re-apply a config while the app is running.
  final config = await MapStyleConfig.fromAsset('assets/map_config.yaml');
  await controller.applyStyleConfig(config);

  // The global switches named in §0.
  await controller.setGreyscale(true);
  await controller.setFade(false);
  await controller.showMarkerTypes({MarkerTypes.washroom});
  await controller.clearMarkerTypeFilter();
}

void main() {
  group('docs/map_layers.md recipes', () {
    test('§0 the two ways to name a layer resolve as documented', () {
      // "MapStyleLayers.normalPolygons is just a typo-safe constant for the
      // string 'normal-polygons-layer' — the same name you would write in the
      // YAML."
      expect(MapStyleLayers.normalPolygons, 'normal-polygons-layer');
      expect(MapStyleLayers.sectionMarkers, 'section-markers-layer');
      expect(MapStyleLayers.baseMapRaster, 'osm-tiles-layer');
    });

    test('recipe 3: the YAML and the Dart form produce the same policy', () {
      final fromYaml = MapStyleConfig.parse('''
layers:
  polygons:
    opacity: 0.5
  normal-polygons-layer:
    opacity: 0.7
    fill-color: red
  extrusions:
    visible: false
''').layers;

      // The Dart form of the same three calls, applied in order.
      var fromDart = MapLayerPolicy.all
          .withGroup(MapLayer.polygons, const MapLayerState(opacity: 0.5))
          .withLayer(
            MapStyleLayers.normalPolygons,
            const MapLayerState(
              opacity: 0.7,
              properties: {'fill-color': 'red'},
            ),
          )
          .withGroup(MapLayer.extrusions, const MapLayerState(visible: false));

      expect(fromDart, fromYaml);

      // And the outcome the prose claims: the unnamed sibling falls through to
      // the family at 0.5 with no colour of its own.
      final sibling = fromYaml.resolveLayer(
          MapStyleLayers.patternPolygons, MapLayer.rooms);
      expect(sibling.opacity, 0.5);
      expect(sibling.properties, isEmpty);

      final named = fromYaml.resolveLayer(
          MapStyleLayers.normalPolygons, MapLayer.rooms);
      expect(named.opacity, 0.7);
      expect(named.properties, {'fill-color': 'red'});

      expect(
          fromYaml
              .resolveLayer(MapStyleLayers.extrudedPolygon, MapLayer.extrusions)
              .visible,
          isFalse);
    });

    test('§0 "calls merge; they do not reset"', () {
      final merged = MapLayerPolicy.all
          .withLayer(MapStyleLayers.normalPolygons,
              const MapLayerState(properties: {'fill-color': 'red'}))
          .merge(MapLayerPolicy.all.withLayer(
              MapStyleLayers.normalPolygons,
              const MapLayerState(
                  properties: {'fill-outline-color': 'black'})));

      expect(merged.layers[MapStyleLayers.normalPolygons]!.properties, {
        'fill-color': 'red',
        'fill-outline-color': 'black',
      });
    });

    test('recipe 8: clearProperties/clearOpacity undo what null cannot', () {
      const state = MapLayerState(
          opacity: 0.7, properties: {'fill-color': 'red'});
      final cleared =
          state.copyWith(clearProperties: true, clearOpacity: true);
      expect(cleared.properties, isEmpty);
      expect(cleared.opacity, isNull);
    });
  });
}
