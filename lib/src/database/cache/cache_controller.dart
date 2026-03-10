import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

class CacheController {

  Future<Uint8List?> fetchWithCache(String url) async {
    final dir = await getApplicationCacheDirectory();
    final fileName = base64Url.encode(utf8.encode(url));
    final file = File('${dir.path}/$fileName');

    // Always serve from disk if available (works offline forever)
    if (await file.exists()) {
      final bytes=await file.readAsBytes();
      _refreshCacheInBackground(url, file);
      return bytes;
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