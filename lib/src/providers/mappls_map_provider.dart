// lib/src/providers/mappls_map_provider.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import 'package:unified_map_view/src/models/selectedLocation.dart';
import '../utils/UnifiedMarkerCreator.dart';
import '../utils/geoJsonUtils.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mappls GL implementation of BaseMapProvider
/// Supports Mappls (MapmyIndia) maps - India's own mapping platform
class MapplsMapProvider extends BaseMapProvider {
  MapplsMapController? _controller;
  final List<GeoJsonMarker> _symbols = [];
  final Map<String, Line> _lines = {};
  final Map<String, Fill> _fills = {};

  SelectedLocation? selectedLocation;

  final String _clusterSourceId = 'markers-source';

  @override
  Widget buildMap({required MapConfig config}) {
    return MapplsMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.mapLocation.latitude,
          config.initialLocation.mapLocation.longitude,
        ),
        zoom: config.initialLocation.zoom,
      ),
      onMapCreated: (MapplsMapController controller) async {
        _controller = controller;
        config.onMapCreated(controller);
        enableClustering(controller);
        controller.onFillTapped.add((Fill){
          var polygons = _fills.entries.where((entry)=>entry.value == Fill);
          print("polygons $polygons");
          if(polygons.isNotEmpty){
            var entry = polygons.first;
            print("key ${entry.key}");
            var keyMap = GeoJsonUtils.extractKeyValueMap(entry.key);
            if(keyMap["id"] == null || keyMap["id"]!.toLowerCase().contains("boundary")) return;
            config.onPolygonTap!(
                coordinates: Fill.options.geometry!.first.map((point)=>MapLocation(latitude: point.latitude, longitude: point.longitude)).toList(),
                polygonId: keyMap["id"]!
            );
            selectLocation(controller,keyMap["id"]!);
          }
        });
      },
      onCameraIdle: ()async{
        if (_controller != null) {
          try {
            final bounds = await _controller!.getVisibleRegion();
              final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
              final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

              final cameraPos = _controller!.cameraPosition;

              config.onCameraMove(UnifiedCameraPosition(
                mapLocation: MapLocation(
                  latitude: centerLat,
                  longitude: centerLng,
                ),
                zoom: cameraPos?.zoom ?? 0.0,
                bearing: cameraPos?.bearing ?? 0.0,
              ));
          } catch (e) {
            print("Error getting camera position: $e");
          }
        }
      },
      myLocationEnabled: config.showUserLocation,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      compassEnabled: true,
      rotateGesturesEnabled: config.rotateGesturesEnabled,
      scrollGesturesEnabled: config.scrollGesturesEnabled,
      tiltGesturesEnabled: config.tiltGesturesEnabled,
      zoomGesturesEnabled: config.zoomControlsEnabled,
      minMaxZoomPreference: const MinMaxZoomPreference(0.0, 23.0),
    );
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapplsMapController) {
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
    
    if (controller is MapplsMapController) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        final cameraPosition = await controller.cameraPosition;
        if(cameraPosition == null) return null;
        return MapLocation(
          latitude: cameraPosition.target.latitude,
          longitude: cameraPosition.target.longitude,
        );
      } catch (e) {
        print('Error getting current location: $e');
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is MapplsMapController && styleJson != null) {
      // Mappls supports different style URLs
      // Default styles: MapmyIndiaStyle.STREET, HYBRID, SATELLITE, etc.
      // Custom style would need to be a valid Mappls style URL
    }
  }


  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is MapplsMapController) {
      if(marker.properties == null || marker.properties!["polyId"] == null) return;
      _symbols.add(marker);

      // Load marker icon if provided
      // if (marker.assetPath != null && marker.iconName != null) {
        await _loadMarkerIcon(controller, marker);
      // }
      try{
        setGeoJsonSource(controller, _symbols);
      }catch(e){
        print("error adding marker $e");
      }
    }
  }

  Future<void> setGeoJsonSource(dynamic controller, List<GeoJsonMarker> symbols) async {
    if (controller is MapplsMapController) {
      final features = _symbols.map((marker)=>
       {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [marker.position.longitude, marker.position.latitude],
        },
        'properties': {
          'title': '',
          'id': marker.id,
          if(marker.iconName != null || true) 'icon': marker.id,
        'isPriority': marker.priority ?? false,
        }
      }).toList();

      await controller.setGeoJsonSource(
        _clusterSourceId,
        {
          "type": "FeatureCollection",
          "features": features,
        },
      );}
    }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MapplsMapController) {
      try {
        // Remove marker from the list
        _symbols.removeWhere((marker) => marker.id.toLowerCase().contains(markerId));

        setGeoJsonSource(controller, _symbols);
      } catch (e) {
        print('Error removing marker: $e');
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        // Clear the marker list
        _symbols.clear();

        // Update the GeoJSON source with empty features
       setGeoJsonSource(controller, []);
      } catch (e) {
        print('Error clearing markers: $e');
      }
    }
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MapplsMapController) {
      try {
        final String? rawType = polygon.properties?["type"]??polygon.properties?["polygonType"];
        final String? type = rawType?.toLowerCase();

        final String? fillColorHex = polygon.properties?["fillColor"];
        final String? strokeColorHex = polygon.properties?["strokeColor"];

        final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(fillColorHex)
            : RenderingUtilities.polygonColorMap[type]?["fillColor"]
            ?? Colors.white;

        final Color strokeColor = (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(strokeColorHex)
            : RenderingUtilities.polygonColorMap[type]?["strokeColor"]
            ?? Color(0xffD3D3D3);

        final coordinates = polygon.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        String fillHex = RenderingUtilities.colorToMapplsHex(fillColor);
        String strokeHex = RenderingUtilities.colorToMapplsHex(strokeColor);

        final fill = await controller.addFill(
          FillOptions(
            geometry: [coordinates],
            fillColor: '#$fillHex',
            fillOpacity: fillColor.opacity,
            fillOutlineColor: '#$strokeHex',
          ),
        );

        _fills[polygon.id] = fill;
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    if (controller is! MapplsMapController) return;

    final entriesToRemove = _fills.entries.where((entry) {
      final id = entry.key;

      if (exclude != null && id.contains(exclude)) {
        return false;
      }

      if (id.contains(polygonId)) {
        return true;
      }

      return false;
    }).toList();
    for (final entry in entriesToRemove) {
      await controller.removeFill(entry.value);
      _fills.remove(entry.key);
    }
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapplsMapController) {
      final fills = List<Fill>.from(_fills.values);

      for (final fill in fills) {
        try {
          await controller.removeFill(fill);
        } catch (_) {}
      }

      _fills.clear();
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MapplsMapController) {
      bool isWaypoint = false;
      if(polyline.properties?["lineCategory"] != null){
        isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }
      if(polyline.properties?["polygonType"] != null){
        isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
      }

      if(isWaypoint) return;
      try {
        final coordinates = polyline.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        final line = await controller.addLine(
          LineOptions(
            geometry: coordinates,
            lineColor: '#fa9b9c9',
            lineWidth: 1.0,
            lineOpacity: 0.8,
          ),
        );

        _lines[polyline.id] = line;
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MapplsMapController) return;

    final matchingEntries = _lines.entries
        .where((entry) => entry.key.contains(polylineId))
        .toList();

    for (final entry in matchingEntries) {
      try {
        await controller.removeLine(entry.value);
      } catch (_) {}

      _lines.remove(entry.key);
    }
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        for (var line in _lines.values) {
          await controller.removeLine(line);
        }
        _lines.clear();
      } catch (e) {
        print('Error clearing polylines: $e');
      }
    }
  }

  /// Clear all map elements
  Future<void> clearAll(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }

  final creator = UnifiedMarkerCreator();
  Future<bool> _loadMarkerIcon(MapplsMapController controller, GeoJsonMarker marker) async {
    try {
      MarkerIconWithAnchor markerIconWithAnchor = await creator.createUnifiedMarker(
        imageSize: const Size(25, 25),
        fontSize: 8.5,
        text: marker.assetPath != null ? "":marker.title ?? "",
        imageSource: marker.assetPath,
        layout: MarkerLayout.horizontal,
        textFormat: TextFormat.smartWrap,
        textColor: const Color(0xff000000),
      );

      final Uint8List iconBytes = markerIconWithAnchor.icon;

      // final ByteData bytes = await rootBundle.load(
      //     marker.assetPath!
      // );
      // final Uint8List image = bytes.buffer.asUint8List();
      await controller.addImage(marker.id, iconBytes);
      return true;
    } catch (e) {
      print('Icon ${marker.iconName}.png not found in ${marker.assetPath!}');
      return false;
    }
  }

  Future<void> enableClustering(dynamic controller) async {
    if (controller is! MapplsMapController) return;

    try {
      await controller.addGeoJsonSource(_clusterSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Layer 1: Normal markers (rendered first, can be hidden)
      await controller.addSymbolLayer(
        _clusterSourceId,
        'normal-markers',
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          textField: ["get", "title"],
          textSize: 12,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 2,
          textAnchor: ["case", ["has", "icon"], "left", "center"],
          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [3.5, 0]],
            ["literal", [0, 0]]
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),
        filter: ["!=", ["get", "isPriority"], true], // Only non-priority markers
        enableInteraction: true,
      );

      // Layer 2: Priority markers (rendered last, always visible)
      await controller.addSymbolLayer(
        _clusterSourceId,
        'priority-markers',
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          textField: ["get", "title"],
          textSize: 12,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 2,
          textAnchor: ["case", ["has", "icon"], "left", "center"],
          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [3.5, 0]],
            ["literal", [0, 0]]
          ],
          iconAllowOverlap: true,  // Priority markers always show
          textAllowOverlap: true,
        ),
        filter: ["==", ["get", "isPriority"], true], // Only priority markers
        enableInteraction: true,
      );

      if(_symbols.isNotEmpty){
        List<GeoJsonMarker> symbols = [..._symbols];
        clearMarkers(controller);
        setGeoJsonSource(controller, symbols);
      }

    } catch (e) {
      print('Error enabling clustering: $e');
    }
  }

  @override
  Future<void> addPolygons(controller, List<GeoJsonPolygon> polygons) {
    // TODO: implement addPolygons
    throw UnimplementedError();
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {

    // Edge case: Validate controller type
    if (controller is! MapplsMapController) {
      print('Error: Invalid controller type');
      return;
    }

    // Edge case: Validate polyID
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }

    // Edge case: Deselect previous location if exists
    if (selectedLocation != null) {
      await deSelectLocation(controller);
    }

    try {
      // Edge case: Check if _fills map is empty
      if (_fills.isEmpty) {
        print('Error: No polygons available to select');
        return;
      }

      // Find the polygon that contains polyID
      final polygonEntry = _fills.entries.firstWhere(
            (entry) => entry.key.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      final Fill polygonFill = polygonEntry.value;
      final String polygonId = polygonEntry.key;

      // Edge case: Validate polygon options
      if (polygonFill.options == null) {
        print('Error: Polygon options are null for $polygonId');
        return;
      }

      // Get the polygon's coordinates
      final coordinates = polygonFill.options.geometry?.first;

      // Edge case: Validate coordinates exist and have sufficient points
      if (coordinates == null || coordinates.isEmpty) {
        print('Error: No coordinates found for polygon: $polygonId');
        return;
      }

      if (coordinates.length < 3) {
        print('Error: Polygon must have at least 3 points: $polygonId');
        return;
      }

      // Calculate bounds of the polygon with validation
      double minLat = coordinates.first.latitude;
      double maxLat = coordinates.first.latitude;
      double minLng = coordinates.first.longitude;
      double maxLng = coordinates.first.longitude;

      for (final point in coordinates) {
        // Edge case: Validate coordinate values
        if (point.latitude < -90 || point.latitude > 90) {
          print('Warning: Invalid latitude ${point.latitude} for $polygonId');
          continue;
        }
        if (point.longitude < -180 || point.longitude > 180) {
          print('Warning: Invalid longitude ${point.longitude} for $polygonId');
          continue;
        }

        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }

      // Edge case: Check for degenerate polygon (all points are the same)
      if (minLat == maxLat && minLng == maxLng) {
        print('Warning: Polygon has no area (all points identical): $polygonId');
        // Still proceed but with a default zoom or fixed offset
      }

      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Edge case: Validate center coordinates
      if (centerLat.isNaN || centerLng.isNaN ||
          centerLat.isInfinite || centerLng.isInfinite) {
        print('Error: Invalid center coordinates calculated for $polygonId');
        return;
      }

      // Remove the old polygon
      try {
        await controller.removeFill(polygonFill);
      } catch (e) {
        print('Warning: Failed to remove old polygon: $e');
        // Continue anyway as it might have been already removed
      }

      // Add the polygon back with highlighted colors
      final highlightedFill = await controller.addFill(
        FillOptions(
          geometry: [coordinates],
          fillColor: '#4CAF50', // Bright green for highlight
          fillOpacity: 0.6,
          fillOutlineColor: '#2E7D32', // Darker green for border
        ),
      );

      // Edge case: Validate the highlighted fill was created
      if (highlightedFill == null) {
        print('Error: Failed to create highlighted fill for $polygonId');
        return;
      }

      // Update the fills map with the new highlighted fill
      _fills[polygonId] = highlightedFill;

      selectedLocation = SelectedLocation(
          polyID: polyID,
          polygon: polygonFill,
          marker: null
      );

      // Find and show the marker associated with this polygon
      try {
        // Edge case: Check if _symbols list is empty
        if (_symbols.isEmpty) {
          print('No markers available for polyID: $polyID');
        } else {
          final marker = _symbols.firstWhere(
                (m) => m.id.contains(polyID),
            orElse: () => throw Exception('Marker not found'),
          );

          selectedLocation?.setLocation(
              polyID: polyID,
              polygon: polygonFill,
              marker: marker
          );

          final genericMarker = GeoJsonMarker.getGenericMarker(marker);

          // Edge case: Validate generic marker creation
          if (genericMarker == null) {
            print('Error: Failed to create generic marker for $polyID');
          } else {
            // Remove the marker first if it exists
            removeMarker(controller, polyID);
            addMarker(controller, genericMarker);
          }
        }
      } catch (e) {
        print('No marker found for polyID: $polyID - $e');
        // Not a critical error, continue without marker
      }

      // Animate camera to the polygon center
      try {
        // Edge case: Calculate appropriate zoom level based on polygon size
        final latSpan = maxLat - minLat;
        final lngSpan = maxLng - minLng;
        final maxSpan = max(latSpan, lngSpan);

        // Adjust zoom based on polygon size (larger polygons need lower zoom)
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
        // Not critical, polygon is still selected
      }

    } catch (e, stackTrace) {
      print('Error selecting location: $e');
      print('Stack trace: $stackTrace');

      // Edge case: Cleanup on failure
      if (selectedLocation != null) {
        selectedLocation = null;
      }
    }
  }

  /// Deselect a polygon and restore its original colors
  Future<void> deSelectLocation(dynamic controller) async {
    // Edge case: Validate controller type
    if (controller is! MapplsMapController) {
      print('Error: Invalid controller type in deSelectLocation');
      return;
    }

    // Edge case: Check if there's anything to deselect
    if (selectedLocation == null) {
      return;
    }

    var polyID = selectedLocation!.polyID;

    // Edge case: Validate polyID
    if (polyID.isEmpty) {
      print('Error: polyID is empty in selectedLocation');
      selectedLocation = null;
      return;
    }

    try {
      // Edge case: Check if _fills map is empty
      if (_fills.isEmpty) {
        print('Error: No polygons available in _fills map');
        selectedLocation = null;
        return;
      }

      // Find the polygon that contains polyID
      final polygonEntry = _fills.entries.firstWhere(
            (entry) => entry.key.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      final Fill polygonFill = polygonEntry.value;
      final String polygonId = polygonEntry.key;

      // Edge case: Validate polygon options
      if (polygonFill.options == null) {
        print('Error: Polygon options are null for $polygonId');
        selectedLocation = null;
        return;
      }

      // Get the polygon's coordinates
      final coordinates = polygonFill.options.geometry?.first;

      // Edge case: Validate coordinates
      if (coordinates == null || coordinates.isEmpty) {
        print('Error: No coordinates found for polygon: $polygonId');
        selectedLocation = null;
        return;
      }

      // Get the original properties
      final originalProps = selectedLocation?.polygon as Fill?;

      // Edge case: Handle missing original properties
      if (originalProps == null || originalProps.options == null) {
        print('Warning: No original properties found, using defaults for: $polygonId');
        // Use default colors instead of failing
      }

      // Remove the highlighted polygon
      try {
        await controller.removeFill(polygonFill);
      } catch (e) {
        print('Warning: Failed to remove highlighted polygon: $e');
        // Continue anyway
      }

      // Add the polygon back with original colors (or defaults if not available)
      final restoredFill = await controller.addFill(
        FillOptions(
          geometry: [coordinates],
          fillColor: originalProps?.options.fillColor ?? '#FFFFFF',
          fillOpacity: originalProps?.options.fillOpacity ?? 0.5,
          fillOutlineColor: originalProps?.options.fillOutlineColor ?? '#D3D3D3',
        ),
      );

      // Edge case: Validate restored fill was created
      if (restoredFill == null) {
        print('Error: Failed to create restored fill for $polygonId');
      } else {
        // Update the fills map with the restored fill
        _fills[polygonId] = restoredFill;
      }

      // Hide the marker associated with this polygon
      try {
        final marker = selectedLocation?.marker as GeoJsonMarker?;

        // Edge case: Check if marker exists before trying to hide it
        if (marker != null) {
          // Remove the marker from the symbols list
          removeMarker(controller, polyID);
            // Marker was removed, now add it back with original state
            await addMarker(controller, marker);
        } else {
          print('No marker associated with this location');
        }
      } catch (e) {
        print('Error hiding marker: $e');
        // Not critical, continue with deselection
      }

      // Remove the stored original properties as it's now restored
      selectedLocation = null;

    } catch (e, stackTrace) {
      print('Error deselecting location: $e');
      print('Stack trace: $stackTrace');

      // Edge case: Force cleanup even on error
      selectedLocation = null;
    }
  }
}