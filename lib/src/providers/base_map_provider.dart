// lib/src/providers/base_map_provider.dart

import 'package:flutter/widgets.dart';
import '../models/camera_position.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Abstract base class for all map providers
/// Implement this class to add a new map provider
abstract class BaseMapProvider {
  /// Build the map widget
  Widget buildMap({
    required MapConfig config,
  });

  /// Move camera to a specific location
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom);

  Future<void> zoom(dynamic controller, {double zoom = 0.0});

  Future<void> zoomTo(dynamic controller, double zoom);

  Future<void> fitCameraToLine(dynamic controller, GeoJsonPolyline polyline);

  /// Add a marker to the map
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker);

  Future<void> addMarkers(dynamic controller, List<GeoJsonMarker> markers);

  Future<void> localizeUser(dynamic controller, GeoJsonMarker marker);

  Future<void> moveUser(dynamic controller, String id, MapLocation location);

  /// Remove a marker from the map
  Future<void> removeMarker(dynamic controller, String markerId);

  /// Clear all markers
  Future<void> clearMarkers(dynamic controller);

  /// Get current camera position
  Future<MapLocation?> getCurrentLocation(dynamic controller);

  /// Animate camera to location
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom);

  /// Set map style (if supported)
  Future<void> setMapStyle(dynamic controller, String? styleJson);

  /// Add a polygon to the map
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon);

  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons);

  /// Remove a polygon from the map
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude});

  /// Clear all polygons
  Future<void> clearPolygons(dynamic controller);

  /// Add a polyline to the map
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline);
  Future<void> addPolylines(dynamic controller, List<GeoJsonPolyline> polylines);

  /// Remove a polyline from the map
  Future<void> removePolyline(dynamic controller, String polylineId);

  /// Clear all polylines
  Future<void> clearPolylines(dynamic controller);

  Future<void> selectLocation(dynamic controller, String polyID);

  Future<void> deSelectLocation(dynamic controller);

  /// Clear all GeoJSON features
  Future<void> clearAllGeoJsonFeatures(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }
}