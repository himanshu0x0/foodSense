import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents one daily operational food record for an organization.
///
/// Firestore document path:
/// organizations/{organizationId}/food_records/{recordId}
///
/// Media:
/// Food record photos are stored in Cloudinary. Firestore stores only the
/// Cloudinary delivery URL and public ID needed to display/manage the asset.
class DailyFoodRecord {
  const DailyFoodRecord({
    required this.id,
    required this.organizationId,
    required this.recordDate,
    required this.mealType,
    required this.menu,
    required this.expectedPeople,
    required this.actualPeople,
    required this.mealsPrepared,
    required this.mealsConsumed,
    required this.mealsRemaining,
    required this.wasteKg,
    required this.specialEvent,
    this.imageUrl,
    this.imagePublicId,
    this.createdBy,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
  });

  final String id;
  final String organizationId;

  /// The operational date this record belongs to.
  final DateTime recordDate;

  /// Examples: Breakfast, Lunch, Dinner, Snack.
  final String mealType;

  final String menu;

  final int expectedPeople;
  final int actualPeople;

  final int mealsPrepared;
  final int mealsConsumed;

  /// Usually calculated as mealsPrepared - mealsConsumed.
  final int mealsRemaining;

  /// Measured food waste in kilograms.
  final double wasteKg;

  /// Marks unusual-demand days such as events or special programs.
  final bool specialEvent;

  /// HTTPS Cloudinary delivery URL for the food-record photo.
  final String? imageUrl;

  /// Cloudinary public ID used to manage/delete the uploaded asset.
  final String? imagePublicId;

  final String? createdBy;
  final DateTime? createdAt;

  final String? updatedBy;
  final DateTime? updatedAt;

  /// Whether this food record currently has an attached Cloudinary image.
  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// Creates a model from a Firestore document.
  factory DailyFoodRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    return DailyFoodRecord.fromMap(data, id: document.id);
  }

  /// Creates a model from a Firestore map.
  factory DailyFoodRecord.fromMap(Map<String, dynamic> map, {String? id}) {
    return DailyFoodRecord(
      id: id ?? (map['id'] as String? ?? ''),
      organizationId: map['organizationId'] as String? ?? '',
      recordDate: _dateTimeFromValue(map['recordDate']) ?? DateTime.now(),
      mealType: map['mealType'] as String? ?? '',
      menu: map['menu'] as String? ?? '',
      expectedPeople: _intFromValue(map['expectedPeople']),
      actualPeople: _intFromValue(map['actualPeople']),
      mealsPrepared: _intFromValue(map['mealsPrepared']),
      mealsConsumed: _intFromValue(map['mealsConsumed']),
      mealsRemaining: _intFromValue(map['mealsRemaining']),
      wasteKg: _doubleFromValue(map['wasteKg']),
      specialEvent: map['specialEvent'] == true,
      imageUrl: _stringFromValue(map['imageUrl']),
      imagePublicId: _stringFromValue(map['imagePublicId']),
      createdBy: map['createdBy'] as String?,
      createdAt: _dateTimeFromValue(map['createdAt']),
      updatedBy: map['updatedBy'] as String?,
      updatedAt: _dateTimeFromValue(map['updatedAt']),
    );
  }

  /// Converts the record into Firestore-safe values.
  ///
  /// The [id] is intentionally not written because it is already the
  /// Firestore document ID.
  Map<String, dynamic> toMap({bool includeMetadata = true}) {
    final Map<String, dynamic> map = <String, dynamic>{
      'organizationId': organizationId,
      'recordDate': Timestamp.fromDate(recordDate),
      'mealType': mealType,
      'menu': menu,
      'expectedPeople': expectedPeople,
      'actualPeople': actualPeople,
      'mealsPrepared': mealsPrepared,
      'mealsConsumed': mealsConsumed,
      'mealsRemaining': mealsRemaining,
      'wasteKg': wasteKg,
      'specialEvent': specialEvent,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl,
      if (imagePublicId != null && imagePublicId!.trim().isNotEmpty)
        'imagePublicId': imagePublicId,
    };

    if (includeMetadata) {
      map.addAll(<String, dynamic>{
        if (createdBy != null) 'createdBy': createdBy,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedBy != null) 'updatedBy': updatedBy,
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      });
    }

    return map;
  }

  /// Creates a copy with selected values replaced.
  DailyFoodRecord copyWith({
    String? id,
    String? organizationId,
    DateTime? recordDate,
    String? mealType,
    String? menu,
    int? expectedPeople,
    int? actualPeople,
    int? mealsPrepared,
    int? mealsConsumed,
    int? mealsRemaining,
    double? wasteKg,
    bool? specialEvent,
    String? imageUrl,
    String? imagePublicId,
    String? createdBy,
    DateTime? createdAt,
    String? updatedBy,
    DateTime? updatedAt,
  }) {
    return DailyFoodRecord(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      recordDate: recordDate ?? this.recordDate,
      mealType: mealType ?? this.mealType,
      menu: menu ?? this.menu,
      expectedPeople: expectedPeople ?? this.expectedPeople,
      actualPeople: actualPeople ?? this.actualPeople,
      mealsPrepared: mealsPrepared ?? this.mealsPrepared,
      mealsConsumed: mealsConsumed ?? this.mealsConsumed,
      mealsRemaining: mealsRemaining ?? this.mealsRemaining,
      wasteKg: wasteKg ?? this.wasteKg,
      specialEvent: specialEvent ?? this.specialEvent,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePublicId: imagePublicId ?? this.imagePublicId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Calculates the remaining meals from prepared and consumed quantities.
  int get calculatedMealsRemaining {
    final int remaining = mealsPrepared - mealsConsumed;
    return remaining < 0 ? 0 : remaining;
  }

  /// True when the recorded waste is greater than zero.
  bool get hasWaste => wasteKg > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is DailyFoodRecord &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.recordDate == recordDate &&
        other.mealType == mealType &&
        other.menu == menu &&
        other.expectedPeople == expectedPeople &&
        other.actualPeople == actualPeople &&
        other.mealsPrepared == mealsPrepared &&
        other.mealsConsumed == mealsConsumed &&
        other.mealsRemaining == mealsRemaining &&
        other.wasteKg == wasteKg &&
        other.specialEvent == specialEvent &&
        other.imageUrl == imageUrl &&
        other.imagePublicId == imagePublicId &&
        other.createdBy == createdBy &&
        other.createdAt == createdAt &&
        other.updatedBy == updatedBy &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    recordDate,
    mealType,
    menu,
    expectedPeople,
    actualPeople,
    mealsPrepared,
    mealsConsumed,
    mealsRemaining,
    wasteKg,
    specialEvent,
    imageUrl,
    imagePublicId,
    createdBy,
    createdAt,
    updatedBy,
    updatedAt,
  );

  @override
  String toString() {
    return 'DailyFoodRecord('
        'id: $id, '
        'organizationId: $organizationId, '
        'recordDate: $recordDate, '
        'mealType: $mealType, '
        'menu: $menu, '
        'expectedPeople: $expectedPeople, '
        'actualPeople: $actualPeople, '
        'mealsPrepared: $mealsPrepared, '
        'mealsConsumed: $mealsConsumed, '
        'mealsRemaining: $mealsRemaining, '
        'wasteKg: $wasteKg, '
        'specialEvent: $specialEvent, '
        'hasImage: $hasImage'
        ')';
  }

  static String? _stringFromValue(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return null;
  }

  static DateTime? _dateTimeFromValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  static int _intFromValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  static double _doubleFromValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }
}
