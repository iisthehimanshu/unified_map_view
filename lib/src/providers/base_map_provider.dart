// lib/src/providers/base_map_provider.dart

import 'package:flutter/widgets.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/map_marker.dart';
import '../models/geojson_models.dart';

/// Abstract base class for all map providers
/// Implement this class to add a new map provider
abstract class BaseMapProvider {
  /// Build the map widget
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    Set<MapMarker>? markers,
  });

  /// Move camera to a specific location
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom);

  /// Add a marker to the map
  Future<void> addMarker(dynamic controller, MapMarker marker);

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

  /// Remove a polygon from the map
  Future<void> removePolygon(dynamic controller, String polygonId);

  /// Clear all polygons
  Future<void> clearPolygons(dynamic controller);

  /// Add a polyline to the map
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline);

  /// Remove a polyline from the map
  Future<void> removePolyline(dynamic controller, String polylineId);

  /// Clear all polylines
  Future<void> clearPolylines(dynamic controller);

  /// Add multiple GeoJSON features at once
  Future<void> addGeoJsonFeatures(dynamic controller, GeoJsonFeatureCollection collection) async {
    // Add markers
    final markers = collection.toMarkers();
    for (var marker in markers) {
      await addMarker(controller, marker);
    }

    // Add polygons
    final polygons = collection.getFeaturesByType(GeoJsonGeometryType.polygon);
    for (var feature in polygons) {
      final polygon = GeoJsonPolygon.fromFeature(feature);
      if (polygon != null) {
        await addPolygon(controller, polygon);
      }
    }

    // Add polylines
    final polylines = collection.getFeaturesByType(GeoJsonGeometryType.lineString);
    for (var feature in polylines) {
      final polyline = GeoJsonPolyline.fromFeature(feature);
      if (polyline != null) {
        await addPolyline(controller, polyline);
      }
    }
  }

  /// Clear all GeoJSON features
  Future<void> clearAllGeoJsonFeatures(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }
}