import 'dart:ui';

class RenderingUtilities{
  static Color hexToColor(String hex, {double opacity = 1.0}) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // add alpha if missing
    }
    return Color(int.parse(hex, radix: 16))
        .withOpacity(opacity);
  }

}