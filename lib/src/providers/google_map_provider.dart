// lib/src/providers/google_map_provider.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/map_marker.dart';
import '../models/geojson_models.dart';

/// Google Maps implementation of BaseMapProvider
class GoogleMapProvider extends BaseMapProvider {
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  final Set<Polyline> _polylines = {};

  @override
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    Set<MapMarker>? markers,
  }) {
    if (markers != null) {
      _markers.clear();
      _markers.addAll(markers.map(_convertMarker));
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.latitude,
          config.initialLocation.longitude,
        ),
        zoom: config.initialZoom,
      ),
      myLocationEnabled: config.showUserLocation,
      buildingsEnabled: false,
      zoomControlsEnabled: config.zoomControlsEnabled,
      rotateGesturesEnabled: config.rotateGesturesEnabled,
      scrollGesturesEnabled: config.scrollGesturesEnabled,
      tiltGesturesEnabled: config.tiltGesturesEnabled,
      // markers: _markers,
      polygons: _polygons,
      polylines: _polylines,
      onMapCreated: (GoogleMapController controller) {
        onMapCreated(controller);
      },
    );
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is GoogleMapController) {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is GoogleMapController) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> addMarker(dynamic controller, MapMarker marker) async {
    _markers.add(_convertMarker(marker));
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    _markers.removeWhere((m) => m.markerId.value == markerId);
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    _markers.clear();
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is GoogleMapController) {
      final position = await controller.getVisibleRegion();
      final center = LatLng(
        (position.northeast.latitude + position.southwest.latitude) / 2,
        (position.northeast.longitude + position.southwest.longitude) / 2,
      );
      return MapLocation(latitude: center.latitude, longitude: center.longitude);
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is GoogleMapController && styleJson != null) {
      await controller.setMapStyle(styleJson);
    }
  }

  Marker _convertMarker(MapMarker marker) {
    return Marker(
      markerId: MarkerId(marker.id),
      position: LatLng(marker.position.latitude, marker.position.longitude),
      infoWindow: InfoWindow(
        title: marker.title,
        snippet: marker.snippet,
      ),
    );
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    final Color fill = (polygon.properties?["fillColor"] != null && polygon.properties?["fillColor"] != "undefined" && polygon.properties?["fillColor"].isNotEmpty)
        ? RenderingUtilities.hexToColor(polygon.properties?["fillColor"], opacity: 1.0)
        : Colors.blue.withOpacity(0);

    final Color stroke = (polygon.properties?["strokeColor"] != null && polygon.properties?["strokeColor"] != "undefined" && polygon.properties?["strokeColor"].isNotEmpty)
        ? RenderingUtilities.hexToColor(polygon.properties?["strokeColor"])
        : Colors.blue;

    _polygons.add(
      Polygon(
        polygonId: PolygonId(polygon.id),
        points: polygon.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(),
        strokeWidth: 2,
        strokeColor: stroke,
        fillColor: fill,
      ),
    );
  }


  @override
  Future<void> removePolygon(dynamic controller, String polygonId) async {
    _polygons.removeWhere((p) => p.polygonId.value == polygonId);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    _polygons.clear();
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    bool isWaypoint = false;
    if(polyline.properties?["lineCategory"] != null){
      isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
    }

    _polylines.add(Polyline(
      polylineId: PolylineId(polyline.id),
      points: polyline.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(),
      width: 1,
      color: Color(0xfffa9b9c9),
        patterns: [
          if(isWaypoint)PatternItem.dash(
              Platform.isIOS ? 2 : 10), // length of each dash
          if(isWaypoint)PatternItem.gap(
              Platform.isIOS ? 1 : 6), // gap between dashes
        ]
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
}