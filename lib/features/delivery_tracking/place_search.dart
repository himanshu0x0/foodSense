import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  LatLng get position => LatLng(latitude, longitude);
}

class LocationSelection {
  const LocationSelection({
    required this.position,
    required this.address,
    this.placeName,
    this.placeId,
  });

  final LatLng position;
  final String address;
  final String? placeName;
  final String? placeId;
}
