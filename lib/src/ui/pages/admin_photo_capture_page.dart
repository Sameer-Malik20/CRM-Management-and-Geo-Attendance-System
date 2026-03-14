import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/admin_service.dart';
import 'package:geo_attendance_system/src/services/face_attendance_api.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_backend_status_banner.dart';

enum AdminPhotoFlow { registerFace, markAttendance }

class AdminPhotoCapturePage extends StatefulWidget {
  final AdminUserProfile selectedUser;
  final String markType;
  final AdminPhotoFlow flow;

  const AdminPhotoCapturePage({
    super.key,
    required this.selectedUser,
    required this.markType,
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
  AdminManualAttendanceResult? _markResult;
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
      (camera) => camera.lensDirection == CameraLensDirection.front,
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
          ? 'Center the worker face and capture a face-lock style scan.'
          : 'Center the worker face and capture attendance.';
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
          ? 'Registering worker face...'
          : 'Recognizing face and marking attendance...';
    });

    try {
      final image = await _controller!.takePicture();
      if (widget.flow == AdminPhotoFlow.registerFace) {
        final response = await FaceAttendanceApi.registerFace(
          imagePath: image.path,
          employeeId: widget.selectedUser.employeeId,
          employeeName: widget.selectedUser.name,
          replaceExisting: true,
        );
        if (response.success) {
          await _adminService.updateFaceRegistrationStatus(
            uid: widget.selectedUser.uid,
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

      final response = await FaceAttendanceApi.verifyFace(
        imagePath: image.path,
        expectedEmployeeId: widget.selectedUser.employeeId,
      );

      AdminManualAttendanceResult? markResult;
      if (response.success) {
        final results = await _adminService.markManualAttendanceForProfiles(
          profiles: [widget.selectedUser],
          markType: widget.markType,
        );
        if (results.isNotEmpty) {
          markResult = results.first;
        }
      }

      if (!mounted) return;
      setState(() {
        _capturedImage = image;
        _markResult = markResult;
        _processing = false;
        _status = response.success
            ? (markResult?.message ?? response.message)
            : response.message;
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
                    onPressed: _loadingCamera || _processing
                        ? null
                        : _captureAndProcess,
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
                          : 'Capture & Mark Attendance',
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
                            _markResult = null;
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
              child: Image.file(
                File(_capturedImage!.path),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_markResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _markResult!.success
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                "${_markResult!.employeeId} - ${_markResult!.employeeName}: ${_markResult!.message}",
              ),
            ),
        ],
      ),
    );
  }
}
