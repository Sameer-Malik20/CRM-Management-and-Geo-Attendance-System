import 'dart:io';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/admin_service.dart';
import 'package:geo_attendance_system/src/services/face_attendance_api.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_backend_status_banner.dart';

enum AdminPhotoFlow { registerFace, markAttendance }

class AdminPhotoCapturePage extends StatefulWidget {
  final List<AdminUserProfile> selectedUsers;
  final String markType;
  final bool groupMode;
  final bool autoDetectAll;
  final AdminPhotoFlow flow;

  const AdminPhotoCapturePage({
    super.key,
    required this.selectedUsers,
    required this.markType,
    required this.groupMode,
    required this.autoDetectAll,
    required this.flow,
  });

  @override
  State<AdminPhotoCapturePage> createState() => _AdminPhotoCapturePageState();
}

class _AdminPhotoCapturePageState extends State<AdminPhotoCapturePage> {
  final AdminService _adminService = AdminService();
  CameraController? _controller;
  Timer? _backendWarmupTimer;
  bool _loadingCamera = true;
  bool _processing = false;
  String _status = 'Initializing the camera...';
  XFile? _capturedImage;
  GroupFaceApiResponse? _groupResponse;
  List<AdminManualAttendanceResult> _markResults = const [];
  FaceBackendWarmupInfo _backendInfo = FaceAttendanceApi.initialWarmupInfo;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _warmUpFaceBackend();
  }

  Future<void> _warmUpFaceBackend() async {
    _backendWarmupTimer?.cancel();
    final info = await FaceAttendanceApi.checkServerWarmup();
    if (!mounted) return;
    setState(() {
      _backendInfo = info;
    });
    if (info.state != FaceBackendWarmupState.ready) {
      _backendWarmupTimer = Timer(
        const Duration(seconds: 5),
        _warmUpFaceBackend,
      );
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final preferredCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      preferredCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _loadingCamera = false;
      _status = widget.flow == AdminPhotoFlow.registerFace
          ? 'Capture a clear worker photo to register the face.'
          : widget.groupMode
              ? widget.autoDetectAll
                  ? 'Capture a group photo. The system will automatically detect 1 to 10 faces.'
                  : 'Capture a group photo after selecting up to 10 workers.'
              : 'Capture a single worker photo to mark attendance.';
    });
  }

  @override
  void dispose() {
    _backendWarmupTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || _processing) {
      return;
    }

    setState(() {
      _processing = true;
      _status = widget.flow == AdminPhotoFlow.registerFace
          ? 'Registering face...'
          : 'Recognizing faces and processing attendance...';
    });

    try {
      final image = await _controller!.takePicture();
      if (widget.flow == AdminPhotoFlow.registerFace) {
        final profile = widget.selectedUsers.first;
        final response = await FaceAttendanceApi.registerFace(
          imagePath: image.path,
          employeeId: profile.employeeId,
          employeeName: profile.name,
        );
        if (response.success) {
          await _adminService.updateFaceRegistrationStatus(
            uid: profile.uid,
            registered: true,
          );
        }
        if (!mounted) return;
        setState(() {
          _capturedImage = image;
          _processing = false;
          _status = response.message;
        });
        return;
      }

      final groupResponse = await FaceAttendanceApi.recognizeGroup(
        imagePath: image.path,
        expectedEmployeeIds: widget.autoDetectAll
            ? const []
            : widget.selectedUsers.map((user) => user.employeeId).toList(),
      );

      final matchedProfiles = widget.selectedUsers
          .where(
            (profile) => groupResponse.matches.any(
              (match) => match.employeeId == profile.employeeId,
            ),
          )
          .toList();

      final results = matchedProfiles.isEmpty
          ? const <AdminManualAttendanceResult>[]
          : await _adminService.markManualAttendanceForProfiles(
              profiles: matchedProfiles,
              markType: widget.markType,
            );

      if (!mounted) return;
      setState(() {
        _capturedImage = image;
        _groupResponse = groupResponse;
        _markResults = results;
        _processing = false;
        _status = groupResponse.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = 'Photo processing failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        title: Text(
          widget.flow == AdminPhotoFlow.registerFace
              ? 'Register Worker Face'
              : widget.groupMode
                  ? 'Group Attendance Photo'
                  : 'Single Attendance Photo',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: _capturedImage == null
                    ? _buildCameraPreview()
                    : _buildCapturedPreview(),
              ),
              const SizedBox(height: 14),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FaceBackendStatusBanner(
                info: _backendInfo,
                margin: const EdgeInsets.only(bottom: 14),
              ),
              if (_capturedImage == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: splashScreenColorTop,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loadingCamera || _processing ? null : _captureAndProcess,
                    icon: _processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(
                      widget.flow == AdminPhotoFlow.registerFace
                          ? 'Capture & Register Face'
                          : 'Capture & Process Attendance',
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _capturedImage = null;
                            _groupResponse = null;
                            _markResults = const [];
                          });
                        },
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: splashScreenColorTop,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_loadingCamera || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: CameraPreview(_controller!),
    );
  }

  Widget _buildCapturedPreview() {
    return SingleChildScrollView(
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(_capturedImage!.path),
                    fit: BoxFit.fill,
                  ),
                  if (_groupResponse != null)
                    ..._groupResponse!.matches.map(
                      (match) => Positioned(
                        left: match.x * MediaQuery.of(context).size.width * 0.82,
                        top: match.y * 420,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            match.employeeId,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_markResults.isNotEmpty)
            Column(
              children: _markResults
                  .map(
                    (result) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: result.success
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "${result.employeeId} - ${result.employeeName}: ${result.message}",
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
