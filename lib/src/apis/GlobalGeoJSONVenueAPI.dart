import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';

class GlobalGeoJSONVenueAPI {

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName, {bool fromDB = true}) async {
    final service = await GlobalGeoJSONVenueStorageService.create();
    final bool dbHasData = service.contiansID(venueName) == true;

    // ── FIRST RUN: Seed from asset if DB is empty ──
    if (!dbHasData) {
      final seeded = await _seedFromAssetIfNeeded(venueName, service);
      if (seeded) {
        // Asset seeded — trigger background API sync if internet available
        _backgroundSync(venueName, service);
        return service.getGeoData(venueName)?.responseBody;
      }
      // No asset, no DB — fall through to API call
      return _fetchFromApi(venueName, service);
    }

    // ── SUBSEQUENT RUNS: DB has data ──
    if (fromDB) {
      _backgroundSync(venueName, service); // refresh in background if internet
      print("GlobalGeoJSONVenueAPI from DataBase");
      return service.getGeoData(venueName)?.responseBody;
    }

    return _fetchFromApi(venueName, service);
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String venueName, GlobalGeoJSONVenueStorageService service) async {
    try {
      final raw = await rootBundle.loadString(
        'packages/unified_map_view/assets/api_data/GeoJsonDataNationalZoologicalPark.json',
      );
      final Map<String, dynamic> responseBody = json.decode(raw);
      final model = GlobalGeoJSONVenueAPIModel(responseBody: responseBody);
      service.saveGeoData(model, venueName);
      print("GlobalGeoJSONVenueAPI seeded from asset.");
      return true;
    } catch (_) {
      print("No bundled GeoJSON asset found.");
      return false;
    }
  }

  /// Fire-and-forget background API sync.
  void _backgroundSync(String venueName, GlobalGeoJSONVenueStorageService service) async {
    final isConnected = await checkInternetConnectivity();
    if (isConnected) {
      print("GlobalGeoJSONVenueAPI background sync started...");
      _fetchFromApi(venueName, service);
    }
  }

  Future<Map<String, dynamic>?> _fetchFromApi(String venueName, GlobalGeoJSONVenueStorageService service) async {
    final baseUrl = "${AppConfig.baseUrl}/secured/get-indoor-geojson-venue/$venueName?api_key=${AppConfig.apiKey}";
    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      service.saveGeoData(GlobalGeoJSONVenueAPIModel(responseBody: body), venueName);
      print("GlobalGeoJSONVenueAPI from API");
      return body;
    } else if (response.statusCode == 403) {
      return _fetchFromApi(venueName, service);
    } else {
      print("getGeoJSONData failed: ${response.statusCode}");
      return null;
    }
  }

  static Future<bool> checkInternetConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi);
  }
}