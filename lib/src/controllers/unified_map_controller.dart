// lib/src/controllers/unified_map_controller.dart

import 'package:flutter/foundation.dart';
import '../controllers/annotation_controller.dart';
import 'package:unified_map_view/src/providers/mappls_map_provider.dart';
import '../enums/map_provider.dart';
import '../models/camera_position.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';
import '../utils/geojson_loader.dart';
import '../providers/base_map_provider.dart';
import '../providers/google_map_provider.dart';
import '../providers/mapbox_map_provider.dart';
import '../providers/apple_map_provider.dart';

/// Main controller for managing map providers and operations
class UnifiedMapController extends ChangeNotifier {
  MapProvider _currentProvider;
  MapConfig _config;
  final Map<MapProvider, BaseMapProvider> _providers = {};
  dynamic _currentMapController;
  final Set<GeoJsonMarker> _markers = {};
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _polylines = [];
  late UnifiedCameraPosition _cameraPosition;
  late AnnotationController _annotationController;

  UnifiedMapController({
    required MapProvider initialProvider,
    required MapConfig config,
    required String venueName,
    bool enableClustering = true,
  })  : _currentProvider = initialProvider,
        _config = config {
    _annotationController = AnnotationController(this, venueName: venueName);
    _cameraPosition = config.initialLocation;
    _initializeProviders(enableClustering);
  }

  /// Initialize all map providers
  void _initializeProviders(bool enableClustering) {
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

  /// Move camera to a specific location
  Future<void> moveCamera(MapLocation location, {double? zoom}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.moveCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialLocation.zoom,
    );
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

    for (var polygon in boundaryPolygons) {
      await addPolygon(polygon);
    }
    // await addPolygons(boundaryPolygons);

    // await addPolygons(otherPolygons);

    for (var polygon in otherPolygons) {
      await addPolygon(polygon);
    }

    // Add polylines
    final polylines = GeoJsonLoader.extractPolylines(collection);
    for (var polyline in polylines) {
      await addPolyline(polyline);
    }

    // Add markers from Point features
    final markers = GeoJsonLoader.extractMarkers(collection);
    for (var marker in markers) {
      await addMarker(marker);
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
    notifyListeners();
  }

  @override
  void dispose() {
    _currentMapController = null;
    super.dispose();
  }
}