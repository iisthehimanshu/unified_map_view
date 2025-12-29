import 'package:unified_map_view/src/utils/mapCalculations.dart';

import '../../unified_map_view.dart';
import '../VenueManager/VenueData.dart';
import '../apis/BuildingByVenue.dart';
import '../apis/GlobalGeoJSONVenueAPI.dart';

class AnnotationController{
  UnifiedMapController _unifiedMapController;
  late VenueData _venueData;

  String? _focusedBuilding;
  List<int>? _focusedBuildingAvailableFloors;
  int? _focusBuildingSelectedFloor;

  String? get focusedBuilding => _focusedBuilding;
  List<int>? get focusedBuildingAvailableFloors => _focusedBuildingAvailableFloors;
  int? get focusBuildingSelectedFloor => _focusBuildingSelectedFloor;

  AnnotationController(this._unifiedMapController, {required String venueName}){
    _setVenue(venueName);
  }

  Future<void> _setVenue(String venueName) async {
    final buildingData = await BuildingByVenue().fetchBuildingIDS(venueName);

    final apiData = await GlobalGeoJSONVenueAPI().getGeoJSONData(venueName);

    if (apiData == null || apiData.isEmpty) {
      throw Exception('No GeoJSON data received from API');
    }

    _venueData = VenueData(venueName, apiData,buildingData);
    List<GeoJsonFeature> venueRenderData = [];
    _venueData.availableFloors.forEach((buildingId,floors){
      venueRenderData.addAll(_venueData.setBuildingFloor(buildingId: buildingId, floor: 0));
    });
    await _unifiedMapController.moveCamera(_venueData.venueLatLng, zoom: 20);

    await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
  }

  Future<void> changeBuildingFloor(String buildingID, int floor) async {
    _focusBuildingSelectedFloor = floor;
    _unifiedMapController.removePolygon(buildingID);
    List<GeoJsonFeature> venueRenderData = _venueData.setBuildingFloor(buildingId: buildingID, floor: floor);
    await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
  }

  List<int>? returnFocusedBuildingFloors(){
    return _focusedBuildingAvailableFloors;
  }

  void cameraFocusChange(UnifiedCameraPosition cameraPosition) {
    try {
      if (_venueData.buildingCenters.isEmpty) return;

      final MapLocation cameraTarget = cameraPosition.mapLocation;
      final variabrl = _focusedBuildingAvailableFloors;

      String? nearestBuildingId = _focusedBuilding;
      double minDistance = double.infinity;

      _venueData.buildingCenters.forEach((buildingId, center) {
        final distance = MapCalculations.distanceInMeters(cameraTarget, center);

        if (distance < minDistance) {
          minDistance = distance;
          nearestBuildingId = buildingId;
        }
      });

      if (nearestBuildingId == null) return;

      _focusedBuilding = nearestBuildingId;
      _focusedBuildingAvailableFloors = _venueData.availableFloors[nearestBuildingId];
      _focusBuildingSelectedFloor = _venueData.selectedFloor[nearestBuildingId];
    } catch(e){
      return;
    }
  }
}