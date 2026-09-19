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
    //
    // A failed fetch falls through to the cache rather than throwing past it.
    // Being "online" is only a guess — on web it is any Wi-Fi or ethernet
    // link, including one with no internet behind it — and when the request
    // then fails, the cached venue is exactly what the app must render.
    if (await checkInternetConnectivity()) {
      try {
        final fresh = await _fetchFromApi(venueName, service);
        if (fresh != null) return fresh;
      } catch (e) {
        print("GlobalGeoJSONVenueAPI: live fetch failed, using the cached "
            "venue if there is one: $e");
      }
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