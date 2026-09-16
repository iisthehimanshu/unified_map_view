import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/VenueManager/VenueData.dart';
import 'package:unified_map_view/src/apimodels/BuildingData.dart';
import 'package:unified_map_view/unified_map_view.dart';

Map<String, dynamic> _building(String id) => {
      '_id': id,
      'initialBuildingName': id,
      'initialVenueName': 'Venue',
      'buildingName': id,
      'venueName': 'Venue',
      'coordinates': [28.54, 77.19],
      'address': '',
      'liveStatus': true,
      'geofencing': false,
      'description': '',
      'locked': false,
      'createdAt': '',
      'updatedAt': '',
      '__v': 0,
      'globalAnnotation': false,
      'boundary': [],
    };

Map<String, dynamic> _feature(String? buildingId, String id) => {
      'id': id,
      'building_ID': buildingId,
      'properties': {'floor': 0, 'name': id},
    };

VenueData _venue() {
  final buildingData = BuildingData.fromJson({
    'buildings': [_building('a'), _building('b')],
    'campus': {
      ..._building('campus'),
      'totalFloors': [0],
      'buildingNames': ['a', 'b'],
    },
  });
  final json = <String, dynamic>{
    'data': [
      _feature('a', 'a-room'),
      _feature('b', 'b-room'),
      _feature('campus', 'road'),
      _feature(null, 'venue-outline'),
    ],
  };
  return VenueData('Venue', json, buildingData);
}

void main() {
  tearDown(() => UnifiedMapViewPackage.setAllowedBuildingIds(null));

  test('with no restriction every building renders', () {
    final venue = _venue();
    expect(venue.availableFloors.keys, containsAll(['a', 'b', 'campus']));
    expect(venue.buildingCenters.keys, ['a', 'b']);
  });

  test('restricted venue drops other buildings and the campus', () {
    UnifiedMapViewPackage.setAllowedBuildingIds(['a']);
    final venue = _venue();
    expect(venue.availableFloors.keys, ['a']);
    expect(venue.buildingCenters.keys, ['a']);
    expect(venue.buildingNameForId('b'), isNull);
    expect(venue.campusBuildingId, isNull);
    final ids = (venue.json['data'] as List).map((f) => f['id']);
    expect(ids, ['a-room', 'venue-outline']);
  });

  test('the campus renders when its id is allowed', () {
    UnifiedMapViewPackage.setAllowedBuildingIds(['a', 'campus']);
    final venue = _venue();
    expect(venue.availableFloors.keys, unorderedEquals(['a', 'campus']));
    expect(venue.campusBuildingId, 'campus');
    final ids = (venue.json['data'] as List).map((f) => f['id']);
    expect(ids, ['a-room', 'road', 'venue-outline']);
  });

  test('the cached response passed in is not modified', () {
    final json = <String, dynamic>{
      'data': [_feature('a', 'a-room'), _feature('b', 'b-room')],
    };
    UnifiedMapViewPackage.setAllowedBuildingIds(['a']);
    VenueData('Venue', json, BuildingData.fromJson({'buildings': [_building('a'), _building('b')]}));
    expect((json['data'] as List).length, 2);
  });

  test('a filter that matches nothing does not crash', () {
    UnifiedMapViewPackage.setAllowedBuildingIds(['elsewhere']);
    expect(_venue().buildingCenters, isEmpty);
  });
}
