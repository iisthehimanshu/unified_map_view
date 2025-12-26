import 'dart:convert';

import '../apimodels/BuildingData.dart';
import '../config.dart';
import 'package:http/http.dart' as http;

class BuildingByVenue {
  final String baseUrl = "${AppConfig.baseUrl}/secured/building/get/venue?api_key=${AppConfig.apiKey}";

  Future<BuildingData> fetchBuildingIDS(String id) async {
    print('venueName:${id}');

    final Map<String, dynamic> data = {
      "venueName":id, //venue Name
      "campusIncludes":true
    };

    final response = await http.post(
      Uri.parse(baseUrl),
      body: json.encode(data),
      headers: {
        'Content-Type': 'application/json'
        // 'x-access-token': accessToken!,
      },
    );

    if (response.statusCode == 200) {
      Map<String, dynamic> responseBody = json.decode(response.body);
      // final buildingByVenueData = BuildingByVenueAPIModel(responseBody: responseBody);
      print("BUILDINGBYVENUE API DATA FROM API $responseBody");
      //BuildingByVenueBox.add(buildingByVenueData);
      // buildingByVenueData.save();
      BuildingData buildingList = BuildingData.fromJson(responseBody);
      return buildingList;

    } else if (response.statusCode == 403) {
      return fetchBuildingIDS(id);
    } else {
      print("else ${response.body}");
      print(response.body);
      throw Exception('Failed to load landmark data');
    }
  }
}