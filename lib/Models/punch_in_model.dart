class Punch {
  int? id;
  int timestamp; // epoch in milliseconds
  double latitude;
  double longitude;
  String address;

  Punch({
    this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }

  factory Punch.fromMap(Map<String, dynamic> map) {
    return Punch(
      id: map['id'],
      timestamp: map['timestamp'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      address: map['address'],
    );
  }
}
