// lib/src/providers/apple_map_provider.dart

import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:unified_map_view/src/models/CameraBound.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';
import '../models/camera_position.dart';

/// Apple Maps implementation of BaseMapProvider
class AppleMapProvider extends BaseMapProvider {
  final Set<Annotation> _annotations = {};
  final Set<Polygon> _polygons = {};
  final Set<Polyline> _polylines = {};

  @override
  Widget buildMap({
    required MapConfig config,
  }) {
    return AppleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.mapLocation.latitude,
          config.initialLocation.mapLocation.longitude,
        ),
        zoom: config.initialLocation.zoom,
      ),
      myLocationEnabled: config.showUserLocation,
      rotateGesturesEnabled: config.rotateGesturesEnabled,
      scrollGesturesEnabled: config.scrollGesturesEnabled,
      annotations: _annotations,
      polygons: _polygons,
      polylines: _polylines,
      onMapCreated: (AppleMapController controller) {
        config.onMapCreated(controller);
      },
    );
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is AppleMapController) {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom, {double? bearing, double? tilt}) async {
    if (controller is AppleMapController) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    _annotations.add(_convertMarker(marker));
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    _annotations.removeWhere((a) => a.annotationId.value == markerId);
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    _annotations.clear();
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is AppleMapController) {
      final region = await controller.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      return MapLocation(latitude: center.latitude, longitude: center.longitude);
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    // Apple Maps doesn't support custom styles in the same way
    // This is a placeholder for potential future implementation
  }

  Annotation _convertMarker(GeoJsonMarker marker) {
    return Annotation(
      annotationId: AnnotationId(marker.id),
      position: LatLng(marker.position.latitude, marker.position.longitude),
      infoWindow: InfoWindow(
        title: marker.title,
        snippet: marker.snippet,
      ),
    );
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    _polygons.add(Polygon(
      polygonId: PolygonId(polygon.id),
      points: polygon.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(),
      strokeWidth: 2,
      strokeColor: Colors.blue,
      fillColor: Colors.blue.withOpacity(0.3),
    ));
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    _polygons.removeWhere((p) => p.polygonId.value == polygonId);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    _polygons.clear();
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    _polylines.add(Polyline(
      polylineId: PolylineId(polyline.id),
      points: polyline.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(),
      width: 3,
      color: Colors.red,
    ));
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    _polylines.removeWhere((p) => p.polylineId.value == polylineId);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    _polylines.clear();
  }

  @override
  Future<void> addPolygons(controller, List<GeoJsonPolygon> polygons) {
    // TODO: implement addPolygons
    throw UnimplementedError();
  }

  @override
  Future<void> selectLocation(controller, String polyID) {
    // TODO: implement selectLocation
    throw UnimplementedError();
  }

  @override
  Future<void> deSelectLocation(controller) {
    // TODO: implement deSelectLocation
    throw UnimplementedError();
  }

  @override
  Future<void> zoom(controller, {double zoom = 0.0}) {
    // TODO: implement zoomOut
    throw UnimplementedError();
  }

  @override
  Future<void> zoomTo(controller, double zoom) {
    // TODO: implement zoomTo
    throw UnimplementedError();
  }

  @override
  Future<void> addPolylines(controller, List<GeoJsonPolyline> polylines) {
    // TODO: implement addPolylines
    throw UnimplementedError();
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> marker) {
    // TODO: implement addMarkers
    throw UnimplementedError();
  }

  @override
  Future<void> fitCameraToLine(controller, GeoJsonPolyline polyline) {
    // TODO: implement fitCameraToLine
    throw UnimplementedError();
  }

  @override
  Future<void> localizeUser(controller, GeoJsonMarker marker) {
    // TODO: implement localizeUser
    throw UnimplementedError();
  }

  @override
  Future<void> moveUser(controller, String id, MapLocation location) {
    // TODO: implement moveMarker
    throw UnimplementedError();
  }

  @override
  Future<void> fitCameraToBounds(controller, CameraBound bound) {
    // TODO: implement fitCameraToBounds
    throw UnimplementedError();
  }

}