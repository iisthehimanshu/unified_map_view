import 'package:unified_map_view/src/utils/mapCalculations.dart';

import '../../unified_map_view.dart';
import '../VenueManager/VenueData.dart';
import '../apis/BuildingByVenue.dart';
import '../apis/GlobalGeoJSONVenueAPI.dart';
import '../models/Cell.dart';
import '../utils/geoJson/predefined_markers.dart';

class AnnotationController{
  final UnifiedMapController _unifiedMapController;
  late VenueData _venueData;

  String? _focusedBuilding;
  List<int>? _focusedBuildingAvailableFloors;
  int? _focusBuildingSelectedFloor;

  String? get focusedBuilding => _focusedBuilding;
  List<int>? get focusedBuildingAvailableFloors => _focusedBuildingAvailableFloors;
  int? get focusBuildingSelectedFloor => _focusBuildingSelectedFloor;

  Map<String, Map<int, List<Cell>>>? _path;

  User? _user;

  List<MapLocation>? _pinSelectionLocation;

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
      var floorData = _venueData.setBuildingFloor(buildingId: buildingId, floor: 0);
      venueRenderData.addAll(floorData);
    });
    await _unifiedMapController.moveCamera(_venueData.venueLatLng, zoom: 18);

    await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
  }

  Future<void> changeBuildingFloor(String buildingID, int floor) async {
    if(_venueData.selectedFloor[buildingID] == floor) return;
    _focusBuildingSelectedFloor = floor;
    _unifiedMapController.removePolygon(buildingID, exclude: 'boundary');
    _unifiedMapController.removePolyline(buildingID);
    _unifiedMapController.removeMarker(buildingID);
    var floorData = _venueData.setBuildingFloor(buildingId: buildingID, floor: floor);
    await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: floorData));
    print(_user);
    if(_user != null && _user!.bid == buildingID && _user!.floor == floor){
      localizeUser(_user!);
    }
  }

  Future<void> switchToLocationFloor(String polyId) async {
    GeoJsonFeature? feature = _venueData.findLocation(polyId);
    if(feature == null) return;

    int? floor = feature.properties?["floor"];
    String? buildingID = feature.buildingId;

    if(floor != null && buildingID != null){
      await changeBuildingFloor(buildingID, floor);
    }
  }

  List<int>? returnFocusedBuildingFloors(){
    return _focusedBuildingAvailableFloors;
  }

  void cameraFocusChange(UnifiedCameraPosition cameraPosition) {
    try {
      if (_venueData.buildingCenters.isEmpty) return;

      final MapLocation cameraTarget = cameraPosition.mapLocation;

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

  bool clearPath(){
    _unifiedMapController.removePolyline('path');
    _unifiedMapController.removeMarker('path');
    _path = null;
    return true;
  }

  bool addPath(List<Cell> path){
    _path ??= <String, Map<int, List<Cell>>>{};
    for (var cell in path) {
      _path!.putIfAbsent(cell.bid!, ()=><int, List<Cell>>{});
      _path![cell.bid]!.putIfAbsent(cell.floor, ()=>[]);
      _path![cell.bid]![cell.floor]!.add(cell);
    }
    return true;
  }

  Future<bool> annotatePath(int sourceFloor) async {
    if(_path == null) return false;
    _path!.forEach((bid, value){
      value.forEach((floor, path) async {
        if(floor == sourceFloor){
          List<MapLocation> points = [];
          for (var point in path) {
            points.add(MapLocation(latitude: point.lat, longitude: point.lng));
          }
          GeoJsonPolyline polyline = GeoJsonPolyline(
              id: GeoJsonUtils.buildKey(buildingID: bid, floor: floor.toString(), path: 'true'),
              points: points
          );
          await _unifiedMapController.fitCameraToLine(polyline);
          await _unifiedMapController.addPolyline(polyline);
          _annotatePathMarkers(path);
        }
      });
    });

    return true;
  }

  void _annotatePathMarkers(List<Cell> path){
    for (var cell in path) {
      if(cell.isDestination){
        _unifiedMapController.addMarker(PredefinedMarkers.getDestinationMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
      }
      if(cell.isSource){
        _unifiedMapController.addMarker(PredefinedMarkers.getSourceMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
      }
      if(cell.isFloorConnection){
        _unifiedMapController.addMarker(PredefinedMarkers.getFloorConnectionMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
      }
    }
  }

  Future<void> annotatePinSelectionLandmarks(List<MapLocation> locations, String buildingID, int floor) async {
    _pinSelectionLocation = locations;
    await changeBuildingFloor(buildingID, floor);
    for (var location in locations) {
      String id = GeoJsonUtils.buildKey(buildingID: buildingID, floor: floor.toString(), id: location.id??"optionPinSelection");
      GeoJsonMarker marker = PredefinedMarkers.getOptionPinSelectionMarker(location, id);
      await _unifiedMapController.addMarker(marker);
    }
  }

  Future<void> selectPinSelectionLandmark(MapLocation selectedLocation, String buildingID, int floor) async {
    if(selectedLocation.id == null) return;

    if(_pinSelectionLocation != null && _pinSelectionLocation!.isNotEmpty){
      for (var location in _pinSelectionLocation!) {
        if(location.id == null) continue;
        _unifiedMapController.removeMarker(location.id!);
        if(location.id!.toLowerCase().contains(selectedLocation.id!)) continue;
        String id = GeoJsonUtils.buildKey(buildingID: buildingID, floor: floor.toString(), id: location.id??"optionPinSelection");
        GeoJsonMarker marker = PredefinedMarkers.getOptionPinSelectionMarker(location, id);
        await _unifiedMapController.addMarker(marker);
      }
    }

    String id = GeoJsonUtils.buildKey(buildingID: buildingID, floor: floor.toString(), id: selectedLocation.id??"selectedPinSelection");
    GeoJsonMarker marker = PredefinedMarkers.getSelectedPinSelectionMarker(selectedLocation, id);
    await _unifiedMapController.addMarker(marker);
  }

  Future<void> clearPinSelectionLandmarks() async {
    await _unifiedMapController.removeMarker("optionPinSelection");
    await _unifiedMapController.removeMarker("selectedPinSelection");
    if(_pinSelectionLocation != null && _pinSelectionLocation!.isNotEmpty){
      for (var location in _pinSelectionLocation!) {
        if(location.id == null) continue;
        await _unifiedMapController.removeMarker(location.id!);
      }
    }
    _pinSelectionLocation = null;
  }

  Future<void> localizeUser(User user) async {
    _user = user;
    String id = GeoJsonUtils.buildKey(buildingID: user.bid, floor: user.floor.toString(), id: "user");
    GeoJsonMarker userMarker = PredefinedMarkers.getUserMarker(user.location, id);
    await changeBuildingFloor(user.bid, user.floor);
    await _unifiedMapController.removeMarker("user");
    await _unifiedMapController.addUserMarker(userMarker);
  }

  Future<void> moveUser(MapLocation location)async {
    _user?.location = location;
    await _unifiedMapController.moveMarker("user", location);
  }

}