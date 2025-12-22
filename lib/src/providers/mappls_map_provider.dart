// lib/src/providers/mappls_map_provider.dart

import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/map_marker.dart';
import '../models/geojson_models.dart';

/// Mappls GL implementation of BaseMapProvider
/// Supports Mappls (MapmyIndia) maps - India's own mapping platform
class MapplsMapProvider extends BaseMapProvider {
  final Map<String, Symbol> _symbols = {};
  final Map<String, Line> _lines = {};
  final Map<String, Fill> _fills = {};

  @override
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    Set<MapMarker>? markers,
  }) {
    return MapplsMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.latitude,
          config.initialLocation.longitude,
        ),
        zoom: config.initialZoom,
      ),
      onMapCreated: (MapplsMapController controller) async {
        onMapCreated(controller);

        // Add initial markers if provided
        if (markers != null) {
          for (var marker in markers) {
            await addMarker(controller, marker);
          }
        }
      },
      onStyleLoadedCallback: () {
        // Style loaded, map is ready
      },
      myLocationEnabled: config.showUserLocation,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      compassEnabled: true,
      rotateGesturesEnabled: config.rotateGesturesEnabled,
      scrollGesturesEnabled: config.scrollGesturesEnabled,
      tiltGesturesEnabled: config.tiltGesturesEnabled,
      zoomGesturesEnabled: config.zoomControlsEnabled,
      minMaxZoomPreference: const MinMaxZoomPreference(4, 18),
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
  Future<void> addMarker(dynamic controller, MapMarker marker) async {
    if (controller is MapplsMapController) {
      try {
        // final symbol = await controller.addSymbol(
        //   SymbolOptions(
        //     geometry: LatLng(
        //       marker.position.latitude,
        //       marker.position.longitude,
        //     ),
        //     iconImage: 'marker-15', // Default Mappls marker icon
        //     iconSize: 1.5,
        //     textField: marker.title,
        //     textSize: 12.0,
        //     textOffset: const Offset(0, 1.5),
        //     textColor: '#000000',
        //     textHaloColor: '#FFFFFF',
        //     textHaloWidth: 2.0,
        //   ),
        // );
        //
        // _symbols[marker.id] = symbol;
      } catch (e) {
        print('Error adding marker: $e');
      }
    }
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MapplsMapController) {
      final symbol = _symbols.remove(markerId);
      if (symbol == null) return;

      try {
        await controller.removeSymbol(symbol);
      } catch (_) {
        // Symbol already removed internally by Mappls
      }
    }
  }


  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        for (var symbol in _symbols.values) {
          await controller.removeSymbol(symbol);
        }
        _symbols.clear();
      } catch (e) {
        print('Error clearing markers: $e');
      }
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
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MapplsMapController) {
      try {
        final coordinates = polygon.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        final fill = await controller.addFill(
          FillOptions(
            geometry: [coordinates],
            fillColor: '#0080FF',
            fillOpacity: 0.3,
            fillOutlineColor: '#000000',
          ),
        );

        final coordinatesForaLL = polygon.points.map((p) => LatLng(p.latitude, p.longitude)).toList();


        _fills[polygon.id] = fill;
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId) async {
    if (controller is MapplsMapController && _fills.containsKey(polygonId)) {
      if (controller is MapplsMapController) {
        // try {
        final fills = List<Fill>.from(_fills.values);

        for (final fill in fills) {
          try {
            await controller.removeFill(fill);
          } catch (_) {
            // ignore – fill already removed internally
          }
        }

        _fills.clear();
        // } catch (e) {
        //   print('Error clearing polygons: $e');
        // }
      }
    }
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapplsMapController) {
      // try {
      final fills = List<Fill>.from(_fills.values);

      for (final fill in fills) {
        try {
          await controller.removeFill(fill);
        } catch (_) {
          // ignore – fill already removed internally
        }
      }

      _fills.clear();
      // } catch (e) {
      //   print('Error clearing polygons: $e');
      // }
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {

    if (controller is MapplsMapController) {
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
    if (controller is MapplsMapController && _lines.containsKey(polylineId)) {
      try {
        await controller.removeLine(_lines[polylineId]!);
        _lines.remove(polylineId);
      } catch (e) {
        print('Error removing polyline: $e');
      }
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

  /// Add custom symbol with custom icon
  Future<void> addCustomMarker(
      MapplsMapController controller,
      MapMarker marker, {
        String? customIconImage,
        double? iconSize,
      }) async {
    try {
      final symbol = await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(
            marker.position.latitude,
            marker.position.longitude,
          ),
          iconImage: customIconImage ?? 'marker-15',
          iconSize: iconSize ?? 1.5,
          textField: marker.title,
          textSize: 12.0,
          textOffset: const Offset(0, 1.5),
        ),
      );

      _symbols[marker.id] = symbol;
    } catch (e) {
      print('Error adding custom marker: $e');
    }
  }

  /// Update polygon style
  Future<void> updatePolygonStyle(
      MapplsMapController controller,
      String polygonId, {
        String? fillColor,
        double? fillOpacity,
        String? outlineColor,
      }) async {
    if (_fills.containsKey(polygonId)) {
      try {
        await controller.updateFill(
          _fills[polygonId]!,
          FillOptions(
            fillColor: fillColor,
            fillOpacity: fillOpacity,
            fillOutlineColor: outlineColor,
          ),
        );
      } catch (e) {
        print('Error updating polygon: $e');
      }
    }
  }

  /// Update polyline style
  Future<void> updatePolylineStyle(
      MapplsMapController controller,
      String polylineId, {
        String? lineColor,
        double? lineWidth,
        double? lineOpacity,
      }) async {
    if (_lines.containsKey(polylineId)) {
      try {
        await controller.updateLine(
          _lines[polylineId]!,
          LineOptions(
            lineColor: lineColor,
            lineWidth: lineWidth,
            lineOpacity: lineOpacity,
          ),
        );
      } catch (e) {
        print('Error updating polyline: $e');
      }
    }
  }

  /// Clear all map elements
  Future<void> clearAll(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }
}