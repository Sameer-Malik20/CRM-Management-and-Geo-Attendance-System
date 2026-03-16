import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/authentication.dart';
import 'package:geo_attendance_system/src/services/fetch_user.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/constants/dashboard_tile_info.dart';
import 'package:geo_attendance_system/src/ui/pages/admin_attendance_page.dart';
import 'package:geo_attendance_system/src/ui/pages/admin_console.dart';
import 'package:geo_attendance_system/src/ui/pages/pending_approval_manager.dart';
import 'package:geo_attendance_system/src/ui/pages/profile_page.dart';
import 'package:geo_attendance_system/src/ui/widgets/dashboard_tile.dart';

import 'login.dart';

class Dashboard extends StatefulWidget {
  final AnimationController controller;
  final BaseAuth? auth;
  final User user;

  Dashboard({
    required this.controller,
    this.auth,
    required this.user,
  });

  @override
  _DashboardState createState() => new _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const header_height = 100.0;

  Animation<RelativeRect> getPanelAnimation(BoxConstraints constraints) {
    final height = constraints.biggest.height;
    final backPanelHeight = height - header_height;
    final frontPanelHeight = -header_height;

    return new RelativeRectTween(
            begin: new RelativeRect.fromLTRB(
                0.0, backPanelHeight, 0.0, frontPanelHeight),
            end: new RelativeRect.fromLTRB(0.0, 0.0, 0.0, 0.0))
        .animate(new CurvedAnimation(
            parent: widget.controller, curve: Curves.linear));
  }

  Widget bothPanels(BuildContext context, BoxConstraints constraints) {
    return new Container(
      child: new Stack(
        children: <Widget>[
          new NavigationPanel(
            user: widget.user,
          ),
          new PositionedTransition(
            rect: getPanelAnimation(constraints),
            child: new Material(
              elevation: 12.0,
              borderRadius: new BorderRadius.only(
                  topLeft: new Radius.circular(16.0),
                  topRight: new Radius.circular(16.0)),
              child: new Column(
                children: <Widget>[
                  new Expanded(
                    child: new Center(
                      child: DashboardMainPanel(
                        user: widget.user,
                      ),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return new LayoutBuilder(
      builder: bothPanels,
    );
  }
}

class DashboardMainPanel extends StatelessWidget {
  final User user;

  DashboardMainPanel({required this.user});

  final List tileData = infoAboutTiles;

  List<Widget> _listWidget(BuildContext context) {
    List<Widget> widgets = [];
    tileData.forEach((tile) {
      widgets.add(buildTile(tile[0], tile[1], tile[2], context, user, tile[3]));
    });

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: const [splashScreenColorBottom, splashScreenColorTop],
            begin: Alignment.bottomCenter,
            end: Alignment.topRight,
          ),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16))),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12.0,
          mainAxisSpacing: 12.0,
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          childAspectRatio: 0.72,
          children: _listWidget(context),
        ),
      ),
    );
  }
}

class NavigationPanel extends StatefulWidget {
  final User user;

  NavigationPanel({required this.user});

  @override
  _NavigationPanelState createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<NavigationPanel> {
  final _databaseReference = FirebaseDatabase.instance.reference();

  Future<void> _handleLogout() async {
    Navigator.of(context).pop();
    final auth = Auth();
    await auth.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => Login()),
      (Route<dynamic> route) => false,
    );
  }

  Widget drawerTile(String title, Function() onTap, [IconData? icon]) {
    return ListTile(
      leading: Icon(icon, color: dashBoardColor),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: "Poppins-Medium",
          color: Colors.black87,
          fontSize: 16,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black45),
      onTap: onTap,
    );
  }

  Future<String> fetchOfficeName() async {
    DataSnapshot dataSnapshot =( await _databaseReference
        .child("users")
        .child(widget.user.uid)
        .child("allotted_office")
        .once()).snapshot;
    DataSnapshot snapshot = (await _databaseReference
        .child("location")
        .child(dataSnapshot.value as String)
        .child("name")
        .once()).snapshot;
    return snapshot.value as String;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [dashBoardColor, appbarcolor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FutureBuilder<Map<String, dynamic>>(
                  future: UserDatabase.getProfileData(widget.user.uid),
                  builder: (context, snapshot) {
                    final imageBase64 = snapshot.data?['profileImageBase64'];
                    final imageProvider =
                        imageBase64 is String && imageBase64.isNotEmpty
                            ? MemoryImage(base64Decode(imageBase64))
                            : null;
                    return CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white24,
                      backgroundImage: imageProvider,
                      child: imageProvider == null
                          ? const Icon(Icons.person, color: Colors.white, size: 28)
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<Map<String, dynamic>>(
                  future: UserDatabase.getProfileData(widget.user.uid),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?['Name']?.toString() ??
                          widget.user.email ??
                          "Logged In User",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  widget.user.email ?? "Logged In User",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Text(
                  "Profile, attendance tools, and admin actions",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          FutureBuilder<String>(
            future: fetchOfficeName(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: drawerTile(
                  "Allocated Site: ${snapshot.data}",
                  () {},
                  Icons.location_on,
                ),
              );
            },
          ),
          FutureBuilder<DatabaseEvent>(
            future: _databaseReference
                .child("users")
                .child(widget.user.uid)
                .child("isManager")
                .once(),
            builder: (context, snapshot) {
              final isManager = snapshot.data?.snapshot.value == 1;
              if (!isManager) {
                return const SizedBox.shrink();
              }

              return Column(
                children: [
                  drawerTile("Admin Attendance", () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AdminAttendancePage(
                          currentUser: widget.user,
                        ),
                      ),
                    );
                  }, Icons.camera_enhance),
                  drawerTile("Admin Console", () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AdminConsolePage(
                          currentUser: widget.user,
                        ),
                      ),
                    );
                  }, Icons.admin_panel_settings),
                  drawerTile("Review Pending Leaves", () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => LeaveApprovalByManagerWidget(
                              title: "Review Leaves",
                              user: widget.user,
                            )));
                  }, Icons.assignment_turned_in),
                ],
              );
            },
          ),
          drawerTile("Edit Profile", () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ProfilePage(
                      user: widget.user,
                    )));
          }, Icons.perm_identity),
          drawerTile("Logout", _handleLogout, Icons.exit_to_app),
        ],
      ),
    );
  }
}
