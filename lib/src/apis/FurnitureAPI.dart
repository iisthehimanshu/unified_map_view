
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/furniture_model.dart';

class FurnitureAPI {
  Future<List<FurnitureModel>> fetchFurniture(String venueName) async {
    final url = Uri.parse(
      '${AppConfig.baseUrl}/secured/get-all-threed-models?venueName=$venueName&api_key=${AppConfig.apiKey}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = (body['data'] as List?) ?? const [];

        // Parse per-model so a single malformed model can't throw out the
        // whole list — one bad field would otherwise leave furnitureData
        // empty and every placement unresolved.
        final models = <FurnitureModel>[];
        for (final item in data) {
          try {
            models.add(FurnitureModel.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            print('Skipping malformed furniture model '
                '(${item is Map ? item['_id'] : '?'}): $e');
          }
        }
        return models;
      } else {
        print('Error fetching furniture: ${response.statusCode}');
        return [];
      }
    } catch (e, st) {
      print('Exception fetching furniture: $e\n$st');
      return [];
    }
  }
}
