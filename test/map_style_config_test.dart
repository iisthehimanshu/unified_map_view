import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:unified_map_view/src/models/map_layer.dart';
import 'package:unified_map_view/src/models/map_style_config.dart';

void main() {
  group('per-layer style properties', () {
    test('unspecified properties fall through to the renderer', () {
      const policy = MapLayerPolicy({}, {
        MapStyleLayers.normalPolygons: MapLayerState(
          properties: {'fill-color': 'red'},
        ),
      });

      final state =
          policy.resolveLayer(MapStyleLayers.normalPolygons, MapLayer.rooms);
      expect(state.properties, {'fill-color': 'red'});
      // Only what was named is carried; nothing else is invented, so the
      // provider keeps its own value for every other property.
      expect(state.opacity, isNull);
      expect(state.visible, isTrue);
      expect(state.tappable, isTrue);
    });

    test('layer id wins over member, member over family, family over default',
        () {
      const policy = MapLayerPolicy({
        MapLayer.polygons: MapLayerState(
          opacity: 0.2,
          properties: {'fill-color': 'blue', 'fill-outline-color': 'black'},
        ),
        MapLayer.rooms: MapLayerState(
          opacity: 0.5,
          properties: {'fill-color': 'green'},
        ),
      }, {
        MapStyleLayers.normalPolygons: MapLayerState(
          opacity: 0.7,
          properties: {'fill-color': 'red'},
        ),
      });

      final rooms =
          policy.resolveLayer(MapStyleLayers.normalPolygons, MapLayer.rooms);
      expect(rooms.opacity, 0.7);
      expect(rooms.properties['fill-color'], 'red');
      // Merged per key rather than replaced wholesale: the family's outline
      // colour survives the member's and the layer's fill-colour overrides.
      expect(rooms.properties['fill-outline-color'], 'black');

      // A sibling layer in the same member sees the member's value, not the
      // one set on normal-polygons-layer.
      final pattern =
          policy.resolveLayer(MapStyleLayers.patternPolygons, MapLayer.rooms);
      expect(pattern.opacity, 0.5);
      expect(pattern.properties['fill-color'], 'green');

      // A different member of the same family sees only the family's.
      final extrusions = policy.resolveLayer(
          MapStyleLayers.extrudedPolygon, MapLayer.extrusions);
      expect(extrusions.opacity, 0.2);
      expect(extrusions.properties['fill-color'], 'blue');
    });

    test('a layer outside the taxonomy is still addressable by id', () {
      const policy = MapLayerPolicy({}, {
        MapStyleLayers.baseMapRaster:
            MapLayerState(properties: {'raster-saturation': -1.0}),
      });
      final state = policy.resolveLayer(MapStyleLayers.baseMapRaster, null);
      expect(state.properties['raster-saturation'], -1.0);
    });

    test('resolve() is group-level and ignores per-layer entries', () {
      const policy = MapLayerPolicy({}, {
        MapStyleLayers.normalPolygons: MapLayerState(visible: false),
      });
      // Hiding one style layer must not read as "the rooms group is hidden" —
      // pattern-filled rooms are still drawn.
      expect(policy.resolve(MapLayer.rooms).visible, isTrue);
      expect(
          policy
              .resolveLayer(MapStyleLayers.patternPolygons, MapLayer.rooms)
              .visible,
          isTrue);
      expect(
          policy
              .resolveLayer(MapStyleLayers.normalPolygons, MapLayer.rooms)
              .visible,
          isFalse);
    });

    test('camelCase and kebab-case keys are the same key', () {
      expect(MapLayerState.normalizeKey('fillColor'), 'fill-color');
      expect(MapLayerState.normalizeKey('iconHaloWidth'), 'icon-halo-width');
      // Idempotent, so normalising twice is safe.
      expect(MapLayerState.normalizeKey('fill-color'), 'fill-color');
    });

    test('merge combines both group and layer entries field-wise', () {
      const base = MapLayerPolicy({
        MapLayer.rooms: MapLayerState(opacity: 0.5),
      }, {
        MapStyleLayers.normalPolygons:
            MapLayerState(properties: {'fill-color': 'red'}),
      });
      const patch = MapLayerPolicy({
        MapLayer.rooms: MapLayerState(tappable: false),
      }, {
        MapStyleLayers.normalPolygons:
            MapLayerState(properties: {'fill-outline-color': 'black'}),
      });

      final merged = base.merge(patch);
      expect(merged.states[MapLayer.rooms]!.opacity, 0.5);
      expect(merged.states[MapLayer.rooms]!.tappable, isFalse);
      expect(merged.layers[MapStyleLayers.normalPolygons]!.properties, {
        'fill-color': 'red',
        'fill-outline-color': 'black',
      });
    });

    test('clearProperties drops overrides; an empty map adds nothing', () {
      const state = MapLayerState(properties: {'fill-color': 'red'});
      expect(state.copyWith(properties: const {}).properties,
          {'fill-color': 'red'});
      expect(state.copyWith(clearProperties: true).properties, isEmpty);
    });
  });

  group('MapStyleConfig.parse', () {
    test('parses the shape the spec documents', () {
      final config = MapStyleConfig.parse('''
immersive: true
greyscale: false
fade: true

symbols:
  mode: only
  types:
    - washroom
    - lift

layers:
  polygons:           { visible: true, tappable: true }
  rooms:              { visible: true, opacity: 1.0, tappable: true }
  normal-polygons-layer:
    opacity: 0.7
    fill-color: red
    fill-outline-color: "#990000"
''');

      expect(config.warnings, isEmpty);
      expect(config.immersive, isTrue);
      expect(config.greyscale, isFalse);
      expect(config.fade, isTrue);
      expect(config.symbolsSpecified, isTrue);
      expect(config.symbolTypes, {'washroom', 'lift'});

      expect(config.layers.states[MapLayer.polygons]!.tappable, isTrue);
      expect(config.layers.states[MapLayer.rooms]!.opacity, 1.0);

      final layer = config.layers.layers[MapStyleLayers.normalPolygons]!;
      expect(layer.opacity, 0.7);
      expect(layer.properties, {
        'fill-color': 'red',
        'fill-outline-color': '#990000',
      });
      // visible/tappable were never named, so they stay unspecified and the
      // renderer's default stands.
      expect(layer.visible, isNull);
      expect(layer.tappable, isNull);
    });

    test('keys the file omits are left alone rather than defaulted', () {
      final config = MapStyleConfig.parse('greyscale: true');
      expect(config.greyscale, isTrue);
      expect(config.fade, isNull);
      expect(config.immersive, isNull);
      expect(config.symbolsSpecified, isFalse);
      expect(config.layers.isEmpty, isTrue);
    });

    test('mode: all is distinguishable from no symbols block at all', () {
      final all = MapStyleConfig.parse('symbols:\n  mode: all');
      expect(all.symbolsSpecified, isTrue);
      expect(all.symbolTypes, isNull);

      final none = MapStyleConfig.parse('greyscale: true');
      expect(none.symbolsSpecified, isFalse);
    });

    test('style property values may be expressions, not just literals', () {
      final config = MapStyleConfig.parse('''
layers:
  normal-polygons-layer:
    fill-color: ["get", "fillColor"]
    fill-translate: [2, 4]
''');
      expect(config.warnings, isEmpty);
      final layer = config.layers.layers[MapStyleLayers.normalPolygons]!;
      expect(layer.properties['fill-color'], ['get', 'fillColor']);
      expect(layer.properties['fill-translate'], [2, 4]);
      // Plain Dart lists, not YamlList views — those do not survive the
      // platform-channel encoding a style property goes through.
      expect(layer.properties['fill-color'], isA<List<Object?>>());
    });

    test('camelCase property keys are normalised at parse time', () {
      final config = MapStyleConfig.parse('''
layers:
  normal-polygons-layer:
    fillColor: red
''');
      expect(config.layers.layers[MapStyleLayers.normalPolygons]!.properties,
          {'fill-color': 'red'});
    });

    test('a bad value warns and is skipped, the rest of the file still applies',
        () {
      final config = MapStyleConfig.parse('''
greyscale: "yes"
layers:
  rooms:
    visible: maybe
    opacity: 0.4
  nonsense-layer:
    fill-color: red
''');
      expect(config.greyscale, isNull);
      expect(config.layers.states[MapLayer.rooms]!.visible, isNull);
      expect(config.layers.states[MapLayer.rooms]!.opacity, 0.4);
      // An unrecognised layer id is applied anyway — it may be a layer the host
      // added itself — but it is reported.
      expect(config.layers.layers['nonsense-layer']!.properties,
          {'fill-color': 'red'});
      expect(config.warnings, hasLength(3));
    });

    test('visibility is rejected in favour of visible', () {
      final config = MapStyleConfig.parse('''
layers:
  normal-polygons-layer:
    visibility: none
''');
      expect(config.layers.layers[MapStyleLayers.normalPolygons]!.properties,
          isEmpty);
      expect(config.warnings.single, contains('visibility'));
    });

    test('opacity is clamped to the documented range', () {
      final config = MapStyleConfig.parse('layers:\n  rooms:\n    opacity: 4');
      expect(config.layers.states[MapLayer.rooms]!.opacity, 1.0);
    });

    test('JSON parses through the same loader', () {
      final config = MapStyleConfig.parse(
          '{"greyscale": true, "layers": {"rooms": {"opacity": 0.5}}}');
      expect(config.greyscale, isTrue);
      expect(config.layers.states[MapLayer.rooms]!.opacity, 0.5);
    });

    test('an empty document is a config that changes nothing', () {
      expect(MapStyleConfig.parse('').isEmpty, isTrue);
      expect(MapStyleConfig.parse('# just a comment').isEmpty, isTrue);
    });

    test('a non-mapping document is a hard error', () {
      expect(() => MapStyleConfig.parse('- a\n- b'), throwsFormatException);
    });
  });

  // The provider merges style overrides on the SERIALISED form and rebuilds
  // through fromJson, because a builder returns a typed LayerProperties whose
  // fields cannot be reached by name. These pin the two assumptions that makes.
  group('LayerProperties json round-trip (what _withStyleOverrides relies on)',
      () {
    test('toJson/fromJson names the same keys and loses nothing', () {
      final built = FillLayerProperties(
        fillColor: const ['get', 'fillColor'],
        fillOutlineColor: const ['get', 'strokeColor'],
        fillOpacity: 0.4,
        visibility: 'visible',
      );
      final round =
          FillLayerProperties.fromJson(built.toJson(skipNulls: false));
      expect(round.toJson(), built.toJson());
    });

    test('an override replaces one key and leaves the rest standing', () {
      final built = FillLayerProperties(
        fillColor: const ['get', 'fillColor'],
        fillOutlineColor: const ['get', 'strokeColor'],
        fillOpacity: 0.4,
        visibility: 'visible',
      );

      final json = built.toJson(skipNulls: false);
      final visibility = json['visibility'];
      json.addAll(MapLayerState.normalizeKeys(const {'fillColor': 'red'}));
      json['visibility'] = visibility;
      final merged = FillLayerProperties.fromJson(json);

      expect(merged.fillColor, 'red');
      // Everything the config did not name is exactly what the renderer built.
      expect(merged.fillOutlineColor, const ['get', 'strokeColor']);
      expect(merged.fillOpacity, 0.4);
      expect(merged.visibility, 'visible');
    });

    test('every layer type the provider builds survives the round-trip', () {
      final cases = <LayerProperties>[
        SymbolLayerProperties(textField: 'x', iconOpacity: 0.5),
        CircleLayerProperties(circleRadius: 12.0, circleColor: '#4CAF50'),
        LineLayerProperties(lineWidth: 2.0, lineColor: '#000'),
        FillLayerProperties(fillOpacity: 0.4),
        FillExtrusionLayerProperties(fillExtrusionOpacity: 0.9),
        RasterLayerProperties(rasterSaturation: -1.0),
      ];
      for (final built in cases) {
        final json = built.toJson(skipNulls: false);
        final merged = switch (built) {
          SymbolLayerProperties _ => SymbolLayerProperties.fromJson(json),
          CircleLayerProperties _ => CircleLayerProperties.fromJson(json),
          LineLayerProperties _ => LineLayerProperties.fromJson(json),
          FillLayerProperties _ => FillLayerProperties.fromJson(json),
          FillExtrusionLayerProperties _ =>
            FillExtrusionLayerProperties.fromJson(json),
          RasterLayerProperties _ => RasterLayerProperties.fromJson(json),
          _ => built,
        };
        expect(merged.runtimeType, built.runtimeType);
        expect(merged.toJson(), built.toJson(),
            reason: '${built.runtimeType} did not survive the round-trip');
      }
    });
  });
}
