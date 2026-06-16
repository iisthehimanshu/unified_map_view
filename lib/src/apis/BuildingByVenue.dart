import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import '../apimodels/BuildingData.dart';
import '../config.dart';
import 'package:http/http.dart' as http;
import '../database/box/BuildingByVenueAPIBOX.dart';
import '../database/model/BuildingByVenueAPIModel.dart';

class BuildingByVenue {
  final String baseUrl = "${AppConfig.baseUrl}/secured/building/get/venue?api_key=${AppConfig.apiKey}";

  Future<BuildingData> fetchBuildingIDS(String id) async {
    final buildingByVenueBox = BuildingByVenueAPIBOX.getData();

    // ── FIRST RUN: Seed from asset if DB is empty ──
    if (!buildingByVenueBox.containsKey(id)) {
      final seeded = await _seedFromAssetIfNeeded(id, buildingByVenueBox);
      final internetAvailable = await checkInternetConnectivity();
      if (seeded) {
        // Asset seeded — also trigger background API sync if internet available
        _backgroundSync(id, buildingByVenueBox);
        final responseBody = buildingByVenueBox.get(id)!.responseBody;
        return BuildingData.fromJson(responseBody);
      }else if(internetAvailable){
        return await _fetchFromApi(id, buildingByVenueBox);
      }else{
        throw("no preload & no DB data & no internet");
      }
    }else{
      _backgroundSync(id, buildingByVenueBox);
      final responseBody = buildingByVenueBox.get(id)!.responseBody;
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      return BuildingData.fromJson(responseBody);
    }
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String id, dynamic box) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/api_data/BuildingByVenue${id}.json',
      );
      final Map<String, dynamic> responseBody = json.decode(raw);
      final model = BuildingByVenueAPIModel(responseBody: responseBody);
      box.put(id, model);
      await model.save();
      print("UNIFIED MAP BUILDINGBYVENUE seeded from asset.");
      return true;
    } catch (_) {
      print("No bundled BuildingByVenue asset found.");
      return false;
    }
  }

  /// Fire-and-forget background API sync.
  void _backgroundSync(String id, dynamic box) async {
    final isConnected = await checkInternetConnectivity();
    if (isConnected) {
      print("UNIFIED MAP BUILDINGBYVENUE background sync started...");
      _fetchFromApi(id, box);
    }
  }

  Future<BuildingData> _fetchFromApi(String id, dynamic box) async {
    final data = {"venueName": id, "campusIncludes": true};
    final response = await http.post(
      Uri.parse(baseUrl),
      body: json.encode(data),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final responseBody = json.decode(response.body);
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM API $responseBody");
      final model = BuildingByVenueAPIModel(responseBody: responseBody);
      box.put(id, model);
      await model.save();
      return BuildingData.fromJson(responseBody);
    } else if (response.statusCode == 403) {
      return _fetchFromApi(id, box);
    } else {
      throw Exception('Failed to load building data');
    }
  }

  static Future<bool> checkInternetConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();

    if (!connectivityResult.contains(ConnectivityResult.mobile) &&
        !connectivityResult.contains(ConnectivityResult.wifi)) {
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}