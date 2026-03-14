import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_attendance_system/src/models/user.dart' show Employee;
import 'package:geo_attendance_system/src/models/office.dart';
import 'package:geo_attendance_system/src/services/attendance_mark.dart';
import 'package:geo_attendance_system/src/services/fetch_attendance.dart';
import 'package:geo_attendance_system/src/services/fetch_offices.dart';
import 'package:geo_attendance_system/src/services/fetch_user.dart';
import 'package:geo_attendance_system/src/services/geofencing.dart';
import 'package:geo_attendance_system/src/services/on_device_face_recognition_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/pages/face_capture_page.dart';
import 'package:geo_attendance_system/src/ui/widgets/attendance_Marker_buttons.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_engine_status_banner.dart';
import 'package:geo_attendance_system/src/ui/widgets/loader_dialog.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class AttendanceRecorderWidget extends StatefulWidget {
  final User user;

  AttendanceRecorderWidget({required this.user});

  @override
  AttendanceRecorderWidgetState createState() =>
      AttendanceRecorderWidgetState();
}

class AttendanceRecorderWidgetState extends State<AttendanceRecorderWidget> {
  Completer<GoogleMapController> _controller = Completer();

  double zoomVal = 5.0;
  OfficeDatabase officeDatabase = new OfficeDatabase();

  // ignore: unused_field
  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _currentLocation;
  LatLng previousLocation = LatLng(0, 0);
  Set<Marker> _markers = {};
  Set<Circle> _circles = new Set();

  Location _locationService = new Location();
  PermissionStatus? _permission;
  String? error;
  late CameraPosition _currentCameraPosition;
  var rMin;
  var rMax;
  var direction = 1;
  var _radius;
  GeoFencingService? geoFencingService;
  GeofenceStatus geofenceStatus = GeofenceStatus.init;
  Employee? _employee;
  Office? _allottedOffice;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _todayAttendanceMap;
  bool _isMarkingAttendance = false;
  bool _isPanelExpanded = true;
  FaceEngineStatusInfo _engineInfo = const FaceEngineStatusInfo(
    state: FaceEngineState.loading,
    message: 'Loading on-device face recognition...',
  );

  @override
  void initState() {
    super.initState();
    initPlatformState();
    _loadEmployeeData();
    _loadTodayAttendance();
    _loadFaceEngineStatus();

    Future.microtask(() {
      geoFencingService = GeoFencing.of(context).service
        ..addListener(onGeofenceStatusUpdate);
    });
  }

  @override
  void dispose() async {
    super.dispose();
    _locationSubscription?.cancel();
    geoFencingService?.removeListener(onGeofenceStatusUpdate);
  }

  Future<void> _loadFaceEngineStatus() async {
    final info = await OnDeviceFaceRecognitionService.instance.initialize();
    if (!mounted) return;
    setState(() {
      _engineInfo = info;
    });
  }

  Future<void> _loadEmployeeData() async {
    final employee = await UserDatabase.getDetailsFromUID(widget.user.uid);
    final profileData = await UserDatabase.getProfileData(widget.user.uid);
    final office = await officeDatabase.getOfficeBasedOnUID(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _employee = employee;
      _allottedOffice = office;
      _profileData = profileData;
    });
  }

  Future<void> _loadTodayAttendance() async {
    final snapshot =
        await AttendanceDatabase.getAttendanceOfParticularDateBasedOnUID(
      widget.user.uid,
      DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _todayAttendanceMap = snapshot == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(snapshot as Map);
    });
  }

  void onGeofenceStatusUpdate() {
    if (mounted) {
      setState(() {
        geofenceStatus =
            geoFencingService?.geofenceStatus ?? GeofenceStatus.init;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        automaticallyImplyLeading: false,
        leading: new IconButton(
          icon: new Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        //shape: RoundedRectangleBorder(
        // borderRadius: BorderRadius.circular(20.0),
        //  ),
        title: Text(
          "Mark your Attendance",
          style: TextStyle(
              color: Colors.white,
              fontFamily: "Poppins-Medium",
              fontSize: 22,
              letterSpacing: .6,
              fontWeight: FontWeight.bold),
        ),
        elevation: 0.8,
        centerTitle: true,
        bottomOpacity: 0,
      ),
      body: Stack(
        children: <Widget>[
          googleMap(context),
          buildAttendanceActionPanel(context),
        ],
      ),
    );
  }

  Widget googleMap(BuildContext context) {
    double _initialLat = 30.677515;
    double _initialLong = 76.743902;
    double _initialZoom = 15;
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: GoogleMap(
        mapType: MapType.normal,
        myLocationEnabled: true,
        circles: _circles,
        onTap: (_) => _setPanelExpanded(false),
        initialCameraPosition: CameraPosition(
            target: LatLng(_initialLat, _initialLong), zoom: _initialZoom),
        markers: _markers,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
          officeDatabase.getOfficeBasedOnUID(widget.user.uid).then((office) {
            if (mounted) {
              setState(() {
                rMax = office.radius;
                rMin = 3 * office.radius / 5;
                _radius = office.radius;
                Timer.periodic(new Duration(milliseconds: 100), (timer) {
                  var radius =
                      _circles.isEmpty ? office.radius : _circles.first.radius;

                  if ((radius > rMax) || (radius < rMin)) {
                    direction *= -1;
                  }
                  var _par = (radius / _radius) - 0.2;
                  var radiusFinal = radius + direction * 10;
                  if (!mounted) {
                    timer.cancel();
                    return;
                  }
                  setState(() {
                    _circles.clear();
                    _circles.add(Circle(
                      circleId: CircleId("GeoFenceCircle"),
                      center: LatLng(office.latitude, office.longitude),
                      radius: radiusFinal,
                      strokeColor: Colors.blueGrey,
                      strokeWidth: 5,
                      fillColor: Colors.blueGrey.withValues(alpha: 0.6 * _par),
                    ));
                  });
//            circleOption.fillOpacity = 0.6 * _par;

//                circle.setOptions(circleOption);
                });
              });
            }
          });
        },
      ),
    );
  }

  Widget buildAttendanceActionPanel(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedPanelMaxHeight = math.min(screenHeight * 0.5, 420.0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: GestureDetector(
          onTap: () {
            if (!_isPanelExpanded) {
              _setPanelExpanded(true);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: _isPanelExpanded ? expandedPanelMaxHeight : 92,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _isPanelExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: _buildExpandedAttendancePanel(
                context,
                expandedPanelMaxHeight,
              ),
              secondChild: _buildCollapsedAttendancePanel(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedAttendancePanel(
    BuildContext context,
    double expandedPanelMaxHeight,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: expandedPanelMaxHeight - 32,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 54,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Selfie Attendance Required",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isFaceRegistered
                  ? "Step 1: Your selfie will be verified automatically. Step 2: Only then will IN or OUT be marked."
                  : "Please register your face from Profile before using selfie attendance.",
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            FaceEngineStatusBanner(
              info: _engineInfo,
              margin: const EdgeInsets.only(bottom: 10),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  icon: Icons.location_on,
                  label: _locationStatusLabel,
                  color: _currentLocation == null ? Colors.orange : Colors.green,
                ),
                _statusChip(
                  icon: Icons.verified_user,
                  label: _isFaceRegistered ? "Face Registered" : "Face Pending",
                  color: _isFaceRegistered ? Colors.green : Colors.orange,
                ),
                _statusChip(
                  icon: Icons.radar,
                  label: _geofenceLabel,
                  color: _geofenceColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: inOutButton(
                    "SELFIE IN",
                    Colors.green,
                    _callMarkInFunction,
                    context: context,
                    enabled: _canMarkIn,
                    disabledMessage: _markInDisabledMessage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: inOutButton(
                    "SELFIE OUT",
                    Colors.orangeAccent,
                    _callMarkOutFunction,
                    context: context,
                    enabled: _canMarkOut,
                    disabledMessage: _markOutDisabledMessage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildTodayAttendanceCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedAttendancePanel(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: splashScreenColorTop.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              const Icon(Icons.keyboard_arrow_up, color: splashScreenColorTop),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Attendance Recorder",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _todayFirstInTime.isEmpty && _todayLastOutTime.isEmpty
                    ? "Tap to expand and mark attendance"
                    : "IN: ${_todayFirstInTime.isEmpty ? "--" : _todayFirstInTime} | OUT: ${_todayLastOutTime.isEmpty ? "--" : _todayLastOutTime}",
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTodayAttendanceCard() {
    final entries = _todayTimelineEntries;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Attendance",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  "First IN",
                  _todayFirstInTime.isEmpty ? "--" : _todayFirstInTime,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  "Last OUT",
                  _todayLastOutTime.isEmpty ? "--" : _todayLastOutTime,
                  Colors.orangeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              "No attendance has been marked today yet.",
              style: TextStyle(color: Colors.black54),
            )
          else
            Column(
              children: entries
                  .map(
                    (entry) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            entry.startsWith('IN') ? Icons.login : Icons.logout,
                            color: entry.startsWith('IN')
                                ? Colors.green
                                : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(entry)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _callMarkInFunction() {
    _startSelfieAttendanceFlow("in");
  }

  void _callMarkOutFunction() {
    _startSelfieAttendanceFlow("out");
  }

  initPlatformState() async {
    await _locationService.changeSettings(
        accuracy: LocationAccuracy.balanced, interval: 1000);

    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      bool serviceStatus = await _locationService.serviceEnabled();
      print("Service status: $serviceStatus");
      if (serviceStatus) {
        _permission = await _locationService.requestPermission();
        print("Permission: $_permission");
        if (_permission == PermissionStatus.granted) {
          await _locationService.getLocation();

          _locationSubscription = _locationService.onLocationChanged
              .listen((LocationData result) async {
            final newLocation = LatLng(
              result.latitude ?? 0,
              result.longitude ?? 0,
            );
            if (previousLocation != newLocation) {
              previousLocation = newLocation;
              _currentCameraPosition = CameraPosition(
                target: newLocation,
                zoom: 16,
                tilt: 50.0,
                bearing: 45.0,
              );

              final GoogleMapController controller = await _controller.future;
              controller.animateCamera(
                CameraUpdate.newCameraPosition(
                  _currentCameraPosition,
                ),
              );
              if (mounted) {
                setState(() {
                  _currentLocation = result;
                  _markers.clear();
                  _markers.add(
                    Marker(
                      markerId: MarkerId("Current Location"),
                      position: newLocation,
                    ),
                  );
                });
              }
            }
          });
        }
      } else {
        bool serviceStatusResult = await _locationService.requestService();
        print("Service status activated after request: $serviceStatusResult");
        if (serviceStatusResult) {
          initPlatformState();
        }
      }
    } on PlatformException catch (e) {
      print(e);
      if (e.code == 'PERMISSION_DENIED') {
        error = e.message;
      } else if (e.code == 'SERVICE_STATUS_ERROR') {
        error = e.message;
      }
    }
  }

  Future<void> _startSelfieAttendanceFlow(String markType) async {
    if (_isMarkingAttendance) {
      return;
    }

    if (!_isFaceRegistered) {
      _showRetryDialog(
        "Please register your face from Profile before marking selfie attendance.",
      );
      return;
    }

    if (markType == "in" && _isCurrentlyIn) {
      _showRetryDialog("You are already IN.");
      return;
    }

    if (markType == "out" && !_hasOpenInEntry) {
      _showRetryDialog(
        _todayAttendanceKeys.isEmpty
            ? "Please mark IN first before marking OUT."
            : "You are already OUT.",
      );
      return;
    }

    if (_currentLocation == null) {
      _showRetryDialog("Current location is still loading. Please try again.");
      return;
    }

    if (_employee == null) {
      _showRetryDialog("Employee profile is still loading. Please try again.");
      return;
    }

    final office = await officeDatabase.getOfficeBasedOnUID(widget.user.uid);
    final effectiveStatus =
        GeoFencingService.resolveStatus(office, _currentLocation);

    if (effectiveStatus == GeofenceStatus.init) {
      _showRetryDialog(
          "Location and site validation are still syncing. Please try again.");
      return;
    }

    if (effectiveStatus == GeofenceStatus.exit) {
      _showRetryDialog(
        "You are outside the assigned site radius. Move to the site location and try again.",
      );
      return;
    }

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => FaceCapturePage(
          title: markType == "in" ? "Selfie Check-In" : "Selfie Check-Out",
          actionLabel: markType == "in"
              ? "Capture Selfie & Mark In"
              : "Capture Selfie & Mark Out",
          employeeId: _employee!.employeeID,
          employeeName: _employee!.firstName,
          mode: FaceCaptureMode.verify,
          userUid: widget.user.uid,
        ),
      ),
    );

    if (verified != true || !mounted) {
      return;
    }

    setState(() {
      _isMarkingAttendance = true;
    });

    onLoadingDialog(context);
    final marked = markType == "in"
        ? await markInAttendance(
            context,
            office,
            _currentLocation!,
            widget.user,
            effectiveStatus,
          )
        : await markOutAttendance(
            context,
            office,
            _currentLocation!,
            widget.user,
            effectiveStatus,
          );

    if (!mounted) {
      return;
    }

    setState(() {
      _isMarkingAttendance = false;
    });

    if (marked) {
      await _loadTodayAttendance();
    }
  }

  void _showRetryDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          height: 200,
          decoration: const BoxDecoration(
            color: Colors.blueGrey,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPanelExpanded(bool value) {
    if (!mounted || _isPanelExpanded == value) {
      return;
    }
    setState(() {
      _isPanelExpanded = value;
    });
  }

  bool get _isFaceRegistered => _profileData?['faceRegistered'] == true;

  Iterable<String> get _todayAttendanceKeys =>
      (_todayAttendanceMap?.keys ?? const <String>[]).cast<String>();

  bool get _hasOpenInEntry {
    final lastIn =
        _todayFirstInTime.isEmpty ? "" : findLatestIn(_todayAttendanceKeys);
    final lastOut = _todayLastOutTime;
    return lastIn.isNotEmpty &&
        (lastOut.isEmpty || lastIn.compareTo(lastOut) > 0);
  }

  bool get _isCurrentlyIn => _hasOpenInEntry;

  bool get _canMarkIn =>
      !_isMarkingAttendance &&
      !_isCurrentlyIn &&
      _isFaceRegistered &&
      _currentLocation != null &&
      _effectiveGeofenceStatus == GeofenceStatus.enter;

  bool get _canMarkOut =>
      !_isMarkingAttendance &&
      _hasOpenInEntry &&
      _isFaceRegistered &&
      _currentLocation != null &&
      _effectiveGeofenceStatus == GeofenceStatus.enter;

  String get _markInDisabledMessage {
    if (_isMarkingAttendance) {
      return "Attendance is being processed.";
    }
    if (!_isFaceRegistered) {
      return "Please register your face from Profile first.";
    }
    if (_currentLocation == null) {
      return "Current location is still loading.";
    }
    if (_effectiveGeofenceStatus == GeofenceStatus.exit) {
      return "Site Outside. Move inside the assigned site radius to mark IN.";
    }
    if (_effectiveGeofenceStatus == GeofenceStatus.init) {
      return "Site validation is still syncing.";
    }
    if (_isCurrentlyIn) {
      return "You are already IN.";
    }
    return "IN will be marked after selfie verification.";
  }

  String get _markOutDisabledMessage {
    if (_isMarkingAttendance) {
      return "Attendance is being processed.";
    }
    if (!_isFaceRegistered) {
      return "Please register your face from Profile first.";
    }
    if (_currentLocation == null) {
      return "Current location is still loading.";
    }
    if (_effectiveGeofenceStatus == GeofenceStatus.exit) {
      return "Site Outside. Move inside the assigned site radius to mark OUT.";
    }
    if (_effectiveGeofenceStatus == GeofenceStatus.init) {
      return "Site validation is still syncing.";
    }
    if (_todayAttendanceKeys.isEmpty) {
      return "Please mark IN first.";
    }
    if (!_hasOpenInEntry) {
      return "You are already OUT.";
    }
    return "OUT will be marked after selfie verification.";
  }

  String get _todayFirstInTime =>
      _todayAttendanceKeys.isEmpty ? "" : findFirstIn(_todayAttendanceKeys);

  String get _todayLastOutTime =>
      _todayAttendanceKeys.isEmpty ? "" : findLatestOut(_todayAttendanceKeys);

  List<String> get _todayTimelineEntries {
    final items = _todayAttendanceKeys.toList()
      ..sort((a, b) => a.split('-').last.compareTo(b.split('-').last));
    return items.map((key) {
      final markType = key.split('-').first.toUpperCase();
      final value = _todayAttendanceMap?[key];
      final officeKey = value is Map ? (value['office']?.toString() ?? '') : '';
      final time = value is Map
          ? (value['time']?.toString() ?? key.split('-').last)
          : key;
      return "$markType at $time${officeKey.isNotEmpty ? " | site: $officeKey" : ""}";
    }).toList();
  }

  String get _locationStatusLabel =>
      _currentLocation == null ? "Location Syncing" : "Location Ready";

  GeofenceStatus get _effectiveGeofenceStatus {
    final office = _allottedOffice;
    if (office == null) {
      return geofenceStatus;
    }
    final resolvedStatus =
        GeoFencingService.resolveStatus(office, _currentLocation);
    return resolvedStatus == GeofenceStatus.init
        ? geofenceStatus
        : resolvedStatus;
  }

  String get _geofenceLabel {
    switch (_effectiveGeofenceStatus) {
      case GeofenceStatus.enter:
        return "Inside Site";
      case GeofenceStatus.exit:
        return "Site Outside";
      case GeofenceStatus.init:
        return "Site Check Syncing";
    }
  }

  Color get _geofenceColor {
    switch (_effectiveGeofenceStatus) {
      case GeofenceStatus.enter:
        return Colors.green;
      case GeofenceStatus.exit:
        return Colors.redAccent;
      case GeofenceStatus.init:
        return Colors.orange;
    }
  }
}
