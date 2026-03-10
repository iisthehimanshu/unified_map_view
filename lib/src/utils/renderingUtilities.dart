import 'package:flutter/material.dart';
import 'package:unified_map_view/src/models/map_location.dart';
import 'dart:math';
import 'LandmarkAssetType.dart';

class RenderingUtilities{
  static Color hexToColor(String hex, {double opacity = 1.0}) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // add alpha if missing
    }

    return Color(int.parse(hex, radix: 16))
        .withOpacity(opacity);
  }

  static final Map<String, Map<String, Color>> polygonColorMap = {
    // Green areas & sports
    'green area': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'auditorium': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'gym': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'swimming': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'basketball': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'football': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'tennis': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},
    'cricket': {'strokeColor': Color(0xffADFA9E), 'fillColor': Color(0xffE7FEE9)},

    // Facilities
    'lift': {'strokeColor': Color(0xffB5CCE3), 'fillColor': Color(0xffDAE6F1)},
    'male washroom': {'strokeColor': Color(0xff6EBCF7), 'fillColor': Color(0xFFE7F4FE)},
    'female washroom': {'strokeColor': Color(0xff6EBCF7), 'fillColor': Color(0xFFE7F4FE)},
    'unisex washroom': {'strokeColor': Color(0xff6EBCF7), 'fillColor': Color(0xFFE7F4FE)},
    'accessible washroom': {'strokeColor': Color(0xff6EBCF7), 'fillColor': Color(0xFFE7F4FE)},
    'fire': {'strokeColor': Color(0xff000000), 'fillColor': Color(0xffF21D0D)},
    'water': {'strokeColor': Color(0xff6EBCF7), 'fillColor': Color(0xffE7F4FE)},

    // Restricted
    'restricted area': {'strokeColor': Color(0xffCCCCCC), 'fillColor': Color(0xffE6E6E6)},
    'non walkable area': {'strokeColor': Color(0xffCCCCCC), 'fillColor': Color(0xffE6E6E6)},
    'wall': {'strokeColor': Color(0xffCCCCCC), 'fillColor': Color(0xffE6E6E6)},

    // Rooms
    'room': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'lr': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'lab': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'office': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'pantry': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'reception': {'strokeColor': Color(0xffA38F9F), 'fillColor': Color(0xffE8E3E7)},
    'atm': {'strokeColor': Color(0xffE99696), 'fillColor': Color(0xffFBEAEA)},
    'health': {'strokeColor': Color(0xffE99696), 'fillColor': Color(0xffFBEAEA)},
    'Cafeteria': {'strokeColor': Color(0xffE99696), 'fillColor': Color(0xffFBEAEA)},

    'boundary': {'strokeColor': Color(0xffC0C0C0), 'fillColor': Color(0xffffffff)},

    'default': {'strokeColor': Color(0xffCCCCCC), 'fillColor': Color(0xffE6E6E6)},
  };

  static String colorToMapplsHex(Color color) {
    return color.value
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toLowerCase();
  }

  static String colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  static String getColorByType(String input) {
    final s = input.toLowerCase();

    if (s.toLowerCase().contains("wall")) {
      return "#8ae9f8";
    } else if (s.contains("female washroom")) {
      return "#f7a8b8";
    } else if (s.contains("male washroom")) {
      return "#5d9cec";
    } else if (s.contains("pantry")) {
      return "#c8f0d1";
    } else if (s.contains("boundary")) {
      return "#ffffff";
    } else if (s.contains("rooms") || s.contains("Room")) {
      return "#d3e0ea";
    } else if (s.contains("conference")) {
      return "#ffe4b5";
    } else if (s.contains("workstations")) {
      return "#c2f0c2";
    } else if (s.contains("washroom")) {
      return "#aec6cf";
    }
    return "#bdbdbd";
  }

  static LandmarkAssetType? getAssetForLandmark(Map<String, dynamic>? landmarkProperties) {
    try {
      if (landmarkProperties == null) return null;

      final isGlobal = landmarkProperties['global'] == true;

      String? rawType;

      if (isGlobal) {
        // 🔹 Global landmarks: type is directly present
        rawType = landmarkProperties['type'] as String?;
      } else {
        final element = landmarkProperties['element'] as Map<String, dynamic>?;
        if (element == null) return null;
        rawType = element['subType'] ?? element['type'];
      }

      if (rawType == null) return null;

      final type = rawType.toLowerCase().trim();

      if(landmarkProperties['landmarkId'] == "d535a87fb7a6e9bae6c91d477c841018"){
        print("type for tuckshop ${type}");
      }

      // ================= Washrooms =================
      if (type.contains('washroom') || type.contains('restroom')) {
        var washroomType = landmarkProperties['washroomType']??type;
        washroomType = washroomType.toLowerCase();
        if (washroomType.contains('female')) {
          return LandmarkAssetType.femaleWashroom;
        }
        if (washroomType.contains('male')) {
          return LandmarkAssetType.maleWashroom;
        }
        if (washroomType.contains('unisex') || type.contains('accessible')) {
          return LandmarkAssetType.unisexWashroom;
        }
        return LandmarkAssetType.washroom;
      }
      if(type.toLowerCase().contains('smoking')){
        return LandmarkAssetType.smokingArea;
      }
      if(type.contains("fire")){
        return LandmarkAssetType.fireExtinguisher;
      }


      // ================= Floor Connections =================
      if (type.contains('lift') || type.contains('elevator')) {
        return LandmarkAssetType.lift;
      }
      if (type.contains('stairs') || type.contains('stair')) {
        return LandmarkAssetType.stairs;
      }
      if (type.contains('escalator')) {
        return LandmarkAssetType.escalator;
      }
      if (type.contains('emergency')) {
        return LandmarkAssetType.emergencyExit;
      }
      if (type.contains('ramp')) {
        return LandmarkAssetType.ramp;
      }
      // ================= Other Types =================
      if (type.contains('gadget') || type.contains('mobile') || type.contains('phone')) {
        return LandmarkAssetType.gadgets;
      }
      if (type.contains('clothes') || type.contains('garment')) {
        return LandmarkAssetType.garments;
      }
      if (type.contains('entry') || type.contains('entrance') || type.contains('exit')) {
        return LandmarkAssetType.mainEntry;
      }
      if(type.contains('assembly area')){
        return LandmarkAssetType.assemblyRoom;
      }
      if(type.contains('hall')){
        return LandmarkAssetType.conferenceRoom;
      }
      if(type.contains('registration')){
        return LandmarkAssetType.registrationDesk;
      }
      if(type.contains('sitting') || type.contains('waiting')){
        return LandmarkAssetType.waitingArea;
      }
      if (type.contains('room') || type.contains('office')) {
        String roomName = landmarkProperties['name'];
        if(roomName.contains("Meeting")){
          return LandmarkAssetType.meetingRoom;
        }
        return null;
      }
      if (type.contains('cafeteria') || type.contains('cafe')) {
        return LandmarkAssetType.cafeteria;
      }
      if (type.contains('vending')) {
        return LandmarkAssetType.vendingMachine;
      }
      if (type.contains('water')) {
        return LandmarkAssetType.waterFountain;
      }

      if (type.contains('door only')) {
        return LandmarkAssetType.doorOnly;
      }
      if (type.contains('trash')) {
        return LandmarkAssetType.sofa;
      }
      if (type.contains('counter')) {
        return LandmarkAssetType.counter;
      }
      if(type.contains('first aid')){
        return LandmarkAssetType.firstAid;
      }
      if(type.contains('parking')){
        return LandmarkAssetType.parking;
      }
      if(type.contains('tuckshop')){
        return LandmarkAssetType.tuckShop;
      }
      if(type.contains('stationary')){
        return LandmarkAssetType.stationary;
      }

      return null;
    } catch (e) {
      debugPrint('Error extracting asset name: $e');
      return null;
    }
  }

  RectangleResult findBestFitRectangleBearing(List<MapLocation> polygon) {
    if (polygon.length < 3) {
      throw ArgumentError('Polygon must have at least 3 points');
    }

    // Convert to local Cartesian coordinates (meters)
    final centroid = _getCentroid(polygon);
    final localPoints = polygon.map((p) => _latLngToLocal(p, centroid)).toList();

    // Find convex hull (for minimum bounding rectangle)
    final hull = _convexHull(localPoints);

    // Find minimum area bounding rectangle using rotating calipers
    final rectData = _minAreaRectangle(hull);

    // Determine longest axis
    final isWidthLonger = rectData.width >= rectData.height;
    final longestAxisAngle = isWidthLonger
        ? rectData.angle
        : (rectData.angle + 90) % 360;

    // Get the corners of the rectangle in local coordinates
    final rectCorners = rectData.corners;

    // Determine which side is the longest
    List<Point> longestSideLocal;
    if (isWidthLonger) {
      // Use the first edge (bottom side)
      longestSideLocal = [rectCorners[0], rectCorners[1]];
    } else {
      // Use the second edge (left side)
      longestSideLocal = [rectCorners[1], rectCorners[2]];
    }

    // Convert back to LatLng
    final longestSide = longestSideLocal
        .map((p) => _localToLatLng(p, centroid))
        .toList();

    // Convert to global bearing (0° = North, clockwise)
    var bearing = _normalizeBearing(longestAxisAngle + 90);

    // if(bearing > 180){
    //   bearing -= 180;
    // }

    return RectangleResult(bearing, longestSide);
  }

  MapLocation _getCentroid(List<MapLocation> polygon) {
    final lat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return MapLocation(latitude: lat, longitude: lon);
  }

  Point _latLngToLocal(MapLocation point, MapLocation origin) {
    final latRad = origin.latitude * pi / 180;
    final dLat = point.latitude - origin.latitude;
    final dLon = point.longitude - origin.longitude;

    final x = dLon * 111320.0 * cos(latRad);
    final y = dLat * 110540.0;

    return Point(x, y);
  }

  List<Point> _convexHull(List<Point> points) {
    if (points.length < 3) return points;

    final sorted = List<Point>.from(points)
      ..sort((a, b) {
        final cmp = a.x.compareTo(b.x);
        return cmp != 0 ? cmp : a.y.compareTo(b.y);
      });

    double cross(Point o, Point a, Point b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x).toDouble();
    }

    final lower = <Point>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Point>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();

    return [...lower, ...upper];
  }

  Rectangle _minAreaRectangle(List<Point> hull) {
    double minArea = double.infinity;
    Rectangle? bestRect;

    for (int i = 0; i < hull.length; i++) {
      final p1 = hull[i];
      final p2 = hull[(i + 1) % hull.length];

      // Edge vector
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final edgeAngle = atan2(dy, dx);

      // Rotate all points to align edge with x-axis
      final rotated = hull.map((p) {
        final rx = (p.x - p1.x) * cos(-edgeAngle) - (p.y - p1.y) * sin(-edgeAngle);
        final ry = (p.x - p1.x) * sin(-edgeAngle) + (p.y - p1.y) * cos(-edgeAngle);
        return Point(rx, ry);
      }).toList();

      // Find bounding box in rotated space
      final minX = rotated.map((p) => p.x).reduce(min);
      final maxX = rotated.map((p) => p.x).reduce(max);
      final minY = rotated.map((p) => p.y).reduce(min);
      final maxY = rotated.map((p) => p.y).reduce(max);

      final width = maxX - minX;
      final height = maxY - minY;
      final area = width * height;

      if (area < minArea) {
        minArea = area;
        // Angle in degrees from positive x-axis (East)
        final angleDeg = edgeAngle * 180 / pi;

        // Calculate the four corners in rotated space
        final corners = [
          Point(minX, minY),
          Point(maxX, minY),
          Point(maxX, maxY),
          Point(minX, maxY),
        ];

        // Rotate corners back to original orientation
        final originalCorners = corners.map((c) {
          final ox = c.x * cos(edgeAngle) - c.y * sin(edgeAngle) + p1.x;
          final oy = c.x * sin(edgeAngle) + c.y * cos(edgeAngle) + p1.y;
          return Point(ox, oy);
        }).toList();

        bestRect = Rectangle(originalCorners, width, height, angleDeg);
      }
    }

    return bestRect!;
  }

  MapLocation _localToLatLng(Point point, MapLocation origin) {
    final latRad = origin.latitude * pi / 180;

    final dLon = point.x / (111320.0 * cos(latRad));
    final dLat = point.y / 110540.0;

    return MapLocation(latitude:origin.latitude + dLat, longitude:origin.longitude + dLon);
  }

  double _normalizeBearing(double angle) {
    // Convert from mathematical angle (0° = East, counter-clockwise)
    // to bearing (0° = North, clockwise)
    double bearing = 90 - angle;

    // Normalize to [0, 360)
    bearing = bearing % 360;
    if (bearing < 0) bearing += 360;

    return bearing;
  }

  static List<MapLocation> generateCirclePoints({
    required MapLocation center,
    required double radiusInMeters,
    int pointCount = 64,
  }) {
    const double earthRadius = 6371000; // meters
    final List<MapLocation> points = [];

    final double centerLat = center.latitude * pi / 180;
    final double centerLng = center.longitude * pi / 180;
    final double angularRadius = radiusInMeters / earthRadius;

    for (int i = 0; i < pointCount; i++) {
      final double bearing = (2 * pi * i) / pointCount;

      // Spherical law of cosines
      final double lat = asin(
        sin(centerLat) * cos(angularRadius) +
            cos(centerLat) * sin(angularRadius) * cos(bearing),
      );

      final double lng = centerLng + atan2(
        sin(bearing) * sin(angularRadius) * cos(centerLat),
        cos(angularRadius) - sin(centerLat) * sin(lat),
      );

      points.add(MapLocation(
        latitude: lat * 180 / pi,
        longitude: lng * 180 / pi,
        id: '${center.id}_circle_$i',
      ));
    }

    // Close the circle by repeating the first point
    if (points.isNotEmpty) {
      points.add(points.first);
    }

    return points;
  }

}

class RectangleResult {
  final double bearing;
  final List<MapLocation> longestSide;

  RectangleResult(this.bearing, this.longestSide);
}

class Rectangle {
  final List<Point> corners;
  final double width;
  final double height;
  final double angle;

  Rectangle(this.corners, this.width, this.height, this.angle);
}