import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geo_attendance_system/src/models/user.dart';

class UserDatabase {
  static final _databaseReference = FirebaseDatabase.instance.reference();
  static final UserDatabase _instance = UserDatabase._internal();

  factory UserDatabase() {
    return _instance;
  }

  UserDatabase._internal();

  static Future<Employee> getDetailsFromUID(String uid) async {
    final profile = await getProfileData(uid);
    return Employee(
        employeeID: profile["UID"].toString(),
        firstName: profile["Name"],
        contactNumber: profile["PhoneNumber"].toString(),
        residentialAddress: profile["Address"],
        designation: profile["designation"]);
  }

  static Future<Map<String, dynamic>> getProfileData(String uid) async {
    DataSnapshot dataSnapshot =
        (await _databaseReference.child("users").child(uid).once()).snapshot;
    final profile = dataSnapshot.value;
    if (profile is Map) {
      return Map<String, dynamic>.from(profile);
    }
    throw StateError("User profile not found for uid: $uid");
  }
}
