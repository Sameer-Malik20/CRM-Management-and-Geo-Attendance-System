import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/admin_service.dart';
import 'package:geo_attendance_system/src/services/on_device_face_recognition_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/face_engine_status_banner.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum AdminPhotoFlow {
  registerFace,
  markSingleAttendance,
  markGroupAttendance,
}

class AdminPhotoCapturePage extends StatefulWidget {
  final AdminUserProfile? selectedUser;
  final List<AdminUserProfile> candidateUsers;
  final String markType;
  final AdminPhotoFlow flow;

  const AdminPhotoCapturePage({
    super.key,
    this.selectedUser,
    this.candidateUsers = const <AdminUserProfile>[],
    required this.markType,
    required this.flow,
  });

  @override
  State<AdminPhotoCapturePage> createState() => _AdminPhotoCapturePageState();
}

class _AdminPhotoCapturePageState extends State<AdminPhotoCapturePage> {
  final AdminService _adminService = AdminService();
  final OnDeviceFaceRecognitionService _faceRecognitionService =
      OnDeviceFaceRecognitionService.instance;
  final FaceDetector _previewFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      minFaceSize: 0.20,
    ),
  );

  CameraController? _controller;
  List<CameraDescription> _availableCameras = const [];
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;
  CameraImage? _latestCameraImage;

  bool _loadingCamera = true;
  bool _processing = false;
  bool _isScanningFrame = false;
  bool _isProcessingGuideFrame = false;
  bool _isFaceDetected = false;
  bool _isFaceAligned = false;
  int _stableAlignedFrames = 0;

  String _status = 'Initializing the camera...';
  String? _capturedImagePath;
  List<AdminManualAttendanceResult> _markResults = const [];
  FaceEngineStatusInfo _engineInfo = const FaceEngineStatusInfo(
    state: FaceEngineState.loading,
    message: 'Loading on-device face recognition...',
  );
  List<_FaceOverlayLabel> _overlayLabels = const [];
  DateTime? _lastOverlayScanAt;
  DateTime? _lastAutoAttemptAt;
  Size _lastFrameSize = const Size(1, 1);

  static const Duration _overlayScanGap = Duration(milliseconds: 1400);
  static const int _requiredStableFrames = 4;
  static const Duration _autoAttemptGap = Duration(milliseconds: 1400);

  List<AdminUserProfile> get _targetUsers {
    if (widget.selectedUser != null) {
      return [widget.selectedUser!];
    }
    return widget.candidateUsers;
  }

  List<_StoredFaceCandidate> get _storedCandidates {
    return _targetUsers
        .map((user) {
          final embedding = _faceRecognitionService.parseStoredEmbedding(
            user.faceEmbeddingJson,
          );
          if (embedding == null || embedding.isEmpty) {
            return null;
          }
          return _StoredFaceCandidate(
            profile: user,
            embedding: embedding,
          );
        })
        .whereType<_StoredFaceCandidate>()
        .toList();
  }

  bool get _isRegisterFlow => widget.flow == AdminPhotoFlow.registerFace;

  bool get _isGroupAttendanceFlow =>
      widget.flow == AdminPhotoFlow.markGroupAttendance;

  bool get _useSingleGuide =>
      widget.flow == AdminPhotoFlow.markSingleAttendance;

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
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }
      _availableCameras = cameras;
      final preferredCamera = _pickCamera(_currentLensDirection);
      await _setCamera(preferredCamera, resetStatus: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCamera = false;
        _status = 'Could not start the camera: $error';
      });
    }
  }

  CameraDescription _pickCamera(CameraLensDirection lensDirection) {
    return _availableCameras.firstWhere(
      (camera) => camera.lensDirection == lensDirection,
      orElse: () => _availableCameras.first,
    );
  }

  Future<void> _setCamera(
    CameraDescription camera, {
    bool resetStatus = false,
  }) async {
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      if (oldController.value.isStreamingImages) {
        await oldController.stopImageStream();
      }
      await oldController.dispose();
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    await controller.startImageStream(_handleCameraFrame);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _currentLensDirection = camera.lensDirection;
      _loadingCamera = false;
      _overlayLabels = const [];
      _isFaceDetected = false;
      _isFaceAligned = false;
      if (resetStatus) {
        _status = _initialStatus;
      }
    });
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2 || _loadingCamera || _processing) {
      return;
    }

    final nextLensDirection =
        _currentLensDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front;

    final nextCamera = _pickCamera(nextLensDirection);
    setState(() {
      _loadingCamera = true;
      _status = 'Switching camera...';
    });

    try {
      await _setCamera(nextCamera, resetStatus: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCamera = false;
        _status = 'Could not switch camera: $error';
      });
    }
  }

  Future<void> _handleCameraFrame(CameraImage image) async {
    _latestCameraImage = image;
    _lastFrameSize = Size(image.width.toDouble(), image.height.toDouble());

    if (_capturedImagePath != null) {
      return;
    }

    if (_useSingleGuide) {
      unawaited(_processGuideFrame(image));
    }

    if (_processing ||
        _isScanningFrame ||
        _engineInfo.state != FaceEngineState.ready ||
        _isRegisterFlow) {
      return;
    }

    final canScan = _lastOverlayScanAt == null ||
        DateTime.now().difference(_lastOverlayScanAt!) >= _overlayScanGap;
    if (!canScan) {
      return;
    }

    _lastOverlayScanAt = DateTime.now();
    await _scanLiveOverlays();
  }

  Future<void> _processGuideFrame(CameraImage image) async {
    if (_isProcessingGuideFrame || _controller == null || _processing) {
      return;
    }

    _isProcessingGuideFrame = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
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
          _stableAlignedFrames = 0;
          if (!_processing) {
            _status = 'No face detected. Move the worker face into the guide circle.';
          }
        });
        return;
      }

      final face = _largestFace(faces);
      final aligned = _isFaceInsideGuide(
        face: face,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      );
      final poseMatched = _isAttendancePose(face);
      final readyForAutoCapture = aligned && poseMatched;
      _stableAlignedFrames = readyForAutoCapture ? _stableAlignedFrames + 1 : 0;

      setState(() {
        _isFaceDetected = true;
        _isFaceAligned = readyForAutoCapture;
        if (!_processing) {
          if (!aligned) {
            _status =
                'Center the worker face inside the circle and keep a comfortable distance.';
          } else if (!poseMatched) {
            _status = 'Ask the worker to look straight into the guide circle.';
          } else {
            _status = 'Face angle looks good. Verifying attendance automatically...';
          }
        }
      });

      final canAttempt = _lastAutoAttemptAt == null ||
          DateTime.now().difference(_lastAutoAttemptAt!) >= _autoAttemptGap;
      if (_useSingleGuide &&
          readyForAutoCapture &&
          canAttempt &&
          _stableAlignedFrames >= _requiredStableFrames) {
        _lastAutoAttemptAt = DateTime.now();
        _stableAlignedFrames = 0;
        await _captureAndProcess(autoTriggered: true);
      }
    } catch (_) {
      // Keep the last guide state if one preview frame fails.
    } finally {
      _isProcessingGuideFrame = false;
    }
  }

  Future<void> _scanLiveOverlays() async {
    if (_latestCameraImage == null || _isScanningFrame) {
      return;
    }

    _isScanningFrame = true;
    try {
      final imagePath = await _saveFrameToTempFile(_latestCameraImage!);
      final recognitions = await _analyzeImage(imagePath);

      if (!mounted) {
        return;
      }

      setState(() {
        _overlayLabels = _useSingleGuide
            ? const []
            : recognitions
                .map(
                  (recognition) => _FaceOverlayLabel(
                    label: recognition.isMatched
                        ? recognition.profile!.employeeId
                        : 'Not Match',
                    isMatched: recognition.isMatched,
                    box: recognition.boundingBox,
                  ),
                )
                .toList();

        if (!_processing && !_useSingleGuide) {
          if (recognitions.isEmpty) {
            _status = 'No face detected yet.';
          } else if (recognitions.any((recognition) => recognition.isMatched)) {
            _status = 'On-device matches found. Worker IDs are shown above the faces.';
          } else {
            _status = 'Faces detected, but no registered worker matched this frame.';
          }
        }
      });
    } catch (_) {
      // Keep the previous overlay state if a background scan fails.
    } finally {
      _isScanningFrame = false;
    }
  }

  Future<List<_OnDeviceRecognition>> _analyzeImage(String imagePath) async {
    final detections = await _faceRecognitionService.createEmbeddingsFromImage(
      imagePath,
      maxFaces: _isGroupAttendanceFlow ? 10 : 1,
    );
    if (detections.isEmpty) {
      return const <_OnDeviceRecognition>[];
    }

    final candidates = _storedCandidates;
    return detections.map((detection) {
      final matchedCandidate = _findBestMatch(
        detection.embedding,
        candidates,
      );
      return _OnDeviceRecognition(
        profile: matchedCandidate?.profile,
        boundingBox: detection.boundingBox,
        distance: matchedCandidate?.distance,
      );
    }).toList();
  }

  _StoredFaceCandidate? _findBestMatch(
    List<double> probeEmbedding,
    List<_StoredFaceCandidate> candidates,
  ) {
    _StoredFaceCandidate? bestMatch;
    double? bestDistance;

    for (final candidate in candidates) {
      final distance = _faceRecognitionService.compareEmbeddings(
        probeEmbedding,
        candidate.embedding,
      );
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestMatch = candidate.copyWith(distance: distance);
      }
    }

    if (bestMatch == null ||
        bestDistance == null ||
        bestDistance > _faceRecognitionService.matchThreshold) {
      return null;
    }
    return bestMatch;
  }

  Future<void> _captureAndProcess({bool autoTriggered = false}) async {
    if (_latestCameraImage == null || _processing || _capturedImagePath != null) {
      return;
    }

    setState(() {
      _processing = true;
      _markResults = const [];
      _status = _processingStatus;
    });

    try {
      final imagePath = await _saveFrameToTempFile(_latestCameraImage!);

      if (_isRegisterFlow) {
        final selectedUser = widget.selectedUser;
        if (selectedUser == null) {
          throw StateError('No worker selected for face registration.');
        }

        final result =
            await _faceRecognitionService.createEmbeddingFromImage(imagePath);
        if (!mounted) {
          return;
        }
        if (!result.success || result.embedding == null) {
          setState(() {
            _capturedImagePath = imagePath;
            _processing = false;
            _status = result.message;
          });
          return;
        }

        await _adminService.updateFaceEmbedding(
          uid: selectedUser.uid,
          embedding: result.embedding!,
        );

        if (!mounted) {
          return;
        }
        setState(() {
          _capturedImagePath = imagePath;
          _processing = false;
          _status = 'Face registered successfully on this device.';
        });
        return;
      }

      final recognitions = await _analyzeImage(imagePath);
      final matchedProfiles = _resolveMatchedProfiles(recognitions);
      final results = matchedProfiles.isNotEmpty
          ? await _adminService.markManualAttendanceForProfiles(
              profiles: matchedProfiles,
              markType: widget.markType,
            )
          : <AdminManualAttendanceResult>[];

      if (!mounted) {
        return;
      }
      setState(() {
        _capturedImagePath = imagePath;
        _overlayLabels = _useSingleGuide
            ? const []
            : recognitions
                .map(
                  (recognition) => _FaceOverlayLabel(
                    label: recognition.isMatched
                        ? recognition.profile!.employeeId
                        : 'Not Match',
                    isMatched: recognition.isMatched,
                    box: recognition.boundingBox,
                  ),
                )
                .toList();
        _markResults = results;
        _processing = false;
        _status = results.isNotEmpty
            ? '${results.where((result) => result.success).length} worker(s) processed successfully.'
            : _noMatchMessage;
      });

      if (autoTriggered &&
          _useSingleGuide &&
          results.any((result) => result.success)) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _processing = false;
        _status = 'Photo processing failed: $error';
      });
    }
  }

  List<AdminUserProfile> _resolveMatchedProfiles(
    List<_OnDeviceRecognition> recognitions,
  ) {
    final result = <AdminUserProfile>[];
    final seenIds = <String>{};

    for (final recognition in recognitions) {
      final profile = recognition.profile;
      if (profile == null) {
        continue;
      }
      final employeeId = profile.employeeId.trim().toLowerCase();
      if (seenIds.contains(employeeId)) {
        continue;
      }
      seenIds.add(employeeId);
      result.add(profile);
    }

    return result.take(_isGroupAttendanceFlow ? 10 : 1).toList();
  }

  Future<String> _saveFrameToTempFile(CameraImage cameraImage) async {
    final convertedImage = _convertCameraImage(cameraImage);
    if (convertedImage == null) {
      throw StateError('Could not read the latest camera frame.');
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/admin_face_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(convertedImage, quality: 92));
    return file.path;
  }

  img.Image? _convertCameraImage(CameraImage cameraImage) {
    img.Image image;
    if (Platform.isAndroid) {
      image = _convertNv21ToImage(cameraImage);
    } else {
      image = _convertBgra8888ToImage(cameraImage);
    }

    if (image.width > image.height) {
      image = img.copyRotate(image, angle: 90);
    }
    if (_currentLensDirection == CameraLensDirection.front) {
      image = img.flipHorizontal(image);
    }
    return image;
  }

  img.Image _convertNv21ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final yPlane = cameraImage.planes[0].bytes;
    final vuPlane = cameraImage.planes[1].bytes;
    final image = img.Image(width: width, height: height);

    var uvIndex = 0;
    for (int y = 0; y < height; y++) {
      final uvRow = (y >> 1) * width;
      for (int x = 0; x < width; x++) {
        final yValue = yPlane[y * width + x];
        uvIndex = uvRow + (x & ~1);
        final v = vuPlane[uvIndex];
        final u = vuPlane[uvIndex + 1];

        final r = (yValue + 1.370705 * (v - 128)).round().clamp(0, 255);
        final g = (yValue - 0.337633 * (u - 128) - 0.698001 * (v - 128))
            .round()
            .clamp(0, 255);
        final b = (yValue + 1.732446 * (u - 128)).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  img.Image _convertBgra8888ToImage(CameraImage cameraImage) {
    final bytes = cameraImage.planes.first.bytes;
    final width = cameraImage.width;
    final height = cameraImage.height;
    final image = img.Image(width: width, height: height);

    int byteOffset = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final b = bytes[byteOffset];
        final g = bytes[byteOffset + 1];
        final r = bytes[byteOffset + 2];
        image.setPixelRgb(x, y, r, g, b);
        byteOffset += 4;
      }
    }
    return image;
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

  bool _isAttendancePose(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    final roll = (face.headEulerAngleZ ?? 0).abs();
    return yaw < 18 && pitch < 18 && roll < 16;
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
        title: Text(_pageTitle),
        actions: [
          if (_availableCameras.length > 1)
            IconButton(
              tooltip: _currentLensDirection == CameraLensDirection.front
                  ? 'Switch to back camera'
                  : 'Switch to front camera',
              onPressed: _switchCamera,
              icon: const Icon(Icons.cameraswitch),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeaderSummary(),
              const SizedBox(height: 12),
              Expanded(
                child: _capturedImagePath == null
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
              FaceEngineStatusBanner(
                info: _engineInfo,
                margin: const EdgeInsets.only(bottom: 14),
              ),
              if (_capturedImagePath == null && !_useSingleGuide)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: splashScreenColorTop,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loadingCamera ||
                            _processing ||
                            (_useSingleGuide && !_isFaceAligned)
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
                    label: Text(_captureButtonLabel),
                  ),
                )
              else if (_capturedImagePath == null && _useSingleGuide)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Attendance will be marked automatically when the face stays inside the green circle.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _capturedImagePath = null;
                            _markResults = const [];
                            _status = _initialStatus;
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

  Widget _buildHeaderSummary() {
    final targets = _targetUsers;
    if (targets.isEmpty) {
      return const SizedBox.shrink();
    }

    final summaryText = _isGroupAttendanceFlow
        ? (targets.length > 10
            ? 'Group auto-detect is active on this device. Up to 10 matched workers will be marked from this photo.'
            : 'Selected group workers: ${targets.length} (max 10)')
        : widget.selectedUser == null
            ? 'Single on-device auto-detect is active. Any matched worker can be marked.'
            : 'Target worker: ${targets.first.name} (${targets.first.employeeId})';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        summaryText,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_loadingCamera || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_controller!),
              if (_useSingleGuide) _buildSingleGuideOverlay(),
              ..._overlayLabels.map(
                (overlayLabel) => _buildOverlayTag(
                  overlayLabel,
                  constraints.biggest,
                ),
              ),
            ],
          );
        },
      ),
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
                File(_capturedImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_markResults.isNotEmpty)
            ..._markResults.map(
              (result) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.success
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${result.employeeId} - ${result.employeeName}: ${result.message}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayTag(_FaceOverlayLabel label, Size canvasSize) {
    final imageWidth = _lastFrameSize.width == 0 ? 1.0 : _lastFrameSize.width;
    final imageHeight = _lastFrameSize.height == 0 ? 1.0 : _lastFrameSize.height;

    final scale = (canvasSize.width / imageWidth) > (canvasSize.height / imageHeight)
        ? canvasSize.width / imageWidth
        : canvasSize.height / imageHeight;
    final scaledWidth = imageWidth * scale;
    final scaledHeight = imageHeight * scale;
    final dx = (canvasSize.width - scaledWidth) / 2;
    final dy = (canvasSize.height - scaledHeight) / 2;

    final left = dx + (label.box.left * scale);
    final top = dy + (label.box.top * scale);
    final width = label.box.width * scale;

    return Positioned(
      left: left,
      top: top - 28,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: width.clamp(90, canvasSize.width * 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: label.isMatched ? Colors.green : Colors.redAccent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleGuideOverlay() {
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
                  ? 'Face angle looks good'
                  : 'Adjust the face inside the circle';

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

  String get _pageTitle {
    switch (widget.flow) {
      case AdminPhotoFlow.registerFace:
        return 'Register Worker Face';
      case AdminPhotoFlow.markSingleAttendance:
        return 'Single Worker Attendance';
      case AdminPhotoFlow.markGroupAttendance:
        return 'Group Attendance Photo';
    }
  }

  String get _initialStatus {
    switch (widget.flow) {
      case AdminPhotoFlow.registerFace:
        return 'Center the worker face and register it on this device.';
      case AdminPhotoFlow.markSingleAttendance:
        return widget.selectedUser == null
            ? 'On-device face matching is active. Keep the worker face inside the circle and capture when the ring turns green.'
            : 'Keep the selected worker face inside the circle. The ring turns green when the angle is ready.';
      case AdminPhotoFlow.markGroupAttendance:
        return 'On-device group face labels are active. Matched employee IDs will appear above each face.';
    }
  }

  String get _processingStatus {
    switch (widget.flow) {
      case AdminPhotoFlow.registerFace:
        return 'Registering worker face on this device...';
      case AdminPhotoFlow.markSingleAttendance:
        return 'Finalizing single-worker attendance...';
      case AdminPhotoFlow.markGroupAttendance:
        return 'Finalizing group attendance...';
    }
  }

  String get _captureButtonLabel {
    switch (widget.flow) {
      case AdminPhotoFlow.registerFace:
        return 'Capture & Register Face';
      case AdminPhotoFlow.markSingleAttendance:
        return widget.selectedUser == null
            ? 'Capture & Auto Detect Attendance'
            : 'Capture & Mark Attendance';
      case AdminPhotoFlow.markGroupAttendance:
        return 'Capture & Mark Group Attendance';
    }
  }

  String get _noMatchMessage {
    switch (widget.flow) {
      case AdminPhotoFlow.registerFace:
        return 'No face match was found.';
      case AdminPhotoFlow.markSingleAttendance:
        return widget.selectedUser == null
            ? 'No registered worker matched this face.'
            : 'The selected worker did not match this face.';
      case AdminPhotoFlow.markGroupAttendance:
        return 'No registered workers matched this group photo.';
    }
  }
}

class _StoredFaceCandidate {
  final AdminUserProfile profile;
  final List<double> embedding;
  final double? distance;

  const _StoredFaceCandidate({
    required this.profile,
    required this.embedding,
    this.distance,
  });

  _StoredFaceCandidate copyWith({
    AdminUserProfile? profile,
    List<double>? embedding,
    double? distance,
  }) {
    return _StoredFaceCandidate(
      profile: profile ?? this.profile,
      embedding: embedding ?? this.embedding,
      distance: distance ?? this.distance,
    );
  }
}

class _OnDeviceRecognition {
  final AdminUserProfile? profile;
  final Rect boundingBox;
  final double? distance;

  const _OnDeviceRecognition({
    required this.profile,
    required this.boundingBox,
    this.distance,
  });

  bool get isMatched => profile != null;
}

class _FaceOverlayLabel {
  final String label;
  final bool isMatched;
  final Rect box;

  const _FaceOverlayLabel({
    required this.label,
    required this.isMatched,
    required this.box,
  });
}
