// lib/src/providers/google_map_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:unified_map_view/src/models/CameraBound.dart';
import 'package:unified_map_view/src/utils/UnifiedMarkerCreator.dart';
import 'package:unified_map_view/src/utils/geoJson/predefined_markers.dart';
import 'package:unified_map_view/src/utils/mapCalculations.dart';
import '../../unified_map_view.dart';
import '../models/camera_position.dart';
import '../models/selectedLocation.dart';
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

  SelectedLocation? selectedLocation;

  late MapConfig _config;


  @override
  Widget buildMap({required MapConfig config, required BuildContext context}) {
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
      markers: _markers,
      polygons: _polygons,
      polylines: _polylines,
      onMapCreated: (GoogleMapController controller) {
        _controller = controller;
        _config = config;
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
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom, {double? bearing, double? tilt}) async {
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
    _markers.add(await _convertMarker(marker));
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

  final creator = UnifiedMarkerCreator();
  Future<Marker> _convertMarker(GeoJsonMarker marker) async {
    MarkerIconWithAnchor markerIconWithAnchor = await creator.createUnifiedMarker(
      text: marker.assetPath != null ? "":marker.title ?? "",
      imageSource: marker.assetPath,
      layout: MarkerLayout.horizontal,
      textFormat: TextFormat.smartWrap,
      textColor: const Color(0xff000000),
    );
    final Uint8List iconBytes = markerIconWithAnchor.icon;
    return Marker(
        icon: BitmapDescriptor.fromBytes(iconBytes),
        markerId: MarkerId(marker.id),
        position: LatLng(marker.position.latitude, marker.position.longitude),
        infoWindow: InfoWindow(
          title: marker.title,
          snippet: marker.snippet,
        ),
        onTap: (){
          print("marker tap");
        },
        anchor: markerIconWithAnchor.anchor
    );
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    final String? rawType = polygon.properties?["type"]?? polygon.properties?["polygonType"];
    final String? type = rawType?.toLowerCase();
    // print("type $type ${polygon.id}");

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
          consumeTapEvents: true,
          onTap: (){
            final polygonId = _extractPolygonIdFromTap(polygon.id);
            if(polygonId != null){
              selectLocation(controller,polygonId);
            }
          }
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
    print("addPolyline ${StackTrace.current}");
    bool isWaypoint = false;
    if(polyline.properties?["lineCategory"] != null){
      isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint" ;
    }
    if (polyline.properties?["polygonType"] != null) {
      isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints" ;
    }

    if (isWaypoint) return;

    _polylines.add(
        Polyline(
            polylineId: PolylineId(polyline.id),
            points: polyline.points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            color: Colors.blueAccent,
            width: 8,
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
    print("removePolyline${_polylines.length}");
    _polylines.removeWhere((p) => p.polylineId.value.contains(polylineId));
    print("removePolyline1${_polylines.length}");

  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    _polylines.clear();
  }

  @override
  Future<void> addPolygons(controller, List<GeoJsonPolygon> polygons) async {
    for (final polygon in polygons) {
      await addPolygon(controller, polygon);
    }
  }

  String? _extractPolygonIdFromTap(String key) {
    var keyMap = GeoJsonUtils.extractKeyValueMap(key);
    if(keyMap["id"] != null) return keyMap["id"];
    return null;
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    if (controller is! GoogleMapController) {
      print('Error: Invalid controller type');
      return;
    }
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }

    // Deselect previous location if exists
    if (selectedLocation != null) {
      await deSelectLocation(controller);
    }

    // try {
    if (_polygons.isEmpty) {
      print('Error: No polygons available to select');
      return;
    }

    // Find the polygon
    final polygon = _polygons.firstWhere(
          (p) => p.polygonId.value.contains(polyID),
      orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
    );

    // Validate coordinates
    if (polygon.points.isEmpty) {
      print('Error: No coordinates found for polygon: ${polygon.polygonId}');
      return;
    }

    if (polygon.points.length < 3) {
      print('Error: Polygon must have at least 3 points: ${polygon.polygonId}');
      return;
    }

    final List<MapLocation> mapLocations = polygon.points.map((latLng) {
      return MapLocation(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
    }).toList();

    print("mapLocations${mapLocations}");
    // Trigger callback
    _config.onPolygonTap?.call(
      coordinates: mapLocations,
      polygonId: polyID,
    );

    // Calculate bounds
    double minLat = polygon.points.first.latitude;
    double maxLat = polygon.points.first.latitude;
    double minLng = polygon.points.first.longitude;
    double maxLng = polygon.points.first.longitude;

    for (final point in polygon.points) {
      if (point.latitude < -90 || point.latitude > 90) {
        print('Warning: Invalid latitude ${point.latitude}');
        continue;
      }
      if (point.longitude < -180 || point.longitude > 180) {
        print('Warning: Invalid longitude ${point.longitude}');
        continue;
      }

      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    // Calculate center
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    if (centerLat.isNaN || centerLng.isNaN || centerLat.isInfinite || centerLng.isInfinite) {
      print('Error: Invalid center coordinates calculated');
      return;
    }

    // Store selected location BEFORE updating polygon state (to preserve original)
    selectedLocation = SelectedLocation(
      polyID: polyID,
      polygon: polygon,
      marker: null,
    );

    // Update polygon selection state (this will highlight it)
    await _updatePolygonSelectionState(controller, polygon.polygonId, true);

    // Handle existing marker
    Marker? existingMarker;
    try {
      existingMarker = _markers.firstWhere(
            (m) => m.markerId.value.contains(polyID),
      );

      // Store the existing marker's info
      if (existingMarker != null) {
        // Remove the existing marker
        _markers.removeWhere((m) => m.markerId.value.contains(polyID));
      }
    } catch (e) {
      print('No existing marker found for polyID: $polyID');
    }

    // Add a selection marker at the center of the polygon
    try {
      final centerMarker = GeoJsonMarker(
        id: 'selected_$polyID',
        position: MapLocation(
          latitude: centerLat,
          longitude: centerLng,
        ),
        title: 'Selected',
        priority: true,
      );

      await addMarker(controller, PredefinedMarkers.getGenericMarker(centerMarker));
    } catch (e) {
      print('Error adding center marker: $e');
    }

    // Animate camera
    try {
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final maxSpan = max(latSpan, lngSpan);

      double targetZoom = 20.0;
      if (maxSpan > 0.01) targetZoom = 15.0;
      if (maxSpan > 0.1) targetZoom = 12.0;
      if (maxSpan > 1.0) targetZoom = 8.0;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(centerLat, centerLng),
          targetZoom,
        ),
      );
    } catch (e) {
      print('Warning: Failed to animate camera: $e');
    }
    // } catch (e, stackTrace) {
    //   print('Error selecting location: $e');
    //   print('Stack trace: $stackTrace');
    //   selectedLocation = null;
    // }
  }

  Future<void> _updatePolygonSelectionState(
      GoogleMapController controller,
      PolygonId polygonId,
      bool isSelected,
      ) async {
    // Find the polygon to update
    final polygon = _polygons.firstWhere(
          (p) => p.polygonId == polygonId,
      orElse: () => throw Exception('Polygon not found'),
    );

    // Remove the old polygon
    _polygons.removeWhere((p) => p.polygonId == polygonId);

    if (isSelected) {
      // Add highlighted version with green colors
      _polygons.add(
        Polygon(
          polygonId: polygon.polygonId,
          points: polygon.points,
          strokeWidth: 1,
          strokeColor: Colors.blue, // Dark green stroke
          fillColor: Colors.lightBlueAccent.withOpacity(0.3), // Light green fill with transparency
          consumeTapEvents: polygon.consumeTapEvents,
          geodesic: polygon.geodesic,
          visible: polygon.visible,
          zIndex: polygon.zIndex + 10, // Ensure it's on top
        ),
      );
    } else {
      // Add back the original polygon
      _polygons.add(polygon);
    }
  }

  @override
  Future<void> deSelectLocation(dynamic controller) async {
    if (controller is! GoogleMapController) {
      print('Error: Invalid controller type in deSelectLocation');
      return;
    }

    if (selectedLocation == null) {
      return;
    }

    final polyID = selectedLocation!.polyID;

    if (polyID.isEmpty) {
      print('Error: polyID is empty in selectedLocation');
      selectedLocation = null;
      return;
    }

    try {
      // Find the original polygon
      final originalPolygon = selectedLocation!.polygon as Polygon?;
      if (originalPolygon == null) {
        print('Error: Original polygon not found');
        selectedLocation = null;
        return;
      }

      // Restore the original polygon (remove highlighted version and add original back)
      _polygons.removeWhere((p) => p.polygonId.value.contains(polyID));
      _polygons.add(originalPolygon);

      // Remove the selection marker
      try {
        _markers.removeWhere((m) => m.markerId.value.contains('selected_$polyID'));
      } catch (e) {
        print('Error removing selection marker: $e');
      }

      // Restore original marker if it existed
      try {
        final marker = selectedLocation?.marker;
        if (marker != null && marker is GeoJsonMarker) {
          await removeMarker(controller, polyID);
          await addMarker(controller, marker);
        }
      } catch (e) {
        print('Error restoring original marker: $e');
      }

      selectedLocation = null;
    } catch (e, stackTrace) {
      print('Error deselecting location: $e');
      print('Stack trace: $stackTrace');
      selectedLocation = null;
    }
  }

  @override
  Future<void> zoom(controller, {double zoom = 0.0}) async {
    if (controller is GoogleMapController && _controller != null) {
      try {
        // Get current visible region to calculate center
        final bounds = await _controller!.getVisibleRegion();
        final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
        final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

        // Get current zoom level (approximate based on visible region)
        final latDiff = bounds.northeast.latitude - bounds.southwest.latitude;
        final currentZoom = MapCalculations.approximateZoomLevel(latDiff);

        // Apply zoom delta
        final newZoom = currentZoom + zoom;

        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(centerLat, centerLng),
            newZoom.clamp(0.0, 21.0), // Google Maps zoom range
          ),
        );
      } catch (e) {
        print("Error during zoom: $e");
      }
    }
  }

  @override
  Future<void> zoomTo(controller, double zoom) async {
    if (controller is GoogleMapController && _controller != null) {
      try {
        // Get current visible region to maintain center position
        final bounds = await _controller!.getVisibleRegion();
        final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
        final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(centerLat, centerLng),
            zoom.clamp(0.0, 21.0),
          ),
        );
      } catch (e) {
        print("Error during zoomTo: $e");
      }
    }
  }

  @override
  Future<void> addPolylines(controller, List<GeoJsonPolyline> polylines) async {
    for (final polyline in polylines) {
      await addPolyline(controller, polyline);
    }
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> marker) async {
    for (final singleMarker in marker) {
      await addMarker(controller, singleMarker);
    }
  }

  @override
  Future<void> fitCameraToLine(dynamic controller, GeoJsonPolyline polyline,) async {
    if (controller is! GoogleMapController) {
      print('Error: Invalid controller type in fitCameraToLine');
      return;
    }

    if (polyline.points.isEmpty) {
      print('Error: Polyline has no points');
      return;
    }

    if (polyline.points.length < 2) {
      print('Error: Polyline must have at least 2 points');
      return;
    }

    try {
      double minLat = polyline.points.first.latitude;
      double maxLat = polyline.points.first.latitude;
      double minLng = polyline.points.first.longitude;
      double maxLng = polyline.points.first.longitude;

      for (final point in polyline.points) {
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }

      // Prevent invalid bounds
      if (minLat == maxLat && minLng == maxLng) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(minLat, minLng),
            18,
          ),
        );
        return;
      }

      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          80, // padding (important)
        ),
      );
    } catch (e, stackTrace) {
      print('Error fitting camera to polyline: $e');
      print(stackTrace);
    }
  }

  Future<Marker> _convertUserMarker(GeoJsonMarker marker) async {
    MarkerIconWithAnchor markerIconWithAnchor = await creator.createUnifiedMarker(
      text: marker.assetPath != null ? "" : marker.title ?? "",
      imageSource: marker.assetPath,
      layout: MarkerLayout.horizontal,
      textFormat: TextFormat.smartWrap,
      textColor: const Color(0xff000000),
      expandCanvasForRotation: true,
    );
    final Uint8List iconBytes = markerIconWithAnchor.icon;

    return Marker(
      icon: BitmapDescriptor.fromBytes(iconBytes),
      markerId: MarkerId(marker.id),
      position: LatLng(marker.position.latitude, marker.position.longitude),
      rotation: 0.0, // Will be updated by compass
      anchor: markerIconWithAnchor.anchor ?? const Offset(0.5, 0.5),
      flat: true, // Important for rotation
      onTap: () {
        print("user marker tap");
      },
    );
  }


  @override
  Future<void> localizeUser(controller, GeoJsonMarker marker) async {
    if (controller is GoogleMapController) {
      try {
        // Create and add the user marker to the separate _userMarkers set
        final userMarker = await _convertUserMarker(marker);
        _markers.add(userMarker);
        print("userMarker ${userMarker}");

        // Start compass-based rotation updates
        _startCompassListening(marker.id);

        print("User marker added with ID: ${marker.id}");
      } catch (e) {
        print("Error adding user marker: $e");
      }
    }
  }

  StreamSubscription<CompassEvent>? _compassSub;

  void _startCompassListening(String markerId) {
    // Cancel existing subscription if any
    _compassSub?.cancel();

    _compassSub = FlutterCompass.events?.listen((event) async {
      if (event.heading == null) return;

      try {
        // Find the existing user marker
        final existingMarker = _markers.firstWhere(
              (m) => m.markerId.value == markerId,
          orElse: () => throw Exception('User marker not found'),
        );

        // Remove old marker
        _markers.removeWhere((m) => m.markerId.value == markerId);

        // Create updated marker with new rotation
        final updatedMarker = Marker(
          markerId: MarkerId(markerId),
          position: existingMarker.position,
          rotation: event.heading!,
          anchor: existingMarker.anchor,
          flat: true,
          icon: existingMarker.icon,
          onTap: existingMarker.onTap,
        );

        _markers.add(updatedMarker);

      } catch (e) {
        print("Error updating marker rotation: $e");
      }
    });
  }

  @override
  Future<void> moveUser(dynamic controller, String id, MapLocation location) async {
    if (controller is GoogleMapController) {
      try {
        // Find and update the user marker position in the list
        for (var singleMarker in _markers) {
          if (singleMarker.markerId.toString().toLowerCase().contains(id.toLowerCase())) {

            // Find the existing marker in _markers
            final existingMarker = _markers.firstWhere(
                  (m) => m.markerId.value.contains(id),
              orElse: () => throw Exception('Marker not found'),
            );

            // Remove old marker
            _markers.removeWhere((m) => m.markerId.value.contains(id));

            // Add updated marker with new position
            _markers.add(
              Marker(
                markerId: existingMarker.markerId,
                position: LatLng(location.latitude, location.longitude),
                rotation: existingMarker.rotation,
                anchor: existingMarker.anchor,
                flat: existingMarker.flat,
                icon: existingMarker.icon,
                onTap: existingMarker.onTap,
              ),
            );

            print("User marker moved to: ${location.latitude}, ${location.longitude}");
            break;
          }
        }
      } catch (e) {
        print("Error moving user marker: $e");
      }
    }
  }

  @override
  Future<void> fitCameraToBounds(dynamic controller, CameraBound bound) async {
    if (controller is! GoogleMapController) {
      print('Error: Invalid controller type in fitCameraToBounds');
      return;
    }

    try {
      final bounds = LatLngBounds(
        southwest: LatLng(
          bound.southwest.latitude,
          bound.southwest.longitude,
        ),
        northeast: LatLng(
          bound.northeast.latitude,
          bound.northeast.longitude,
        ),
      );

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          80, // padding in pixels
        ),
      );

      print("Camera fitted to bounds: SW(${bound.southwest.latitude}, ${bound.southwest.longitude}) - NE(${bound.northeast.latitude}, ${bound.northeast.longitude})");
    } catch (e, stackTrace) {
      print('Error fitting camera to bounds: $e');
      print('Stack trace: $stackTrace');
    }
  }

// Don't forget to dispose the compass subscription when needed
  void dispose() {
    _compassSub?.cancel();
  }

  @override
  Future<void> addCircle(controller, GeoJsonCircle circle) {
    // TODO: implement addCircle
    throw UnimplementedError();
  }

  @override
  Future<void> removeCircle(controller, String id) {
    // TODO: implement removeCircle
    throw UnimplementedError();
  }

  @override
  Future<void> addSection(controller, GeoJsonPolygon polygon) {
    // TODO: implement addSection
    throw UnimplementedError();
  }

  @override
  void setOnMapTapCallback(Function(MapLocation p1)? callback) {
    // TODO: implement setOnMapTapCallback
    throw UnimplementedError();
  }

}