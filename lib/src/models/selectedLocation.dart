class SelectedLocation{
  late String _polyID;
  late dynamic _polygon;
  late dynamic _marker;

  SelectedLocation({required String polyID, required dynamic polygon, required dynamic marker}){
   setLocation(polyID: polyID, polygon: polygon, marker: marker);
  }

  dynamic get marker => _marker;

  dynamic get polygon => _polygon;

  String get polyID => _polyID;

  void setLocation({required String polyID, required dynamic polygon, required dynamic marker}){
    if (polygon == null && marker == null) {
      throw ArgumentError('Both polygon and marker cannot be null at the same time');
    }
    _marker = marker;
    _polygon = polygon;
    _polyID = polyID;
  }
}