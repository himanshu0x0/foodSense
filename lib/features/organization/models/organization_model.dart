/// Represents an organization using the FoodSense platform.
///
/// Phase 1 keeps the organization profile focused on information required
/// for basic onboarding and future food-operation data collection.
/// Additional fields should only be introduced when a later feature needs
/// them.
class OrganizationModel {
  final String id;
  final String name;
  final String type;
  final String address;
  final String city;
  final String state;
  final String country;
  final int peopleServed;
  final String ownerId;

  const OrganizationModel({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    required this.peopleServed,
    required this.ownerId,
  });

  /// Creates an organization model from a Firestore document/map.
  factory OrganizationModel.fromMap(Map<String, dynamic> map) {
    return OrganizationModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? '',
      address: map['address'] as String? ?? '',
      city: map['city'] as String? ?? '',
      state: map['state'] as String? ?? '',
      country: map['country'] as String? ?? 'India',
      peopleServed: _readInt(map['peopleServed']),
      ownerId: map['ownerId'] as String? ?? '',
    );
  }

  /// Converts this model into a Firestore-safe map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'peopleServed': peopleServed,
      'ownerId': ownerId,
    };
  }

  /// Creates a copy with selected fields changed.
  OrganizationModel copyWith({
    String? id,
    String? name,
    String? type,
    String? address,
    String? city,
    String? state,
    String? country,
    int? peopleServed,
    String? ownerId,
  }) {
    return OrganizationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      peopleServed: peopleServed ?? this.peopleServed,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  String toString() {
    return 'OrganizationModel('
        'id: $id, '
        'name: $name, '
        'type: $type, '
        'address: $address, '
        'city: $city, '
        'state: $state, '
        'country: $country, '
        'peopleServed: $peopleServed, '
        'ownerId: $ownerId'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OrganizationModel &&
        other.id == id &&
        other.name == name &&
        other.type == type &&
        other.address == address &&
        other.city == city &&
        other.state == state &&
        other.country == country &&
        other.peopleServed == peopleServed &&
        other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    address,
    city,
    state,
    country,
    peopleServed,
    ownerId,
  );
}
