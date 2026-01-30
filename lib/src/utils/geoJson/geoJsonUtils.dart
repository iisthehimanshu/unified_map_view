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
    String? path
  }) {
    final Map<String, String?> values = {
      'id': id,
      'polyId': polyId,
      'buildingID': buildingID,
      'floor': floor,
      'path': path,
      'time': DateTime.now().millisecondsSinceEpoch.toString()
    };

    return values.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => '${e.key}:${e.value}')
        .join(' | ');
  }
}