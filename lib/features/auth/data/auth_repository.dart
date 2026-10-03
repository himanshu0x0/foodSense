import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';

/// Repository responsible for FoodSense authentication and the minimal
/// authenticated-user profile stored in Firestore.
///
/// Phase 1 responsibilities:
/// - Register a user with Firebase Authentication.
/// - Create the corresponding user profile in Firestore.
/// - Sign in and sign out.
/// - Listen to authentication-state changes.
/// - Send password-reset emails.
///
/// Organization-specific data is handled separately by the organization
/// feature in Phase 1.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Returns the currently authenticated Firebase user, if any.
  User? get currentUser => _auth.currentUser;

  /// Emits the current Firebase authentication state and subsequent changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Registers a new FoodSense user.
  ///
  /// The Firebase Authentication account is created first. A minimal
  /// user profile is then stored in Firestore under `users/{uid}`.
  ///
  /// If the Firestore profile write fails after the auth account is created,
  /// the Firebase account is deleted to avoid leaving a partial registration.
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    String role = 'kitchen_manager',
    String organizationId = '',
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();
    final String normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw ArgumentError('Name cannot be empty.');
    }

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    if (password.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }

    UserCredential credential;

    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }

    final User? firebaseUser = credential.user;

    if (firebaseUser == null) {
      throw StateError('Firebase did not return a user after registration.');
    }

    final UserModel userModel = UserModel(
      uid: firebaseUser.uid,
      name: normalizedName,
      email: firebaseUser.email ?? normalizedEmail,
      role: role,
      organizationId: organizationId,
    );

    try {
      await _usersCollection
          .doc(firebaseUser.uid)
          .set(userModel.toMap(), SetOptions(merge: true));

      return userModel;
    } catch (_) {
      // Keep authentication and profile data consistent when possible.
      try {
        await firebaseUser.delete();
      } catch (_) {
        // The original Firestore error is more useful to the caller.
      }
      rethrow;
    }
  }

  /// Signs an existing user in with email and password.
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty.');
    }

    final UserCredential credential = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final User? firebaseUser = credential.user;

    if (firebaseUser == null) {
      throw StateError('Firebase did not return a user after sign-in.');
    }

    final UserModel? existingProfile = await getUserProfile(firebaseUser.uid);

    if (existingProfile != null) {
      return existingProfile;
    }

    // Handles users that were authenticated successfully but whose profile
    // document does not exist yet.
    final UserModel fallbackProfile = UserModel(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName ?? '',
      email: firebaseUser.email ?? normalizedEmail,
      role: 'kitchen_manager',
      organizationId: '',
    );

    await _usersCollection
        .doc(firebaseUser.uid)
        .set(fallbackProfile.toMap(), SetOptions(merge: true));

    return fallbackProfile;
  }

  /// Signs the current user out.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Sends a Firebase password-reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    final String normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email cannot be empty.');
    }

    await _auth.sendPasswordResetEmail(email: normalizedEmail);
  }

  /// Fetches the FoodSense profile for a Firebase UID.
  Future<UserModel?> getUserProfile(String uid) async {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _usersCollection.doc(normalizedUid).get();

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return null;
    }

    return UserModel.fromMap(data);
  }

  /// Updates the minimal FoodSense user profile.
  Future<void> updateUserProfile(UserModel user) async {
    await _usersCollection
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true));
  }
}
