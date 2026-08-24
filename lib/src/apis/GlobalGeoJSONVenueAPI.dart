import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';

class GlobalGeoJSONVenueAPI {

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName) async {
    final service = await GlobalGeoJSONVenueStorageService();
    await service.init();
    final bool dbHasData = service.containsID(venueName) == true;

    // Seed from the bundled asset (if any) so there's something to fall
    // back to below even if the live fetch fails or there's no internet.
    if (!dbHasData) {
      await _seedFromAssetIfNeeded(venueName, service);
    }

    // Prefer a live fetch whenever we're online, and use its result for
    // THIS render — not just save it for next launch. The previous
    // fire-and-forget "_backgroundSync" always rendered from whatever was
    // cached (a bundled asset, or a prior session's fetch) and only
    // updated the cache for the *next* launch, so any server-side data
    // fix (e.g. corrected per-part colors on furniture/landmark models)
    // stayed invisible until the app was uninstalled and reinstalled,
    // which is the only path that starts with an empty cache.
    if (await checkInternetConnectivity()) {
      final fresh = await _fetchFromApi(venueName, service);
      if (fresh != null) return fresh;
    }

    if (service.containsID(venueName)) {
      print("GlobalGeoJSONVenueAPI from DataBase");
      return service.getGeoData(venueName)?.responseBody;
    }

    throw("no preload & no DB data & no internet");
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String venueName, GlobalGeoJSONVenueStorageService service) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/api_data/GeoJsonData${venueName}.json',
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

  Future<Map<String, dynamic>?> _fetchFromApi(String venueName, GlobalGeoJSONVenueStorageService service) async {
    final baseUrl = "${AppConfig.baseUrl}/secured/get-indoor-geojson-venue/$venueName?expand=0.1&api_key=${AppConfig.apiKey}";
    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      service.saveGeoData(GlobalGeoJSONVenueAPIModel(responseBody: body), venueName);
      print("GlobalGeoJSONVenueAPI from API $body");
      return body;
    } else if (response.statusCode == 403) {
      return _fetchFromApi(venueName, service);
    } else {
      print("getGeoJSONData failed: ${response.statusCode} ${response.body}");
      return null;
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