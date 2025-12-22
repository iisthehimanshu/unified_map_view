import 'package:unified_map_view/src/apimodels/GlobalAppGeoJsonDataModel.dart';

import '../../unified_map_view.dart';

class VenueData{
  VenueData._internal(this.venueName, this.json) {
    extractBuildingWiseData(json);
  }

  // Singleton instance
  static VenueData? _instance;

  // Public factory constructor
  factory VenueData(String venueName, Map<String, dynamic> json) {
    _instance = VenueData._internal(venueName, json);
    return _instance!;
  }

  // Get the current instance
  static VenueData? get instance => _instance;

  String venueName;
  Map<String, dynamic> json;
  String selectedBuildingId = "65d887a5db333f89457145f6";
  Map<String,int> _selectedFloor = {};
  Map<String,List<int>> _availableFloors = {};

  Map<String, List<int>> get availableFloors => _availableFloors;

  void extractBuildingWiseData(Map<String, dynamic> json){
    GlobalAppGeoJsonDataModel globalAppGeoJsonDataModel = GlobalAppGeoJsonDataModel.fromJson(json);
    _availableFloors.clear();
    _selectedFloor.clear();

    // Temporary map to track unique floors per building
    Map<String, Set<int>> buildingFloorsMap = {};

    // Iterate through all features
    for (var feature in globalAppGeoJsonDataModel.data!) {
      // Get building ID
      String? buildingId = feature.buildingID;

      // Get floor from properties
      int? floor = feature.properties?.floor;

      // Skip if building ID or floor is null
      if (buildingId == null || floor == null) {
        continue;
      }

      // Add floor to the building's set (automatically handles duplicates)
      if (!buildingFloorsMap.containsKey(buildingId)) {
        buildingFloorsMap[buildingId] = <int>{};
      }
      buildingFloorsMap[buildingId]!.add(floor);
    }

    // Convert sets to sorted lists and populate availableFloors
    buildingFloorsMap.forEach((buildingId, floorsSet) {
      List<int> sortedFloors = floorsSet.toList()..sort();
      _availableFloors[buildingId] = sortedFloors;

      // Set default selected floor (lowest floor or 0 if available)
      if (sortedFloors.isNotEmpty) {
        // Prefer ground floor (0) if available, otherwise use the lowest floor
        _selectedFloor[buildingId] = sortedFloors.contains(0)
            ? 0
            : sortedFloors.first;
      }
    });

    // Debug print
    print("Building-wise available floors:");
    _availableFloors.forEach((buildingId, floors) {
      print("Building $buildingId: Floors $floors (Selected: ${_selectedFloor[buildingId]})");
    });
  }

  int? getSelectedFloor(String buildingId) {
    return _selectedFloor[buildingId];
  }

  // Helper method to set selected floor for a building
  void setSelectedFloor(String buildingId, int floor) {
    if (availableFloors[buildingId]?.contains(floor) ?? false) {
      _selectedFloor[buildingId] = floor;
      print("Selected floor $floor for building $buildingId");
    } else {
      print("Floor $floor not available for building $buildingId");
    }
  }

  List<GeoJsonFeature> getFeaturesForBuildingAndFloor(
      String buildingId, int floor) {
    // try {
      GlobalAppGeoJsonDataModel model = GlobalAppGeoJsonDataModel.fromJson(json);
      if (model.data != null) {

        var filteredData = model.data!
            .where((feature) =>
        feature.buildingID == buildingId &&
            feature.properties?.floor == floor &&
            feature.properties?.name != null &&
            feature.properties?.name!.toLowerCase() != 'undefined'
            && !feature.properties!.name!.contains("Piller")
            && !feature.properties!.name!.contains("Non Walkable")
        )
            .toList();

        List<GeoJsonFeature> featureList = filteredData
            .map((f) => GeoJsonFeature.fromJson(f.toJson() as Map<String, dynamic>))
            .toList();

        return featureList;
      }
    // } catch (e) {
    //   print("Error getting features: $e");
    // }
    return [];
  }

}