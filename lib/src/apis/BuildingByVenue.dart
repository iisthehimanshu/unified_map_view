import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../apimodels/BuildingData.dart';
import '../config.dart';
import 'package:http/http.dart' as http;

import '../database/box/BuildingByVenueAPIBOX.dart';
import '../database/model/BuildingByVenueAPIModel.dart';

class BuildingByVenue {
  final String baseUrl = "${AppConfig.baseUrl}/secured/building/get/venue?api_key=${AppConfig.apiKey}";

  Future<BuildingData> fetchBuildingIDS(String id,{bool fromDB = true}) async {
    final BuildingByVenueBox = BuildingByVenueAPIBOX.getData();

    if(fromDB && BuildingByVenueBox.containsKey(id)){
      bool isInternetConnected = await checkInternetConnectivity();
      if(isInternetConnected){
        fetchBuildingIDS(id, fromDB: false);
      }
      Map<String, dynamic> responseBody = BuildingByVenueBox.get(id)!.responseBody;
      BuildingData buildingList = BuildingData.fromJson(responseBody);
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      return buildingList;
    }

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
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM API");
      final buildingByVenueData = BuildingByVenueAPIModel(responseBody: responseBody);
      BuildingByVenueBox.put(id,buildingByVenueData);
      buildingByVenueData.save();
      BuildingData buildingList = BuildingData.fromJson(responseBody);
      return buildingList;

    } else if (response.statusCode == 403) {
      return fetchBuildingIDS(id);
    } else {
      throw Exception('Failed to load landmark data');
    }
  }
  static Future<bool> checkInternetConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi)) {
      return true;
    }
    return false;
  }
}