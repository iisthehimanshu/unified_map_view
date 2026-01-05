// lib/src/providers/mappls_map_provider.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import 'package:unified_map_view/src/models/selectedLocation.dart';
import '../utils/UnifiedMarkerCreator.dart';
import '../utils/geoJson/geoJsonUtils.dart';
import '../utils/geoJson/predefined_markers.dart';
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
  final List<GeoJsonMarker> _rotatingSymbols = [];
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _lines = [];

  late MapConfig _config;

  SelectedLocation? selectedLocation;

  final String _clusterSourceId = 'markers-source';
  final String _normalMarkerLayerId = 'normal-markers-layer';
  final String _priorityMarkerLayerId = 'priority-marker-layer';

  final String _rotationSourceId = 'rotation-markers-source';
  final String _rotationMarkerLayerId = 'rotation-marker-layer';

  final String _polygonSourceId = 'polygons-source';
  final String _normalPolygonLayerId = 'normal-polygons-layer';
  final String _selectedPolygonLayerId = 'selected-polygon-layer';
  final String _patchPolygonLayerId = 'patch-polygon-layer';

  final String _polylineSourceId = 'polylines-source';
  final String _pathLayerId = 'path-polyline-layer';
  final String _polylineLayerId = 'normal-polyline-layer';

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
        _config = config;
        _controller = controller;
        config.onMapCreated(controller);
        await enableClustering(controller);
        await enablePolygonLayers(controller);
        await enablePolylineLayers(controller);

        // Handle polygon taps
        controller.onFeatureTapped.add((id, point, coordinates) {
          print("id $id $point $coordinates");
            // Extract polygon ID from the feature
            final polygonId = _extractPolygonIdFromTap(id);
            if (polygonId != null && !polygonId.toLowerCase().contains("boundary")) {
              selectLocation(controller, polygonId);
            }
        });
      },
      onCameraIdle: () async {
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
        if (cameraPosition == null) return null;
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
    print("addMarker ${StackTrace.current}");
    if (controller is MapplsMapController) {

      await _loadMarkerIcon(controller, marker);
      if(marker.compassBasedRotation){
        _rotatingSymbols.add(marker);
        try{
          setGeoJsonSource(controller, _rotatingSymbols, sourceID: _rotationSourceId);
        }catch(e){
          print("error adding marker $e");
        }
      }else{
        _symbols.add(marker);
        try{
          setGeoJsonSource(controller, _symbols);
        }catch(e){
          print("error adding marker $e");
        }
      }

      // Load marker icon if provided
      // if (marker.assetPath != null && marker.iconName != null) {
      // }
    }
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> markers) async {
    if (controller is MapplsMapController) {
      _symbols.addAll(markers);
      for (var marker in markers) {
        if(marker.properties == null || marker.properties!["polyId"] == null) continue;
        await _loadMarkerIcon(controller, marker);
      }
      try{
        setGeoJsonSource(controller, _symbols);
      }catch(e){
        print("error adding marker $e");
      }
    }
  }

  Future<void> setGeoJsonSource(dynamic controller, List<GeoJsonMarker> symbols, {String? sourceID}) async {
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
          'intractable': marker.properties?["polyId"] != null
        }
      }).toList();

      await controller.setGeoJsonSource(
        sourceID??_clusterSourceId,
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
        _polygons.add(polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.addAll(polygons);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygons: $e');
      }
    }
  }

  Future<void> _updatePolygonSource(MapplsMapController controller) async {
    final features = _polygons.map((polygon) {
      final String? rawType = polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];
      final String? strokeColorHex = polygon.properties?["strokeColor"];

      final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"] ?? Colors.white;

      final Color strokeColor = (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(strokeColorHex)
          : RenderingUtilities.polygonColorMap[type]?["strokeColor"] ?? Color(0xffD3D3D3);

      final coordinates = polygon.points
          .map((p) => [p.longitude, p.latitude])
          .toList();

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coordinates],
        },
        'properties': {
          'id': polygon.id,
          'type': type ?? 'default',
          'fillColor': '#${RenderingUtilities.colorToMapplsHex(fillColor)}',
          'strokeColor': '#${RenderingUtilities.colorToMapplsHex(strokeColor)}',
          'fillOpacity': fillColor.opacity,
          'isSelected': false,
          'boundary' : polygon.id.toLowerCase().contains("boundary")
        }
      };
    }).toList();

    await controller.setGeoJsonSource(
      _polygonSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId, {String? exclude}) async {
    if (controller is! MapplsMapController) return;

    _polygons.removeWhere((polygon) {
      final id = polygon.id;

      if (exclude != null && id.contains(exclude)) {
        return false;
      }

      return id.contains(polygonId);
    });

    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.clear();
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error clearing polygons: $e');
      }
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MapplsMapController) {
      bool isWaypoint = false;
      if (polyline.properties?["lineCategory"] != null) {
        isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }
      if (polyline.properties?["polygonType"] != null) {
        isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
      }

      if (isWaypoint) return;

      try {
        _lines.add(polyline);
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> addPolylines(controller, List<GeoJsonPolyline> polylines) async {
    if (controller is MapplsMapController) {
      for (var polyline in polylines) {
        bool isWaypoint = false;
        if (polyline.properties?["lineCategory"] != null) {
          isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
        }
        if (polyline.properties?["polygonType"] != null) {
          isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
        }

        if (isWaypoint) continue;

        try {
          _lines.add(polyline);
        } catch (e) {
          print('Error adding polyline: $e');
        }
      }
      await _updatePolylineSource(controller);
    }
  }

  Future<void> _updatePolylineSource(MapplsMapController controller) async {
    final features = _lines.map((line) {
      return {
        'type': 'Feature',
        'id': line.id,
        'geometry': {
          'type': 'LineString',
          'coordinates': line.points.map((point) => [point.longitude, point.latitude]).toList(),
        },
        'properties': {
          'id': line.id,
          'type': 'default',
          'isSelected': false,
          'strokeColor': '#000000',
          'fillColor': '#000000',
          'fillOpacity': 1.0,
          'path': line.id.toLowerCase().contains("path")
        }
      };
    }).toList();

    await controller.setGeoJsonSource(
      _polylineSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MapplsMapController) return;

    _lines.removeWhere((line) {
      final id = line.id;
      return id.contains(polylineId);
    });

    await _updatePolylineSource(controller);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        _lines.clear();
        await _updatePolylineSource(controller);
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
        imageSize: marker.imageSize??const Size(25, 25),
        fontSize: 8.5,
        text: marker.assetPath != null ? "" : marker.title ?? "",
        imageSource: marker.assetPath,
        layout: MarkerLayout.horizontal,
        textFormat: TextFormat.smartWrap,
        textColor: const Color(0xff000000),
      );

      final Uint8List iconBytes = markerIconWithAnchor.icon;
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
          _normalMarkerLayerId,
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
          filter: ["!=", ["get", "isPriority"], true],
          enableInteraction: true,
          belowLayerId: _priorityMarkerLayerId
      );

      // Layer 2: Priority markers (rendered last, always visible)
      await controller.addSymbolLayer(
        _clusterSourceId,
        _priorityMarkerLayerId,
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
          iconAllowOverlap: true,
          textAllowOverlap: true,
        ),
        filter: ["==", ["get", "isPriority"], true],
        enableInteraction: true,
      );

      await controller.addSymbolLayer(
          _rotationSourceId,
          _rotationMarkerLayerId,
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
            iconRotate: ["get", "bearing"],
            iconRotationAlignment: "map",
            iconAllowOverlap: true,
            textAllowOverlap: false,
          ),
          filter: ["!=", ["get", "isPriority"], true],
          enableInteraction: true,
          belowLayerId: _priorityMarkerLayerId
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

  /// Enable polygon layers with GeoJSON source
  Future<void> enablePolygonLayers(MapplsMapController controller) async {
    try {
      // Create GeoJSON source for polygons
      await controller.addGeoJsonSource(_polygonSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Add fill layer for patch polygons (bottom-most)
      await controller.addFillLayer(
          _polygonSourceId,
          _patchPolygonLayerId,
          FillLayerProperties(
            fillColor: ["get", "fillColor"],
            fillOpacity: ["get", "fillOpacity"],
            fillOutlineColor: ["get", "strokeColor"],
          ),
          filter: ["==", ["get", "boundary"], true],
          enableInteraction: true,
          belowLayerId: _normalMarkerLayerId // Position below markers
      );

      // Add fill layer for normal polygons
      await controller.addFillLayer(
          _polygonSourceId,
          _normalPolygonLayerId,
          FillLayerProperties(
            fillColor: ["get", "fillColor"],
            fillOpacity: ["get", "fillOpacity"],
            fillOutlineColor: ["get", "strokeColor"],
          ),
          filter: ["!=", ["get", "isSelected"], true],
          enableInteraction: true,
          belowLayerId: _normalMarkerLayerId // Position below markers
      );

      // Add fill layer for selected polygon
      await controller.addFillLayer(
          _polygonSourceId,
          _selectedPolygonLayerId,
          FillLayerProperties(
            fillColor: "#4CAF50",
            fillOpacity: 0.6,
            fillOutlineColor: "#2E7D32",
          ),
          filter: ["==", ["get", "isSelected"], true],
          enableInteraction: true,
          belowLayerId: _normalMarkerLayerId // Position below markers
      );

      if (_polygons.isNotEmpty) {
        await _updatePolygonSource(controller);
      }
    } catch (e) {
      print('Error enabling polygon layers: $e');
    }
  }

  Future<void> enablePolylineLayers(MapplsMapController controller) async {
    try {
      // Create GeoJSON source for polylines
      await controller.addGeoJsonSource(_polylineSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Add line layer for path polylines
      await controller.addLineLayer(
          _polylineSourceId,
          _pathLayerId,
          LineLayerProperties(
            lineColor: '#448AFF',
            lineWidth: 4.0,
            lineOpacity: 1.0,
          ),
          filter: ["==", ["get", "path"], true],
          enableInteraction: true,
          belowLayerId: _normalMarkerLayerId // Position below markers
      );

      // Add line layer for normal polylines
      await controller.addLineLayer(
          _polylineSourceId,
          _polylineLayerId,
          LineLayerProperties(
            lineColor: ["get", "strokeColor"],
            lineWidth: ["get", "strokeWidth"],
            lineOpacity: ["get", "strokeOpacity"],
          ),
          filter: ["!=", ["get", "path"], true],
          enableInteraction: true,
          belowLayerId: _normalMarkerLayerId // Position below markers
      );

      if (_lines.isNotEmpty) {
        await _updatePolylineSource(controller);
      }
    } catch (e) {
      print('Error enabling polyline layers: $e');
    }
  }

  /// Extract polygon ID from tap coordinates
  String? _extractPolygonIdFromTap(String key) {
    var keyMap = GeoJsonUtils.extractKeyValueMap(key);
    if(keyMap["id"] != null) return keyMap["id"];
    return null;
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    if (controller is! MapplsMapController) {
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

    try {
      if (_polygons.isEmpty) {
        print('Error: No polygons available to select');
        return;
      }

      // Find the polygon
      final polygon = _polygons.firstWhere(
            (p) => p.id.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      // Validate coordinates
      if (polygon.points.isEmpty) {
        print('Error: No coordinates found for polygon: ${polygon.id}');
        return;
      }

      if (polygon.points.length < 3) {
        print('Error: Polygon must have at least 3 points: ${polygon.id}');
        return;
      }

      // Trigger callback
      _config.onPolygonTap?.call(
        coordinates: polygon.points,
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

      // Update polygon selection state in source
      await _updatePolygonSelectionState(controller, polygon.id, true);

      // Store selected location
      selectedLocation = SelectedLocation(
        polyID: polyID,
        polygon: polygon,
        marker: null,
      );

      // Handle marker
      try {
        if (_symbols.isNotEmpty) {
          final marker = _symbols.firstWhere(
                (m) => m.id.contains(polyID),
            orElse: () => throw Exception('Marker not found'),
          );

          selectedLocation?.setLocation(
            polyID: polyID,
            polygon: polygon,
            marker: marker,
          );

          final genericMarker = PredefinedMarkers.getGenericMarker(marker);
          await removeMarker(controller, polyID);
          await addMarker(controller, genericMarker);
        }
      } catch (e) {
        print('No marker found for polyID: $polyID - $e');
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
    } catch (e, stackTrace) {
      print('Error selecting location: $e');
      print('Stack trace: $stackTrace');
      selectedLocation = null;
    }
  }

  /// Update polygon selection state in GeoJSON source
  Future<void> _updatePolygonSelectionState(
      MapplsMapController controller,
      String polygonId,
      bool isSelected,
      ) async {
    // Update the polygon's isSelected property in the list
    final index = _polygons.indexWhere((p) => p.id == polygonId);
    if (index == -1) return;

    // Rebuild the GeoJSON with updated selection state
    final features = _polygons.map((polygon) {
      final String? rawType = polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];
      final String? strokeColorHex = polygon.properties?["strokeColor"];

      final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"] ?? Colors.white;

      final Color strokeColor = (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(strokeColorHex)
          : RenderingUtilities.polygonColorMap[type]?["strokeColor"] ?? Color(0xffD3D3D3);

      final coordinates = polygon.points
          .map((p) => [p.longitude, p.latitude])
          .toList();

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coordinates],
        },
        'properties': {
          'id': polygon.id,
          'type': type ?? 'default',
          'fillColor': '#${RenderingUtilities.colorToMapplsHex(fillColor)}',
          'strokeColor': '#${RenderingUtilities.colorToMapplsHex(strokeColor)}',
          'fillOpacity': fillColor.opacity,
          'isSelected': polygon.id == polygonId ? isSelected : false,
        }
      };
    }).toList();

    await controller.setGeoJsonSource(
      _polygonSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  /// Deselect a polygon and restore its original colors
  Future<void> deSelectLocation(dynamic controller) async {
    if (controller is! MapplsMapController) {
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
      // Update polygon selection state
      await _updatePolygonSelectionState(controller, polyID, false);

      // Handle marker
      try {
        final marker = selectedLocation?.marker as GeoJsonMarker?;
        if (marker != null) {
          await removeMarker(controller, polyID);
          await addMarker(controller, marker);
        }
      } catch (e) {
        print('Error handling marker during deselection: $e');
      }

      selectedLocation = null;
    } catch (e, stackTrace) {
      print('Error deselecting location: $e');
      print('Stack trace: $stackTrace');
      selectedLocation = null;
    }
  }

  @override
  Future<void> zoom(dynamic controller, {double zoom = 0.0}) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      final cameraPos = _controller!.cameraPosition;

      await animateCamera(
        controller,
        MapLocation(
          latitude: centerLat,
          longitude: centerLng,
        ),
        (cameraPos?.zoom ?? 0.0) + zoom,
      );
    } catch (e) {
      print("Error zoom: $e");
    }
  }

  @override
  Future<void> zoomTo(controller, double zoom) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      await animateCamera(
        controller,
        MapLocation(
          latitude: centerLat,
          longitude: centerLng,
        ),
        zoom,
      );
    } catch (e) {
      print("Error zoomTo: $e");
    }
  }

  @override
  Future<void> fitCameraToLine(controller, GeoJsonPolyline polyline) async {
    if (polyline.points.isEmpty) return;

    // Calculate bounds from all points in the line
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

    // Add padding to the bounds (adjust these values as needed)
    final latPadding = (maxLat - minLat) * 0.1; // 10% padding
    final lngPadding = (maxLng - minLng) * 0.1;

    // Create bounds with padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    // Animate camera to fit bounds
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,    // Edge padding in pixels
        top: 50,
        right: 50,
        bottom: 50,
      ),
    );
  }
}