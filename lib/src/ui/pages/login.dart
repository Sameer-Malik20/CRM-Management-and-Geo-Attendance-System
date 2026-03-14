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

    if (dataSnapshot != null) {
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
          color: Colors.black26.withOpacity(.2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    return new Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: new AssetImage('assets/back.jpg'),
            fit: BoxFit.fill,
          ),
//          gradient: LinearGradient(
//            colors: <Color>[Colors.white, Colors.grey[350]],
//            begin: Alignment.topCenter,
//            end: Alignment.bottomCenter,
//          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            /* Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.only(top: 20.0),
                  child: Image.asset("assets/image_01.png"),
                ),
                Expanded(
                  child: Container(),
                ),
                Image.asset("assets/image_02.png")
              ],
            ),*/
            SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(left: 28.0, right: 28.0, top: 60.0),
                child: Column(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        SusaGeoBranding(
                          monogramSize: scaleWidth(context, 180),
                          titleSize: scaleText(context, 72),
                          subtitleSize: scaleText(context, 20),
                        ),
                        SizedBox(
                          height: scaleHeight(context, 18),
                        ),
                        Text(
                          "Susalabs Geo-Attendance and Workforce System",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: "Poppins-Bold",
                              color: Colors.black54,
                              fontSize: scaleText(context, 25),
                              letterSpacing: 0.2,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: scaleHeight(context, 90),
                    ),
                    formCard(),
                    SizedBox(height: scaleHeight(context, 40)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        /*Row(
                          children: <Widget>[
                            SizedBox(
                              width: 12.0,
                            ),
                            GestureDetector(
                              onTap: _radio,
                              child: radioButton(_isSelected),
                            ),
                            SizedBox(
                              width: 8.0,
                            ),
                            Text("Remember me",
                                style: TextStyle(
                                    fontSize: 12, fontFamily: "Poppins-Medium"))
                          ],
                        ),*/
                        InkWell(
                          child: Container(
                            width: scaleWidth(context, 330),
                            height: scaleHeight(context, 100),
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  splashScreenColorBottom,
                                  Color(0xFF6078ea)
                                ]),
                                borderRadius: BorderRadius.circular(6.0),
                                boxShadow: [
                                  BoxShadow(
                                      color: Color(0xFF6078ea).withOpacity(.3),
                                      offset: Offset(0.0, 8.0),
                                      blurRadius: 8.0)
                                ]),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: validateAndSubmit,
                                child: Center(
                                  child: Text("LOGIN",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: "Poppins-Bold",
                                          fontSize: 18,
                                          letterSpacing: 1.0)),
                                ),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                    SizedBox(
                      height: scaleHeight(context, 40),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        horizontalLine(context),
                        Text("Other Options",
                            style: TextStyle(
                                fontSize: 16.0, fontFamily: "Poppins-Medium")),
                        horizontalLine(context)
                      ],
                    ),
                    SizedBox(
                      height: scaleHeight(context, 40),
                    ),
                    SizedBox(
                      height: scaleHeight(context, 30),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "Need login details? ",
                          style: TextStyle(fontFamily: "Poppins-Medium"),
                        ),
                        InkWell(
                          onTap: _showContactAdminSheet,
                          child: Text("Contact Admin",
                              style: TextStyle(
                                  color: splashScreenColorTop,
                                  fontFamily: "Poppins-Bold")),
                        )
                      ],
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget formCard() {
    return new Container(
      width: double.infinity,
      height: 260,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                offset: Offset(0.0, 15.0),
                blurRadius: 15.0),
            BoxShadow(
                color: Colors.black12,
                offset: Offset(0.0, -10.0),
                blurRadius: 10.0),
          ]),
      child: Padding(
        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Login",
                  style: TextStyle(
                      fontSize: scaleText(context, 45),
                      fontFamily: "Poppins-Bold",
                      letterSpacing: .6)),
              SizedBox(
                height: scaleHeight(context, 30),
              ),
              Container(
                height: 60,
                child: TextFormField(
                  decoration: InputDecoration(
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: dashBoardColor),
                      ),
                      icon: Icon(
                        Icons.person,
                        color: dashBoardColor,
                      ),
                      hintText: "Employee ID or Super Admin Email",
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 15.0)),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Login ID cannot be empty.'
                      : null,
                  onSaved: (value) => _username = value?.trim(),
                ),
              ),
              Container(
                height: 60,
                child: TextFormField(
                  obscureText: true,
                  decoration: InputDecoration(
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: dashBoardColor),
                      ),
                      icon: Icon(
                        Icons.lock,
                        color: dashBoardColor,
                      ),
                      hintText: "Password",
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 15.0)),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Password can\'t be empty'
                      : null,
                  onChanged: (value) => _password = value,
                ),
              ),
              Text(
                _errorMessage,
                style: TextStyle(color: Colors.red),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    style: ButtonStyle(
                      padding: MaterialStateProperty.resolveWith(
                        (states) => EdgeInsets.symmetric(horizontal: 16.0),
                      ),
                      shape: MaterialStateProperty.resolveWith(
                        (states) => const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(2.0)),
                        ),
                      ),
                      backgroundColor: MaterialStateProperty.resolveWith(
                        (states) => Colors.blue,
                      ),
                    ),
                    onPressed: () => _formKey.currentState?.reset(),
                    child: Text(
                      "Reset",
                      style: TextStyle(
                          color: dashBoardColor,
                          fontFamily: "Poppins-Medium",
                          fontSize: scaleText(context, 28)),
                    ),
                  ),
                  TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: Text(
                      "Forgot Password?",
                      style: TextStyle(
                          color: splashScreenColorTop,
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
    );
  }
}
