import 'dart:ui';

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

  static String? getAssetNameForLandmark(Map<String, dynamic>? landmarkProperties) {
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
            return LandmarkAssetType.lift.assetPath;
          case 'stairs':
          case 'staircase':
            return LandmarkAssetType.stairs.assetPath;
          case 'escalator':
            return LandmarkAssetType.escalator.assetPath;
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
                return LandmarkAssetType.femaleWashroom.assetPath;
              case 'male':
                return LandmarkAssetType.maleWashroom.assetPath;
              case 'unisex':
              case 'accessible':
                return LandmarkAssetType.accessibleWashroom.assetPath;
              default:
                return LandmarkAssetType.washroom.assetPath;
            }
          case 'water':
          case 'waterfountain':
            return LandmarkAssetType.waterFountain.assetPath;
          case 'cafe':
          case 'cafeteria':
            return LandmarkAssetType.cafeteria.assetPath;
          default:
            return null;
        }
      }

      // Handle other common types
      switch (type?.toLowerCase()) {
        case 'room':
        case 'office':
          return LandmarkAssetType.room.assetPath;
        case 'entrance':
        case 'exit':
          return LandmarkAssetType.entrance.assetPath;
        case 'emergency':
          return LandmarkAssetType.emergency.assetPath;
        default:
          return null;
      }

    } catch (e) {
      print('Error extracting asset name: $e');
      return null;
    }
  }


}