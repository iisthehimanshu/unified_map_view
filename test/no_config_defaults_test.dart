import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/models/map_layer.dart';
import 'package:unified_map_view/src/models/map_style_config.dart';

/// Pins the contract that matters most: **a host that passes no config gets the
/// map it had before any of this existed.**
///
/// The per-layer feature is opt-in at every level, and each level has one guard
/// that must keep holding:
///
/// * `MapLayerPolicy.all` is empty, so every layer resolves to
///   `MapLayerState.defaults` — the same value `_stateForLayer` returned when it
///   read `_policy.resolve(group)` and nothing else.
/// * `defaults.properties` is empty, and `_withStyleOverrides` early-returns the
///   builder's own object untouched on an empty override map — no json
///   round-trip, no rebuilt property set, nothing sent that was not sent before.
/// * `defaults.opacity` is null, so `_layerProps`' resolver is the identity and
///   every layer keeps the renderer's own opacity expression, zoom fade ramp
///   included.
void main() {
  group('no config passed', () {
    test('the default policy is empty at both tiers', () {
      expect(MapLayerPolicy.all.isEmpty, isTrue);
      expect(MapLayerPolicy.all.states, isEmpty);
      expect(MapLayerPolicy.all.layers, isEmpty);
    });

    test('every style layer resolves to exactly the old defaults', () {
      // Covers the ids that belong to a group and the ones that do not (the
      // basemap raster), since those took different branches before.
      for (final layerId in MapStyleLayers.known) {
        for (final group in [null, ...MapLayer.values]) {
          final state = MapLayerPolicy.all.resolveLayer(layerId, group);
          expect(state, MapLayerState.defaults,
              reason: '$layerId (group: $group) is not at defaults');
          // Spelled out, because these three are what the provider branches on.
          expect(state.opacity, isNull, reason: '$layerId gained an opacity');
          expect(state.properties, isEmpty,
              reason: '$layerId gained a style override');
          expect(state.visible, isTrue);
          expect(state.tappable, isTrue);
        }
      }
    });

    test('an empty override map normalises to empty, so the merge is skipped',
        () {
      // The guard in _withStyleOverrides is `if (overrides.isEmpty) return
      // built;` — this is the input that has to reach it for every layer when no
      // config is passed.
      expect(MapLayerState.normalizeKeys(MapLayerState.defaults.properties),
          isEmpty);
      expect(MapLayerState.normalizeKeys(const {}), isEmpty);
    });

    test('the group tier still behaves exactly as it did', () {
      // Unchanged from the original map_layer_test expectations — per-layer
      // entries must not have leaked into group resolution.
      expect(MapLayerPolicy.all.resolve(MapLayer.rooms), MapLayerState.defaults);
      expect(MapLayerPolicy.polygonsOnly.resolve(MapLayer.landmarkMarkers).visible,
          isFalse);
      expect(MapLayerPolicy.polygonsOnly.resolve(MapLayer.rooms).visible, isTrue);
      expect(MapLayerPolicy.polygonsOnly.resolve(MapLayer.userLocation).visible,
          isTrue);
    });

    test('MapStyleConfig.none asks for nothing', () {
      const config = MapStyleConfig.none;
      expect(config.isEmpty, isTrue);
      expect(config.layers.isEmpty, isTrue);
      // Null, not false: "the file did not say" is distinct from "the file said
      // off". Only a non-null value is ever pushed to the provider, so a config
      // that omits a mode leaves the renderer's own default alone.
      expect(config.immersive, isNull);
      expect(config.greyscale, isNull);
      expect(config.fade, isNull);
      expect(config.symbolsSpecified, isFalse);
      expect(config.symbolTypes, isNull);
    });

    test('a config naming one layer leaves every other layer at defaults', () {
      final config = MapStyleConfig.parse('''
layers:
  normal-polygons-layer:
    fill-color: red
''');
      final policy = config.layers;

      // The named layer changed.
      expect(
          policy
              .resolveLayer(MapStyleLayers.normalPolygons, MapLayer.rooms)
              .properties,
          {'fill-color': 'red'});

      // Nothing else did — including its own sibling in the same member, and
      // the basemap the config never mentions.
      for (final layerId in MapStyleLayers.known) {
        if (layerId == MapStyleLayers.normalPolygons) continue;
        expect(policy.resolveLayer(layerId, null), MapLayerState.defaults,
            reason: '$layerId was disturbed by a config that never named it');
      }
    });
  });
}
