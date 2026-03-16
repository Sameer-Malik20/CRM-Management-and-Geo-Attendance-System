import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return WillPopScope(
      onWillPop: () async {
        await SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("SusaGeo Workspace"),
          elevation: 0.0,
          backgroundColor: appbarcolor,
          centerTitle: true,
        ),
        drawer: Drawer(
          child: NavigationPanel(user: widget.user),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFF7F2EA),
                Color(0xFFEFE8DD),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
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
        gradient: LinearGradient(
          colors: [
            splashScreenColorBottom.withValues(alpha: 0.92),
            appbarcolor.withValues(alpha: 0.94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: dashBoardColor.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
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
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
