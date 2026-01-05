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

  static bool? getTextVisiblity(Map<String, dynamic>? landmarkProperties){
    try {
      if (landmarkProperties == null) return null;

      final element = landmarkProperties['element'] as Map<String, dynamic>?;
      if (element == null) return null;

      final type = element['type'] as String?;
      final subType = element['subType'] as String?;

      // Handle FloorConnection type (Lifts, Stairs, etc.)
      if (type == 'FloorConnection') {
        switch (subType?.toLowerCase()) {
          case 'lift':
          case 'elevator':
            return false;
          case 'stairs':
          case 'staircase':
            return false;
          case 'escalator':
            return false;
          default:
            return null;
        }
      }

      // Handle Services type (Washrooms, etc.)
      if (type == 'Services') {
        switch (subType?.toLowerCase()) {
          case 'restroom':
          case 'washroom':
          // Check washroom type from properties
            final washroomType = landmarkProperties['washroomType'] as String?;
            switch (washroomType?.toLowerCase()) {
              case 'female':
                return false;
              case 'male':
                return false;
              case 'unisex':
              case 'accessible':
                return false;
              default:
                return false;
            }
          case 'water':
          case 'waterfountain':
            return true;
          case 'cafe':
          case 'cafeteria':
            return false;
          default:
            return null;
        }
      }

      // Handle other common types
      switch (type?.toLowerCase()) {
        case 'room':
        case 'office':
          return true;
        case 'entrance':
        case 'exit':
          return false;
        case 'emergency':
          return false;
        default:
          return null;
      }

    } catch (e) {
      print('Error in getTextVisiblity$e');
      return null;
    }
  }

  static LandmarkAssetType? getAssetForLandmark(Map<String, dynamic>? landmarkProperties) {
    try {
      if (landmarkProperties == null) return null;

      final element = landmarkProperties['element'] as Map<String, dynamic>?;
      if (element == null) return null;

      final type = element['type'] as String?;
      final subType = element['subType'] as String?;

      // Handle FloorConnection type (Lifts, Stairs, etc.)
      if (type == 'FloorConnection') {
        switch (subType?.toLowerCase()) {
          case 'lift':
          case 'elevator':
            return LandmarkAssetType.lift;
          case 'stairs':
          case 'staircase':
            return LandmarkAssetType.stairs;
          case 'escalator':
            return LandmarkAssetType.escalator;
          default:
            return null;
        }
      }

      // Handle Services type (Washrooms, etc.)
      if (type == 'Services') {
        switch (subType?.toLowerCase()) {
          case 'restroom':
          case 'washroom':
          // Check washroom type from properties
            final washroomType = landmarkProperties['washroomType'] as String?;
            switch (washroomType?.toLowerCase()) {
              case 'female':
                return LandmarkAssetType.femaleWashroom;
              case 'male':
                return LandmarkAssetType.maleWashroom;
              case 'unisex':
              case 'accessible':
                return LandmarkAssetType.accessibleWashroom;
              default:
                return LandmarkAssetType.washroom;
            }
          case 'water':
          case 'waterfountain':
            return LandmarkAssetType.waterFountain;
          case 'cafe':
          case 'cafeteria':
            return LandmarkAssetType.cafeteria;
          default:
            return null;
        }
      }

      // Handle other common types
      switch (type?.toLowerCase()) {
        case 'room':
        case 'office':
          return LandmarkAssetType.room;
        case 'entrance':
        case 'exit':
          return LandmarkAssetType.entrance;
        case 'emergency':
          return LandmarkAssetType.emergency;
        default:
          return null;
      }

    } catch (e) {
      print('Error extracting asset name: $e');
      return null;
    }
  }

}