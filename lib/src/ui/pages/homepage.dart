import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/models/office.dart';
import 'package:geo_attendance_system/src/services/fetch_offices.dart';
import 'package:geo_attendance_system/src/services/geofencing.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/pages/dashboard.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  final User user;

  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final OfficeDatabase officeDatabase = OfficeDatabase();
  Office? allottedOffice;
  bool _geoFenceLoading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _initializeGeoFence(context));
  }

  Future<void> _initializeGeoFence(BuildContext context) async {
    try {
      final permission = await Permission.location.request();
      if (permission != PermissionStatus.granted) {
        if (!mounted) return;
        setState(() {
          _geoFenceLoading = false;
          _statusMessage =
              "Please allow location permission so site attendance can work correctly.";
        });
        return;
      }

      final office = await officeDatabase.getOfficeBasedOnUID(widget.user.uid);
      await GeoFencing.of(context).service.startGeofencing(office);

      if (!mounted) return;
      setState(() {
        allottedOffice = office;
        _geoFenceLoading = false;
        _statusMessage = "Allocated site synced successfully.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geoFenceLoading = false;
        _statusMessage =
            "Site sync failed. Please check your internet connection and location settings.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "DASHBOARD",
          style: TextStyle(
            fontSize: 24.0,
            fontFamily: "Poppins-Medium",
            fontWeight: FontWeight.w300,
            letterSpacing: 0.6,
          ),
        ),
        elevation: 0.0,
        backgroundColor: dashBoardColor,
        centerTitle: true,
      ),
      drawer: Drawer(
        child: NavigationPanel(user: widget.user),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [splashScreenColorBottom, splashScreenColorTop],
            begin: Alignment.bottomCenter,
            end: Alignment.topRight,
          ),
        ),
        child: Column(
          children: [
            _buildStatusBanner(),
            Expanded(
              child: DashboardMainPanel(user: widget.user),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final message = _statusMessage;
    if (_geoFenceLoading && message == null) {
      return const LinearProgressIndicator(
        minHeight: 3,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        backgroundColor: Colors.transparent,
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(
            allottedOffice != null ? Icons.location_on : Icons.info_outline,
            color: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              allottedOffice != null
                  ? "Site: ${allottedOffice!.name}\n${message ?? "Ready"}"
                  : (message ?? "Dashboard loading..."),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
