import 'package:flutter/material.dart';

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

  static LandmarkAssetType? getAssetForLandmark(
      Map<String, dynamic>? landmarkProperties) {
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
          return LandmarkAssetType.accessibleWashroom;
        }
        return LandmarkAssetType.washroom;
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

      // ================= Other Types =================
      if (type.contains('entrance') || type.contains('exit')) {
        return LandmarkAssetType.mainEntry;
      }
      if (type.contains('room') || type.contains('office')) {
        return null;
        return LandmarkAssetType.room;
      }
      if (type.contains('cafeteria') || type.contains('cafe')) {
        return LandmarkAssetType.cafeteria;
      }
      if (type.contains('water')) {
        return LandmarkAssetType.waterFountain;
      }
      if (type.contains('emergency')) {
        return LandmarkAssetType.emergency;
      }
      if (type.contains('door only')) {
        return LandmarkAssetType.doorOnly;
      }

      return null;
    } catch (e) {
      debugPrint('Error extracting asset name: $e');
      return null;
    }
  }



}