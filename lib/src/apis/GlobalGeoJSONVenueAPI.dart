
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';


class GlobalGeoJSONVenueAPI{

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName) async {

    String baseUrl = "${AppConfig.baseUrl}/secured/get-indoor-geojson-venue/${venueName}?expand=-1&api_key=${AppConfig.apiKey}";

    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {

      GlobalAppGeoJsonDataModel globalAppGeoJsonDataModel = GlobalAppGeoJsonDataModel.fromJson(json.decode(response.body));
      return json.decode(response.body);
    } else if (response.statusCode == 403) {
      return await getGeoJSONData(venueName);
    } else {
      print("getGeoJSONData response.statusCode ${response.statusCode} ${response.body}");
      return null;
      throw Exception('Failed to load data');
    }
  }
}