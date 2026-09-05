import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/models/map_layer.dart';

void main() {
  group('MapLayer taxonomy', () {
    test('every group is either a family or a member of exactly one family', () {
      for (final group in MapLayer.values) {
        if (group.isFamily) {
          expect(group.family, isNull);
        } else {
          expect(group.family, isNotNull, reason: '$group has no family');
          expect(group.family!.members, contains(group));
        }
      }
    });

    test('members are leaves and families expand to their members', () {
      expect(MapLayer.markers.leaves, MapLayer.markers.members);
      expect(MapLayer.rooms.leaves, [MapLayer.rooms]);
      // Families with no members are their own leaf.
      expect(MapLayer.furniture.leaves, [MapLayer.furniture]);
      expect(MapLayer.userLocation.leaves, [MapLayer.userLocation]);
      expect(MapLayer.selection.leaves, [MapLayer.selection]);
    });

    test('userLocation and selection are not part of markers or polygons', () {
      expect(MapLayer.markers.members, isNot(contains(MapLayer.userLocation)));
      expect(MapLayer.markers.members, isNot(contains(MapLayer.selection)));
      expect(MapLayer.polygons.members, isNot(contains(MapLayer.selection)));
    });

    test('generic polylines are separate from the route line', () {
      // route: hidden must still hide them, but they can be controlled alone.
      expect(MapLayer.polylines.family, MapLayer.route);
      expect(MapLayer.routeLine.family, MapLayer.route);
      expect(MapLayer.polylines, isNot(MapLayer.routeLine));
    });
  });

  group('MapLayerPolicy.resolve', () {
    test('an unmentioned group gets the defaults', () {
      const policy = MapLayerPolicy();
      final state = policy.resolve(MapLayer.rooms);
      expect(state.visible, isTrue);
      expect(state.tappable, isTrue);
      expect(state.opacity, isNull);
    });

    test('a family value reaches its members', () {
      const policy = MapLayerPolicy({MapLayer.markers: MapLayerState.hidden});
      expect(policy.resolve(MapLayer.landmarkMarkers).visible, isFalse);
      expect(policy.resolve(MapLayer.venueLabel).visible, isFalse);
      // and does not leak to another family
      expect(policy.resolve(MapLayer.rooms).visible, isTrue);
    });

    test('a member overrides its family per field, not wholesale', () {
      const policy = MapLayerPolicy({
        MapLayer.polygons: MapLayerState(opacity: 0.4),
        MapLayer.rooms: MapLayerState(visible: false),
      });
      final rooms = policy.resolve(MapLayer.rooms);
      expect(rooms.visible, isFalse);
      // the family's opacity survives the member's visibility override
      expect(rooms.opacity, 0.4);

      final sections = policy.resolve(MapLayer.sections);
      expect(sections.visible, isTrue);
      expect(sections.opacity, 0.4);
    });

    test('hiding markers leaves the user puck and selection alone', () {
      const policy = MapLayerPolicy({MapLayer.markers: MapLayerState.hidden});
      expect(policy.resolve(MapLayer.userLocation).visible, isTrue);
      expect(policy.resolve(MapLayer.selection).visible, isTrue);
    });
  });

  group('presets', () {
    test('polygonsOnly hides markers but keeps polygons tappable', () {
      const p = MapLayerPolicy.polygonsOnly;
      expect(p.resolve(MapLayer.landmarkMarkers).visible, isFalse);
      expect(p.resolve(MapLayer.rooms).visible, isTrue);
      expect(p.resolve(MapLayer.rooms).tappable, isTrue);
      // the puck survives, so navigation still shows the user
      expect(p.resolve(MapLayer.userLocation).visible, isTrue);
    });

    test('polygonsOnlyNoTap keeps polygons visible but inert', () {
      const p = MapLayerPolicy.polygonsOnlyNoTap;
      expect(p.resolve(MapLayer.landmarkMarkers).visible, isFalse);
      expect(p.resolve(MapLayer.rooms).visible, isTrue);
      expect(p.resolve(MapLayer.rooms).tappable, isFalse);
      expect(p.resolve(MapLayer.sections).tappable, isFalse);
      expect(p.resolve(MapLayer.extrusions).tappable, isFalse);
    });

    test('markersOnly hides polygons and route', () {
      const p = MapLayerPolicy.markersOnly;
      expect(p.resolve(MapLayer.rooms).visible, isFalse);
      expect(p.resolve(MapLayer.routeLine).visible, isFalse);
      expect(p.resolve(MapLayer.landmarkMarkers).visible, isTrue);
    });

    test('all is the empty policy', () {
      expect(MapLayerPolicy.all.isEmpty, isTrue);
      for (final leaf in MapLayer.allLeaves) {
        expect(MapLayerPolicy.all.resolve(leaf).visible, isTrue);
        expect(MapLayerPolicy.all.resolve(leaf).tappable, isTrue);
        expect(MapLayerPolicy.all.resolve(leaf).opacity, isNull);
      }
    });
  });

  group('mutation', () {
    test('merge is field-wise and the patch wins', () {
      const base = MapLayerPolicy({
        MapLayer.rooms: MapLayerState(visible: false, opacity: 0.5),
      });
      const patch = MapLayerPolicy({
        MapLayer.rooms: MapLayerState(tappable: false),
      });
      final merged = base.merge(patch);
      final rooms = merged.resolve(MapLayer.rooms);
      expect(rooms.visible, isFalse);
      expect(rooms.opacity, 0.5);
      expect(rooms.tappable, isFalse);
    });

    test('clearOpacity drops an override that null cannot express', () {
      const state = MapLayerState(visible: false, opacity: 0.5);
      expect(state.copyWith(opacity: null).opacity, 0.5);
      expect(state.copyWith(clearOpacity: true).opacity, isNull);
      // and it leaves the other fields alone
      expect(state.copyWith(clearOpacity: true).visible, isFalse);
    });

    test('equality is by value, so a no-op push can be skipped', () {
      const a = MapLayerPolicy({MapLayer.rooms: MapLayerState(opacity: 0.5)});
      const b = MapLayerPolicy({MapLayer.rooms: MapLayerState(opacity: 0.5)});
      expect(a, equals(b));
      expect(a.withGroup(MapLayer.rooms, const MapLayerState(opacity: 0.6)),
          isNot(equals(b)));
    });
  });
}
