import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ProfileService {
  static final DatabaseReference _database =
      FirebaseDatabase.instance.reference();
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phoneNumber,
    required String address,
    required String designation,
  }) async {
    await _database.child('users').child(uid).update({
      'Name': name.trim(),
      'PhoneNumber': phoneNumber.trim(),
      'Address': address.trim(),
      'designation': designation.trim(),
    });
  }

  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No signed in user found.');
    }
    await user.updatePassword(newPassword);
  }

  Future<void> updateProfilePhoto({
    required String uid,
    required File imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    await _database.child('users').child(uid).update({
      'profileImageBase64': base64Encode(bytes),
      'profileImageUpdatedAt': DateTime.now().toIso8601String(),
    });
  }
}
