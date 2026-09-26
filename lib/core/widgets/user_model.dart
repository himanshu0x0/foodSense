/// Represents an authenticated FoodSense user.
///
/// This model intentionally keeps the profile minimal for Phase 1.
/// Additional fields can be added later only when a real product
/// requirement needs them.
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String organizationId;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.organizationId,
  });

  /// Creates a [UserModel] from a Firestore document/map.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'kitchen_manager',
      organizationId: map['organizationId'] as String? ?? '',
    );
  }

  /// Converts this model into a Firestore-safe map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'organizationId': organizationId,
    };
  }

  /// Creates a copy with selected fields changed.
  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? organizationId,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      organizationId: organizationId ?? this.organizationId,
    );
  }

  @override
  String toString() {
    return 'UserModel('
        'uid: $uid, '
        'name: $name, '
        'email: $email, '
        'role: $role, '
        'organizationId: $organizationId'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserModel &&
        other.uid == uid &&
        other.name == name &&
        other.email == email &&
        other.role == role &&
        other.organizationId == organizationId;
  }

  @override
  int get hashCode => Object.hash(
        uid,
        name,
        email,
        role,
        organizationId,
      );
}
