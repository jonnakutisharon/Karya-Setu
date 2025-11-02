class LocationModel {
  final String state;
  final String district;
  final String pincode;
  final String locality;

  LocationModel({
    required this.state,
    required this.district,
    required this.pincode,
    required this.locality,
  });

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'district': district,
      'pincode': pincode,
      'locality': locality,
    };
  }

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      state: json['state'] ?? '',
      district: json['district'] ?? '',
      pincode: json['pincode'] ?? '',
      locality: json['locality'] ?? '',
    );
  }

  LocationModel copyWith({
    String? state,
    String? district,
    String? pincode,
    String? locality,
  }) {
    return LocationModel(
      state: state ?? this.state,
      district: district ?? this.district,
      pincode: pincode ?? this.pincode,
      locality: locality ?? this.locality,
    );
  }
}
