
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
        final List<dynamic> data = body['data'];
        return data.map((item) => FurnitureModel.fromJson(item)).toList();
      } else {
        print('Error fetching furniture: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Exception fetching furniture: $e');
      return [];
    }
  }
}
