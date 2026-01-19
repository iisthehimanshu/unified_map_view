
import 'package:hive/hive.dart';

import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';


class GlobalGeoJSONVenueAPIBOX {
  static Box<GlobalGeoJSONVenueAPIModel> getData() => Hive.box<GlobalGeoJSONVenueAPIModel>("GlobalGeoJSONVenueAPIModelFile");
}