import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/VenueManager/VenueData.dart';
import 'package:unified_map_view/src/apimodels/BuildingData.dart';
import 'package:unified_map_view/src/apimodels/GlobalAppGeoJsonDataModel.dart';

void main() {
  test('floor names and render levels come from floor-configs-venue entries', () {
    // As floor-configs-venue sends them: building_ID and buildingId, string
    // sizes, no floorRenderLevel or initialOrientation.
    final configs = [
      {'_id': '1', 'building_ID': 'lhc', 'buildingId': 'lhc', 'floorNumber': 0, 'floorName': 'Ground', 'length': '278', 'breadth': '629', 'floorHeight': null, 'dynamicValues': []},
      {'_id': '2', 'building_ID': 'lhc', 'floorNumber': 1, 'floorName': 'First '},
    ].map(FloorConfigs.fromJson).toList();

    final venue = VenueData(
      'Venue',
      {'data': [], 'floorConfigs': [{'buildingId': 'lhc', 'floorNumber': 0, 'floorName': 'from GeoJSON'}]},
      BuildingData.fromJson({'buildings': []}),
      floorConfigs: configs,
    );

    expect(venue.getFloorName(0, 'lhc'), 'Ground');
    expect(venue.getFloorName(1, 'lhc'), 'First', reason: 'building_ID alone is enough');
    expect(venue.getFloorName(2, 'lhc'), isNull);
    expect(venue.getFloorRenderLevel(1, 'lhc'), 1);
    expect(venue.getFloorOrientation(0), 0.0);
  });

  test('the GeoJSON floorConfigs are ignored', () {
    final venue = VenueData(
      'Venue',
      {'data': [], 'floorConfigs': [{'buildingId': 'lhc', 'floorNumber': 0, 'floorName': 'from GeoJSON'}]},
      BuildingData.fromJson({'buildings': []}),
    );
    expect(venue.getFloorName(0, 'lhc'), isNull);
  });
}
