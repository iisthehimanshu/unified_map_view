class Location{
  double latitude;
  double longitude;
  double accuracy;
  DateTime timeStamp;
  double? bearing;

  Location({required this.latitude,required this.longitude,required this.accuracy, required this.timeStamp, required this.bearing});
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timeStamp': timeStamp.toIso8601String(), // Serializing DateTime to string
      'bearing': bearing
    };
  }
}