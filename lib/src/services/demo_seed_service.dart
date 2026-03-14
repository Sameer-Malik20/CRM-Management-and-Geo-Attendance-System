import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class DemoAccountCredentials {
  final String employeeId;
  final String email;
  final String password;
  final String name;

  const DemoAccountCredentials({
    required this.employeeId,
    required this.email,
    required this.password,
    required this.name,
  });
}

class DemoSeedResult {
  final DemoAccountCredentials superAdmin;
  final DemoAccountCredentials admin;
  final DemoAccountCredentials employee;

  const DemoSeedResult({
    required this.superAdmin,
    required this.admin,
    required this.employee,
  });
}

class DemoSeedService {
  static const DemoAccountCredentials superAdminCredentials =
      DemoAccountCredentials(
    employeeId: 'SA1001',
    email: 'superadmin@susageo.com',
    password: 'Susa@12345',
    name: 'SusaGeo Super Admin',
  );

  static const DemoAccountCredentials adminCredentials = DemoAccountCredentials(
    employeeId: 'ADM1001',
    email: 'admin.demo@crmapp.test',
    password: 'Admin@12345',
    name: 'Demo Admin',
  );

  static const DemoAccountCredentials employeeCredentials =
      DemoAccountCredentials(
    employeeId: 'EMP1001',
    email: 'worker.demo@crmapp.test',
    password: 'Employee@12345',
    name: 'Demo Worker',
  );

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final DatabaseReference _database =
      FirebaseDatabase.instance.reference();

  static Future<DemoSeedResult> seedDemoData() async {
    const officeKey = 'office_demo';

    await _database.child('location').child(officeKey).update({
      'name': 'Demo Construction Site',
      'latitude': 28.6139,
      'longitude': 77.2090,
      'radius': 200,
    });

    final superAdminUid = await _ensureUser(
      credentials: superAdminCredentials,
      officeKey: officeKey,
      designation: 'Super Admin',
      isManager: true,
      managerKey: superAdminCredentials.employeeId,
      isSuperAdmin: true,
    );

    await _database.child('managers').child(superAdminUid).update({
      'name': superAdminCredentials.name,
      'designation': 'Super Admin',
    });

    final adminUid = await _ensureUser(
      credentials: adminCredentials,
      officeKey: officeKey,
      designation: 'Site Admin',
      isManager: true,
      managerKey: superAdminUid,
      isSuperAdmin: false,
    );

    await _database.child('managers').child(adminUid).update({
      'name': adminCredentials.name,
      'designation': 'Site Admin',
    });

    final employeeUid = await _ensureUser(
      credentials: employeeCredentials,
      officeKey: officeKey,
      designation: 'Construction Worker',
      isManager: false,
      managerKey: adminUid,
      isSuperAdmin: false,
    );

    await _database.child('Managers').child(superAdminUid).set({
      superAdminUid: 1,
      adminUid: 1,
      employeeUid: 1,
    });

    await _database.child('Managers').child(adminUid).set({
      adminUid: 1,
      employeeUid: 1,
    });

    await _database.child('users').child(superAdminUid).update({
      'manager': superAdminUid,
    });

    await _database.child('users').child(adminUid).update({
      'manager': superAdminUid,
    });

    await _auth.signOut();

    return const DemoSeedResult(
      superAdmin: superAdminCredentials,
      admin: adminCredentials,
      employee: employeeCredentials,
    );
  }

  static Future<String> _ensureUser({
    required DemoAccountCredentials credentials,
    required String officeKey,
    required String designation,
    required bool isManager,
    required String managerKey,
    required bool isSuperAdmin,
  }) async {
    final uid = await _ensureAuthUser(
      email: credentials.email,
      password: credentials.password,
    );

    await _database.child('EmployeeID').child(credentials.employeeId).set(
          credentials.email,
        );

    await _database.child('users').child(uid).update({
      'UID': credentials.employeeId,
      'employeeID': credentials.employeeId,
      'Name': credentials.name,
      'PhoneNumber': isManager ? '9999999999' : '8888888888',
      'Address': isManager
          ? 'Demo Admin Office, Construction HQ'
          : 'Demo Worker Camp, Construction Site',
      'designation': designation,
      'allotted_office': officeKey,
      'manager': managerKey,
      'isManager': isManager ? 1 : 0,
      'isSuperAdmin': isSuperAdmin,
      'leaves': {
        'al': 10,
        'cl': 10,
        'ml': 10,
      },
    });

    return uid;
  }

  static Future<String> _ensureAuthUser({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') {
        rethrow;
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user!.uid;
    }
  }
}
