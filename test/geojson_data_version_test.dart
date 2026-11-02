import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unified_map_view/src/apis/GlobalGeoJSONVenueAPI.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';
import 'package:unified_map_view/src/models/venue_data_version.dart';

Map<String, dynamic> _body(String tag) =>
    {'message': tag, 'data': [], 'floorConfigs': []};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<GlobalGeoJSONVenueAPIModel> box;
  var requests = 0;
  Completer<void>? gate;

  final client = MockClient((req) async {
    if (req.url.host == 'clients3.google.com') {
      return http.Response('', 204);
    }
    requests++;
    await gate?.future;
    return http.Response(jsonEncode(_body('fresh')), 200);
  });

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('geojson_version');
    Hive.init(dir.path);
    Hive.registerAdapter(GlobalGeoJSONVenueAPIModelAdapter());
    box = await Hive.openBox<GlobalGeoJSONVenueAPIModel>(
        'GlobalGeoJSONVenueAPIModelFile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (call) async => ['wifi']);
  });

  setUp(() {
    requests = 0;
    gate = null;
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 50));

  test('label is v + sum of the buildings\' versions', () {
    expect(VenueDataVersion.format('a:4,b:64'), 'v68');
    expect(VenueDataVersion.format(null), 'v—');
  });

  test('same version: serves the cache and makes no request', () async {
    await box.put('Same',
        GlobalGeoJSONVenueAPIModel(
            responseBody: {..._body('cached'), '_dataVersion': 'a:1,b:2'}));
    GlobalGeoJSONVenueAPI.provideVersion('Same', Future.value('a:1,b:2'));

    final data = await http.runWithClient(
        () => GlobalGeoJSONVenueAPI().getGeoJSONData('Same'), () => client);
    await settle();

    expect(data!['message'], 'cached');
    expect(requests, 0);
    final v = GlobalGeoJSONVenueAPI.versionOf('Same').value;
    expect(v.label, 'v3');
    expect(v.fetching, false);
    expect(v.pending, isNull);
  });

  test('new version: spins while fetching, keeps showing the old one',
      () async {
    await box.put('Bumped',
        GlobalGeoJSONVenueAPIModel(
            responseBody: {..._body('cached'), '_dataVersion': 'a:1,b:2'}));
    gate = Completer();
    final data = await http.runWithClient(() {
      // Handed in after the load starts, as when the map opens first.
      final load = GlobalGeoJSONVenueAPI().getGeoJSONData('Bumped');
      GlobalGeoJSONVenueAPI.provideVersion('Bumped', Future.value('a:1,b:5'));
      return load;
    }, () => client);
    await settle();

    final n = GlobalGeoJSONVenueAPI.versionOf('Bumped');
    expect(data!['message'], 'cached');
    expect(n.value.fetching, true);
    expect(n.value.label, 'v3');

    gate!.complete();
    await settle();
    expect(requests, 1);
    expect(n.value.fetching, false);
    expect(n.value.label, 'v3');
    expect(n.value.pending, 'a:1,b:5');
    expect(box.get('Bumped')!.responseBody['message'], 'fresh');
    expect(box.get('Bumped')!.responseBody['_dataVersion'], 'a:1,b:5');
  });

  test('no cache: spins on first load, then shows the host version',
      () async {
    gate = Completer();
    final n = GlobalGeoJSONVenueAPI.versionOf('Cold');
    final load = http.runWithClient(
        () => GlobalGeoJSONVenueAPI().getGeoJSONData('Cold'), () => client);
    await settle();
    expect(n.value.fetching, true);
    expect(n.value.label, 'v—');

    gate!.complete();
    final data = await load;
    expect(data!['message'], 'fresh');
    GlobalGeoJSONVenueAPI.provideVersion('Cold', Future.value('a:7'));
    await settle();
    expect(n.value.fetching, false);
    expect(n.value.label, 'v7');
    expect(box.get('Cold')!.responseBody['_dataVersion'], 'a:7');
  });
}
