// lib/src/providers/mappls_map_provider.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import '../utils/UnifiedMarkerCreator.dart';
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

  final Map<String, Map<String, dynamic>> _originalPolygonProperties = {};

  String _clusterSourceId = 'markers-source';

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
          if(polygons.isNotEmpty){
            var entry = polygons.first;
            config.onPolygonTap!(
                coordinates: Fill.options.geometry!.first.map((point)=>MapLocation(latitude: point.latitude, longitude: point.longitude)).toList(),
                polygonId: entry.key
            );
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
      _symbols.add(marker);

      // Load marker icon if provided
      // if (marker.assetPath != null && marker.iconName != null) {
        await _loadMarkerIcon(controller, marker);
      // }
      try{
        setGeoJsonSource(controller, _symbols);
      }catch(e){
        rethrow;
      }
    }
  }

  Future<void> setGeoJsonSource(dynamic controller, List<GeoJsonMarker> symbols) async {
    if (controller is MapplsMapController) {
      final features = _symbols.map((marker) =>
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [marker.position.longitude, marker.position.latitude],
        },
        'properties': {
          'title': '',
          'id': marker.id,
          if(marker.iconName != null || true)'icon': marker.id,
        }
      }).toList();

      await controller.setGeoJsonSource(
        _clusterSourceId,
        {
          "type": "FeatureCollection",
          "features": features,
        },
      );
    }
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
        await controller.setGeoJsonSource(
          _clusterSourceId,
          {
            "type": "FeatureCollection",
            "features": [],
          },
        );
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

      await controller.addSymbolLayer(
        _clusterSourceId,
        'cluster-count',
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          textField: ["get", "title"],
          textSize: 12,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 2,
          textAnchor: [
            "case",
            ["has", "icon"],
            "left",
            "center"
          ],
          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [3.5, 0]],
            ["literal", [0, 0]]
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),
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
    if (controller is! MapplsMapController) return;

    try {
      // Find the polygon that contains polyID
      final polygonEntry = _fills.entries.firstWhere(
            (entry) => entry.key.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      final Fill polygonFill = polygonEntry.value;
      final String polygonId = polygonEntry.key;

      // Get the polygon's coordinates
      final coordinates = polygonFill.options.geometry?.first;
      if (coordinates == null || coordinates.isEmpty) {
        print('No coordinates found for polygon: $polygonId');
        return;
      }

      // Store original properties if not already stored
      if (!_originalPolygonProperties.containsKey(polygonId)) {
        _originalPolygonProperties[polygonId] = {
          'fillColor': polygonFill.options.fillColor,
          'fillOpacity': polygonFill.options.fillOpacity,
          'fillOutlineColor': polygonFill.options.fillOutlineColor,
        };
      }

      // Calculate bounds of the polygon
      double minLat = coordinates.first.latitude;
      double maxLat = coordinates.first.latitude;
      double minLng = coordinates.first.longitude;
      double maxLng = coordinates.first.longitude;

      for (final point in coordinates) {
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }

      // Calculate center point
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Remove the old polygon
      await controller.removeFill(polygonFill);

      // Add the polygon back with highlighted colors
      final highlightedFill = await controller.addFill(
        FillOptions(
          geometry: [coordinates],
          fillColor: '#4CAF50', // Bright green for highlight
          fillOpacity: 0.6,
          fillOutlineColor: '#2E7D32', // Darker green for border
        ),
      );

      // Update the fills map with the new highlighted fill
      _fills[polygonId] = highlightedFill;

      // Find and show the marker associated with this polygon
      try {
        final marker = _symbols.firstWhere(
              (m) => m.id.contains(polyID),
        );

        // Remove the marker first if it exists
        _symbols.removeWhere((m) => m.id.contains(polyID));

        // Add it back to ensure it's visible and on top
        _symbols.add(GeoJsonMarker.getGenericMarker(marker.position));

        // Update the GeoJSON source to show the marker
        await setGeoJsonSource(controller, _symbols);

        print('Showing marker: ${marker.id}');
      } catch (e) {
        print('No marker found for polyID: $polyID');
      }

      // Animate camera to the polygon center
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(centerLat, centerLng),
          20,
        ),
      );

      print('Selected and zoomed to polygon: $polygonId with marker');
    } catch (e) {
      print('Error selecting location: $e');
    }
  }

  /// Deselect a polygon and restore its original colors
  Future<void> deSelectLocation(dynamic controller, String polyID) async {
    if (controller is! MapplsMapController) return;

    try {
      // Find the polygon that contains polyID
      final polygonEntry = _fills.entries.firstWhere(
            (entry) => entry.key.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      final Fill polygonFill = polygonEntry.value;
      final String polygonId = polygonEntry.key;

      // Get the polygon's coordinates
      final coordinates = polygonFill.options.geometry?.first;
      if (coordinates == null || coordinates.isEmpty) {
        print('No coordinates found for polygon: $polygonId');
        return;
      }

      // Get the original properties
      final originalProps = _originalPolygonProperties[polygonId];
      if (originalProps == null) {
        print('No original properties found for polygon: $polygonId');
        return;
      }

      // Remove the highlighted polygon
      await controller.removeFill(polygonFill);

      // Add the polygon back with original colors
      final restoredFill = await controller.addFill(
        FillOptions(
          geometry: [coordinates],
          fillColor: originalProps['fillColor'] ?? '#FFFFFF',
          fillOpacity: originalProps['fillOpacity'] ?? 0.5,
          fillOutlineColor: originalProps['fillOutlineColor'] ?? '#D3D3D3',
        ),
      );

      // Update the fills map with the restored fill
      _fills[polygonId] = restoredFill;

      // Hide the marker associated with this polygon
      try {
        // Remove the marker from the symbols list
        _symbols.removeWhere((m) => m.id.contains(polyID));

        // Update the GeoJSON source to hide the marker
        await setGeoJsonSource(controller, _symbols);

        print('Hidden marker for polyID: $polyID');
      } catch (e) {
        print('Error hiding marker: $e');
      }

      // Remove the stored original properties as it's now restored
      _originalPolygonProperties.remove(polygonId);

      print('Deselected polygon: $polygonId');
    } catch (e) {
      print('Error deselecting location: $e');
    }
  }
}