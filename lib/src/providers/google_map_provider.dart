// lib/src/providers/google_map_provider.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/camera_position.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Google Maps implementation of BaseMapProvider
class GoogleMapProvider extends BaseMapProvider {
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};
  final Set<Polyline> _polylines = {};
  GoogleMapController? _controller;

  @override
  Widget buildMap({required MapConfig config}) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.mapLocation.latitude,
          config.initialLocation.mapLocation.longitude,
        ),
        zoom: config.initialLocation.zoom,
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
        _controller = controller;
        config.onMapCreated(controller);
      },
      onCameraIdle: () async {
        print("onCameraIdle");
        if (_controller != null) {
          try {
            // Try getting the visible region instead
            final bounds = await _controller!.getVisibleRegion();
            if (bounds != null) {
              // Calculate center from bounds
              final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
              final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

              config.onCameraMove(UnifiedCameraPosition(
                mapLocation: MapLocation(
                  latitude: centerLat,
                  longitude: centerLng,
                ),
                zoom: 0.0,
                bearing: 0.0,
              ));
            }
          } catch (e) {
            print("Error getting camera position: $e");
          }
        }
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
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    _markers.add(_convertMarker(marker));
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    _markers.removeWhere((m) => m.markerId.value.contains(markerId));
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

  Marker _convertMarker(GeoJsonMarker marker) {
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
    final String? rawType = polygon.properties?["type"]?? polygon.properties?["polygonType"];
    final String? type = rawType?.toLowerCase();
    print("type $type ${polygon.id}");

    final String? fillColorHex = polygon.properties?["fillColor"];
    final String? strokeColorHex = polygon.properties?["strokeColor"];

    final Color fill =
    (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
        ? RenderingUtilities.hexToColor(fillColorHex, opacity: 1.0)
        : RenderingUtilities.polygonColorMap[type]?["fillColor"]
        ?? Colors.blue.withOpacity(0.0);

    final Color stroke =
    (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
        ? RenderingUtilities.hexToColor(strokeColorHex)
        : RenderingUtilities.polygonColorMap[type]?["strokeColor"]
        ?? Colors.blue.withOpacity(0.0);

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
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    _polygons.removeWhere((p) {
      final id = p.polygonId.value;

      if (exclude != null && id.contains(exclude)) {
        return false;
      }

      if (id.contains(polygonId)) {
        return true;
      }

      return false;
    });
  }


  @override
  Future<void> clearPolygons(dynamic controller) async {
    _polygons.clear();
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    bool isWaypoint = false;
    if(polyline.properties?["lineCategory"] != null){
      isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint" ;
    }else{
      isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints" ;
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
    _polylines.removeWhere((p) => p.polylineId.value.contains(polylineId));
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
  Future<void> deSelectLocation(controller, String polyID) {
    // TODO: implement deSelectLocation
    throw UnimplementedError();
  }

}