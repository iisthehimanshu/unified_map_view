
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import '../database/model/GlobalGeoJSONVenueAPIModel.dart';
import '../services/GlobalGeoJSONStorageService.dart';


class GlobalGeoJSONVenueAPI{

  Future<Map<String, dynamic>?> getGeoJSONData(String venueName,{bool fromDB = true}) async {
    final _globalGeoJSONService = await GlobalGeoJSONVenueStorageService.create();

    if(fromDB && _globalGeoJSONService.contiansID(venueName) != null && _globalGeoJSONService.contiansID(venueName)==true){
      print("GlobalGeoJSONVenueAPI from DataBase");
      getGeoJSONData(venueName,fromDB: false);
      GlobalGeoJSONVenueAPIModel? globalGeoJSONVenueAPIModel = _globalGeoJSONService.getGeoData(venueName);
      return globalGeoJSONVenueAPIModel?.responseBody;
    }

    String baseUrl = "${AppConfig.baseUrl}/secured/get-indoor-geojson-venue/${venueName}?expand=-1&api_key=${AppConfig.apiKey}";

    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      _globalGeoJSONService.saveGeoData(GlobalGeoJSONVenueAPIModel(responseBody: json.decode(response.body)), venueName);
      print("GlobalGeoJSONVenueAPI from API");
      return json.decode(response.body);
    } else if (response.statusCode == 403) {
      return await getGeoJSONData(venueName);
    } else {
      print("getGeoJSONData response.statusCode ${response.statusCode} ${response.body}");
      return null;
      throw Exception('Failed to load data');
    }
  }
}