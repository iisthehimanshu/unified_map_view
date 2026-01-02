// lib/src/providers/mapbox_map_provider.dart

import 'dart:convert';

import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/camera_position.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mapbox implementation of BaseMapProvider
class MapboxMapProvider extends BaseMapProvider {
  PointAnnotationManager? _annotationManager;

  static const String _markerSourceId = 'marker-source';
  static const String _markerLayerId = 'marker-symbol-layer';
  final Map<String, GeoJsonMarker> _markers = {};

  static const String _polygonSourceId = 'polygon-source';
  static const String _polygonLayerId  = 'polygon-extrusion-layer';
  final Map<String, GeoJsonPolygon> _polygons = {};


  @override
  Widget buildMap({
    required MapConfig config}) {
    return MapWidget(       
      onMapCreated: (mapboxMap) async {
        config.onMapCreated(mapboxMap);
         await _initMarkerLayer(mapboxMap);

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



  Future<void> _initMarkerLayer(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

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

    final layerExists = await style.styleLayerExists(_markerLayerId);
    if (!layerExists) {
      await style.addLayer(
        SymbolLayer(
          id: _markerLayerId,
          sourceId: _markerSourceId,
          textFieldExpression: ['get', 'title'],
          textSize: 14,
          textOffset: [0, -1.5],
          textAnchor: TextAnchor.TOP,
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),

      );
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

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is! MapboxMap) return;

    _markers[marker.id] = marker;
    await _updateMarkerSource(controller);
  }

  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is! MapboxMap) return;

    // Add all polygons to the map
    for (var polygon in polygons) {
      _polygons[polygon.id] = polygon;
    }

    // Update source only once
    await _updatePolygonSource(controller);
  }



  Future<void> _updateMarkerSource(MapboxMap mapboxMap) async {
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
          'title': marker.title,
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
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is! MapboxMap) return;

    _markers.remove(markerId);
    await _updateMarkerSource(controller);
  }


  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _markers.clear();
    await _updateMarkerSource(controller);
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
    if (controller is! MapboxMap) return;

    _polygons[polygon.id] = polygon;
    await _updatePolygonSource(controller);
  }

  Future<void> _updatePolygonSource(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    final features = _polygons.values
        .where((polygon) => polygon.properties?["polygonType"] != "Boundary")
        .map((polygon) {

      final String? rawType =
          polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];

      final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"]
          ?? Colors.white;

      print("Color${fillColor}");
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
          'height': 3.0,
          'base': 0.0,
          'r': fillColor.red,
          'g': fillColor.green,
          'b': fillColor.blue,
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

      await style.addLayer(
        FillExtrusionLayer(
          id: _polygonLayerId,
          sourceId: _polygonSourceId,
          fillExtrusionColorExpression: [
            'rgb',
            ['get', 'r'],
            ['get', 'g'],
            ['get', 'b'],
          ],
          fillExtrusionHeightExpression: ['get', 'height'],
          fillExtrusionOpacity: 1,
        ),
      );
    }
  }



  @override
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    if (controller is! MapboxMap) return;

    if (exclude != null && polygonId.contains(exclude)) return;

    _polygons.remove(polygonId);
    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _polygons.clear();
    await _updatePolygonSource(controller);
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

}