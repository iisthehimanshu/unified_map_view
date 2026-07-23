import 'package:turn_highlighter/turn_highlighter.dart';
import 'package:unified_map_view/src/utils/geoJson/predefined_circles.dart';
import 'package:unified_map_view/src/utils/mapCalculations.dart';
import 'package:unified_map_view/src/utils/renderingUtilities.dart';
import 'dart:math' as math;
import 'dart:developer' as dev;
import '../../unified_map_view.dart';
import '../VenueManager/VenueData.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import '../apis/BuildingByVenue.dart';
import '../apis/GlobalGeoJSONVenueAPI.dart';
import '../config.dart';
import '../models/Cell.dart';
import '../utils/geoJson/predefined_markers.dart';

class AnnotationController{
  final UnifiedMapController _unifiedMapController;
  late VenueData _venueData;

  String? _focusedBuilding;
  List<int>? _focusedBuildingAvailableFloors;
  int? _focusBuildingSelectedFloor;

  String? get focusedBuilding => _focusedBuilding;
  String? get focusedBuildingName => _venueData.buildingNameForId(_focusedBuilding);
  List<int>? get focusedBuildingAvailableFloors => _focusedBuildingAvailableFloors;
  int? get focusBuildingSelectedFloor => _focusBuildingSelectedFloor;
  Map<String, int> get selectedFloor => _venueData.selectedFloor;
  List<int> get floorsContainingPath => extractFloorsContainingPath(_path).toList();

  Map<String, Map<int, List<List<Cell>>>>? _path;
  List<Map<String, Map<int, List<Cell>>>>? _multiPath;
  List<MapLocation> _pathPoints = [];
  String? _greyPathPolylineId;

  /// The floor most recently drawn by [annotatePath]. Reused by
  /// [recolorPathUpToStop] so a recolor redraws the same floor without the
  /// caller having to track it.
  int _lastSourceFloor = 0;

  /// How far the user has progressed along [_pathPoints], as a segment index.
  /// Used to keep the grey "traversed" overlay monotonic so it can't jump
  /// across loops/self-intersections in the path (which produced lines that
  /// connected cyclic points).
  int _lastProjectionIndex = 0;

  /// Every accepted projection of the user onto [_pathPoints], in walk order.
  /// The grey overlay is rebuilt by stitching these together *along the path*
  /// (inserting the intermediate path vertices between consecutive
  /// projections) so it never short-cuts straight from one projection to the
  /// next.
  final List<({MapLocation point, int segmentIndex})> _projectionHistory = [];

  User? _user;

  List<MapLocation>? _pinSelectionLocation;


  AnnotationController(this._unifiedMapController, {required String venueName}){
    _setVenue(venueName);
  }

  Future<void> _setVenue(String venueName) async {
    // Independent network/DB fetches — start both immediately and await them
    // concurrently instead of one after another (was roughly doubling the
    // bootstrap latency for no reason, since neither depends on the other).
    final buildingDataFuture = BuildingByVenue().fetchBuildingIDS(venueName);
    final apiDataFuture = GlobalGeoJSONVenueAPI().getGeoJSONData(venueName);
    final buildingData = await buildingDataFuture;
    final apiData = await apiDataFuture;

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
      double orientation = _venueData.getFloorOrientation(0);
      // await _unifiedMapController.animateCamera(_venueData.venueLatLng, zoom: 15);
      await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
      await _unifiedMapController.fitBoundsToGeoJson();
      // List<MapLocation> circlePoints = RenderingUtilities.generateCirclePoints(center: _venueData.venueLatLng, radiusInMeters: 5000);
      // _unifiedMapController.addPolygon(GeoJsonPolygon(id: "venue patch", points: circlePoints, properties: {"type":"Boundary"}));
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
      _unifiedMapController.removeFurniture(buildingID);
      await _unifiedMapController.addGeoJsonFeatures(GeoJsonFeatureCollection(features: floorData));
    }
    if(_user != null && _user!.bid == buildingID && _user!.floor == floor){
      String id = GeoJsonUtils.buildKey(buildingID: _user!.bid, floor: _user!.floor.toString(), id: "user");
      GeoJsonMarker userMarker = PredefinedMarkers.getUserMarker(_user!.location, id);
      GeoJsonCircle userCircle = PredefinedCircles.getGenericMarker(_user!.location, id);
      await _unifiedMapController.removeMarker("user");
      await _unifiedMapController.removeCircle("user");
      await _unifiedMapController.addUserMarker(userMarker);
      await _unifiedMapController.addCircle(userCircle);
      localizeUser(_user!);
    }else{

    }
  }

  /// Moves every building to [floor] at once, independent of which building is
  /// currently focused. A building that has walkable content on [floor] renders
  /// that content; a building that has none renders only its `Boundary` polygon
  /// from its highest floor so its footprint stays visible. The campus is not
  /// re-fitted/re-rendered — only per-building annotations are swapped.
  Future<void> changeAllBuildingsFloor(int floor) async {
    final campusId = _venueData.campusBuildingId;
    for (final buildingID in _venueData.availableFloors.keys) {
      // The campus holds the base map; never floor-swap or clear it.
      if (buildingID == campusId) continue;
      if (_venueData.selectedFloor[buildingID] == floor) continue;

      final floorData =
          _venueData.setBuildingFloor(buildingId: buildingID, floor: floor);

      // Swap only this building's floor annotations. `exclude: 'boundary'`
      // keeps the persistent campus footprint so the campus is never cleared.
      // The floor-fallback outline below is *not* a 'boundary' id, so it is
      // removed here too and never stacks across switches.
      _unifiedMapController.removePolygon(buildingID, exclude: 'boundary');
      _unifiedMapController.removePolyline(buildingID);
      _unifiedMapController.removeMarker(buildingID);
      _unifiedMapController.removeCircle(buildingID);
      _unifiedMapController.removeFurniture(buildingID);

      final featuresToRender =
          floorData.isNotEmpty ? floorData : _floorFallbackBoundary(buildingID);

      if (featuresToRender.isNotEmpty) {
        await _unifiedMapController.addGeoJsonFeatures(
            GeoJsonFeatureCollection(features: featuresToRender));
      }

      if (_user != null && _user!.bid == buildingID && _user!.floor == floor) {
        String id = GeoJsonUtils.buildKey(
            buildingID: _user!.bid, floor: _user!.floor.toString(), id: "user");
        GeoJsonMarker userMarker =
            PredefinedMarkers.getUserMarker(_user!.location, id);
        GeoJsonCircle userCircle =
            PredefinedCircles.getGenericMarker(_user!.location, id);
        await _unifiedMapController.removeMarker("user");
        await _unifiedMapController.removeCircle("user");
        await _unifiedMapController.addUserMarker(userMarker);
        await _unifiedMapController.addCircle(userCircle);
        localizeUser(_user!);
      }
    }

    // Reflect the tapped floor on the focused-building floor selector.
    _focusBuildingSelectedFloor = floor;
  }

  /// Highest-floor `Boundary` polygon(s) for [buildingID], re-tagged with a
  /// non-`boundary` id so they render as a swappable fallback outline (removed
  /// on the next floor switch) instead of a persistent campus boundary.
  List<GeoJsonFeature> _floorFallbackBoundary(String buildingID) {
    return _venueData
        .highestFloorBoundaryFeatures(buildingID)
        .asMap()
        .entries
        .map((entry) => GeoJsonFeature(
              buildingId: entry.value.buildingId,
              id: 'floorFallback_${buildingID}_${entry.key}',
              geometry: entry.value.geometry,
              properties: entry.value.properties,
            ))
        .toList();
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
    _unifiedMapController.removePolyline('greyTraversed_');
    _unifiedMapController.removeMarker('path');
    _path = null;
    _multiPath = null;
    _pathPoints.clear();
    _lastProjectionIndex = 0;
    _projectionHistory.clear();
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

  /// Draws the stored [_path] on [sourceFloor].
  ///
  /// [fitCamera] refits the camera to the whole path when true (the default for
  /// an initial draw); pass false for an in-place redraw (e.g. a recolor) so the
  /// camera isn't yanked away from the user mid-navigation.
  ///
  /// [resetProjection] clears the grey "traversed" overlay and its projection
  /// history when true (the default). Pass false to preserve the already-walked
  /// greying across a redraw.
  Future<bool> annotatePath(int sourceFloor,
      {bool fitCamera = true, bool resetProjection = true}) async {
    if (_path == null) return false;
    dev.log("_path in annotate path $_path");
    _lastSourceFloor = sourceFloor;
    _pathPoints.clear();
    if (resetProjection) {
      _lastProjectionIndex = 0;
      _projectionHistory.clear();
      _unifiedMapController.removePolyline('greyTraversed_');
    }
    _unifiedMapController.removePolyline("path");

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
            final color = point.color ?? "#6B0D12"; // default color

            final mapLocation =
            MapLocation(latitude: point.lat, longitude: point.lng);

            _pathPoints.add(mapLocation);

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

    // Annotate turn highlights over the drawn path
    // await _annotateTurnHighlights(sourceFloor);

    if (fitCamera) fitPathInScreen();

    return true;
  }

  /// Recolors the drawn path so that cells up to and including the
  /// [nextStopNumber]-th [Cell.pathStop] marker use [activeColor] (the leg the
  /// user is currently travelling) and every cell after it uses [upcomingColor]
  /// (legs to be covered after the next stop). Redraws the path polylines in
  /// place — no camera refit and the grey traversed overlay is preserved, so it
  /// is safe to call mid-navigation each time the next stop advances.
  ///
  /// [nextStopNumber] is 1-based: 1 = the first stop, 2 = the second, etc. When
  /// there are fewer than [nextStopNumber] stops ahead (heading to the final
  /// destination) the whole path stays [activeColor].
  Future<void> recolorPathUpToStop(
    int nextStopNumber, {
    String activeColor = "#448AFF",
    String upcomingColor = "#9FB6D4",
  }) async {
    if (_path == null) return;

    // Walk the stored path cells in draw order, colouring each cell and
    // flipping to [upcomingColor] once the next stop's marker has been passed.
    int stopsSeen = 0;
    bool pastNextStop = false;
    for (final floors in _path!.values) {
      for (final segments in floors.values) {
        for (final segment in segments) {
          for (final cell in segment) {
            cell.color = pastNextStop ? upcomingColor : activeColor;
            if (cell.pathStop) {
              stopsSeen++;
              if (stopsSeen >= nextStopNumber) pastNextStop = true;
            }
          }
        }
      }
    }

    await annotatePath(_lastSourceFloor,
        fitCamera: false, resetProjection: false);
  }

  /// Repaints the whole drawn path a single [color] and clears the grey
  /// traversed overlay, returning the route to its pre-navigation preview look.
  /// Used when guided navigation is exited. No camera refit.
  Future<void> resetPathColoring({String color = "#448AFF"}) async {
    if (_path == null) return;
    for (final floors in _path!.values) {
      for (final segments in floors.values) {
        for (final segment in segments) {
          for (final cell in segment) {
            cell.color = color;
          }
        }
      }
    }
    await annotatePath(_lastSourceFloor,
        fitCamera: false, resetProjection: true);
  }

  /// Runs TurnHighlighter over the collected path points for [sourceFloor] and
  /// draws each resulting turn polyline on the map.
  Future<void> _annotateTurnHighlights(int sourceFloor) async {
    if (_pathPoints.length < 3) return;

    // TurnHighlighter expects List<Map<String,dynamic>> with 'latitude'/'longitude' keys.
    final rawPoints = _pathPoints
        .map((loc) => {'latitude': loc.latitude, 'longitude': loc.longitude})
        .toList();

    final highlighter = TurnHighlighter(path: rawPoints);
    final turnPolylineMaps = highlighter.getTurnPolylines();
    // print("turnPolylineMaps $turnPolylineMaps");
    for (final map in turnPolylineMaps) {
      // getTurnPolylines() returns GeoJsonPolyline.toJson() maps.
      // Re-hydrate into the typed GeoJsonPolyline the controller expects.
      final polyline = GeoJsonPolyline.fromJson(map);
      print("turnPolylineMaps ${map}");
      await _unifiedMapController.addPolyline(polyline);
    }
  }

  Future<void> annotateDottedPath(
      List<MapLocation> points,
      String bid,
      int floor, {String? customKey, String color = "#448AFF"}) async {
    final polyline = GeoJsonPolyline(
      id: GeoJsonUtils.buildKey(
        buildingID: bid,
        floor: floor.toString(),
        path: 'curved_mainLine_${DateTime.now().microsecondsSinceEpoch}',
        custom: customKey
      ),
      points: points,
      properties: {
        "fillColor": color,
        "width": 6.0,
        "fillOpacity": 1.0,
        "style":"dashed",
      },
    );

    _unifiedMapController.addPolyline(polyline);
  }

  Future<void> annotateCurvedPath(
      MapLocation p1,
      MapLocation p2,
      String bid,
      int floor,
      {String? customKey, String color = "#448AFF"}
      ) async {
    final curvedPoints = _generateCurvedPoints(p1, p2);

    await annotateDottedPath(
      curvedPoints,
      bid,
      floor,
      customKey: customKey,
      color: color
    );
  }

  List<MapLocation> _generateCurvedPoints(MapLocation start, MapLocation end, {int segments = 50}) {
    List<MapLocation> points = [];

    // Calculate the control point for the curve (midpoint with offset)
    double midLat = (start.latitude + end.latitude) / 2;
    double midLng = (start.longitude + end.longitude) / 2;

    // Calculate perpendicular offset for curve height
    double dx = end.longitude - start.longitude;
    double dy = end.latitude - start.latitude;
    double distance = math.sqrt(dx * dx + dy * dy);

    // Degenerate case: start and end coincide (distance == 0). Dividing by
    // distance below would yield NaN coordinates, which then poison the whole
    // polyline GeoJSON source (setGeoJsonSource throws on NaN). Return a simple
    // two-point line instead of a curve.
    if (distance == 0) {
      return [start, end];
    }

    // Adjust curve height based on distance (20% of distance)
    double curveHeight = distance * 0.4;

    // Create control point perpendicular to the line
    MapLocation controlPoint = MapLocation(
      latitude: midLat + curveHeight * (dx / distance),
      longitude: midLng - curveHeight * (dy / distance),
    );

    // Generate points along the quadratic Bezier curve
    for (int i = 0; i <= segments; i++) {
      double t = i / segments;
      double lat = math.pow(1 - t, 2) * start.latitude +
          2 * (1 - t) * t * controlPoint.latitude +
          math.pow(t, 2) * end.latitude;
      double lng = math.pow(1 - t, 2) * start.longitude +
          2 * (1 - t) * t * controlPoint.longitude +
          math.pow(t, 2) * end.longitude;

      points.add(MapLocation(latitude: lat, longitude: lng));
    }

    return points;
  }

  Future<void> fitPathInScreen() async {
    await _unifiedMapController.fitBoundsToGeoJson(
      allPoint: _pathPoints,
      padding: 0.0,
    );
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
        'style': "solid"
      },
    );

    await _unifiedMapController.addPolyline(polyline);
  }

  /// Whether the currently drawn path belongs to a guided tour. Tours render
  /// the start/end as tour "stop" markers; regular (including multi-point)
  /// navigation renders normal source/destination markers even though it also
  /// has [Cell.pathStop] waypoints. Set by [UnifiedMapController.annotatePath].
  bool isTourPath = false;

  Future<void> _annotatePathMarkers(List<Cell> path) async {
    bool isTour = isTourPath;
    for (var cell in path) {
      if(cell.isDestination){
        if(isTour){
          _unifiedMapController.addMarker(PredefinedMarkers.getStopMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
        }else if(cell.destinationLat != null && cell.destinationLng != null){
          await annotateCurvedPath(MapLocation(latitude: cell.lat, longitude: cell.lng), MapLocation(latitude: cell.destinationLat!, longitude: cell.destinationLng!), cell.bid!, cell.floor);
          _unifiedMapController.addMarker(PredefinedMarkers.getDestinationMarker(MapLocation(latitude: cell.destinationLat!, longitude: cell.destinationLng!), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true'),title: cell.name??""));
        }else{
          _unifiedMapController.addMarker(PredefinedMarkers.getDestinationMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true'), title: cell.name??""));
        }
      }else if(cell.isSource){
        if(isTour){
          _unifiedMapController.addMarker(PredefinedMarkers.getStartMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
        }else{
          _unifiedMapController.addMarker(PredefinedMarkers.getSourceMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true')));
        }
      }else if(cell.pathStop){
        _unifiedMapController.addMarker(PredefinedMarkers.getPathStopMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true'), title: cell.name??"", stopName: cell.stopName??""));
      }
      // if(cell.isFloorConnection){
      //   _unifiedMapController.addMarker(PredefinedMarkers.getFloorConnectionMarker(MapLocation(latitude: cell.lat, longitude: cell.lng), GeoJsonUtils.buildKey(buildingID: cell.bid, floor: cell.floor.toString(), id: cell.node.toString(), path: 'true'), cell.connectorType));
      // }
    }
  }

  void addDebugMarker(MapLocation location){
    GeoJsonMarker marker = PredefinedMarkers.getDestinationMarker(location, "debugmarker");
    _unifiedMapController.addMarker(marker);
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

  Future<void> localizeUser(User user, {bool changeFloor = true}) async {
    if(_user != null && _user!.bid == user.bid && _user!.floor == user.floor ){
      if(changeFloor){
        await changeBuildingFloor(user.bid, user.floor);
      }
      moveUser(user.location, user.floor);
      return;
    }
    await clearUser();
    _user = user;
    String id = GeoJsonUtils.buildKey(buildingID: user.bid, floor: user.floor.toString(), id: "user");
    GeoJsonMarker userMarker = PredefinedMarkers.getUserMarker(user.location, id);
    GeoJsonCircle userCircle = PredefinedCircles.getGenericMarker(user.location, id);
    if(changeFloor){
      await changeBuildingFloor(user.bid, user.floor);
    }
    await _unifiedMapController.removeMarker("user");
    await _unifiedMapController.removeCircle("user");
    if(_venueData.selectedFloor[user.bid] == user.floor){
      await _unifiedMapController.addUserMarker(userMarker);
      await _unifiedMapController.addCircle(userCircle);
    }
  }

  Future<void> clearUser() async {
    _user = null;
    await _unifiedMapController.removeMarker("user");
  }

  Future<void> moveUser(MapLocation location, int floor, {Duration duration = const Duration(milliseconds: 300), bool compensateForDistance = false}) async {
    print("_userMoveUser $_user $location");
    if (_user == null) return;
    if(_user?.floor != floor){
      await localizeUser(User(location, _user!.bid, floor));
      await annotatePath(floor);
      return;
    }
    if(compensateForDistance){
      MapLocation previousLocation = _user!.location;
      double distance = MapCalculations.distanceInMeters(previousLocation, location);
      duration = Duration(milliseconds: ((300/0.91)*distance).toInt());
      print("calculatedDuration ${duration.inMilliseconds}");
    }
    _user?.location = location;
    await _unifiedMapController.moveMarker("user", location, duration: duration);

    // ── NEW: draw grey path from start of last polyline → user's projection
    await _updateGreyTraversedPath(location);
  }

  Future<void> _updateGreyTraversedPath(MapLocation userLocation) async {
    if (_pathPoints.length < 2) return;

    final projected = _projectPointOntoPolyline(
      userLocation,
      _pathPoints,
      searchFromIndex: _lastProjectionIndex,
    );
    if (projected == null) return;

    // If the user is too far from the route, the projection isn't trustworthy —
    // keep the existing grey overlay (and projection index) untouched.
    if (projected.distanceMeters > 2.0) return;

    // Once we have an established position, reject a projection that jumps too
    // many segments in a single update. Even inside the search window a nearby
    // parallel segment can win; capping the per-update jump stops that spurious
    // hit from being recorded (and stitched into grey) as walked route.
    if (_projectionHistory.isNotEmpty &&
        (projected.segmentIndex - _lastProjectionIndex).abs() >
            _maxProjectionJump) {
      return;
    }

    // Record this projection in walk order. A projection on a different segment
    // (forward or backward) extends the history; one on the same segment just
    // advances the tail along that segment.
    if (_projectionHistory.isEmpty ||
        projected.segmentIndex != _projectionHistory.last.segmentIndex) {
      _projectionHistory
          .add((point: projected.point, segmentIndex: projected.segmentIndex));
    } else {
      _projectionHistory[_projectionHistory.length - 1] =
          (point: projected.point, segmentIndex: projected.segmentIndex);
    }

    _lastProjectionIndex = projected.segmentIndex;

    // Remove the previous grey overlay (if any).
    if (_greyPathPolylineId != null) {
      await _unifiedMapController.removePolyline(_greyPathPolylineId!);
      _greyPathPolylineId = null;
    }

    // Stitch the grey path through every recorded projection, following the
    // path geometry between them. The grey "traversed" line always begins at the
    // real route start (_pathPoints.first): seed it with the vertices from the
    // path start up to the first projection's segment, then the first projection
    // point itself. Without this, everything between the route start and the
    // first recorded projection would stay un-greyed. For each subsequent
    // projection insert the intermediate path vertices before the projection
    // point (reversed when walking backward) so the line stays on the route
    // instead of cutting straight from one projection to the next.
    final firstProjection = _projectionHistory.first;
    final greyPoints = <MapLocation>[
      ..._pathPoints.sublist(0, firstProjection.segmentIndex + 1),
      firstProjection.point,
    ];
    var prevSegment = firstProjection.segmentIndex;
    for (var i = 1; i < _projectionHistory.length; i++) {
      final current = _projectionHistory[i];
      if (current.segmentIndex > prevSegment) {
        // Forward: vertices after the previous segment up to the current one.
        greyPoints.addAll(
          _pathPoints.sublist(prevSegment + 1, current.segmentIndex + 1),
        );
      } else if (current.segmentIndex < prevSegment) {
        // Backward: the same vertices traversed in reverse.
        greyPoints.addAll(
          _pathPoints
              .sublist(current.segmentIndex + 1, prevSegment + 1)
              .reversed,
        );
      }
      greyPoints.add(current.point);
      prevSegment = current.segmentIndex;
    }

    if (greyPoints.length < 2) return;

    _greyPathPolylineId =
    'greyTraversed_${DateTime.now().microsecondsSinceEpoch}';

    final greyPolyline = GeoJsonPolyline(
      id: _greyPathPolylineId!,
      points: greyPoints,
      properties: {
        "fillColor": "#C4C4C4", // neutral grey
        "width": 9.0,
        "fillOpacity": 1.0,
        'style': "solid",
        'isGreyOverlay': true,
      },
    );

    await _unifiedMapController.addPolyline(greyPolyline);
  }

  /// How many segments behind [searchFromIndex] the projection may look, to
  /// allow the user to retrace a little of the route.
  static const int _projectionBackWindow = 5;

  /// How many segments ahead of [searchFromIndex] the projection may look, to
  /// allow for forward progress between location updates.
  static const int _projectionForwardWindow = 20;

  /// Maximum number of segments a single projection may advance or retreat from
  /// the last recorded position. Tighter than the search window, this rejects a
  /// physically-close-but-index-distant segment that still fell inside it.
  static const int _maxProjectionJump = 8;

  /// Result of projecting a point onto a polyline.
  ///
  /// The search is restricted to a window of segments around [searchFromIndex]
  /// so that a segment which is physically close but far away by index (e.g. a
  /// parallel corridor, switchback or self-intersection) can never win. That
  /// prevents the grey overlay from filling in a huge stretch of route the user
  /// never walked.
  ({MapLocation point, int segmentIndex, double distanceMeters}) ?
  _projectPointOntoPolyline(
      MapLocation user,
      List<MapLocation> polyline, {
        int searchFromIndex = 0,
      }) {
    if (polyline.length < 2) return null;

    final lastSegment = polyline.length - 2;
    final start =
        (searchFromIndex - _projectionBackWindow).clamp(0, lastSegment);
    final end =
        (searchFromIndex + _projectionForwardWindow).clamp(0, lastSegment);

    MapLocation? bestPoint;
    int bestIndex = start;
    double bestDist = double.infinity;

    // Only search segments within the window around the last known position.
    for (int i = start; i <= end; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      final proj = _closestPointOnSegment(user, a, b);
      final dist = MapCalculations.distanceInMeters(user, proj);

      if (dist < bestDist) {
        bestDist = dist;
        bestPoint = proj;
        bestIndex = i;
      }
    }

    if (bestPoint == null) return null;
    return (point: bestPoint, segmentIndex: bestIndex, distanceMeters: bestDist);
  }

  MapLocation _closestPointOnSegment(
      MapLocation p,
      MapLocation a,
      MapLocation b,
      ) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) return a; // degenerate segment — a == b

    // Scalar projection of (p - a) onto (b - a), clamped to [0, 1].
    final t = (((p.longitude - a.longitude) * dx +
        (p.latitude - a.latitude) * dy) /
        lenSq)
        .clamp(0.0, 1.0);

    return MapLocation(
      latitude: a.latitude + t * dy,
      longitude: a.longitude + t * dx,
    );
  }

  Set<int> extractFloorsContainingPath(Map<String, Map<int, List<List<Cell>>>>? path) {
    if (path == null) return {};
    final floors = <int>{};

    for (final building in path.values) {
      floors.addAll(building.keys);
    }
    return floors;
  }

}