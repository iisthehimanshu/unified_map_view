
import 'package:hive/hive.dart';

import '../model/GlobalGeoJSONVenueAPIModel.dart';

class GlobalGeoJSONVenueAPIBOX {
  static Box<GlobalGeoJSONVenueAPIModel> getData() => Hive.box<GlobalGeoJSONVenueAPIModel>("GlobalGeoJSONVenueAPIModelFile");
}