class GeoJsonUtils{

  static Map<String, String> extractKeyValueMap(String input) {
    final Map<String, String> result = {};

    final parts = input.split('|');

    for (var part in parts) {
      final pair = part.split(':');
      if (pair.length == 2) {
        result[pair[0].trim()] = pair[1].trim();
      }
    }

    return result;
  }

  static String buildKey({
    String? id,
    String? polyId,
    String? buildingID,
    String? floor,
    String? path,
    String? custom
  }) {
    final Map<String, String?> values = {
      'id': id,
      'polyId': polyId,
      'buildingID': buildingID,
      'floor': floor,
      'path': path,
      'custom': custom,
      'time': DateTime.now().millisecondsSinceEpoch.toString()
    };

    return values.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => '${e.key}:${e.value}')
        .join(' | ');
  }

  static String buildPatternKey({
    String? name,
    int? size,
    int? gap,
    int? rotation,
    String? color,
  }) {
    final Map<String, String?> values = {
      'pattern': name,
      'size': size?.toString(),
      'gap': gap.toString(),
      'rotation': rotation.toString(),
      'color': color,
    };

    return values.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => '${e.key}:${e.value}')
        .join(' | ');
  }
}