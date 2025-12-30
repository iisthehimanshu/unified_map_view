import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:unified_map_view/src/apimodels/BuildingData.dart';
import 'package:unified_map_view/src/apimodels/GlobalAppGeoJsonDataModel.dart';

import '../../unified_map_view.dart';

class VenueData{
  VenueData._internal(this.venueName, this.json, this.buildingData) {
    extractBuildingWiseData(json);
    findBuildingCenters();
  }

  // Singleton instance
  static VenueData? _instance;

  // Public factory constructor
  factory VenueData(String venueName, Map<String, dynamic> json, BuildingData buildingData) {
    _instance = VenueData._internal(venueName, json, buildingData);
    return _instance!;
  }
  static VenueData? get instance => _instance;

  String venueName;
  MapLocation venueLatLng = MapLocation(latitude: 28.543733294529066, longitude: 77.18772931714324);
  Map<String, dynamic> json;

  Map<String,int> _selectedFloor = {};
  Map<String,List<int>> _availableFloors = {};
  BuildingData buildingData;
  Map<String, MapLocation> buildingCenters = {};

  Map<String, List<int>> get availableFloors => _availableFloors;
  Map<String, int> get selectedFloor => _selectedFloor;

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
  }

  int? getSelectedFloor(String buildingId) {
    return _selectedFloor[buildingId];
  }

  // Helper method to set selected floor for a building
  void setSelectedFloor(String buildingId, int floor) {
    if (availableFloors[buildingId]?.contains(floor) ?? false) {
      _selectedFloor[buildingId] = floor;
    }
  }

  List<GeoJsonFeature> _getFeaturesForBuildingAndFloor(
      String buildingId,
      int floor,
      ) {
    GlobalAppGeoJsonDataModel model = GlobalAppGeoJsonDataModel.fromJson(json);

    if (model.data == null) return [];

    final filteredData = model.data!.where((feature) {
      final name = feature.properties?.name;
      final lowerName = name?.toLowerCase() ?? '';

      return feature.buildingID == buildingId &&
          feature.properties?.floor == floor &&
          name != null &&
          !lowerName.contains('piller') &&
          !lowerName.contains('non walkable') &&
          !lowerName.contains('iw');
    }).toList();

    return filteredData.map((f) => GeoJsonFeature.fromJson(f.toJson())).toList();
  }


  List<GeoJsonFeature> setBuildingFloor({required String buildingId, required int floor}){
    _selectedFloor[buildingId] = floor;
    return _getFeaturesForBuildingAndFloor(buildingId, floor);
  }

  void findBuildingCenters() {
    buildingCenters.clear();

    final List<Building>? buildings = buildingData.buildings;
    if (buildings == null || buildings.isEmpty) return;

    for (final building in buildings) {
      // coordinates = [lat, lng]
      if (building.coordinates.length < 2) continue;

      final double lat = building.coordinates[0];
      final double lng = building.coordinates[1];

      // Use building ID as key (recommended)
      buildingCenters[building.id] = MapLocation(latitude: lat, longitude: lng);
    }
  }




}