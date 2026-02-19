// lib/src/controllers/unified_map_controller.dart

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:unified_map_view/src/providers/mappls_map_provider.dart';
import '../../unified_map_view.dart';
import '../config.dart';
import '../models/Cell.dart';
import '../providers/google_map_provider.dart';
import '../providers/mapbox_map_provider.dart';
import '../utils/LandmarkAssetType.dart';

/// Main controller for managing map providers and operations
class UnifiedMapController extends ChangeNotifier {
  late MapProvider _currentProvider;
  late MapConfig _config;
  final Map<MapProvider, BaseMapProvider> _providers = {};
  dynamic _currentMapController;
  final Set<GeoJsonMarker> _markers = {};
  final Set<GeoJsonCircle> _circles = {};
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _polylines = [];
  late UnifiedCameraPosition _cameraPosition;
  late AnnotationController _annotationController;
  Function(MapLocation)? _onMapTapCallback;


  final List<MapLocation> _fingerprintPositions = [];
  MapLocation? _droppedPinPosition;

  // Getters
  List<MapLocation> get fingerprintPositions => _fingerprintPositions;
  MapLocation? get droppedPinPosition => _droppedPinPosition;
  bool get hasPinDropped => _droppedPinPosition != null;



  String? onReadyLandmarkSelectionID;

  UnifiedMapController({
    required MapProvider initialProvider,
    required String venueName,
    bool enableClustering = true,

    required UnifiedCameraPosition initialLocation,
    bool showUserLocation = false,
    bool zoomControlsEnabled = true,
    bool rotateGesturesEnabled = true,
    bool scrollGesturesEnabled = true,
    bool tiltGesturesEnabled = true,

    Function ({required String markerId, required MapLocation coordinates})? onMarker,
    Function ({required String polygonId, required List<MapLocation> coordinates})? onPolygon,
    Function ({required String polylineId, required List<MapLocation> coordinates})? onPolyline,

    this.onReadyLandmarkSelectionID,

    String? url

  }) {

    AppConfig.url = url;

    _currentProvider = initialProvider;

    _config = MapConfig(
        initialLocation: initialLocation,
      showUserLocation: showUserLocation,
      zoomControlsEnabled: zoomControlsEnabled,
      rotateGesturesEnabled: rotateGesturesEnabled,
      scrollGesturesEnabled: scrollGesturesEnabled,
      tiltGesturesEnabled: tiltGesturesEnabled,
      onMapCreated: onMapCreated,
      onCameraMove: onCameraMove,
      onMarkerTap: onMarker??onMarkerTap,
      onPolygonTap: onPolygon??onPolygonTap,
      onPolylineTap: onPolyline??onPolylineTap
    );

    _annotationController = AnnotationController(this, venueName: venueName);

    _cameraPosition = initialLocation;

    _initializeProviders();
  }


  bool get controllerIsInitialized => (_currentMapController != null);

  /// Initialize all map providers
  void _initializeProviders() {
    _providers[MapProvider.google] = GoogleMapProvider();
    _providers[MapProvider.mapbox] = MapboxMapProvider();
    _providers[MapProvider.mappls] = MapplsMapProvider();
  }

  /// Register a custom map provider
  /// This allows adding new map providers without modifying the package
  void registerCustomProvider(MapProvider provider, BaseMapProvider implementation) {
    _providers[provider] = implementation;
    notifyListeners();
  }

  /// Get current map provider
  MapProvider get currentProvider => _currentProvider;

  /// Get current map configuration
  MapConfig get config => _config;

  /// Get current provider implementation
  BaseMapProvider get currentProviderImplementation => _providers[_currentProvider]!;

  UnifiedCameraPosition get cameraPosition => _cameraPosition;

  /// Switch to a different map provider
  void switchProvider(MapProvider newProvider) {
    if (_providers.containsKey(newProvider)) {
      _currentProvider = newProvider;
      _currentMapController = null; // Reset controller for new provider
      notifyListeners();
    } else {
      throw Exception('Provider $newProvider is not registered');
    }
  }

  /// Update map configuration
  void updateConfig(MapConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  /// Called when map is created
  void onMapCreated(dynamic controller) {
    _currentMapController = controller;
    _annotationController.renderVenue();
    // fitBoundsToGeoJson();
  }

  void onCameraMove(UnifiedCameraPosition position) async {
    _cameraPosition = position;
    _annotationController.cameraFocusChange(position);
    notifyListeners();
  }

  void onPolylineTap({required String polylineId, required List<MapLocation> coordinates}){
    print("unified controller onPolylineTap $polylineId $coordinates");
  }

  void onPolygonTap({required String polygonId, required List<MapLocation> coordinates}){
    print("unified controller onPolygonTap $polygonId $coordinates");
  }

  void onMarkerTap({required String markerId, required MapLocation coordinates}){
    print("unified controller onMarkerTap $markerId $coordinates");
  }

  /// Move camera to a specific location
  Future<void> moveCamera(MapLocation location, {double? zoom}) async {
    if (_currentMapController == null){
      print("_currentMapController is null when trying moveCamera");
      return;
    }
    await currentProviderImplementation.moveCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialLocation.zoom,
    );
  }

  Future<void> zoom({double zoom = 1.0}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.zoom(_currentMapController, zoom: zoom);
  }

  Future<void> zoomTo(double zoom) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.zoomTo(_currentMapController, zoom);
  }

  Future<void> fitCameraToLine(GeoJsonPolyline polyline) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.fitCameraToLine(_currentMapController, polyline);
  }

  /// Animate camera to a specific location
  Future<void> animateCamera(MapLocation location, {double? zoom, double? bearing, double? tilt}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.animateCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialLocation.zoom,
      bearing: bearing,
      tilt: tilt
    );
  }

  /// Animate camera to a fit bound
  Future<void> fitCameraToBounds(CameraBound bound) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.fitCameraToBounds(
      _currentMapController,
      bound
    );
  }

  Future<void> addCircle(GeoJsonCircle circle) async {
    _circles.add(circle);
    if (_currentMapController != null) {
      await currentProviderImplementation.addCircle(_currentMapController, circle);
    }
    notifyListeners();
  }

  Future<void> removeCircle(String id) async {
    _circles.removeWhere((circle)=>circle.id.toLowerCase().contains(id));
    if (_currentMapController != null) {
      await currentProviderImplementation.removeCircle(_currentMapController, id);
    }
    notifyListeners();
  }

  /// Add a marker to the map
  Future<void> addMarker(GeoJsonMarker marker) async {
    _markers.add(marker);
    if (_currentMapController != null) {
      await currentProviderImplementation.addMarker(_currentMapController, marker);
    }
    notifyListeners();
  }

  Future<void> addUserMarker(GeoJsonMarker marker) async {
    _markers.add(marker);
    if (_currentMapController != null) {
      await currentProviderImplementation.localizeUser(_currentMapController, marker);
    }
    notifyListeners();
  }

  Future<void> addMarkers(List<GeoJsonMarker> markers) async {
    _markers.addAll(markers);
    if (_currentMapController != null) {
      await currentProviderImplementation.addMarkers(_currentMapController, markers);
    }
    notifyListeners();
  }

  Future<void> moveMarker(String id, MapLocation location) async {
    if (_currentMapController != null) {
      await currentProviderImplementation.moveUser(_currentMapController, id, location);
    }
    notifyListeners();
  }

  /// Remove a marker from the map
  Future<void> removeMarker(String markerId) async {
    _markers.removeWhere((m) => m.id == markerId);
    if (_currentMapController != null) {
      await currentProviderImplementation.removeMarker(_currentMapController, markerId);
    }
    notifyListeners();
  }

  /// Clear all markers
  Future<void> clearMarkers() async {
    _markers.clear();
    if (_currentMapController != null) {

      await currentProviderImplementation.clearMarkers(_currentMapController);
    }
    notifyListeners();
  }

  /// Get current camera location
  Future<MapLocation?> getCurrentLocation() async {
    if (_currentMapController == null) return null;
    return await currentProviderImplementation.getCurrentLocation(_currentMapController);
  }

  /// Set map style (if supported by provider)
  Future<void> setMapStyle(String? styleJson) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.setMapStyle(_currentMapController, styleJson);
  }

  // ============================================
  // GeoJSON Methods
  // ============================================

  /// Add GeoJSON feature collection to map
  Future<void> addGeoJsonFeatures(GeoJsonFeatureCollection collection) async {
    print("addGeoJsonFeatures ${StackTrace.current}");
    // Add polygons
    final polygons = GeoJsonLoader.extractPolygons(collection);
    final sectionPolygons = polygons.where((p) => p.properties?["type"] == "Section").toList();
    final subSection = polygons.where((p) => p.properties?["type"] == "SubSection").toList();
    final boundaryPolygons = polygons.where((p) => p.properties?["type"] == "Boundary").toList();
    final otherPolygons = polygons.where((p) => !sectionPolygons.contains(p) && !boundaryPolygons.contains(p)).toList();
    await addPolygons(boundaryPolygons);
    await addPolygons(otherPolygons);
    await addPolygons(sectionPolygons);
    await addPolygons(subSection);

    final polylines = GeoJsonLoader.extractPolylines(collection);
    await addPolylines(polylines);

    final markers = GeoJsonLoader.extractMarkers(collection);
    final urlMarkers = markers.where((marker)=> (marker.assetPath != null && marker.assetPath!.contains("http"))).toList();
    addMarkers(urlMarkers);
    final localMarkers = markers.where((marker)=> !urlMarkers.contains(marker)).toList();
    final sectionMarkers = localMarkers.where((marker) => marker.properties?["type"] == "Section").toList();
    final subSectionMarkers = localMarkers.where((marker) => marker.properties?["type"] == "SubSection").toList();
    final normalMarker = localMarkers.where((marker) => !sectionMarkers.contains(marker) && !subSectionMarkers.contains(marker)).toList();
    await addMarkers(normalMarker);
    await addMarkers(sectionMarkers);
    await addMarkers(subSectionMarkers);

    notifyListeners();
  }

  Future<void> selectLocation({required String polyID}) async {
    if (_currentMapController != null) {
      await _annotationController.switchToLocationFloor(polyID);
      await currentProviderImplementation.selectLocation(_currentMapController, polyID);
    }
    notifyListeners();
  }

  Future<void> deSelectLocation() async {
    if (_currentMapController != null) {
      await currentProviderImplementation.deSelectLocation(_currentMapController);
    }
    notifyListeners();
  }

  /// Add a polygon to the map
  Future<void> addPolygon(GeoJsonPolygon polygon) async {
    _polygons.add(polygon);
    if (_currentMapController != null) {
      await currentProviderImplementation.addPolygon(_currentMapController, polygon);
    }
    notifyListeners();
  }

  Future<void> addPolygons(List<GeoJsonPolygon> polygons) async {
    _polygons.addAll(polygons);
    if (_currentMapController != null) {
      await currentProviderImplementation.addPolygons(_currentMapController, polygons);
    }
    notifyListeners();
  }
  /// Remove a polygon from the map
  Future<void> removePolygon(String polygonId,{String? exclude}) async {
    _polygons.removeWhere((p) => p.id == polygonId);
    if (_currentMapController != null) {
      await currentProviderImplementation.removePolygon(_currentMapController, polygonId, exclude: exclude);
    }
    notifyListeners();
  }
  /// Clear all polygons
  Future<void> clearPolygons() async {
    _polygons.clear();
    if (_currentMapController != null) {
      await currentProviderImplementation.clearPolygons(_currentMapController);
    }
    notifyListeners();
  }
  /// Clear polygons by id
  Future<void> clearPolygonByID(String id) async {
    _polygons.removeWhere((polygon){
      return polygon.id.contains(id);
    });
    if (_currentMapController != null) {
      await currentProviderImplementation.clearPolygons(_currentMapController);
    }
    notifyListeners();
  }

  /// Add a polyline to the map
  Future<void> addPolyline(GeoJsonPolyline polyline) async {
    _polylines.add(polyline);
    if (_currentMapController != null) {
      await currentProviderImplementation.addPolyline(_currentMapController, polyline);
    }
    notifyListeners();
  }

  Future<void> addPolylines(List<GeoJsonPolyline> polylines) async {
    _polylines.addAll(polylines);
    if (_currentMapController != null) {
      await currentProviderImplementation.addPolylines(_currentMapController, polylines);
    }
    notifyListeners();
  }

  /// Remove a polyline from the map
  Future<void> removePolyline(String polylineId) async {
    _polylines.removeWhere((p) => p.id == polylineId);
    if (_currentMapController != null) {
      await currentProviderImplementation.removePolyline(_currentMapController, polylineId);
    }
    notifyListeners();
  }

  /// Clear all polylines
  Future<void> clearPolylines() async {
    _polylines.clear();
    if (_currentMapController != null) {
      await currentProviderImplementation.clearPolylines(_currentMapController);
    }
    notifyListeners();
  }

  void setOnMapTapCallback(Function(MapLocation)? callback) {
    _onMapTapCallback = callback;
      currentProviderImplementation.setOnMapTapCallback(callback);
    notifyListeners();
  }

  void handleMapTap(MapLocation location) {
    _onMapTapCallback?.call(location);
  }

  /// Clear all GeoJSON features (markers, polygons, polylines)
  Future<void> clearAllGeoJsonFeatures() async {
    await clearMarkers();
    await clearPolygons();
    await clearPolylines();
  }

  /// Fit map bounds to show all GeoJSON features
  Future<void> fitBoundsToGeoJson({List<MapLocation>? allPoint, double padding = 0.1}) async {
    if (_currentMapController == null) return;

    var allPoints = <MapLocation>[];
    if(allPoint == null){
      // Collect all points from markers
      allPoints.addAll(_markers.map((m){
        return m.position;
      }));

      // Collect points from polygons
      for (var polygon in _polygons) {
        allPoints.addAll(polygon.points);
      }

      // Collect points from polylines
      for (var polyline in _polylines) {
        allPoints.addAll(polyline.points);
      }
    }else{
      allPoints = allPoint;
    }

    if (allPoints.isEmpty) return;

    // Calculate bounds
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (var point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Move to center
    try{
      // Add padding to the bounds (adjust these values as needed)
      final latPadding = (maxLat - minLat) * padding; // 10% padding
      final lngPadding = (maxLng - minLng) * padding;

      // Create bounds with padding
      final bounds = CameraBound(
        southwest: MapLocation(latitude: minLat - latPadding, longitude: minLng - lngPadding),
        northeast: MapLocation(latitude: maxLat + latPadding, longitude: maxLng + lngPadding),
      );

      await fitCameraToBounds(bounds);
    }catch(e){
      // Calculate center
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      await animateCamera(
        MapLocation(latitude: centerLat, longitude: centerLng),
        zoom: 10.0, // You may want to calculate zoom based on bounds
      );
    }
  }

  /// Annotation Controller
  String? get focusedBuilding => _annotationController.focusedBuilding;
  List<int>? get focusedBuildingAvailableFloors => _annotationController.focusedBuildingAvailableFloors;
  int? get focusBuildingSelectedFloor => _annotationController.focusBuildingSelectedFloor;
  String get focusedBuildingName =>_annotationController.focusedBuilding??"";
  String get focusedVenueName => _annotationController.venueName;

  Future<void> changeBuildingFloor({required String buildingID, required int floor}) async {
    await _annotationController.changeBuildingFloor(buildingID, floor);
    await _annotationController.annotatePath(floor);
    notifyListeners();
  }

  Future<bool> addPath({required List<Map<String, dynamic>> path}) async {
    return _annotationController.addPath(path.map((map)=>Cell.fromJson(map)).toList());
  }

  Future<bool> addMultiPathGraph({required List<Map<String, dynamic>> path}) async {
    return _annotationController.addMultiPathGraph(path.map((map)=>Cell.fromJson(map)).toList());
  }

  Future<void> clearPath() async {
    _annotationController.clearPath();
    notifyListeners();
  }

  Future<void> annotatePath({required List<String> bids, required int sourceFloor}) async {
    deSelectLocation();
    for (var bid in bids) {
      changeBuildingFloor(buildingID: bid, floor: sourceFloor);
    }
    await _annotationController.annotatePath(sourceFloor);
    notifyListeners();
  }

  Future<void> annotatePinSelectionLandmarks({required List<MapLocation> locations, required String bid, required int floor}) async {
    await _annotationController.annotatePinSelectionLandmarks(locations, bid, floor);
    notifyListeners();
  }

  Future<void> selectPinSelectionLandmarks({required MapLocation location, required String bid, required int floor}) async {
    await _annotationController.selectPinSelectionLandmark(location, bid, floor);
    notifyListeners();
  }

  Future<void> clearPinSelectionLandmarks() async {
    await _annotationController.clearPinSelectionLandmarks();
    notifyListeners();
  }

  void localizeUser(User user) async {
    await _annotationController.localizeUser(user);
    notifyListeners();
  }

  void clearUser() async {
    await _annotationController.clearUser();
    notifyListeners();
  }

  Future<void> moveUser(MapLocation location) async {
    await _annotationController.moveUser(location);
    notifyListeners();
  }


  /// Add markers at multiple predefined locations
  Future<void> addMarkersAtLocations(List<MapLocation> locations, {
    String? title,
    LandmarkAssetType assetType = LandmarkAssetType.genericMarker,
    Size imageSize = const Size(45, 45),
  }) async {
    for (int i = 0; i < locations.length; i++) {
      final location = locations[i];
      try {
        final marker = GeoJsonMarker(
          id: 'Fingerprinted-marker-$i-${DateTime.now().millisecondsSinceEpoch}',
          position: location,
          title: title ?? 'Marker ${i + 1}',
          snippet: 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}',
          assetPath: assetType.assetPath,
          iconName: title ?? 'Marker ${i + 1}',
          properties: {
            'type': 'Fingerprinted-marker',
            'index': i,
            'latitude': location.latitude,
            'longitude': location.longitude,
          },
          priority: false,
          imageSize: imageSize,
          anchor: assetType.anchor,
        );
        await addMarker(marker);
      } catch (e) {
        debugPrint('Error adding marker at index $i: $e');
      }
    }
  }


  void setFingerprintPositions(List<MapLocation> positions) {
    print("positions:${positions}");
    _fingerprintPositions.clear();
    _fingerprintPositions.addAll(positions);
    notifyListeners();
  }

  void addFingerprintPosition(MapLocation position) {
    _fingerprintPositions.add(position);
    notifyListeners();
  }

  void clearFingerprintPositions() {
    _fingerprintPositions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _currentMapController = null;
    super.dispose();
  }
}