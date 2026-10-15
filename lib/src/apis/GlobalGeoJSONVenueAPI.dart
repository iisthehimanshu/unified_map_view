import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/perf_trace.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import '../models/venue_data_version.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';

class GlobalGeoJSONVenueAPI {

  /// One load per venue per session, shared by every caller. `initialize`, each
  /// map's annotation controller and the host (navigation_sdk builds its
  /// per-building mapping elements from this response) all ask for the same
  /// multi-MB venue; each call used to start its own live fetch.
  static final Map<String, Future<Map<String, dynamic>?>> _loads = {};

  /// Key the data version is stored under in the cached body.
  static const String _versionKey = '_dataVersion';

  /// Each venue's data version as handed in by the host, pending until the
  /// host's versions request answers.
  static final Map<String, Completer<Future<String?>>> _hostVersions = {};

  static final Map<String, ValueNotifier<VenueDataVersion>> _versions = {};

  /// Supplies the version (see [VenueDataVersion]) the cached GeoJSON for
  /// [venueName] is checked against. The host already fetches the venue's
  /// versions, so this package makes no versions request of its own.
  static void provideVersion(String venueName, Future<String?> version) {
    final c = _hostVersions[venueName];
    if (c == null || c.isCompleted) {
      _hostVersions[venueName] = Completer()..complete(version);
    } else {
      c.complete(version);
    }
  }

  /// The host's version for [venueName]. A refresh can get here before the
  /// host has started its request, so wait a while for it to be handed in.
  /// Null when it never was, or the host's request failed.
  static Future<String?> _versionFor(String venueName) async {
    final c = _hostVersions.putIfAbsent(venueName, () => Completer());
    try {
      final version = await c.future.timeout(const Duration(seconds: 15));
      return await version;
    } catch (_) {
      return null;
    }
  }

  /// The version of [venueName]'s GeoJSON the map is showing, and whether a
  /// newer one is downloading. See [VenueDataVersion].
  static ValueNotifier<VenueDataVersion> versionOf(String venueName) =>
      _versions.putIfAbsent(
          venueName, () => ValueNotifier(const VenueDataVersion()));

  /// The response each venue's map is drawing, so a version attached to it
  /// later (a first run fetches before the host's version is known) shows.
  static final Map<String, Map<String, dynamic>> _shown = {};

  static void _showing(String venueName, Map<String, dynamic> data) {
    _shown[venueName] = data;
    final n = versionOf(venueName);
    final v = data[_versionKey] as String?;
    n.value = VenueDataVersion(
      showing: v,
      fetching: n.value.fetching,
      pending: n.value.pending == v ? null : n.value.pending,
    );
  }

  static void _setFetching(String venueName, bool fetching) {
    final n = versionOf(venueName);
    if (n.value.fetching != fetching) {
      n.value = n.value.copyWith(fetching: fetching);
    }
  }

  /// Hands the package a venue response the host already has, so no request
  /// is made for it. It is not written to the cache — the host owns that.
  static void provide(String venueName, Map<String, dynamic> data) {
    _loads[venueName] = Future.value(data);
    _showing(venueName, data);
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
      if (data != null && identical(_loads[venueName], load)) {
        _showing(venueName, data);
      }
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
        _refreshIfStale(venueName, service, cached[_versionKey] as String?);
        return cached;
      }
    }

    // Being "online" is only a guess — on web it is any Wi-Fi or ethernet
    // link, including one with no internet behind it.
    if (await checkInternetConnectivity()) {
      _setFetching(venueName, true);
      try {
        final fresh = await _fetchFromApi(venueName, service);
        if (fresh != null) return fresh;
      } finally {
        _setFetching(venueName, false);
      }
    }

    throw("no preload & no DB data & no internet");
  }

  /// Re-fetches the venue for the next launch when the host's version is not
  /// the one the cache was stored with. An unknown version counts as changed.
  Future<void> _refreshIfStale(String venueName,
      GlobalGeoJSONVenueStorageService service, String? cachedVersion) async {
    try {
      final version = await _versionFor(venueName);
      if (version != null && version == cachedVersion) {
        print("GlobalGeoJSONVenueAPI: version unchanged — cache is current");
        return;
      }
      if (!await checkInternetConnectivity()) return;
      print("GlobalGeoJSONVenueAPI: version changed — refreshing the cache");
      _setFetching(venueName, true);
      final fresh = await _fetchFromApi(venueName, service);
      final n = versionOf(venueName);
      if (fresh != null && version != n.value.showing) {
        n.value = n.value.copyWith(pending: version);
      }
    } catch (e) {
      print("GlobalGeoJSONVenueAPI: background refresh failed: $e");
    } finally {
      _setFetching(venueName, false);
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
      // Stored under the host's version, once that is known; the body goes to
      // the map without waiting for it.
      _versionFor(venueName).then((version) {
        if (version != null) {
          body[_versionKey] = version;
          if (identical(_shown[venueName], body)) _showing(venueName, body);
        }
        service.saveGeoData(
            GlobalGeoJSONVenueAPIModel(responseBody: body), venueName);
      });
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