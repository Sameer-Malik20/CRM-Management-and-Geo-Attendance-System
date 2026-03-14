import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:geo_attendance_system/src/models/user.dart';
import 'package:geo_attendance_system/src/services/fetch_user.dart';
import 'package:geo_attendance_system/src/services/on_device_face_recognition_service.dart';
import 'package:geo_attendance_system/src/services/profile_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/pages/face_capture_page.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_engine_status_banner.dart';
import 'package:image_picker/image_picker.dart';

enum AppBarBehavior { normal, pinned, floating, snapping }

class ProfilePageWidget extends StatelessWidget {
  const ProfilePageWidget({
    super.key,
    required this.icon,
    required this.children,
  });

  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeData.dividerColor)),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.headlineMedium!,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                width: 72.0,
                child: Icon(icon, color: themeData.primaryColor),
              ),
              Expanded(child: Column(children: children)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.icon,
    required this.lines,
    required this.onPressed,
  }) : assert(lines.length > 1);

  final IconData icon;
  final List<String> lines;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ...lines
                      .sublist(0, lines.length - 1)
                      .map<Widget>((String line) => Text(line)),
                  Text(lines.last, style: themeData.textTheme.bodySmall),
                ],
              ),
            ),
            SizedBox(
              width: 72.0,
              child: IconButton(
                icon: Icon(icon),
                color: themeData.primaryColor,
                onPressed: onPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.user});

  final User user;

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  static final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();
  final double _appBarHeight = 270.0;
  final ProfileService _profileService = ProfileService();
  final ImagePicker _imagePicker = ImagePicker();
  AppBarBehavior _appBarBehavior = AppBarBehavior.pinned;
  Employee? employee;
  Map<String, dynamic>? _profileData;
  bool _savingPhoto = false;
  FaceEngineStatusInfo _engineInfo = const FaceEngineStatusInfo(
    state: FaceEngineState.loading,
    message: 'Loading on-device face recognition...',
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadFaceEngineStatus();
  }

  Future<void> _loadProfile() async {
    final loadedEmployee =
        await UserDatabase.getDetailsFromUID(widget.user.uid);
    final loadedProfile = await UserDatabase.getProfileData(widget.user.uid);
    if (!mounted) return;
    setState(() {
      employee = loadedEmployee;
      _profileData = loadedProfile;
    });
  }

  Future<void> _openFaceRegistration() async {
    if (employee == null) return;

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => FaceCapturePage(
          title: "Register Face Selfie",
          actionLabel: _isFaceRegistered
              ? "Capture & Update Face"
              : "Capture & Register Face",
          employeeId: employee!.employeeID,
          employeeName: employee!.firstName,
          mode: FaceCaptureMode.register,
          userUid: widget.user.uid,
        ),
      ),
    );

    if (updated == true) {
      await _loadProfile();
    }
  }

  Future<void> _openEditProfileSheet() async {
    if (_profileData == null) return;
    final nameController =
        TextEditingController(text: _profileData?['Name']?.toString() ?? '');
    final phoneController = TextEditingController(
      text: _profileData?['PhoneNumber']?.toString() ?? '',
    );
    final addressController =
        TextEditingController(text: _profileData?['Address']?.toString() ?? '');
    final designationController = TextEditingController(
      text: _profileData?['designation']?.toString() ?? '',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Edit Profile",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _inputField(nameController, "Full Name"),
              _inputField(phoneController, "Phone Number"),
              _inputField(addressController, "Address", maxLines: 2),
              _inputField(designationController, "Designation"),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: splashScreenColorTop,
                  ),
                  onPressed: () async {
                    await _profileService.updateProfile(
                      uid: widget.user.uid,
                      name: nameController.text,
                      phoneNumber: phoneController.text,
                      address: addressController.text,
                      designation: designationController.text,
                    );
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    await _loadProfile();
                    _showSnackBar("Profile updated successfully.");
                  },
                  child: const Text("Save Profile"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPasswordDialog() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Change Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "New Password"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: "Confirm Password"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text.trim();
                final confirm = confirmController.text.trim();
                if (password.length < 6) {
                  _showSnackBar("Password must be at least 6 characters.");
                  return;
                }
                if (password != confirm) {
                  _showSnackBar("Passwords do not match.");
                  return;
                }
                try {
                  await _profileService.updatePassword(password);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  _showSnackBar("Password updated successfully.");
                } catch (error) {
                  _showSnackBar(
                      error.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text("Update Password"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPhotoPickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Take Photo"),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickProfilePhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Choose From Gallery"),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickProfilePhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 60,
      maxWidth: 600,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _savingPhoto = true;
    });

    try {
      await _profileService.updateProfilePhoto(
        uid: widget.user.uid,
        imageFile: File(picked.path),
      );
      await _loadProfile();
      _showSnackBar("Profile photo updated.");
    } finally {
      if (mounted) {
        setState(() {
          _savingPhoto = false;
        });
      }
    }
  }

  Future<void> _loadFaceEngineStatus() async {
    final info = await OnDeviceFaceRecognitionService.instance.initialize();
    if (!mounted) return;
    setState(() {
      _engineInfo = info;
    });
  }

  Widget _inputField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.blueGrey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _isFaceRegistered => _profileData?['faceRegistered'] == true;

  MemoryImage? get _profileImage {
    final base64Image = _profileData?['profileImageBase64'];
    if (base64Image is String && base64Image.isNotEmpty) {
      return MemoryImage(base64Decode(base64Image));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primaryColor: splashScreenColorTop,
        brightness: Brightness.light,
        platform: Theme.of(context).platform,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        body: employee == null
            ? Container(
                color: dashBoardColor,
                child: const Center(
                  child: SpinKitChasingDots(
                    color: Colors.white,
                    size: 30.0,
                  ),
                ),
              )
            : CustomScrollView(
                slivers: <Widget>[
                  SliverAppBar(
                    expandedHeight: _appBarHeight,
                    pinned: _appBarBehavior == AppBarBehavior.pinned,
                    actions: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: TextButton(
                          style: ButtonStyle(
                            padding: WidgetStateProperty.resolveWith(
                              (states) =>
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => Colors.blue,
                            ),
                          ),
                          onPressed: _openPasswordDialog,
                          child: const Text(
                            "CHANGE PASSWORD",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      title: Container(
                        decoration: BoxDecoration(
                          color: Colors.deepOrangeAccent.withValues(alpha: 0.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.white30, blurRadius: 10),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 10,
                          ),
                          child: Text(
                            "${employee?.firstName} - ${employee?.employeeID}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      background: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image.asset(
                            'assets/logo/profile.jpg',
                            fit: BoxFit.cover,
                            height: _appBarHeight,
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(0.0, -1.0),
                                end: Alignment(0.0, -0.4),
                                colors: <Color>[
                                  Color(0x60000000),
                                  Color(0x00000000)
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: 20,
                            bottom: 70,
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.white,
                                      backgroundImage: _profileImage,
                                      child: _profileImage == null
                                          ? const Icon(
                                              Icons.person,
                                              size: 40,
                                              color: splashScreenColorTop,
                                            )
                                          : null,
                                    ),
                                    if (_savingPhoto)
                                      const Positioned.fill(
                                        child: CircularProgressIndicator(),
                                      ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _savingPhoto
                                      ? null
                                      : _showPhotoPickerSheet,
                                  icon: const Icon(Icons.add_a_photo,
                                      color: Colors.white),
                                  label: const Text(
                                    "Upload Photo",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildListDelegate(<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: splashScreenColorTop,
                            ),
                            onPressed: _openEditProfileSheet,
                            icon: const Icon(Icons.edit),
                            label: const Text("Edit Profile"),
                          ),
                        ),
                      ),
                      AnnotatedRegion<SystemUiOverlayStyle>(
                        value: SystemUiOverlayStyle.dark,
                        child: ProfilePageWidget(
                          icon: Icons.call,
                          children: <Widget>[
                            _ContactItem(
                              icon: Icons.call,
                              onPressed: () {},
                              lines: <String>[
                                employee?.contactNumber ?? '',
                                'Phone Number',
                              ],
                            ),
                          ],
                        ),
                      ),
                      ProfilePageWidget(
                        icon: Icons.contact_mail,
                        children: <Widget>[
                          _ContactItem(
                            icon: Icons.email,
                            onPressed: () {},
                            lines: <String>[
                              widget.user.email ?? '',
                              'Email',
                            ],
                          ),
                        ],
                      ),
                      ProfilePageWidget(
                        icon: Icons.location_on,
                        children: <Widget>[
                          _ContactItem(
                            icon: Icons.map,
                            onPressed: () {},
                            lines: <String>[
                              employee?.residentialAddress ?? '',
                              'Address',
                            ],
                          ),
                        ],
                      ),
                      if (employee?.designation != null)
                        ProfilePageWidget(
                          icon: Icons.description,
                          children: <Widget>[
                            _ContactItem(
                              icon: Icons.work,
                              onPressed: () {},
                              lines: <String>[
                                employee!.designation,
                                'Designation',
                              ],
                            ),
                          ],
                        ),
                      ProfilePageWidget(
                        icon: Icons.camera_alt,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  "Selfie Attendance",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FaceEngineStatusBanner(
                                  info: _engineInfo,
                                  margin: const EdgeInsets.only(bottom: 12),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _isFaceRegistered
                                        ? Colors.green.shade50
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _isFaceRegistered
                                          ? Colors.green.shade300
                                          : Colors.orange.shade300,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _isFaceRegistered
                                              ? Icons.verified_user
                                              : Icons.face_retouching_natural,
                                          color: _isFaceRegistered
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _isFaceRegistered
                                              ? "Face registration completed successfully"
                                              : "Face registration is pending",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: _isFaceRegistered
                                                ? Colors.green.shade800
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _isFaceRegistered
                                              ? "You can now verify your selfie on-device automatically before marking attendance. Use this section any time to update your registered face."
                                              : "Register your face here before using automatic on-device selfie attendance.",
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        if (_profileData?['faceRegisteredAt'] !=
                                            null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                              "Registered at: ${_profileData?['faceRegisteredAt']}",
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: splashScreenColorTop,
                                  ),
                                  onPressed: _openFaceRegistration,
                                  icon: const Icon(Icons.camera_alt),
                                  label: Text(
                                    _isFaceRegistered
                                        ? "Update Face"
                                        : "Register Face",
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }
}
