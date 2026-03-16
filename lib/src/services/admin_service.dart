import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:geo_attendance_system/src/models/office.dart';
import 'package:geo_attendance_system/src/services/attendance_mark.dart';
import 'package:geo_attendance_system/src/services/fetch_attendance.dart';
import 'package:http/http.dart' as http;

class AdminUserProfile {
  final String uid;
  final String employeeId;
  final String name;
  final String email;
  final String phoneNumber;
  final String address;
  final String designation;
  final String allottedOffice;
  final String allottedOfficeName;
  final String managerUid;
  final bool isManager;
  final bool isSuperAdmin;
  final bool faceRegistered;
  final String faceEmbeddingJson;

  const AdminUserProfile({
    required this.uid,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.address,
    required this.designation,
    required this.allottedOffice,
    required this.allottedOfficeName,
    required this.managerUid,
    required this.isManager,
    required this.isSuperAdmin,
    required this.faceRegistered,
    required this.faceEmbeddingJson,
  });

  AdminUserProfile copyWith({
    String? uid,
    String? employeeId,
    String? name,
    String? email,
    String? phoneNumber,
    String? address,
    String? designation,
    String? allottedOffice,
    String? allottedOfficeName,
    String? managerUid,
    bool? isManager,
    bool? isSuperAdmin,
    bool? faceRegistered,
    String? faceEmbeddingJson,
  }) {
    return AdminUserProfile(
      uid: uid ?? this.uid,
      employeeId: employeeId ?? this.employeeId,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      designation: designation ?? this.designation,
      allottedOffice: allottedOffice ?? this.allottedOffice,
      allottedOfficeName: allottedOfficeName ?? this.allottedOfficeName,
      managerUid: managerUid ?? this.managerUid,
      isManager: isManager ?? this.isManager,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      faceRegistered: faceRegistered ?? this.faceRegistered,
      faceEmbeddingJson: faceEmbeddingJson ?? this.faceEmbeddingJson,
    );
  }
}

class AdminCreateUserRequest {
  final String employeeId;
  final String name;
  final String email;
  final String password;
  final String phoneNumber;
  final String address;
  final String designation;
  final String allottedOffice;
  final String managerUid;
  final bool isManager;
  final bool isSuperAdmin;

  const AdminCreateUserRequest({
    required this.employeeId,
    required this.name,
    required this.email,
    required this.password,
    required this.phoneNumber,
    required this.address,
    required this.designation,
    required this.allottedOffice,
    required this.managerUid,
    required this.isManager,
    required this.isSuperAdmin,
  });
}

class AdminService {
  static const String _apiKey = 'AIzaSyBJvn4I1Z1Nqf7WjYq2mhF_jhn0rw_dFYA';
  static final DatabaseReference _database =
      FirebaseDatabase.instance.reference();

  String generatedEmailForEmployeeId(String employeeId) {
    final safeId = employeeId.trim().toLowerCase().replaceAll(' ', '');
    return '$safeId@susageo.local';
  }

  Future<List<AdminUserProfile>> fetchUsers() async {
    final usersSnapshot = (await _database.child('users').once()).snapshot;
    final employeeIdSnapshot =
        (await _database.child('EmployeeID').once()).snapshot;
    final officeSnapshot = (await _database.child('location').once()).snapshot;

    final usersMap = _asStringDynamicMap(usersSnapshot.value);
    final employeeEmailMap = _asStringDynamicMap(employeeIdSnapshot.value);
    final locationMap = _asStringDynamicMap(officeSnapshot.value);

    final officeNames = <String, String>{};
    locationMap.forEach((key, value) {
      final site = _asStringDynamicMap(value);
      officeNames[key] = site['name']?.toString() ?? key;
    });

    final result = <AdminUserProfile>[];
    usersMap.forEach((uid, rawValue) {
      final userMap = _asStringDynamicMap(rawValue);
      final employeeId = userMap['UID']?.toString() ??
          userMap['employeeID']?.toString() ??
          '';
      final allottedOffice = userMap['allotted_office']?.toString() ?? '';
      result.add(
        AdminUserProfile(
          uid: uid,
          employeeId: employeeId,
          name: userMap['Name']?.toString() ?? '',
          email: employeeEmailMap[employeeId]?.toString() ??
              userMap['email']?.toString() ??
              '',
          phoneNumber: userMap['PhoneNumber']?.toString() ?? '',
          address: userMap['Address']?.toString() ?? '',
          designation: userMap['designation']?.toString() ?? '',
          allottedOffice: allottedOffice,
          allottedOfficeName: officeNames[allottedOffice] ?? allottedOffice,
          managerUid: userMap['manager']?.toString() ?? '',
          isManager: _parseManagerFlag(userMap['isManager']),
          isSuperAdmin: userMap['isSuperAdmin'] == true,
          faceRegistered: userMap['faceRegistered'] == true,
          faceEmbeddingJson: userMap['faceEmbeddingJson']?.toString() ?? '',
        ),
      );
    });

    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<AdminUserProfile?> getUserByEmployeeId(String employeeId) async {
    final users = await fetchUsers();
    for (final user in users) {
      if (user.employeeId.trim().toLowerCase() ==
          employeeId.trim().toLowerCase()) {
        return user;
      }
    }
    return null;
  }

  Future<List<Office>> fetchSites() async {
    final snapshot = (await _database.child('location').once()).snapshot;
    final rawMap = _asStringDynamicMap(snapshot.value);
    final result = <Office>[];
    rawMap.forEach((key, value) {
      final siteMap = _asStringDynamicMap(value);
      result.add(
        Office(
          key: key,
          name: siteMap['name']?.toString() ?? key,
          latitude: _toDouble(siteMap['latitude']),
          longitude: _toDouble(siteMap['longitude']),
          radius: _toDouble(siteMap['radius'], fallback: 200),
        ),
      );
    });
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> saveSite({
    String? siteKey,
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
  }) async {
    final key = (siteKey == null || siteKey.trim().isEmpty)
        ? _database.child('location').push().key
        : siteKey.trim();
    if (key == null || key.isEmpty) {
      throw Exception('Could not generate a site key.');
    }

    await _database.child('location').child(key).update({
      'name': name.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
    });
  }

  Future<AdminUserProfile> createUser(AdminCreateUserRequest request) async {
    final resolvedEmail = request.email.trim().isEmpty
        ? generatedEmailForEmployeeId(request.employeeId)
        : request.email.trim();
    final signUpResponse = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': resolvedEmail,
        'password': request.password,
        'returnSecureToken': true,
      }),
    );

    final payload = _decodePayload(signUpResponse.body);
    if (signUpResponse.statusCode >= 400) {
      throw Exception(_friendlyAuthError(payload));
    }

    final uid = payload['localId']?.toString();
    if (uid == null || uid.isEmpty) {
      throw Exception('The user was created, but no UID was returned.');
    }

    final managerUid = request.managerUid.trim().isEmpty
        ? (request.isManager ? uid : '')
        : request.managerUid.trim();

    await _database.child('EmployeeID').child(request.employeeId.trim()).set(
          resolvedEmail,
        );

    await _database.child('users').child(uid).set({
      'UID': request.employeeId.trim(),
      'employeeID': request.employeeId.trim(),
      'Name': request.name.trim(),
      'email': resolvedEmail,
      'PhoneNumber': request.phoneNumber.trim(),
      'Address': request.address.trim(),
      'designation': request.designation.trim(),
      'allotted_office': request.allottedOffice,
      'manager': managerUid,
      'isManager': request.isManager ? 1 : 0,
      'isSuperAdmin': request.isSuperAdmin,
      'faceRegistered': false,
      'leaves': {
        'al': 10,
        'cl': 10,
        'ml': 10,
      },
    });

    await _syncManagerState(
      uid: uid,
      name: request.name.trim(),
      designation: request.designation.trim(),
      isManager: request.isManager,
      managerUid: managerUid,
    );

    final sites = await fetchSites();
    final siteName = sites
        .where((site) => site.key == request.allottedOffice)
        .map((site) => site.name)
        .cast<String?>()
        .firstWhere((name) => name != null, orElse: () => request.allottedOffice);

    return AdminUserProfile(
      uid: uid,
      employeeId: request.employeeId.trim(),
      name: request.name.trim(),
      email: resolvedEmail,
      phoneNumber: request.phoneNumber.trim(),
      address: request.address.trim(),
      designation: request.designation.trim(),
      allottedOffice: request.allottedOffice,
      allottedOfficeName: siteName ?? request.allottedOffice,
      managerUid: managerUid,
      isManager: request.isManager,
      isSuperAdmin: request.isSuperAdmin,
      faceRegistered: false,
      faceEmbeddingJson: '',
    );
  }

  Future<void> updateUser({
    required AdminUserProfile profile,
    required String previousEmployeeId,
    required String previousManagerUid,
  }) async {
    final cleanedEmployeeId = profile.employeeId.trim();
    final cleanedEmail = profile.email.trim().isEmpty
        ? generatedEmailForEmployeeId(profile.employeeId)
        : profile.email.trim();
    final cleanedManagerUid = profile.managerUid.trim().isEmpty
        ? (profile.isManager ? profile.uid : '')
        : profile.managerUid.trim();

    if (previousEmployeeId.trim() != cleanedEmployeeId) {
      await _database.child('EmployeeID').child(previousEmployeeId.trim()).remove();
    }
    await _database.child('EmployeeID').child(cleanedEmployeeId).set(cleanedEmail);

    await _database.child('users').child(profile.uid).update({
      'UID': cleanedEmployeeId,
      'employeeID': cleanedEmployeeId,
      'Name': profile.name.trim(),
      'email': cleanedEmail,
      'PhoneNumber': profile.phoneNumber.trim(),
      'Address': profile.address.trim(),
      'designation': profile.designation.trim(),
      'allotted_office': profile.allottedOffice,
      'manager': cleanedManagerUid,
      'isManager': profile.isManager ? 1 : 0,
      'isSuperAdmin': profile.isSuperAdmin,
      'faceRegistered': profile.faceRegistered,
    });

    if (previousManagerUid.trim().isNotEmpty &&
        previousManagerUid.trim() != cleanedManagerUid) {
      await _database
          .child('Managers')
          .child(previousManagerUid.trim())
          .child(profile.uid)
          .remove();
    }

    await _syncManagerState(
      uid: profile.uid,
      name: profile.name.trim(),
      designation: profile.designation.trim(),
      isManager: profile.isManager,
      managerUid: cleanedManagerUid,
    );
  }

  Future<List<AdminManualAttendanceResult>> markManualAttendanceForProfiles({
    required List<AdminUserProfile> profiles,
    required String markType,
  }) async {
    final now = DateTime.now();
    final officeMap = {
      for (final office in await fetchSites()) office.key: office,
    };
    final results = <AdminManualAttendanceResult>[];

    for (final profile in profiles) {
      final office = officeMap[profile.allottedOffice];
      if (office == null) {
        results.add(
          AdminManualAttendanceResult(
            employeeId: profile.employeeId,
            employeeName: profile.name,
            success: false,
            message: 'No allocated site was found.',
          ),
        );
        continue;
      }

      final snapshot = await AttendanceDatabase.getAttendanceOfParticularDateBasedOnUID(
        profile.uid,
        now,
      );
      final attendanceKeys =
          snapshot == null ? <String>[] : List<String>.from((snapshot as Map).keys);

      bool isAllowed;
      String failureMessage = '';
      if (markType == 'in') {
        isAllowed = attendanceKeys.isEmpty || checkSuccessiveIn(attendanceKeys);
        if (!isAllowed) {
          failureMessage = 'Already IN';
        }
      } else {
        isAllowed = attendanceKeys.isNotEmpty && checkSuccessiveOut(attendanceKeys);
        if (!isAllowed) {
          failureMessage = attendanceKeys.isEmpty ? 'No IN found' : 'Already OUT';
        }
      }

      if (!isAllowed) {
        results.add(
          AdminManualAttendanceResult(
            employeeId: profile.employeeId,
            employeeName: profile.name,
            success: false,
            message: failureMessage,
          ),
        );
        continue;
      }

      await AttendanceDatabase.markAttendance(profile.uid, now, office, markType);
      results.add(
        AdminManualAttendanceResult(
          employeeId: profile.employeeId,
          employeeName: profile.name,
          success: true,
          message: '${markType.toUpperCase()} marked at ${getFormattedTime(now)}',
        ),
      );
    }

    return results;
  }

  Future<void> updateFaceRegistrationStatus({
    required String uid,
    required bool registered,
  }) async {
    await _database.child('users').child(uid).update({
      'faceRegistered': registered,
      'faceRegisteredAt': registered ? DateTime.now().toIso8601String() : null,
    });
  }

  Future<void> updateFaceEmbedding({
    required String uid,
    required List<double> embedding,
  }) async {
    await _database.child('users').child(uid).update({
      'faceRegistered': true,
      'faceRegisteredAt': DateTime.now().toIso8601String(),
      'faceEmbeddingJson': jsonEncode(embedding),
      'faceEmbeddingVersion': 'mobilefacenet-v1',
    });
  }

  Future<void> deleteUser(AdminUserProfile profile) async {
    await _database.child('EmployeeID').child(profile.employeeId.trim()).remove();
    await _database.child('users').child(profile.uid).remove();
    await _database.child('Attendance').child(profile.uid).remove();
    await _database.child('leaves').child(profile.uid).remove();
    await _database.child('managers').child(profile.uid).remove();
    await _database.child('Managers').child(profile.uid).remove();

    if (profile.managerUid.trim().isNotEmpty) {
      await _database
          .child('Managers')
          .child(profile.managerUid.trim())
          .child(profile.uid)
          .remove();
    }
  }

  Future<String> exportFullCsv() async {
    final users = await fetchUsers();
    final sites = await fetchSites();
    final attendanceSnapshot =
        (await _database.child('Attendance').once()).snapshot;
    final leavesSnapshot = (await _database.child('leaves').once()).snapshot;

    final attendanceMap = _asStringDynamicMap(attendanceSnapshot.value);
    final leavesMap = _asStringDynamicMap(leavesSnapshot.value);
    final buffer = StringBuffer();

    buffer.writeln('Section,Users');
    _writeCsvRow(buffer, const [
      'uid',
      'employeeId',
      'name',
      'email',
      'phoneNumber',
      'address',
      'designation',
      'allottedOffice',
      'allottedOfficeName',
      'managerUid',
      'isManager',
      'isSuperAdmin',
      'faceRegistered',
    ]);
    for (final user in users) {
      _writeCsvRow(buffer, [
        user.uid,
        user.employeeId,
        user.name,
        user.email,
        user.phoneNumber,
        user.address,
        user.designation,
        user.allottedOffice,
        user.allottedOfficeName,
        user.managerUid,
        user.isManager.toString(),
        user.isSuperAdmin.toString(),
        user.faceRegistered.toString(),
      ]);
    }

    buffer.writeln();
    buffer.writeln('Section,Sites');
    _writeCsvRow(buffer, const [
      'siteKey',
      'name',
      'latitude',
      'longitude',
      'radiusMeters',
    ]);
    for (final site in sites) {
      _writeCsvRow(buffer, [
        site.key,
        site.name,
        site.latitude.toString(),
        site.longitude.toString(),
        site.radius.toStringAsFixed(0),
      ]);
    }

    buffer.writeln();
    buffer.writeln('Section,Attendance');
    _writeCsvRow(buffer, const [
      'userUid',
      'date',
      'entryKey',
      'markType',
      'time',
      'office',
      'latitude',
      'longitude',
    ]);
    attendanceMap.forEach((uid, rawDateMap) {
      final dateMap = _asStringDynamicMap(rawDateMap);
      dateMap.forEach((dateKey, rawEntries) {
        final entries = _asStringDynamicMap(rawEntries);
        entries.forEach((entryKey, rawPayload) {
          final payload = _asStringDynamicMap(rawPayload);
          _writeCsvRow(buffer, [
            uid,
            dateKey,
            entryKey,
            entryKey.split('-').first.toUpperCase(),
            payload['time']?.toString() ?? '',
            payload['office']?.toString() ?? '',
            payload['latitude']?.toString() ?? '',
            payload['longitude']?.toString() ?? '',
          ]);
        });
      });
    });

    buffer.writeln();
    buffer.writeln('Section,Leaves');
    _writeCsvRow(buffer, const [
      'userUid',
      'leaveKey',
      'from',
      'to',
      'leaveType',
      'days',
      'status',
      'withdrawalStatus',
      'reason',
    ]);
    leavesMap.forEach((uid, rawLeaveMap) {
      final leaveMap = _asStringDynamicMap(rawLeaveMap);
      leaveMap.forEach((leaveKey, rawLeave) {
        final leave = _asStringDynamicMap(rawLeave);
        _writeCsvRow(buffer, [
          uid,
          leaveKey,
          leave['fromDate']?.toString() ?? leave['from']?.toString() ?? '',
          leave['toDate']?.toString() ?? leave['to']?.toString() ?? '',
          leave['leaveType']?.toString() ?? '',
          leave['days']?.toString() ?? '',
          leave['status']?.toString() ?? '',
          leave['withdrawalStatus']?.toString() ?? '',
          leave['reason']?.toString() ?? '',
        ]);
      });
    });

    return buffer.toString();
  }

  static void _writeCsvRow(StringBuffer buffer, List<String> values) {
    buffer.writeln(values.map(_escapeCsvCell).join(','));
  }

  static String _escapeCsvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('\r') ||
        escaped.contains('"')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Future<void> _syncManagerState({
    required String uid,
    required String name,
    required String designation,
    required bool isManager,
    required String managerUid,
  }) async {
    if (isManager) {
      await _database.child('managers').child(uid).update({
        'name': name,
        'designation': designation,
      });
      await _database.child('Managers').child(uid).update({});
    } else {
      await _database.child('managers').child(uid).remove();
    }

    if (managerUid.isNotEmpty) {
      await _database.child('Managers').child(managerUid).child(uid).set(1);
    }
  }

  static Map<String, dynamic> _decodePayload(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String _friendlyAuthError(Map<String, dynamic> payload) {
    final rawMessage = payload['error'] is Map<String, dynamic>
        ? payload['error']['message']?.toString() ?? 'UNKNOWN'
        : 'UNKNOWN';

    switch (rawMessage) {
      case 'EMAIL_EXISTS':
        return 'This email is already registered.';
      case 'INVALID_EMAIL':
        return 'The email format is invalid.';
      case 'WEAK_PASSWORD : Password should be at least 6 characters':
      case 'WEAK_PASSWORD':
        return 'Password must be at least 6 characters long.';
      default:
        return 'Could not create the user: $rawMessage';
    }
  }

  static Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(
          key.toString(),
          mapValue,
        ),
      );
    }
    return <String, dynamic>{};
  }

  static bool _parseManagerFlag(dynamic value) {
    if (value == true || value == 1 || value == '1') {
      return true;
    }
    return false;
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class AdminManualAttendanceResult {
  final String employeeId;
  final String employeeName;
  final bool success;
  final String message;

  const AdminManualAttendanceResult({
    required this.employeeId,
    required this.employeeName,
    required this.success,
    required this.message,
  });
}
