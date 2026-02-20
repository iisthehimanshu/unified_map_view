import 'package:turn_highlighter/turn_highlighter.dart';
import 'package:unified_map_view/src/utils/geoJson/predefined_circles.dart';
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

  Map<String, Map<int, List<List<Cell>>>>? _path;
  List<Map<String, Map<int, List<Cell>>>>? _multiPath;

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
    print("apiD Data recieved at ${DateTime.now()}");
    _venueData = VenueData(venueName, apiData,buildingData);
    await renderVenue();
  }

  Future<void> renderVenue() async {
    if(!_unifiedMapController.controllerIsInitialized) return;
    try{
      List<GeoJsonFeature> venueRenderData = [];
      _venueData.availableFloors.forEach((buildingId,floors){
        var floorData = _venueData.setBuildingFloor(buildingId: buildingId, floor: 0);
        venueRenderData.addAll(floorData);
      });
      await _unifiedMapController.animateCamera(_venueData.venueLatLng, zoom: 15);
      await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
      await _unifiedMapController.fitBoundsToGeoJson();
      if(_user != null){
        localizeUser(_user!);
      }
      print("onReadyLandmarkSelectionID ${_unifiedMapController.onReadyLandmarkSelectionID}");
      if(_unifiedMapController.onReadyLandmarkSelectionID != null && _unifiedMapController.onReadyLandmarkSelectionID!.isNotEmpty){
        await _unifiedMapController.selectLocation(polyID: _unifiedMapController.onReadyLandmarkSelectionID!);
      }
    }catch(e){
      print("e ${e}");
    }
  }

  Future<void> changeBuildingFloor(String buildingID, int floor) async {
    if(_venueData.selectedFloor[buildingID] == floor) return;
    _focusBuildingSelectedFloor = floor;
    var floorData = _venueData.setBuildingFloor(buildingId: buildingID, floor: floor);
    if(floorData.isNotEmpty){
      _unifiedMapController.removePolygon(buildingID, exclude: 'boundary');
      _unifiedMapController.removePolyline(buildingID);
      _unifiedMapController.removeMarker(buildingID);
      _unifiedMapController.removeCircle(buildingID);
      await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: floorData));
    }
    if(_user != null && _user!.bid == buildingID && _user!.floor == floor){
      localizeUser(_user!);
    }else{

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
    _multiPath = null;
    return true;
  }

  bool addPath(List<Cell> path) {
    _path ??= <String, Map<int, List<List<Cell>>>>{};

    if (path.isEmpty) return false;

    List<Cell> currentSegment = [];
    String? lastBid;

    for (var cell in path) {
      final bid = cell.bid ?? "";
      final floor = cell.floor;

      // If building changes, store previous segment
      if (lastBid != null && bid != lastBid) {
        _storeSegment(currentSegment);
        currentSegment = [];
      }

      currentSegment.add(cell);
      lastBid = bid;
    }

    // Store last segment
    if (currentSegment.isNotEmpty) {
      _storeSegment(currentSegment);
    }

    return true;
  }

  void _storeSegment(List<Cell> segment) {
    if (segment.isEmpty) return;

    final bid = segment.first.bid!;
    final floor = segment.first.floor;

    _path!.putIfAbsent(bid, () => <int, List<List<Cell>>>{});
    _path![bid]!.putIfAbsent(floor, () => <List<Cell>>[]);

    // Add whole segment as a separate list
    _path![bid]![floor]!.add(segment);
  }


  bool addMultiPathGraph(List<Cell> path){
    _multiPath ??= [];
    Map<String, Map<int, List<Cell>>> obj = Map();
    for (var cell in path) {
      obj.putIfAbsent(cell.bid!, ()=><int, List<Cell>>{});
      obj[cell.bid]!.putIfAbsent(cell.floor, ()=>[]);
      obj[cell.bid]![cell.floor]!.add(cell);
    }
    _multiPath!.add(obj);
    return true;
  }

  Future<bool> annotatePath(int sourceFloor) async {
    if (_path == null) return false;

    List<MapLocation> pathPoints = [];

    for (var entry in _path!.entries) {
      final bid = entry.key;
      final floors = entry.value;

      for (var floorEntry in floors.entries) {
        final floor = floorEntry.key;
        final paths = floorEntry.value;

        if (floor != sourceFloor) continue;

        for (var path in paths) {
          List<MapLocation> segmentPoints = [];
          String? currentColor;

          for (int i = 0; i < path.length; i++) {
            final point = path[i];
            final color = point.color ?? "#448AFF"; // default color

            final mapLocation =
            MapLocation(latitude: point.lat, longitude: point.lng);

            pathPoints.add(mapLocation);

            // If color changes, draw previous segment
            if (currentColor != null && color != currentColor) {
              await _drawSegmentPolyline(
                bid,
                floor,
                segmentPoints,
                currentColor,
              );
              segmentPoints = [];
            }

            segmentPoints.add(mapLocation);
            currentColor = color;
          }

          // Draw last segment
          if (segmentPoints.length > 1 && currentColor != null) {
            await _drawSegmentPolyline(
              bid,
              floor,
              segmentPoints,
              currentColor,
            );
          }

          _annotatePathMarkers(path);
        }
      }
    }

    await _unifiedMapController.fitBoundsToGeoJson(
      allPoint: pathPoints,
      padding: 0.3,
    );


    // _multiPath?.forEach((possiblePath){
    //   possiblePath.forEach((bid, value){
    //     value.forEach((floor, path) async {
    //       if(floor == sourceFloor){
    //         List<MapLocation> points = [];
    //         for (var point in path) {
    //           points.add(MapLocation(latitude: point.lat, longitude: point.lng));
    //         }
    //         GeoJsonPolyline polyline = GeoJsonPolyline(
    //             id: GeoJsonUtils.buildKey(buildingID: bid, floor: floor.toString(), path: 'alternatePath'),
    //             points: points,
    //             properties: {
    //               "fillColor": "#D3D3D3",
    //               "width": 8.0,
    //               "fillOpacity": 1.0,
    //             }
    //         );
    //         await _unifiedMapController.addPolyline(polyline);
    //       }
    //     });
    //   });
    // });

    return true;
  }

  Future<void> _drawSegmentPolyline(
      String bid,
      int floor,
      List<MapLocation> points,
      String color,
      ) async {
    if (points.length < 2) return;

    final polyline = GeoJsonPolyline(
      id: GeoJsonUtils.buildKey(
        buildingID: bid,
        floor: floor.toString(),
        path: 'mainLine_${DateTime.now().microsecondsSinceEpoch}',
      ),
      points: points,
      properties: {
        "fillColor": color,
        "width": 8.0,
        "fillOpacity": 1.0,
      },
    );

    await _unifiedMapController.addPolyline(polyline);
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
        _unifiedMapController.addMarker(PredefinedMarkers.getFloorConnectionMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true'), cell.connectorType));
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
    await clearUser();
    _user = user;
    String id = GeoJsonUtils.buildKey(buildingID: user.bid, floor: user.floor.toString(), id: "user");
    GeoJsonMarker userMarker = PredefinedMarkers.getUserMarker(user.location, id);
    GeoJsonCircle userCircle = PredefinedCircles.getGenericMarker(user.location, id);
    await changeBuildingFloor(user.bid, user.floor);
    await _unifiedMapController.removeMarker("user");
    await _unifiedMapController.removeCircle("user");
    await _unifiedMapController.addUserMarker(userMarker);
    await _unifiedMapController.addCircle(userCircle);
  }

  Future<void> clearUser() async {
    _user = null;
    await _unifiedMapController.removeMarker("user");
  }

  Future<void> moveUser(MapLocation location)async {
    if(_user == null) return;
    _user?.location = location;
    await _unifiedMapController.moveMarker("user", location);
  }

}