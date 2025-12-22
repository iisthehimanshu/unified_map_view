// lib/src/controllers/unified_map_controller.dart

import 'package:flutter/foundation.dart';
import 'package:unified_map_view/src/VenueManager/VenueData.dart';
import '../apis/GlobalGeoJSONVenueAPI.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import '../enums/map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/map_marker.dart';
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
  final Set<MapMarker> _markers = {};
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _polylines = [];

  UnifiedMapController({
    required MapProvider initialProvider,
    required MapConfig config,
  })  : _currentProvider = initialProvider,
        _config = config {
    _initializeProviders();
  }

  /// Initialize all map providers
  void _initializeProviders() {
    _providers[MapProvider.google] = GoogleMapProvider();
    _providers[MapProvider.mapbox] = MapboxMapProvider();
    _providers[MapProvider.apple] = AppleMapProvider();
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

  /// Move camera to a specific location
  Future<void> moveCamera(MapLocation location, {double? zoom}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.moveCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialZoom,
    );
  }

  /// Animate camera to a specific location
  Future<void> animateCamera(MapLocation location, {double? zoom}) async {
    if (_currentMapController == null) return;
    await currentProviderImplementation.animateCamera(
      _currentMapController,
      location,
      zoom ?? _config.initialZoom,
    );
  }

  /// Add a marker to the map
  Future<void> addMarker(MapMarker marker) async {
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

  /// Get all current markers
  Set<MapMarker> get markers => Set.unmodifiable(_markers);

  // ============================================
  // GeoJSON Methods
  // ============================================

  Future<void> changeBuildingFloor(String buildingId, int floor) async {
    clearAllGeoJsonFeatures();
    final venueData = VenueData.instance;
    List<GeoJsonFeature> venueRenderData = [];
    venueData?.availableFloors.forEach((buildingId,floors){
      venueRenderData.addAll(venueData.getFeaturesForBuildingAndFloor(buildingId, floor));
    });

    await addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
  }

  Future<void> setVenue(String venueName) async {
    final apiData = await GlobalGeoJSONVenueAPI().getGeoJSONData(venueName);

    if (apiData == null || apiData.isEmpty) {
      throw Exception('No GeoJSON data received from API');
    }
    debugPrint("apiData ${apiData.length}");

    VenueData venueData = VenueData(venueName, apiData);
    List<GeoJsonFeature> venueRenderData = [];
    venueData.availableFloors.forEach((buildingId,floors){
      venueRenderData.addAll(venueData.getFeaturesForBuildingAndFloor(buildingId, 0));
    });

    await addGeoJsonFeatures(GeoJsonFeatureCollection(features: venueRenderData));
  }

  /// Load and render GeoJSON from assets
  Future<void> loadGeoJsonFromAsset(String assetPath) async {
    try {
      final collection = await GeoJsonLoader.loadFromAsset(assetPath);
      await addGeoJsonFeatures(collection);
    } catch (e) {
      throw Exception('Failed to load GeoJSON: $e');
    }
  }

  /// Load and render GeoJSON from JSON string
  Future<void> loadGeoJsonFromString(String jsonString) async {
    // try {
      final collection = GeoJsonLoader.loadFromString(jsonString);
      await addGeoJsonFeatures(collection);
    // } catch (e) {
    //   throw Exception('Failed to parse GeoJSON: $e');
    // }
  }

  /// Add GeoJSON feature collection to map
  Future<void> addGeoJsonFeatures(GeoJsonFeatureCollection collection) async {
    if (_currentMapController == null) return;

    // Add markers from Point features
    final markers = collection.toMarkers();
    for (var marker in markers) {
      await addMarker(marker);
    }

    // Add polygons
    final polygons = GeoJsonLoader.extractPolygons(collection);
    for (var polygon in polygons) {
      await addPolygon(polygon);
    }

    // Add polylines
    final polylines = GeoJsonLoader.extractPolylines(collection);
    for (var polyline in polylines) {
      await addPolyline(polyline);
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

  /// Remove a polygon from the map
  Future<void> removePolygon(String polygonId) async {
    _polygons.removeWhere((p) => p.id == polygonId);
    if (_currentMapController != null) {
      await currentProviderImplementation.removePolygon(_currentMapController, polygonId);
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

  @override
  void dispose() {
    _currentMapController = null;
    super.dispose();
  }
}