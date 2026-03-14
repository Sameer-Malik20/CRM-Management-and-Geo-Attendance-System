import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/fetch_user.dart';
import 'package:geo_attendance_system/src/services/on_device_face_recognition_service.dart';
import 'package:geo_attendance_system/src/services/profile_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_engine_status_banner.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum FaceCaptureMode { register, verify }

class FaceCapturePage extends StatefulWidget {
  final String title;
  final String actionLabel;
  final String employeeId;
  final String employeeName;
  final FaceCaptureMode mode;
  final String? userUid;

  const FaceCapturePage({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.employeeId,
    required this.employeeName,
    required this.mode,
    this.userUid,
  });

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  final OnDeviceFaceRecognitionService _faceRecognitionService =
      OnDeviceFaceRecognitionService.instance;
  final ProfileService _profileService = ProfileService();
  final FaceDetector _previewFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      minFaceSize: 0.20,
    ),
  );

  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isSubmitting = false;
  bool _isProcessingFrame = false;
  bool _isFaceDetected = false;
  bool _isFaceAligned = false;
  int _stableAlignedFrames = 0;
  DateTime? _lastAutoAttemptAt;
  String _statusMessage = 'Initializing the front camera...';
  FaceEngineStatusInfo _engineInfo = const FaceEngineStatusInfo(
    state: FaceEngineState.loading,
    message: 'Loading on-device face recognition...',
  );
  static const int _requiredStableFrames = 4;
  static const Duration _autoAttemptGap = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    await Future.wait([
      _initCamera(),
      _initFaceEngine(),
    ]);
  }

  Future<void> _initFaceEngine() async {
    final info = await _faceRecognitionService.initialize();
    if (!mounted) {
      return;
    }
    setState(() {
      _engineInfo = info;
    });
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
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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
            ? 'Keep your face inside the circle. The app will register automatically when the ring turns green.'
            : 'Keep your face inside the circle. The app will verify automatically when the ring turns green.';
      });

      await controller.startImageStream(_processCameraImage);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Could not start the camera: $error';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessingFrame || _controller == null || _isSubmitting) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) {
        return;
      }

      final faces = await _previewFaceDetector.processImage(inputImage);
      if (!mounted) {
        return;
      }

      if (faces.isEmpty) {
        setState(() {
          _isFaceDetected = false;
          _isFaceAligned = false;
          _statusMessage =
              'No face detected. Move your face into the guide circle.';
        });
        return;
      }

      final face = _largestFace(faces);
      final aligned = _isFaceInsideGuide(
        face: face,
        imageSize: Size(
          cameraImage.width.toDouble(),
          cameraImage.height.toDouble(),
        ),
      );
      final poseMatched = widget.mode == FaceCaptureMode.verify
          ? _isVerificationPose(face)
          : _isRegistrationPose(face);
      final readyForAutoCapture = aligned && poseMatched;
      _stableAlignedFrames = readyForAutoCapture ? _stableAlignedFrames + 1 : 0;

      setState(() {
        _isFaceDetected = true;
        _isFaceAligned = readyForAutoCapture;
        if (!aligned) {
          _statusMessage =
              'Center your face inside the circle and keep a comfortable distance.';
        } else if (!poseMatched) {
          _statusMessage =
              'Look straight into the circle and keep your face level.';
        } else {
          _statusMessage = widget.mode == FaceCaptureMode.register
              ? 'Face looks good. Registering automatically...'
              : 'Face looks good. Verifying automatically...';
        }
      });

      final canAttempt = _lastAutoAttemptAt == null ||
          DateTime.now().difference(_lastAutoAttemptAt!) >= _autoAttemptGap;

      if (readyForAutoCapture &&
          canAttempt &&
          _stableAlignedFrames >= _requiredStableFrames) {
        _lastAutoAttemptAt = DateTime.now();
        _stableAlignedFrames = 0;
        if (widget.mode == FaceCaptureMode.register) {
          await _registerFace(autoTriggered: true);
        } else {
          await _verifyFace(autoTriggered: true);
        }
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _registerFace({bool autoTriggered = false}) async {
    if (!_canStartFaceAction()) {
      return;
    }
    if (widget.userUid == null || widget.userUid!.isEmpty) {
      setState(() {
        _statusMessage = 'User profile is missing. Please sign in again.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = 'Registering face on this device...';
    });

    try {
      final picturePath = await _capturePicturePath();
      final result =
          await _faceRecognitionService.createEmbeddingFromImage(picturePath);

      if (!mounted) {
        return;
      }

      if (!result.success || result.embedding == null) {
        setState(() {
          _isSubmitting = false;
          _statusMessage = result.message;
        });
        return;
      }

      await _profileService.updateFaceEmbedding(
        uid: widget.userUid!,
        embedding: result.embedding!,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Face registration completed successfully.';
      });

      if (autoTriggered) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      await _showResultDialog(
        success: true,
        message:
            'Your face profile has been saved on-device and linked to your account.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Face registration failed. Please try again.';
      });
      if (autoTriggered) {
        return;
      }
      await _showResultDialog(
        success: false,
        message: 'Face registration failed: $error',
      );
    }
  }

  Future<void> _verifyFace({bool autoTriggered = false}) async {
    if (!_canStartFaceAction()) {
      return;
    }
    if (widget.userUid == null || widget.userUid!.isEmpty) {
      setState(() {
        _statusMessage = 'User profile is missing. Please sign in again.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = 'Verifying face on this device...';
    });

    try {
      final profileData = await UserDatabase.getProfileData(widget.userUid!);
      final storedEmbedding = _faceRecognitionService.parseStoredEmbedding(
        profileData['faceEmbeddingJson'],
      );

      if (storedEmbedding == null || storedEmbedding.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSubmitting = false;
          _statusMessage =
              'No registered face profile was found. Please register your face first.';
        });
        return;
      }

      final picturePath = await _capturePicturePath();
      final result = await _faceRecognitionService.verifyImageAgainstEmbedding(
        imagePath: picturePath,
        storedEmbedding: storedEmbedding,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _statusMessage = result.message;
      });

      if (result.success) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      if (autoTriggered) {
        return;
      }

      await _showResultDialog(
        success: false,
        message: result.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _statusMessage = 'Face verification failed. Please try again.';
      });
      if (autoTriggered) {
        return;
      }
      await _showResultDialog(
        success: false,
        message: 'Face verification failed: $error',
      );
    }
  }

  bool _canStartFaceAction() {
    if (_engineInfo.state != FaceEngineState.ready) {
      setState(() {
        _statusMessage = 'The on-device face engine is still loading.';
      });
      return false;
    }

    if (!_isFaceAligned) {
      setState(() {
        _statusMessage =
            'Align your face inside the circle until the ring turns green.';
      });
      return false;
    }

    return true;
  }

  Future<String> _capturePicturePath() async {
    if (_controller == null) {
      throw StateError('Camera controller is not ready.');
    }

    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }

    try {
      final picture = await _controller!.takePicture();
      return picture.path;
    } finally {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          !_controller!.value.isStreamingImages) {
        await _controller!.startImageStream(_processCameraImage);
      }
    }
  }

  Future<void> _showResultDialog({
    required bool success,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(success ? 'Success' : 'Face Check Failed'),
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

  Face _largestFace(List<Face> faces) {
    return faces.reduce((current, next) {
      final currentArea =
          current.boundingBox.width.abs() * current.boundingBox.height.abs();
      final nextArea =
          next.boundingBox.width.abs() * next.boundingBox.height.abs();
      return nextArea > currentArea ? next : current;
    });
  }

  bool _isVerificationPose(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();
    return yaw < 18 && pitch < 18 && roll < 16;
  }

  bool _isRegistrationPose(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();
    return yaw < 20 && pitch < 20 && roll < 18;
  }

  bool _isFaceInsideGuide({
    required Face face,
    required Size imageSize,
  }) {
    final rect = face.boundingBox;
    final centerX = (rect.left + rect.width / 2) / imageSize.width;
    final centerY = (rect.top + rect.height / 2) / imageSize.height;
    final widthRatio = rect.width / imageSize.width;
    final heightRatio = rect.height / imageSize.height;

    final closeEnoughToCenter =
        (centerX - 0.5).abs() < 0.16 && (centerY - 0.5).abs() < 0.18;
    final goodScale =
        widthRatio > 0.24 && widthRatio < 0.62 && heightRatio > 0.24;

    return closeEnoughToCenter && goodScale;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) {
      return null;
    }

    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );
    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      return null;
    }

    if (Platform.isAndroid && format != InputImageFormat.nv21) {
      return null;
    }
    if (Platform.isIOS && format != InputImageFormat.bgra8888) {
      return null;
    }

    final bytes = _concatenatePlaneBytes(image.planes);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlaneBytes(List<Plane> planes) {
    final builder = BytesBuilder(copy: false);
    for (final plane in planes) {
      builder.add(plane.bytes);
    }
    return builder.takeBytes();
  }

  @override
  void dispose() {
    _previewFaceDetector.close();
    _controller?.dispose();
    super.dispose();
  }

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
                              _buildFaceGuideOverlay(),
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
              FaceEngineStatusBanner(
                info: _engineInfo,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.phone_android),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recognition runs on this device. Only the detected face is used, and registration or verification starts automatically when alignment is good.',
                      ),
                    ),
                  ],
                ),
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
          final borderColor =
              _isFaceAligned ? Colors.greenAccent : Colors.white;
          final helperText = !_isFaceDetected
              ? 'Face not detected yet'
              : _isFaceAligned
                  ? widget.mode == FaceCaptureMode.register
                      ? 'Registering automatically'
                      : 'Verifying automatically'
                  : 'Adjust your face inside the circle';

          return Stack(
            children: [
              Container(color: Colors.black26),
              Center(
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: _isFaceAligned
                            ? Colors.greenAccent.withValues(alpha: 0.35)
                            : Colors.white24,
                        blurRadius: 18,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  helperText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: borderColor,
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
