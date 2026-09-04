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

    // Always serve from disk if available (works offline forever)
    if (await file.exists()) {
      final bytes=await file.readAsBytes();
      return bytes;
    }

    try {
      final assetPath = 'assets/icons/$fileName'; // 👈 define your folder
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      print("$fileName found in assets");
      // Optional: save to cache for next time
      await file.writeAsBytes(bytes);

      return bytes;
    } catch (_) {
      print("$fileName not found in assets");
    }

    // if (AppConfig.internetSpeedInMbps < 1) {
    //   return null;
    // }

    // First time — fetch from network AND cache it
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes); // cache for next time
        return response.bodyBytes;
      }
    } catch (_) {}
    return null; // not cached + no internet
  }

  /// Requests already in flight, keyed by url. A whole enclosure's markers ask
  /// for the same photo within the same tick, and without this each one would
  /// issue its own fetch — the disk check that dedupes them on native has no
  /// web equivalent.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Web variant of [fetchWithCache]: no filesystem, so bundled icons still
  /// come from rootBundle and everything else is fetched over the network with
  /// the browser's own HTTP cache standing in for the disk cache. Bytes are not
  /// retained here — callers keep the composited icon, and holding every source
  /// photo for the life of the tab would cost far more memory than a re-fetch.
  Future<Uint8List?> _fetchWithCacheWeb(String url) {
    return _inFlight.putIfAbsent(url, () async {
      try {
        final fileName = md5.convert(utf8.encode(url)).toString();
        try {
          final data = await rootBundle.load('assets/icons/$fileName');
          return data.buffer.asUint8List();
        } catch (_) {
          // Not bundled — fall through to the network.
        }
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) return response.bodyBytes;
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

  void _refreshCacheInBackground(String url, File file) {

    http.get(Uri.parse(url)).then((response) {
      if (response.statusCode == 200) {
        file.writeAsBytes(response.bodyBytes);
      }
    }).catchError((_) {}); // silently fail if offline
  }
}
