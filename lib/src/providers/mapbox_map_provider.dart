// lib/src/providers/mapbox_map_provider.dart

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/camera_position.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mapbox implementation of BaseMapProvider
class MapboxMapProvider extends BaseMapProvider {
  PointAnnotationManager? _annotationManager;

  @override
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    required void Function(UnifiedCameraPosition position) onCameraMove,

  }) {
    return MapWidget(
      onMapCreated: (mapboxMap) {
        onMapCreated(mapboxMap);
      },
      styleUri: MapboxStyles.MAPBOX_STREETS,
      cameraOptions: CameraOptions(
        center: Point(
          coordinates: Position(
            config.initialLocation.mapLocation.longitude,
            config.initialLocation.mapLocation.latitude,
          ),
        ),
        zoom: config.initialLocation.zoom,
      ),
      textureView: true,
    );
  }

  Future<void> _initializeAnnotations(MapboxMap mapboxMap, Set<GeoJsonMarker>? markers) async {
    _annotationManager = await mapboxMap.annotations.createPointAnnotationManager();

    if (markers != null && _annotationManager != null) {
      for (var marker in markers) {
        await _addMarkerToManager(marker);
      }
    }
  }

  Future<void> _addMarkerToManager(GeoJsonMarker marker) async {
    if (_annotationManager == null) return;

    final options = PointAnnotationOptions(
      geometry: Point(
        coordinates: Position(
          marker.position.longitude,
          marker.position.latitude,
        ),
      ),
      textField: marker.title,
      textOffset: [0.0, -2.0],
      iconSize: 1.0,
    );

    await _annotationManager!.create(options);
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapboxMap) {
      await controller.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapboxMap) {
      await controller.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: zoom,
        ),
        MapAnimationOptions(duration: 2000, startDelay: 0),
      );
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is MapboxMap && _annotationManager == null) {
      _annotationManager = await controller.annotations.createPointAnnotationManager();
    }
    await _addMarkerToManager(marker);
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    // Note: Current Mapbox SDK requires managing annotation IDs
    // This would need enhancement with a marker ID tracking system
    if (_annotationManager != null) {
      // Implementation would require tracking created annotation IDs
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (_annotationManager != null) {
      await _annotationManager!.deleteAll();
    }
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapboxMap) {
      final cameraState = await controller.getCameraState();
      final center = cameraState.center;
      return MapLocation(
        latitude: center.coordinates.lat.toDouble(),
        longitude: center.coordinates.lng.toDouble(),
      );
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is MapboxMap && styleJson != null) {
      await controller.loadStyleURI(styleJson);
    }
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    // Mapbox polygons require style layer implementation
    // This is a simplified version - full implementation would use style layers
    if (controller is MapboxMap) {
      // TODO: Implement polygon rendering using Mapbox style layers
      // For now, this is a placeholder
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId) async {
    // Mapbox polygon removal
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    // Clear all Mapbox polygons
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    // Mapbox polylines require style layer implementation
    if (controller is MapboxMap) {
      // TODO: Implement polyline rendering using Mapbox style layers
    }
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    // Mapbox polyline removal
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    // Clear all Mapbox polylines
  }

}