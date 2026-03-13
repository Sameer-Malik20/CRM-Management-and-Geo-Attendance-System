import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/face_attendance_api.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_backend_status_banner.dart';

enum FaceCaptureMode { register, verify }

class FaceCapturePage extends StatefulWidget {
  final String title;
  final String actionLabel;
  final String employeeId;
  final String employeeName;
  final FaceCaptureMode mode;
  final String? userUid;

  const FaceCapturePage({
    Key? key,
    required this.title,
    required this.actionLabel,
    required this.employeeId,
    required this.employeeName,
    required this.mode,
    this.userUid,
  }) : super(key: key);

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  CameraController? _controller;
  Timer? _autoCaptureTimer;
  Timer? _backendWarmupTimer;
  bool _isCameraReady = false;
  bool _isSubmitting = false;
  String _statusMessage = 'Initializing the front camera...';
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
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isCameraReady = true;
        _statusMessage = widget.mode == FaceCaptureMode.register
            ? 'Capture a clear selfie to register the face.'
            : 'Keep your face inside the circle. Auto-scan is starting.';
      });

      if (_isAutoScanMode) {
        _scheduleAutoCapture();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not start the camera: $e';
      });
    }
  }

  Future<void> _handleCapture({bool autoTriggered = false}) async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = widget.mode == FaceCaptureMode.register
          ? 'Uploading selfie...'
          : 'Detecting and verifying face...';
    });

    try {
      final picture = await _controller!.takePicture();
      final response = widget.mode == FaceCaptureMode.register
          ? await FaceAttendanceApi.registerFace(
              imagePath: picture.path,
              employeeId: widget.employeeId,
              employeeName: widget.employeeName,
            )
          : await FaceAttendanceApi.verifyFace(
              imagePath: picture.path,
              expectedEmployeeId: widget.employeeId,
            );

      if (!mounted) return;

      if (response.success && widget.mode == FaceCaptureMode.register) {
        await _persistFaceRegistration();
      }

      if (_isAutoScanMode && widget.mode == FaceCaptureMode.verify) {
        if (response.success) {
          setState(() {
            _isSubmitting = false;
            _statusMessage = response.message;
          });
          await Future.delayed(const Duration(milliseconds: 350));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        }

        setState(() {
          _isSubmitting = false;
          _statusMessage = "${response.message} Retrying automatically...";
        });
        _scheduleAutoCapture(
          delay: const Duration(milliseconds: 1300),
        );
        return;
      }

      setState(() {
        _isSubmitting = false;
        _statusMessage = response.message;
      });

      await _showResultDialog(
        success: response.success,
        message: response.message,
      );
    } catch (e) {
      if (!mounted) return;

      if (_isAutoScanMode && autoTriggered) {
        setState(() {
          _isSubmitting = false;
          _statusMessage =
              'Face scan failed. Keep your face inside the circle. Retrying automatically.';
        });
        _scheduleAutoCapture(
          delay: const Duration(milliseconds: 1300),
        );
        return;
      }

      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Selfie capture failed. Please try again.';
      });

      await _showResultDialog(
        success: false,
        message: 'Selfie capture failed: $e',
      );
    }
  }

  void _scheduleAutoCapture({Duration delay = const Duration(milliseconds: 900)}) {
    _autoCaptureTimer?.cancel();
    if (!_isAutoScanMode || !_isCameraReady || _isSubmitting) {
      return;
    }
    _autoCaptureTimer = Timer(delay, () {
      if (!mounted) return;
      _handleCapture(autoTriggered: true);
    });
  }

  Future<void> _persistFaceRegistration() async {
    final userUid = widget.userUid;
    if (userUid == null || userUid.isEmpty) {
      return;
    }

    await FirebaseDatabase.instance.reference().child('users').child(userUid).update({
      'faceRegistered': true,
      'faceRegisteredAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _showResultDialog({
    required bool success,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(success ? 'Success' : 'Verification Failed'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (success) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _backendWarmupTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  bool get _isAutoScanMode => widget.mode == FaceCaptureMode.verify;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    color: Colors.black87,
                    child: _isCameraReady && _controller != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(_controller!),
                              if (_isAutoScanMode) _buildFaceGuideOverlay(),
                            ],
                          )
                        : const Center(
                            child: CircularProgressIndicator(),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Employee: ${widget.employeeName} (${widget.employeeId})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              FaceBackendStatusBanner(
                info: _backendInfo,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              if (_isAutoScanMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      if (_isSubmitting)
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.center_focus_strong),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Auto-scan is on. Keep your face inside the circle and capture will happen automatically.",
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: splashScreenColorTop,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: !_isCameraReady || _isSubmitting
                      ? null
                      : _handleCapture,
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(widget.actionLabel),
                ),
              const SizedBox(height: 8),
              Text(
                'Face backend URL: ${FaceAttendanceApi.baseUrl}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceGuideOverlay() {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final diameter = size.width * 0.68;
          return Stack(
            children: [
              Container(color: Colors.black26),
              Center(
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white24,
                        blurRadius: 18,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  "Keep your face inside the circle",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
