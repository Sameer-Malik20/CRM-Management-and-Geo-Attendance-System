import 'dart:ui';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:geo_attendance_system/src/services/demo_seed_service.dart';
import 'package:geo_attendance_system/src/services/fetch_IMEI.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/pages/homepage.dart';
import 'package:geo_attendance_system/src/ui/widgets/susa_branding.dart';
import 'package:geo_attendance_system/src/ui/widgets/loader_dialog.dart';

import '../../services/authentication.dart';

class Login extends StatefulWidget {
  Login({this.auth});

  final BaseAuth? auth;

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = new GlobalKey<FormState>();
  FirebaseDatabase db = new FirebaseDatabase();
  late DatabaseReference _empIdRef, _userRef;

  String? _username;
  String? _password;
  String _errorMessage = "";
  late User _user;
  bool formSubmit = false;
  late Auth authObject;

  double scaleWidth(BuildContext context, double value) {
    return MediaQuery.of(context).size.width * (value / 750);
  }

  double scaleHeight(BuildContext context, double value) {
    return MediaQuery.of(context).size.height * (value / 1334);
  }

  double scaleText(BuildContext context, double value) {
    return scaleWidth(context, value).clamp(12.0, 42.0);
  }

  @override
  void initState() {
    super.initState();
    _userRef = db.reference().child("users");
    _empIdRef = db.reference().child('EmployeeID');
    authObject = new Auth();
    _redirectIfAlreadyLoggedIn();
  }

  Future<void> _redirectIfAlreadyLoggedIn() async {
    final currentUser = await authObject.getCurrentUser();
    if (!mounted || currentUser == null) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
      (route) => false,
    );
  }

  bool validateAndSave() {
    final form = _formKey.currentState;
    if (form?.validate() ?? false) {
      form!.save();
      setState(() {
        _errorMessage = "";
      });
      return true;
    }
    return false;
  }

  void validateAndSubmit() async {
    if (validateAndSave()) {
      FocusScope.of(context).unfocus();
      onLoadingDialog(context);
      final username = _username?.trim() ?? '';
      if (username.contains('@')) {
        loginUser(username);
        return;
      }
      try {
        _empIdRef.child(username).once().then((DatabaseEvent event) {
          final snapshot = event.snapshot;
          if (snapshot.value == null) {
            print("popped");
            _errorMessage = "Invalid login details.";
            Navigator.pop(context);
          } else {
            final email = snapshot.value as String;
            loginUser(email);
          }
        });
      } catch (e) {
        print(e);
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Forgot Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter an employee ID or email address. A password reset email will be sent.",
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "Employee ID or Email",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop();
                await _sendPasswordReset(value);
              },
              child: const Text("Send Reset Link"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendPasswordReset(String employeeIdOrEmail) async {
    onLoadingDialog(context);
    try {
      final email = employeeIdOrEmail.contains('@')
          ? employeeIdOrEmail
          : await _lookupEmailFromEmployeeId(employeeIdOrEmail);

      await authObject.sendPasswordResetEmail(email);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("A password reset email has been sent to $email."),
        ),
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? "Password reset failed."),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String> _lookupEmailFromEmployeeId(String employeeId) async {
    final snapshot = (await _empIdRef.child(employeeId).once()).snapshot;
    final value = snapshot.value;
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw Exception("No email mapping was found for this employee ID.");
  }

  Future<void> _showContactAdminSheet() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Contact Admin",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Use the button below to create demo credentials. This will add test super admin, admin, and employee accounts to Firebase Auth and Realtime Database.",
                ),
                const SizedBox(height: 16),
                _credentialCard(
                  title: "Super Admin",
                  loginId: "Email Login",
                  email: DemoSeedService.superAdminCredentials.email,
                  password: DemoSeedService.superAdminCredentials.password,
                ),
                const SizedBox(height: 12),
                _credentialCard(
                  title: "Demo Admin",
                  loginId: DemoSeedService.adminCredentials.employeeId,
                  email: DemoSeedService.adminCredentials.email,
                  password: DemoSeedService.adminCredentials.password,
                ),
                const SizedBox(height: 12),
                _credentialCard(
                  title: "Demo Employee",
                  loginId: DemoSeedService.employeeCredentials.employeeId,
                  email: DemoSeedService.employeeCredentials.email,
                  password: DemoSeedService.employeeCredentials.password,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _seedDemoCredentials();
                    },
                    child: const Text("Create / Refresh Demo Credentials"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _credentialCard({
    required String title,
    required String loginId,
    required String email,
    required String password,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text("Login ID: $loginId"),
          Text("Email: $email"),
          Text("Password: $password"),
        ],
      ),
    );
  }

  Future<void> _seedDemoCredentials() async {
    onLoadingDialog(context);
    try {
      final result = await DemoSeedService.seedDemoData();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Demo users ready. Super Admin: ${result.superAdmin.email} | Admin: ${result.admin.employeeId} | Employee: ${result.employee.employeeId}",
          ),
        ),
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? "Demo credentials could not be created."),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List> checkForSingleSignOn(User _user) async {
    DataSnapshot dataSnapshot =
        (await _userRef.child(_user.uid).once()).snapshot;

    if (dataSnapshot.value != null) {
      var uuid = (dataSnapshot.value as Map)["UUID"];
      List listOfDetails = await getDeviceDetails();

      if (uuid != null) {
        if (listOfDetails[2] == uuid)
          return List.from([true, listOfDetails[2], true]);
        else
          return List.from([false, listOfDetails[2], true]);
      }
      return List.from([true, listOfDetails[2], false]);
    }
    return List.from([false, null, false]);
  }

  void loginUser(String email) async {
    if (_password != null) {
      try {
        _user = await authObject.signIn(email, _password!);

        // checkForSingleSignOn(_user).then((list) {
        //   Navigator.of(context).pop();
        //
        //   // Adding UUID to database
        //   if (list[0] == true && list[2] == false) {
        //     _userRef.child(_user.uid).update({"UUID": list[1]});
        //   }
        //
        //   if (list[0] == true) {
        //     Navigator.pushReplacement(
        //       context,
        //       MaterialPageRoute(builder: (context) => HomePage(user: _user)),
        //     );
        //   } else {
        //     showDialogTemplate(
        //         context,
        //         "ATTENTION!",
        //         "\nUnauthorized Access Detected!\nIf you are a Legit user, Kindly Contact HR Dept for the same",
        //         "assets/gif/no_entry.gif",
        //         Color.fromRGBO(170, 160, 160, 1.0),
        //         "Ok");
        //   }
        // });

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => HomePage(user: _user)),
          (route) => false,
        );
      } catch (e) {
        Navigator.of(context).pop();
        print("Error" + e.toString());
        setState(() {
          _errorMessage = e.toString();
          _formKey.currentState?.reset();
        });
      }
    } else {
      setState(() {
        _errorMessage = "Invalid login details.";
        _formKey.currentState?.reset();
        Navigator.of(context).pop();
      });
    }
  }

  Widget radioButton(bool isSelected) => Container(
        width: 16.0,
        height: 16.0,
        padding: EdgeInsets.all(2.0),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(width: 2.0, color: Colors.black)),
        child: isSelected
            ? Container(
                width: double.infinity,
                height: double.infinity,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: Colors.black),
              )
            : Container(),
      );

  Widget horizontalLine(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Container(
          width: scaleWidth(context, 120),
          height: 1.0,
          color: dashBoardColor.withValues(alpha: 0.14),
        ),
      );

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF5EFE5),
              Color(0xFFE6F0ED),
              Color(0xFFDDE5EF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: <Widget>[
            _backgroundOrb(
              top: -90,
              right: -30,
              size: 220,
              color: leaveCardcolor.withValues(alpha: 0.18),
            ),
            _backgroundOrb(
              top: 180,
              left: -60,
              size: 180,
              color: splashScreenColorBottom.withValues(alpha: 0.16),
            ),
            _backgroundOrb(
              bottom: -60,
              right: 20,
              size: 190,
              color: dashBoardColor.withValues(alpha: 0.10),
            ),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  tween: Tween(begin: 0, end: 1),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 36),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 22),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 28,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: dashBoardColor.withValues(alpha: 0.10),
                                  blurRadius: 30,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              children: <Widget>[
                                SusaGeoBranding(
                                  monogramSize: scaleWidth(context, 168),
                                  titleSize: scaleText(context, 68),
                                  subtitleSize: scaleText(context, 20),
                                ),
                                SizedBox(height: scaleHeight(context, 16)),
                                Text(
                                  "Premium workforce attendance for modern field teams",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: "Bitter",
                                    color: appbarcolor.withValues(alpha: 0.86),
                                    fontSize: scaleText(context, 27),
                                    height: 1.28,
                                  ),
                                ),
                                SizedBox(height: scaleHeight(context, 10)),
                                Text(
                                  "Secure login, geo-fenced attendance, and on-device face verification in one elegant workflow.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: "Poppins-Medium",
                                    color: Colors.black54,
                                    fontSize: scaleText(context, 20),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: scaleHeight(context, 34)),
                      formCard(),
                      SizedBox(height: scaleHeight(context, 26)),
                      SizedBox(
                        width: double.infinity,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [dashBoardColor, splashScreenColorBottom],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: dashBoardColor.withValues(alpha: 0.24),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: validateAndSubmit,
                            child: const Text(
                              "ENTER SusaGeo",
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: "Poppins-Bold",
                                letterSpacing: 0.7,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: scaleHeight(context, 26)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          horizontalLine(context),
                          Text(
                            "More Options",
                            style: TextStyle(
                              fontSize: 15.0,
                              color: dashBoardColor.withValues(alpha: 0.72),
                              fontFamily: "Poppins-Medium",
                            ),
                          ),
                          horizontalLine(context)
                        ],
                      ),
                      SizedBox(height: scaleHeight(context, 24)),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _pillAction(
                            icon: Icons.key_rounded,
                            label: "Forgot Password",
                            onTap: _showForgotPasswordDialog,
                          ),
                          _pillAction(
                            icon: Icons.support_agent,
                            label: "Contact Admin",
                            onTap: _showContactAdminSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget formCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(30.0),
            border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
            boxShadow: [
              BoxShadow(
                color: dashBoardColor.withValues(alpha: 0.10),
                offset: const Offset(0.0, 18.0),
                blurRadius: 28.0,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.60),
                offset: const Offset(0.0, -4.0),
                blurRadius: 12.0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Welcome back",
                    style: TextStyle(
                      fontSize: scaleText(context, 44),
                      fontFamily: "Bitter",
                      color: appbarcolor,
                      letterSpacing: .4,
                    ),
                  ),
                  SizedBox(
                    height: scaleHeight(context, 8),
                  ),
                  Text(
                    "Sign in to continue into your attendance workspace.",
                    style: TextStyle(
                      color: Colors.black54,
                      fontFamily: "Poppins-Medium",
                      fontSize: scaleText(context, 20),
                    ),
                  ),
                  SizedBox(
                    height: scaleHeight(context, 24),
                  ),
                  TextFormField(
                    style: const TextStyle(
                      fontFamily: "Poppins-Medium",
                      color: appbarcolor,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: surfaceAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: dashBoardColor,
                        ),
                      ),
                      labelText: "Login ID",
                      hintText: "Employee ID or Super Admin Email",
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Login ID cannot be empty.'
                        : null,
                    onSaved: (value) => _username = value?.trim(),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    obscureText: true,
                    style: const TextStyle(
                      fontFamily: "Poppins-Medium",
                      color: appbarcolor,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: surfaceAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: dashBoardColor,
                        ),
                      ),
                      labelText: "Password",
                      hintText: "Enter your password",
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Password can\'t be empty'
                        : null,
                    onChanged: (value) => _password = value,
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: dashBoardColor.withValues(alpha: 0.16),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _formKey.currentState?.reset(),
                        child: Text(
                          "Reset",
                          style: TextStyle(
                              color: appbarcolor,
                              fontFamily: "Poppins-Medium",
                              fontSize: scaleText(context, 28)),
                        ),
                      ),
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: Text(
                          "Forgot Password?",
                          style: TextStyle(
                              color: leaveCardcolor,
                              fontFamily: "Poppins-Medium",
                              fontSize: scaleText(context, 28)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dashBoardColor.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: dashBoardColor, size: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: appbarcolor,
                  fontFamily: "Poppins-Medium",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backgroundOrb({
    double? top,
    double? right,
    double? bottom,
    double? left,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
