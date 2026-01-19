// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GlobalGeoJSONVenueAPIModelAdapter
    extends TypeAdapter<GlobalGeoJSONVenueAPIModel> {
  @override
  final int typeId = 10;

  @override
  GlobalGeoJSONVenueAPIModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GlobalGeoJSONVenueAPIModel(
      responseBody: (fields[0] as Map).cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, GlobalGeoJSONVenueAPIModel obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.responseBody);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalGeoJSONVenueAPIModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
