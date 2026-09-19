import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/models/geojson_models.dart';

/// A square ring, so `GeoJsonPolygon.fromFeature` accepts the geometry.
const _ring = [
  [78.412, 17.414],
  [78.413, 17.414],
  [78.413, 17.415],
  [78.412, 17.415],
  [78.412, 17.414],
];

Map<String, dynamic> _polygonJson(
  String id, {
  List<String>? associatedTopLevel,
  List<String>? associatedInProperties,
}) =>
    {
      'id': id,
      'building_ID': 'b1',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [_ring],
      },
      'properties': {
        'type': 'Room',
        if (associatedInProperties != null)
          'associatedPolygons': associatedInProperties,
      },
      if (associatedTopLevel != null) 'associatedPolygons': associatedTopLevel,
    };

void main() {
  group('associatedPolygons parsing', () {
    // Polygon features carry it at the TOP level and nowhere else, which is why
    // it cannot be read through `properties` like everything else.
    test('is read from the top level of a polygon feature', () {
      final feature = GeoJsonFeature.fromJson(_polygonJson(
        'point-7ypw8j7',
        associatedTopLevel: const [
          'point-7ypw8j7wall0',
          'point-7ypw8j7wall1',
          'point-7ypw8j7wall2',
        ],
      ));

      expect(feature.associatedPolygons, [
        'point-7ypw8j7wall0',
        'point-7ypw8j7wall1',
        'point-7ypw8j7wall2',
      ]);
    });

    // Point features put it in both places; properties is the one the marker
    // path already reads, so it has to keep working.
    test('falls back to properties when the top level has none', () {
      final feature = GeoJsonFeature.fromJson(_polygonJson(
        'point-7ypw8j7wall0',
        associatedInProperties: const ['point-7ypw8j7'],
      ));

      expect(feature.associatedPolygons, ['point-7ypw8j7']);
    });

    test('is empty, not null, when the feature has no links', () {
      final feature = GeoJsonFeature.fromJson(_polygonJson('point-standalone'));

      expect(feature.associatedPolygons, isEmpty);
    });

    test('survives the hop onto GeoJsonPolygon', () {
      final polygon = GeoJsonPolygon.fromFeature(GeoJsonFeature.fromJson(
        _polygonJson(
          'point-7ypw8j7',
          associatedTopLevel: const ['point-7ypw8j7wall0'],
        ),
      ));

      expect(polygon, isNotNull);
      expect(polygon!.associatedPolygonIds, ['point-7ypw8j7wall0']);
    });

    test('a room and its wall point at each other, so either can start the '
        'walk', () {
      final room = GeoJsonPolygon.fromFeature(GeoJsonFeature.fromJson(
        _polygonJson('point-7ypw8j7',
            associatedTopLevel: const ['point-7ypw8j7wall0']),
      ))!;
      final wall = GeoJsonPolygon.fromFeature(GeoJsonFeature.fromJson(
        _polygonJson('point-7ypw8j7wall0',
            associatedTopLevel: const ['point-7ypw8j7']),
      ))!;

      expect(room.associatedPolygonIds, contains('point-7ypw8j7wall0'));
      expect(wall.associatedPolygonIds, contains('point-7ypw8j7'));
    });
  });
}
