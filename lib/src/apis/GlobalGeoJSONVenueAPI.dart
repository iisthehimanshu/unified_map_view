import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';

class GlobalGeoJSONVenueAPI {

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName) async {
    final service = await GlobalGeoJSONVenueStorageService.create();
    final bool dbHasData = service.contiansID(venueName) == true;

    // ── FIRST RUN: Seed from asset if DB is empty ──
    if (!dbHasData) {
      final seeded = await _seedFromAssetIfNeeded(venueName, service);
      final internetAvailable = await checkInternetConnectivity();
      if (seeded) {
        // Asset seeded — trigger background API sync if internet available
        _backgroundSync(venueName, service);
        return service.getGeoData(venueName)?.responseBody;
      }else if(internetAvailable){
        return await _fetchFromApi(venueName, service);
      }else{
        throw("no preload & no DB data & no internet");
      }
    }else{
      _backgroundSync(venueName, service);
      print("GlobalGeoJSONVenueAPI from DataBase");
      return service.getGeoData(venueName)?.responseBody;
    }
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String venueName, GlobalGeoJSONVenueStorageService service) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/api_data/GeoJsonDataNationalZoologicalPark.json',
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