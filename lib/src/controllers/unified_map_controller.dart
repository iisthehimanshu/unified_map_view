// lib/src/controllers/unified_map_controller.dart

import 'package:flutter/foundation.dart';
import 'package:unified_map_view/src/providers/mappls_map_provider.dart';

import '../../unified_map_view.dart';
import '../models/Cell.dart';
import '../providers/apple_map_provider.dart';
import '../providers/google_map_provider.dart';
import '../providers/mapbox_map_provider.dart';

/// Main controller for managing map providers and operations
class UnifiedMapController extends ChangeNotifier {
  late MapProvider _currentProvider;
  late MapConfig _config;
  final Map<MapProvider, BaseMapProvider> _providers = {};
  dynamic _currentMapController;
  final Set<GeoJsonMarker> _markers = {};
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _polylines = [];
  late UnifiedCameraPosition _cameraPosition;
  late AnnotationController _annotationController;

  UnifiedMapController({
    required MapProvider initialProvider,
    required String venueName,
    bool enableClustering = true,

    required UnifiedCameraPosition initialLocation,
    bool showUserLocation = false,
    bool zoomControlsEnabled = true,
    bool rotateGesturesEnabled = true,
    bool scrollGesturesEnabled = true,
    bool tiltGesturesEnabled = false,

    Function ({required String markerId, required MapLocation coordinates})? onMarker,
    Function ({required String polygonId, required List<MapLocation> coordinates})? onPolygon,
    Function ({required String polylineId, required List<MapLocation> coordinates})? onPolyline

  }) {
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

  /// Initialize all map providers
  void _initializeProviders() {
    _providers[MapProvider.google] = GoogleMapProvider();
    _providers[MapProvider.mapbox] = MapboxMapProvider();
    _providers[MapProvider.apple] = AppleMapProvider();
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
    if (_currentMapController == null) return;
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
  Future<void> animateCamera(MapLocation location, {double? zoom}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.animateCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialLocation.zoom,
    );
  }

  /// Add a marker to the map
  Future<void> addMarker(GeoJsonMarker marker) async {
    _markers.add(marker);
    if (_currentMapController != null) {
      await currentProviderImplementation.addMarker(_currentMapController, marker);
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
    if (_currentMapController == null) return;

    // Add polygons
    final polygons = GeoJsonLoader.extractPolygons(collection);
    final boundaryPolygons = polygons.where((p) => p.properties?["polygonType"] == "Boundary").toList();
    final otherPolygons = polygons.where((p) => p.properties?["polygonType"] != "Boundary").toList();

    // for (var polygon in boundaryPolygons) {
    //   await addPolygon(polygon);
    // }
    await addPolygons(boundaryPolygons);

    await addPolygons(otherPolygons);

    // for (var polygon in otherPolygons) {
    //   await addPolygon(polygon);
    // }

    // Add polylines
    final polylines = GeoJsonLoader.extractPolylines(collection);
    // for (var polyline in polylines) {
    //   await addPolyline(polyline);
    // }
    addPolylines(polylines);

    // Add markers from Point features
    final markers = GeoJsonLoader.extractMarkers(collection);
    // for (var marker in markers) {
    //   await addMarker(marker);
    // }
    addMarkers(markers);

    notifyListeners();
  }

  Future<void> selectLocation({required String polyID}) async {
    if (_currentMapController != null) {
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

  /// Clear all GeoJSON features (markers, polygons, polylines)
  Future<void> clearAllGeoJsonFeatures() async {
    await clearMarkers();
    await clearPolygons();
    await clearPolylines();
  }

  /// Fit map bounds to show all GeoJSON features
  Future<void> fitBoundsToGeoJson() async {
    if (_currentMapController == null) return;

    final allPoints = <MapLocation>[];

    // Collect all points from markers
    allPoints.addAll(_markers.map((m) => m.position));

    // Collect points from polygons
    for (var polygon in _polygons) {
      allPoints.addAll(polygon.points);
    }

    // Collect points from polylines
    for (var polyline in _polylines) {
      allPoints.addAll(polyline.points);
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

    // Calculate center
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Move to center
    await animateCamera(
      MapLocation(latitude: centerLat, longitude: centerLng),
      zoom: 10.0, // You may want to calculate zoom based on bounds
    );
  }

  /// Annotation Controller
  String? get focusedBuilding => _annotationController.focusedBuilding;
  List<int>? get focusedBuildingAvailableFloors => _annotationController.focusedBuildingAvailableFloors;
  int? get focusBuildingSelectedFloor => _annotationController.focusBuildingSelectedFloor;

  Future<void> changeBuildingFloor({required String buildingID, required int floor}) async {
    await _annotationController.changeBuildingFloor(buildingID, floor);
    await _annotationController.annotatePath(floor);
    notifyListeners();
  }

  Future<bool> addPath({required List<Map<String, dynamic>> path}) async {
    return _annotationController.addPath(path.map((map)=>Cell.fromJson(map)).toList());
  }

  Future<void> annotatePath({required List<String> bids, required int sourceFloor}) async {
    for (var bid in bids) {
      changeBuildingFloor(buildingID: bid, floor: sourceFloor);
    }
    await _annotationController.annotatePath(sourceFloor);
    notifyListeners();
  }

  @override
  void dispose() {
    _currentMapController = null;
    super.dispose();
  }
}