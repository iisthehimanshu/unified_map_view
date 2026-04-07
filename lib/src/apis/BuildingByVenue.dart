import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import '../apimodels/BuildingData.dart';
import '../config.dart';
import 'package:http/http.dart' as http;
import '../database/box/BuildingByVenueAPIBOX.dart';
import '../database/model/BuildingByVenueAPIModel.dart';

class BuildingByVenue {
  final String baseUrl = "${AppConfig.baseUrl}/secured/building/get/venue?api_key=${AppConfig.apiKey}";

  Future<BuildingData> fetchBuildingIDS(String id, {bool fromDB = true}) async {
    final buildingByVenueBox = BuildingByVenueAPIBOX.getData();

    // ── FIRST RUN: Seed from asset if DB is empty ──
    if (!buildingByVenueBox.containsKey(id)) {
      final seeded = await _seedFromAssetIfNeeded(id, buildingByVenueBox);
      if (seeded) {
        // Asset seeded — also trigger background API sync if internet available
        _backgroundSync(id, buildingByVenueBox);
        final responseBody = buildingByVenueBox.get(id)!.responseBody;
        return BuildingData.fromJson(responseBody);
      }
      // No asset, no DB — fall through to API call
      return _fetchFromApi(id, buildingByVenueBox);
    }
    // ── SUBSEQUENT RUNS: DB has data ──
    if (fromDB) {
      _backgroundSync(id, buildingByVenueBox); // refresh in background if internet
      final responseBody = buildingByVenueBox.get(id)!.responseBody;
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      return BuildingData.fromJson(responseBody);
    }
    return _fetchFromApi(id, buildingByVenueBox);
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String id, dynamic box) async {
    try {
      final raw = await rootBundle.loadString(
        'packages/unified_map_view/assets/api_data/BuildingByVenueNationalZoologicalPark.json',
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
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM API");
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
    var result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi);
  }
}