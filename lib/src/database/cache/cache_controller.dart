import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

import '../../config.dart';

class CacheController {
  /// Every bundled asset path, resolved once from the asset manifest.
  ///
  /// Checked for the *exact* file before any `rootBundle.load`, so a miss costs
  /// a set lookup instead of a failing load. Testing the folder is not enough:
  /// `assets/icons/.gitkeep` is bundled as a directory placeholder, so a "does
  /// this folder exist" check passes while every real icon is still absent.
  static Future<Set<String>>? _bundledAssets;

  static Future<Set<String>> _assetIndex() {
    return _bundledAssets ??= () async {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        return manifest.listAssets().toSet();
      } catch (_) {
        // Manifest unreadable — treat everything as unbundled rather than
        // paying a failing probe per icon.
        return <String>{};
      }
    }();
  }

  static Future<bool> _isBundled(String assetPath) async =>
      (await _assetIndex()).contains(assetPath);

  /// Requests already in flight, keyed by url. A whole enclosure's markers ask
  /// for the same photo within the same tick, and without this each one would
  /// issue its own fetch — the disk check that dedupes them on native has no
  /// web equivalent.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Web has no `dart:io` filesystem and no `path_provider`, so the on-disk
  /// cache used on mobile is unavailable — `getApplicationCacheDirectory()`
  /// throws a MissingPluginException on the very first line and every marker
  /// icon fetched over http fails. The browser's own HTTP cache already gives
  /// the persistence the disk cache provides on mobile, so just read the
  /// bundled asset and otherwise go straight to the network.
  ///
  /// The bundled read is skipped unless the manifest actually lists that exact
  /// file. On web a `rootBundle.load` miss is a real network round trip that
  /// 404s, and no venue icon is bundled — so the probe could never hit, while
  /// costing one 404 per icon. Measured on device: 215 such 404s spread over
  /// 63s of an otherwise idle map, cut to 4.
  ///
  /// Coalesced through [_inFlight]: a whole enclosure's markers ask for the
  /// same photo within the same tick, and the disk check that dedupes them on
  /// native has no web equivalent.
  Future<Uint8List?> _fetchWithCacheWeb(String url) {
    return _inFlight.putIfAbsent(url, () async {
      try {
        final fileName = md5.convert(utf8.encode(url)).toString();
        final assetPath = 'assets/icons/$fileName';
        if (await _isBundled(assetPath)) {
          try {
            final data = await rootBundle.load(assetPath);
            return data.buffer.asUint8List();
          } catch (_) {
            // Listed but unreadable — fall through to the network.
          }
        }
        // Same reasoning as the cache-hit path above: skipping the bundle probe
        // removed this call's only guaranteed yield to the event loop.
        await Future<void>.delayed(Duration.zero);
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            // Same empty-200 rejection as the native path above.
            if (response.bodyBytes.isEmpty) {
              print("fetchWithCache: $url -> HTTP 200 but EMPTY body "
                  "(asset is missing server-side)");
              return null;
            }
            return response.bodyBytes;
          }
          print("fetchWithCache: $url -> HTTP ${response.statusCode}");
        } catch (e) {
          // Most likely CORS or an offline tab; either way the caller keeps its
          // placeholder, so say why rather than failing silently.
          print("fetchWithCache: $url -> $e");
        }
        return null;
      } finally {
        _inFlight.remove(url);
      }
    });
  }

  /// NOTE: deliberately NOT memoising the bytes here.
  ///
  /// An in-memory cache keyed by URL was tried and reverted: it hands the SAME
  /// Uint8List instance to every marker sharing a photo, and on web
  /// `ui.instantiateImageCodec` can take ownership of the underlying buffer, so
  /// the second consumer gets a detached one. The failure is silent and total —
  /// the throw escapes the icon rebake inside onStyleLoadedCallback, the
  /// enable*Layers calls at its end never run, and the map sits on the grey
  /// basemap with no error. The bake already caches its *composited output*
  /// (_bakedIconCache / _animalIconCache / _animalSourceCache), which is where
  /// dedup belongs.

  Future<Uint8List?> fetchWithCache(String url) async {
    // path_provider ships no web implementation (it isn't in the generated web
    // plugin registrant at all), so getApplicationCacheDirectory below throws
    // MissingPluginException on the very first line for *every* URL in a
    // browser. Callers swallow that and fall back to their placeholder, which
    // is why http-sourced marker icons stayed dots/paws on web while working
    // on device.
    if (kIsWeb) return _fetchWithCacheWeb(url);

    final dir = await getApplicationCacheDirectory();
    final fileName = md5.convert(utf8.encode(url)).toString(); // 32 chars
    final file = File('${dir.path}/$fileName');

    // Always serve from disk if available (works offline forever).
    //
    // An EMPTY cached file is treated as a miss and deleted rather than served.
    // The write below used to persist a zero-byte 200 response, and once that
    // landed on disk the marker's icon could never recover on any later run —
    // the cache hit short-circuits the network every time. Deleting it here
    // gives a re-uploaded asset a chance to be picked up.
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
      print('fetchWithCache: cached file for $url is empty — discarding');
      try {
        await file.delete();
      } catch (_) {}
    }

    final assetPath = 'assets/icons/$fileName'; // 👈 define your folder
    if (await _isBundled(assetPath)) {
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        // Optional: save to cache for next time
        await file.writeAsBytes(bytes);

        return bytes;
      } catch (_) {
        // Listed but unreadable — fall through to the network.
      }
    }

    // if (AppConfig.internetSpeedInMbps < 1) {
    //   return null;
    // }

    // First time — fetch from network AND cache it.
    //
    // A 200 carrying an EMPTY body is a failure, not a success. This server
    // serves 0 bytes for some uploads, and returning those bytes made the
    // caller believe it had an image: the marker was then built claiming an
    // icon that could never be registered, and MapLibre drew its label with no
    // icon. Empty is rejected here and never cached, so the marker is routed
    // as icon-less and a re-uploaded asset can still recover later.
    //
    // Every failure path logs. This whole method used to be `catch (_) {}` with
    // a bare `return null`, which is why a server-side problem was invisible
    // from the app for as long as it was.
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (response.bodyBytes.isEmpty) {
          print('fetchWithCache: $url -> HTTP 200 but EMPTY body '
              '(asset is missing server-side; not cached)');
          return null;
        }
        await file.writeAsBytes(response.bodyBytes); // cache for next time
        return response.bodyBytes;
      }
      print('fetchWithCache: $url -> HTTP ${response.statusCode}');
    } catch (e) {
      print('fetchWithCache: $url -> $e');
    }
    return null; // not cached + no internet
  }

  void _refreshCacheInBackground(String url, File file) {
    http.get(Uri.parse(url)).then((response) {
      if (response.statusCode == 200) {
        file.writeAsBytes(response.bodyBytes);
      }
    }).catchError((_) {}); // silently fail if offline
  }
}
