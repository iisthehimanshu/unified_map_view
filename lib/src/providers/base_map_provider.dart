// lib/src/providers/base_map_provider.dart

import 'package:flutter/widgets.dart';
import '../../unified_map_view.dart';
import '../models/CameraBound.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Abstract base class for all map providers
/// Implement this class to add a new map provider
abstract class BaseMapProvider {
  /// Build the map widget
  Widget buildMap({
    required MapConfig config,
    required BuildContext context,
    Function(UnifiedCameraPosition position)? onCameraMove
  });

  /// Move camera to a specific location
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom);

  Future<void> zoom(dynamic controller, {double zoom = 0.0});

  Future<void> zoomTo(dynamic controller, double zoom);

  Future<void> fitCameraToLine(dynamic controller, GeoJsonPolyline polyline);

  Future<void> fitCameraToBounds(dynamic controller, CameraBound bound);

  Future<void> addCircle(dynamic controller, GeoJsonCircle circle);
  Future<void> removeCircle(dynamic controller, String id);

  /// Add a marker to the map
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker);

  Future<void> addMarkers(dynamic controller, List<GeoJsonMarker> markers);

  Future<void> localizeUser(dynamic controller, GeoJsonMarker marker);

  Future<void> moveUser(dynamic controller, String id, MapLocation location, Duration duration);

  /// Remove a marker from the map
  Future<void> removeMarker(dynamic controller, String markerId);

  /// Clear all markers
  Future<void> clearMarkers(dynamic controller);

  /// Temporarily force icon/text overlap ON for the given marker ids so they
  /// are never hidden by collision. Providers without support inherit a no-op.
  Future<void> setMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {}

  /// Turn the temporary overlap override back OFF for the given marker ids.
  Future<void> clearMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {}

  /// Turn the temporary overlap override OFF for every marker it was set on.
  Future<void> clearAllMarkersAllowOverlap(dynamic controller) async {}

  /// Get current camera position
  Future<MapLocation?> getCurrentLocation(dynamic controller);

  /// Animate camera to location
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom, {double? bearing, double? tilt, Duration? duration});

  /// Set content insets so camera operations center on the unobstructed part
  /// of the viewport (e.g. the area not covered by bottom panels).
  /// Providers without native support inherit this no-op.
  Future<void> setContentInsets(dynamic controller, EdgeInsets insets, {bool animated = true}) async {}

  /// Set map style (if supported)
  Future<void> setMapStyle(dynamic controller, String? styleJson);

  /// Add a polygon to the map
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon);

  Future<void> addSection(dynamic controller, GeoJsonPolygon polygon);

  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons);

  /// Remove a polygon from the map
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude});

  /// Clear all polygons
  Future<void> clearPolygons(dynamic controller);

  /// Render point features carrying a "3dRef" part list as extruded 3D
  /// furniture/objects. Items are raw GeoJSON feature maps
  /// ({geometry, properties}). Default is a no-op so providers without
  /// fill-extrusion support don't have to implement it.
  Future<void> addFurniture(
      dynamic controller, List<Map<String, dynamic>> items) async {}

  /// Remove one building's furniture (floor switch), matched on the
  /// item's 'buildingId'.
  Future<void> removeFurniture(dynamic controller, String buildingId) async {}

  /// Remove all furniture/3D objects added via [addFurniture].
  Future<void> clearFurniture(dynamic controller) async {}

  /// Add a polyline to the map
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline);
  Future<void> addPolylines(dynamic controller, List<GeoJsonPolyline> polylines);

  /// Remove a polyline from the map
  Future<void> removePolyline(dynamic controller, String polylineId);

  /// Clear all polylines
  Future<void> clearPolylines(dynamic controller);

  Future<void> selectLocation(dynamic controller, String polyID);

  Future<void> deSelectLocation(dynamic controller);

  Future<void> addMapFade(dynamic controller);
  Future<void> removeMapFade(dynamic controller);

  Future<void> toggle3DView(dynamic controller, {double? tiltWhen3D});

  void dispose();

}