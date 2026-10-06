import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/perf_trace.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';

class GlobalGeoJSONVenueAPI {

  /// One load per venue per session, shared by every caller. `initialize`, each
  /// map's annotation controller and the host (navigation_sdk builds its
  /// per-building mapping elements from this response) all ask for the same
  /// multi-MB venue; each call used to start its own live fetch.
  static final Map<String, Future<Map<String, dynamic>?>> _loads = {};

  /// Hands the package a venue response the host already has, so no request
  /// is made for it. It is not written to the cache — the host owns that.
  static void provide(String venueName, Map<String, dynamic> data) {
    _loads[venueName] = Future.value(data);
  }

  /// Drops the shared load, so the next call fetches again. Null clears all.
  static void invalidate([String? venueName]) {
    if (venueName == null) {
      _loads.clear();
    } else {
      _loads.remove(venueName);
    }
  }

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName) {
    // The venue goes in the URL path, so an empty name requests
    // `/secured/get-indoor-geojson-venue/` — which answers 500. Callers reach
    // here before the venue is known (initialize is passed `venueName ?? ""`),
    // so bail without spending the round-trip. Deliberately not recorded in
    // [_loads]: the next call with a real venue must still fetch.
    if (venueName.trim().isEmpty) {
      print("getGeoJSONData: empty venue name — skipping request");
      return Future.value(null);
    }
    final existing = _loads[venueName];
    if (existing != null) return existing;
    final load = _load(venueName);
    _loads[venueName] = load;
    // A failed load must not be remembered — the next caller retries.
    load.then((data) {
      if (data == null && identical(_loads[venueName], load)) {
        _loads.remove(venueName);
      }
    }, onError: (_) {
      if (identical(_loads[venueName], load)) _loads.remove(venueName);
    });
    return load;
  }

  Future<Map<String, dynamic>?> _load(String venueName) async {
    final service = await GlobalGeoJSONVenueStorageService();
    await service.init();
    final bool dbHasData = service.containsID(venueName) == true;

    // Seed from the bundled asset (if any) so a first run has something to
    // serve below.
    if (!dbHasData) {
      await _seedFromAssetIfNeeded(venueName, service);
    }

    // Cached: render from it now and refresh the cache behind it, for the next
    // launch. Waiting on the live fetch here held the whole venue off screen
    // for as long as a multi-MB download took, on every launch, for a response
    // that rarely differs from the cached one.
    if (service.containsID(venueName)) {
      final cached = service.getGeoData(venueName)?.responseBody;
      if (cached != null) {
        print("GlobalGeoJSONVenueAPI from DataBase");
        _refresh(venueName, service);
        return cached;
      }
    }

    // Being "online" is only a guess — on web it is any Wi-Fi or ethernet
    // link, including one with no internet behind it.
    if (await checkInternetConnectivity()) {
      final fresh = await _fetchFromApi(venueName, service);
      if (fresh != null) return fresh;
    }

    throw("no preload & no DB data & no internet");
  }

  /// Fetches the venue live and stores it for the next launch.
  Future<void> _refresh(String venueName, GlobalGeoJSONVenueStorageService service) async {
    try {
      if (!await checkInternetConnectivity()) return;
      await _fetchFromApi(venueName, service);
    } catch (e) {
      print("GlobalGeoJSONVenueAPI: background refresh failed: $e");
    }
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
      final body = PerfTrace.time(
        'GlobalGeoJSONVenueAPI json.decode (${response.body.length ~/ 1024}KB)',
        () => json.decode(response.body),
      );
      service.saveGeoData(GlobalGeoJSONVenueAPIModel(responseBody: body), venueName);
      // Interpolating `body` here stringifies the whole decoded payload — ~2.8MB
      // for ApolloHospital — on the main thread, and `print` is not stripped from
      // Flutter web release builds. Native keeps the original log.
      if (!kIsWeb) print("GlobalGeoJSONVenueAPI from API $body");
      return body;
    } else if (response.statusCode == 403) {
      // Rejected key. Retrying cannot fix that, and retrying with no delay or
      // limit (as this used to) floods the server until the page is closed.
      print("getGeoJSONData: api key rejected (403)");
      return null;
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