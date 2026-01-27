import 'package:hive/hive.dart';
part 'BuildingByVenueAPIModel.g.dart';

@HiveType(typeId: 79)
class BuildingByVenueAPIModel extends HiveObject{
  @HiveField(0)
  Map<String, dynamic> responseBody;

  BuildingByVenueAPIModel({required this.responseBody});
}