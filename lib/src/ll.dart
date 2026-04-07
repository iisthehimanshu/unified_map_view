import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'apimodels/BuildingData.dart';

class ApiDataFetcher {
  final String accessToken;
  final String baseUrl;

  ApiDataFetcher({
    required this.accessToken,
    required this.baseUrl,
  });

  // Generic method to make API calls
  Future<dynamic> makeApiCall({
    required String endpoint,
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      final url = Uri.parse(endpoint);
      http.Response response;

      if (method == 'POST') {
        response = await http.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else {
        response = await http.get(url, headers: headers);
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception during API call: $e');
      return null;
    }
  }

  // Save data to file
  Future<void> saveToFile(String filename, dynamic data) async {
    try {
      final file = File('assets/api_data/$filename');
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
      print('✓ Saved: $filename');
    } catch (e) {
      print('Error saving $filename: $e');
    }
  }

  Future<BuildingData> fetchBuildingIDS(String venueName) async {
    print('\nFetching Building data...');
    final data = await makeApiCall(
      endpoint: '$baseUrl/secured/building/get/venue?api_key=${accessToken}',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: {
        "venueName": venueName,
        "campusIncludes":true //venue Name
      },
    );
    var buildingData = BuildingData.fromJson(data);
    return buildingData;
  }

  // 6. Global Annotation API
  Future<void> fetchGeoJsonData(String venueName) async {
    print('\nFetching GeoJson Data...');
    final data = await makeApiCall(
      endpoint: '$baseUrl/secured/get-indoor-geojson-venue/${venueName}?api_key=${accessToken}',
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (data != null) {
      await saveToFile('GeoJsonData$venueName.json', data);
    }
  }


  // Fetch all data for a building/venue
  Future<void> fetchAllData({required String venueName}) async {
    print('========================================');
    print('Starting API Data Fetch');
    print('========================================');

    await fetchGeoJsonData(venueName);

    print('\n========================================');
    print('All API calls completed!');
    print('Data saved in ./api_data/ directory');
    print('========================================');
  }
}

void main() async {
  // Configuration - REPLACE WITH YOUR ACTUAL VALUES
  final fetcher = ApiDataFetcher(
    accessToken: "7cc62870-d67e-11f0-91ed-2f0eb903e7db",
    baseUrl: "https://dev.iwayplus.in",
  );
  var buildingData = await fetcher.fetchBuildingIDS("NationalZoologicalPark");

  fetcher.saveToFile("BuildingByVenueNationalZoologicalPark.json", buildingData);


    await fetcher.fetchAllData(venueName: 'NationalZoologicalPark');
}