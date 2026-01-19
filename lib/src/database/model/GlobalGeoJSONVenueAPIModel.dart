import 'package:hive_flutter/adapters.dart';
part 'GlobalGeoJSONVenueAPIModel.g.dart';

@HiveType(typeId: 10)
class GlobalGeoJSONVenueAPIModel{
  @HiveField(0)
  Map<String, dynamic> responseBody;

  GlobalGeoJSONVenueAPIModel({required this.responseBody});
}
