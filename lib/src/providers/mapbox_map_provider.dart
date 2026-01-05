// lib/src/providers/mapbox_map_provider.dart

import 'dart:convert';
import 'dart:math';
import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../unified_map_view.dart';
import '../models/camera_position.dart';
import '../models/selectedLocation.dart';
import '../utils/LandmarkAssetType.dart';
import '../utils/geoJson/predefined_markers.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mapbox implementation of BaseMapProvider
class MapboxMapProvider extends BaseMapProvider {
  late MapboxMap _mapboxMap;
  static const String _markerSourceId = 'marker-source';
  static const String _normalMarkerLayerId = 'normal-marker-layer';
  static const String _priorityMarkerLayerId = 'priority-marker-layer';
  final Map<String, GeoJsonMarker> _markers = {};

  static const String _polygonSourceId = 'polygon-source';
  static const String _polygonLayerId  = 'polygon-extrusion-layer';
  final Map<String, GeoJsonPolygon> _polygons = {};

  static const String _polylineSourceId = 'polyline-source';
  static const String _pathPolylineLayerId = 'path-polyline-layer';
  static const String _normalPolylineLayerId = 'normal-polyline-layer';
  final Map<String, GeoJsonPolyline> _polylines = {};

  SelectedLocation? selectedLocation;

  @override
  Widget buildMap({
    required MapConfig config}) {
    return MapWidget(       
      onMapCreated: (mapboxMap) async {
        config.onMapCreated(mapboxMap);
        _mapboxMap = mapboxMap;
         await _initMarkerLayer(mapboxMap);
         mapboxMap.setOnMapTapListener((value) async {
           print("🟢 Map tapped at: ${value.point.coordinates.lat}, ${value.point.coordinates.lng}");
           final screenCoordinate = await mapboxMap.pixelForCoordinate(value.point);

           final features = await mapboxMap.queryRenderedFeatures(
             RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
             RenderedQueryOptions(
               layerIds: [
                 'marker-symbol-layer',
                 'polygon-extrusion-layer',
               ],
             ),
           );

           features.forEach((value){
             if(value?.layers[0] == _polygonLayerId && value?.layers[0] != null && !value!.queriedFeature.feature['id'].toString().contains('boundary')){
               dynamic geometry = value.queriedFeature.feature['geometry']!;
               final coordinates = geometry['coordinates'] as List<dynamic>;
               final List<MapLocation> polygonPoints = (coordinates.first as List<dynamic>).map((point) {
                 final lng = point[0] as double;
                 final lat = point[1] as double;
                 return MapLocation(latitude: lat, longitude: lng,);
               }).toList();
               if(coordinates.length == 1){
                 config.onPolygonTap!(coordinates: polygonPoints, polygonId: value.queriedFeature.feature['id']!.toString());
                 var keyMap = GeoJsonUtils.extractKeyValueMap(value.queriedFeature.feature['id'].toString());
                 print("keyMap $keyMap");
                 if(keyMap["id"] == null || keyMap["id"]!.toLowerCase().contains("boundary")) return;
                 selectLocation(mapboxMap,keyMap["id"]!);
               }
             }
           });
         });
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
      onMapIdleListener: (MapIdleEventData mapIdleEventData) async {
        try {
          final cameraState = await _mapboxMap.getCameraState();
          config.onCameraMove(
            UnifiedCameraPosition(
              mapLocation: MapLocation(
                latitude: cameraState.center.coordinates.lat.toDouble(),
                longitude: cameraState.center.coordinates.lng.toDouble(),
              ),
              zoom: cameraState.zoom ?? 0.0,
              bearing: cameraState.bearing ?? 0.0,
            ),
          );
        } catch (e) {
          print("Error getting camera state: $e");
        }
      },
      textureView: true,
    );
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    if (controller is! MapboxMap) {
      print('Error: Invalid controller type');
      return;
    }
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }
    if (selectedLocation != null) {
      await deSelectLocation(controller);
    }

    try {
      if (_polygons.isEmpty) {
        print('Error: No polygons available to select');
        return;
      }

      final polygonEntry = _polygons.entries.firstWhere(
            (entry) => entry.key.contains(polyID),
        orElse: () => throw Exception('Polygon with ID containing "$polyID" not found'),
      );

      GeoJsonPolygon polygon = polygonEntry.value;
      final String polygonId = polygonEntry.key;

      print("received polyID $polygonId");

      final coordinates = polygon.points;
      if (coordinates == null || coordinates.isEmpty || coordinates.length < 3) {
        print('Error: Invalid polygon coordinates');
        return;
      }

      // Calculate bounds and center
      double minLat = coordinates.first.latitude;
      double maxLat = coordinates.first.latitude;
      double minLng = coordinates.first.longitude;
      double maxLng = coordinates.first.longitude;

      for (final point in coordinates) {
        if (point.latitude < -90 || point.latitude > 90 ||
            point.longitude < -180 || point.longitude > 180) {
          continue;
        }
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }

      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      if (centerLat.isNaN || centerLng.isNaN ||
          centerLat.isInfinite || centerLng.isInfinite) {
        print('Error: Invalid center coordinates');
        return;
      }

      // Update polygon color
      final updatedProperties = Map<String, dynamic>.from(polygon.properties ?? {});
      updatedProperties['onTap'] = "#aec6cf";

      final updatedPolygon = GeoJsonPolygon(
        id: polygon.id,
        points: polygon.points,
        properties: updatedProperties,
      );

      _polygons[polygonId] = updatedPolygon;
      await _updatePolygonSource(controller);

      // Remove existing markers for this polygon
      await removeMarker(controller, polygonId);

      // Add priority landmark marker (will render on top layer)
      final landmarkMarker = GeoJsonMarker(
        id: 'landmark_$polygonId',
        position: MapLocation(latitude: centerLat, longitude: centerLng),
        title: 'generic',  // Change based on your needs
        priority: true,  // KEY: This makes it render on the priority layer
        properties: {
          'polyId': polygonId,
          'type': 'Wall',

        },
        textVisibility: false
      );
      final marker = PredefinedMarkers.getGenericMarker(_markers[polyID]??landmarkMarker);
      await removeMarker(controller, polyID);
      await addMarker(controller, marker);

      // Store for deselection
      selectedLocation = SelectedLocation(
        polyID: polygonId,
        polygon: polygon,  // Store original polygon
        marker: null,
      );

      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final maxSpan = max(latSpan, lngSpan);

      // Adjust zoom based on polygon size (larger polygons need lower zoom)
      double targetZoom = 20.0;
      if (maxSpan > 0.01) targetZoom = 15.0;
      if (maxSpan > 0.1) targetZoom = 12.0;
      if (maxSpan > 1.0) targetZoom = 8.0;

      await _mapboxMap.flyTo(
          CameraOptions(center:Point(coordinates: Position(centerLng, centerLat),),zoom: targetZoom),
          MapAnimationOptions(duration: 500),
      );
    } catch (e) {
      print('Error selecting polygon (Mapbox): $e');
    }
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


  Future<void> _initMarkerLayer(MapboxMap mapboxMap) async {
    print("_initMarkerLayer${StackTrace.current}");
    final style = mapboxMap.style;

    // ============================================
    // Create single GeoJSON source
    // ============================================
    final exists = await style.styleSourceExists(_markerSourceId);
    if (!exists) {
      await style.addSource(
        GeoJsonSource(
          id: _markerSourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': [],
          }),
        ),
      );
    }

    // ============================================
    // Layer 1: Normal markers (rendered first, can be hidden by overlap)
    // ============================================
    final normalLayerExists = await style.styleLayerExists(_normalMarkerLayerId);
    if (!normalLayerExists) {
      await style.addLayer(
        SymbolLayer(
          id: _normalMarkerLayerId,
          sourceId: _markerSourceId,
          iconImageExpression: ['get', 'icon'],
          iconSizeExpression: ['get', 'iconSize'],
          textFieldExpression: ['get', 'title'],
          textFont: ["Roboto Medium", "Arial Unicode MS Regular"],
          textSize: 12,
          textColor: 0xFF000000,
          textHaloColor: 0xFFFFFFFF,
          textHaloWidth: 1,
          textHaloBlur: 0.5,
          iconAllowOverlap: false,  // Can be hidden
          textAllowOverlap: false,  // Can be hidden
          textMaxWidth: 5,
          textAnchor: TextAnchor.CENTER,
          symbolZOffset: 3.0,
          textJustify: TextJustify.LEFT,
          filter: ['!=', ['get', 'isPriority'], true],
        ),
      );
    }

    // ============================================
    // Layer 2: Priority markers (rendered last, always visible)
    // ============================================
    final priorityLayerExists = await style.styleLayerExists(_priorityMarkerLayerId);
    if (!priorityLayerExists) {
      await style.addLayer(
        SymbolLayer(
          id: _priorityMarkerLayerId,
          sourceId: _markerSourceId,
          iconImageExpression: ['get', 'icon'],
          iconSizeExpression: ['get', 'iconSize'],
          iconOffset: [0, -6],
          textFont: ["Roboto Medium", "Arial Unicode MS Regular"],
          textSize: 12,
          textColor: 0xFF000000,
          textHaloColor: 0xFFFFFFFF,
          textHaloWidth: 1,
          textHaloBlur: 0.5,
          iconAllowOverlap: true,   // Always visible
          textAllowOverlap: true,   // Always visible
          textMaxWidth: 5,
          textAnchor: TextAnchor.CENTER,
          symbolZOffset: 3.0,  // Higher z-order
          textJustify: TextJustify.LEFT,
          // FILTER: Only show priority markers
          filter: ['==', ['get', 'isPriority'], true],
        ),
      );
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is! MapboxMap) return;
    if (marker.properties == null || marker.properties!["polyId"] == null) return;
    _markers[marker.id] = marker;
    if(marker.assetPath != null && marker.iconName != null) await _loadMarkerIcon(controller, marker);

    // try {
      await _updateMarkerSource(controller);
    // } catch (e) {
    //   print("Error adding marker: $e");
    // }
  }

  Future<void> _loadMarkerIcon(MapboxMap mapboxMap, GeoJsonMarker marker) async {
    try {

      final bytes = await rootBundle.load(marker.assetPath??"");
      final list = bytes.buffer.asUint8List();
      final image = await decodeImageFromList(list);

      await mapboxMap.style.addStyleImage(
        marker.iconName??"",
        1.0,
        MbxImage(
          width: image.width,
          height: image.height,
          data: list,
        ),
        false,
        [],
        [],
        null,
      );
    } catch (e) {
      print('Icon ${marker.iconName}.png not found in ${marker.assetPath!}');
    }
  }

  /// Update marker source - single source feeds both layers
  Future<void> _updateMarkerSource(MapboxMap mapboxMap) async {
    print("_updateMarkerSource${StackTrace.current}");
    print("_markers ${_markers.length}");
    final features = _markers.values.map((marker) {

      return {
        'type': 'Feature',
        'id': marker.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [
            marker.position.longitude,
            marker.position.latitude,
          ],
        },
        'properties': {
          'title': marker.textVisibility == true ? marker.title : "",
          'icon': marker.iconName,
          'iconSize': marker.iconSizeRatio,
          'isPriority': marker.priority ?? false,  // This determines which layer renders it
        },
      };
    }).toList();

    await mapboxMap.style.setStyleSourceProperty(
      _markerSourceId,
      'data',
      {
        'type': 'FeatureCollection',
        'features': features,
      },
    );
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId, {String? exclude}) async {
    print("removeMarker ${StackTrace.current}");
    if (controller is! MapboxMap) return;

    final markersToRemove = _markers.entries.where((entry) {
      final id = entry.key;
      if (exclude != null && id.contains(exclude)) {
        return false;
      }
      if (id.contains(markerId)) {
        return true;
      }
      return false;
    }).toList();

    for (final entry in markersToRemove) {
      _markers.remove(entry.key);
    }

    await _updateMarkerSource(controller);
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _markers.clear();
    await _updateMarkerSource(controller);
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is! MapboxMap) return;

    try {
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

      _polygons[polygon.id] = polygon;

      await _updatePolygonSource(controller);
    } catch (e) {
      print('Error adding polygon: $e');
    }
  }

  @override
  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is! MapboxMap) return;

    // Add all polygons to the map
    for (var polygon in polygons) {
      _polygons[polygon.id] = polygon;
    }

    // Update source only once
    await _updatePolygonSource(controller);
  }

  Future<void> _updatePolygonSource(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    final features = _polygons.values
        .map((polygon) {

      final String? rawType =
          polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];


      String color = (fillColorHex != null &&
          fillColorHex != "undefined" &&
          fillColorHex.isNotEmpty)
          ? fillColorHex
          : RenderingUtilities.colorToHex(
        RenderingUtilities.polygonColorMap[type]?["fillColor"]
            ?? RenderingUtilities.polygonColorMap['default']!["fillColor"]!,
      );
      if(polygon.properties?["type"] != null){
        color = RenderingUtilities.getColorByType(polygon.properties?["type"]);
      }
      if(polygon.properties?['onTap'] != null){
        color = polygon.properties?['onTap'];
      }

      final height = (polygon.properties?["name"] !=null && polygon.properties!["name"].toString().toLowerCase().contains("boundary"))? 0 : 3;
      double opacity = (polygon.properties?["polygonType"]?.toString().toLowerCase() == "wall") ? 0.5 : 1.0;

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            polygon.points
                .map((p) => [p.longitude, p.latitude])
                .toList()
          ],
        },
        'properties': {
          'height': height,
          'fillColor': color, // Pass the color value directly
          'opacity': opacity
        },
      };
    }).toList();

    // ---- Create source once ----
    if (!await style.styleSourceExists(_polygonSourceId)) {
      await style.addSource(
        GeoJsonSource(
          id: _polygonSourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': features,
          }),
        ),
      );
    } else {
      // ---- Update source data ----
      await style.setStyleSourceProperty(
        _polygonSourceId,
        'data',
        jsonEncode({
          'type': 'FeatureCollection',
          'features': features,
        }),
      );
    }

    // ---- Create ONE extrusion layer ----
    if (!await style.styleLayerExists(_polygonLayerId)) {

      await style.addLayerAt(
        FillExtrusionLayer(
          id: _polygonLayerId,
          sourceId: _polygonSourceId,
          fillExtrusionColorExpression: ['get', 'fillColor'],
          fillExtrusionHeightExpression: ['get', 'height'],
        ),
        LayerPosition(below: _normalMarkerLayerId)
      );
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    if (controller is! MapboxMap) return;

    final entriesToRemove = _polygons.entries.where((entry) {
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
      _polygons.remove(entry.key);
    }
    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _polygons.clear();
    await _updatePolygonSource(controller);
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
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is! MapboxMap) return;

    bool isWaypoint = false;
    if (polyline.properties?["lineCategory"] != null) {
      isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
    }
    if (polyline.properties?["polygonType"] != null) {
      isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
    }

    if (isWaypoint) return;

    try {
      _polylines[polyline.id] = polyline;
      await _updatePolylineSource(controller);
    } catch (e) {
      print('Error adding polyline: $e');
    }
  }

  @override
  Future<void> deSelectLocation(controller) async {
    if (controller is! MapboxMap) return;
    if (selectedLocation == null) return;

    // try {
      final polygonId = selectedLocation!.polyID;
      final polygon = selectedLocation!.polygon;
      final restoredProperties = Map<String, dynamic>.from(polygon.properties ?? {});

      restoredProperties.remove('onTap');
      final restoredPolygon = GeoJsonPolygon(
        id: polygon.id,
        points: polygon.points,
        properties: restoredProperties,
      );

      _polygons[polygonId] = restoredPolygon;
      await _updatePolygonSource(controller);

      selectedLocation = null;


    // } catch (e) {
    //   print('Error deselecting polygon: $e');
    // }

  }

  @override
  Future<void> zoom(controller, {double zoom = 0.0}) async {
    if(controller is MapboxMap){
      final bounds = await controller.getBounds();

      controller.flyTo(
        CameraOptions(zoom: zoom),
        MapAnimationOptions(duration: 2000, startDelay: 0)
      );
    }
  }

  @override
  Future<void> zoomTo(controller, double zoom) {
    // TODO: implement zoomTo
    throw UnimplementedError();
  }

  @override
  Future<void> addPolylines(controller, List<GeoJsonPolyline> polylines) async {
    if (controller is! MapboxMap) return;

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
        _polylines[polyline.id] = polyline;
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }

    await _updatePolylineSource(controller);
  }

  Future<void> _updatePolylineSource(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    final features = _polylines.values.map((line) {
      final isPath = line.id.toLowerCase().contains("path");

      return {
        'type': 'Feature',
        'id': line.id,
        'geometry': {
          'type': 'LineString',
          'coordinates': line.points
              .map((point) => [point.longitude, point.latitude])
              .toList(),
        },
        'properties': {
          'id': line.id,
          'strokeColor': line.properties?['strokeColor'] ?? '#000000',
          'strokeWidth': line.properties?['strokeWidth'] ?? 2.0,
          'strokeOpacity': line.properties?['strokeOpacity'] ?? 1.0,
          'isPath': isPath,
        },
      };
    }).toList();

    // Create or update source
    if (!await style.styleSourceExists(_polylineSourceId)) {
      await style.addSource(
        GeoJsonSource(
          id: _polylineSourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': features,
          }),
        ),
      );
    } else {
      await style.setStyleSourceProperty(
        _polylineSourceId,
        'data',
        jsonEncode({
          'type': 'FeatureCollection',
          'features': features,
        }),
      );
    }
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MapboxMap) return;

    final linesToRemove = _polylines.entries
        .where((entry) => entry.key.contains(polylineId))
        .toList();

    for (final entry in linesToRemove) {
      _polylines.remove(entry.key);
    }

    await _updatePolylineSource(controller);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is! MapboxMap) return;

    try {
      _polylines.clear();
      await _updatePolylineSource(controller);
    } catch (e) {
      print('Error clearing polylines: $e');
    }
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> marker) async {
    print("addMarkers${StackTrace.current}");
    if (controller is! MapboxMap) return;
    for(var ele in marker) {
      if (ele.properties == null || ele.properties!["polyId"] == null){
        print("ele.properties == null");
        // return;
      };
      _markers[ele.id] = ele;
      if(ele.iconName != null && ele.assetPath!= null){
        await _loadMarkerIcon(controller, ele);
      }
      // debugPrint("_loadMarkerIcon ${ele.iconName} ${ele.assetPath}");
    }

    try{
      await _updateMarkerSource(controller);
    }catch(e){
      print("Error adding markers: $e");
    }
  }

  @override
  Future<void> fitCameraToLine(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is! MapboxMap) return;
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

    // Add padding (10%)
    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    // Create camera bounds
    final bounds = CoordinateBounds(
      southwest: Point(
        coordinates: Position(minLng - lngPadding, minLat - latPadding),
      ),
      northeast: Point(
        coordinates: Position(maxLng + lngPadding, maxLat + latPadding),
      ),
      infiniteBounds: false,
    );

    // Animate camera to fit bounds
    await controller.flyTo(
      CameraOptions(
        // bounds: CameraOptions(bounds: bounds),
        padding: MbxEdgeInsets(
          top: 50,
          left: 50,
          bottom: 50,
          right: 50,
        ),
      ),
      MapAnimationOptions(duration: 1000),
    );
  }

}