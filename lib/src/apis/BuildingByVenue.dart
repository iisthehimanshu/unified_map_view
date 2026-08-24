import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

    // Seed from the bundled asset (if any) so there's something to fall
    // back to below even if the live fetch fails or there's no internet.
    if (!buildingByVenueBox.containsKey(id)) {
      await _seedFromAssetIfNeeded(id, buildingByVenueBox);
    }

    // Prefer a live fetch whenever we're online, and use its result for
    // THIS render — not just save it for next launch. The previous
    // fire-and-forget "_backgroundSync" always rendered from whatever was
    // cached (a bundled asset, or a prior session's fetch) and only
    // updated the cache for the *next* launch, so a server-side data fix
    // stayed invisible until the app was uninstalled and reinstalled,
    // which is the only path that starts with an empty cache.
    if (await checkInternetConnectivity()) {
      try {
        return await _fetchFromApi(id, buildingByVenueBox);
      } catch (_) {
        // fall through to cache below
      }
    }

    if (buildingByVenueBox.containsKey(id)) {
      final responseBody = buildingByVenueBox.get(id)!.responseBody;
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      return BuildingData.fromJson(responseBody);
    }

    throw("no preload & no DB data & no internet");
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
        !connectivityResult.contains(ConnectivityResult.wifi) &&
        !(kIsWeb && connectivityResult.contains(ConnectivityResult.ethernet))) {
      return false;
    }

    // The reachability probe is a cross-origin request the browser blocks
    // (clients3.google.com sends no CORS headers), so it always reports
    // offline on web. Trust the connectivity result there instead.
    if (kIsWeb) return true;

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