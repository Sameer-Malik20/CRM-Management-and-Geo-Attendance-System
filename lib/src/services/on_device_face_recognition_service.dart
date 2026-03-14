import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

enum FaceEngineState { loading, ready, error }

class FaceEngineStatusInfo {
  final FaceEngineState state;
  final String message;

  const FaceEngineStatusInfo({
    required this.state,
    required this.message,
  });
}

class FaceEmbeddingResult {
  final bool success;
  final String message;
  final List<double>? embedding;
  final double? distance;

  const FaceEmbeddingResult({
    required this.success,
    required this.message,
    this.embedding,
    this.distance,
  });
}

class OnDeviceFaceRecognitionService {
  OnDeviceFaceRecognitionService._();

  static final OnDeviceFaceRecognitionService instance =
      OnDeviceFaceRecognitionService._();

  static const String _modelAssetPath = 'assets/models/mobilefacenet.tflite';
  static const double _matchThreshold = 1.10;

  final FaceDetector _fileFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: 0.18,
    ),
  );

  Interpreter? _interpreter;
  Future<void>? _initializationFuture;

  Future<FaceEngineStatusInfo> initialize() async {
    if (_interpreter != null) {
      return const FaceEngineStatusInfo(
        state: FaceEngineState.ready,
        message: 'On-device face recognition is ready.',
      );
    }

    try {
      _initializationFuture ??= _initializeInterpreter();
      await _initializationFuture;
      return const FaceEngineStatusInfo(
        state: FaceEngineState.ready,
        message: 'On-device face recognition is ready.',
      );
    } catch (error) {
      _initializationFuture = null;
      return FaceEngineStatusInfo(
        state: FaceEngineState.error,
        message: 'Could not load the on-device face engine: $error',
      );
    }
  }

  Future<FaceEmbeddingResult> createEmbeddingFromImage(String imagePath) async {
    final status = await initialize();
    if (status.state != FaceEngineState.ready || _interpreter == null) {
      return FaceEmbeddingResult(
        success: false,
        message: status.message,
      );
    }

    final cropResult = await _extractFaceCrop(imagePath);
    if (!cropResult.success || cropResult.faceImage == null) {
      return FaceEmbeddingResult(
        success: false,
        message: cropResult.message,
      );
    }

    final input = _imageToModelInput(cropResult.faceImage!);
    final output = List.generate(1, (_) => List<double>.filled(192, 0));

    _interpreter!.run(input, output);
    final embedding = _normalizeEmbedding(output.first);

    return FaceEmbeddingResult(
      success: true,
      message: 'Face processed successfully.',
      embedding: embedding,
    );
  }

  Future<FaceEmbeddingResult> verifyImageAgainstEmbedding({
    required String imagePath,
    required List<double> storedEmbedding,
  }) async {
    final currentResult = await createEmbeddingFromImage(imagePath);
    if (!currentResult.success || currentResult.embedding == null) {
      return currentResult;
    }

    final distance = _euclideanDistance(
      storedEmbedding,
      currentResult.embedding!,
    );
    if (distance <= _matchThreshold) {
      return FaceEmbeddingResult(
        success: true,
        message: 'Face verified successfully.',
        embedding: currentResult.embedding,
        distance: distance,
      );
    }

    return FaceEmbeddingResult(
      success: false,
      message: 'Face did not match the registered profile. Please try again.',
      embedding: currentResult.embedding,
      distance: distance,
    );
  }

  List<double>? parseStoredEmbedding(dynamic rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((item) => double.tryParse(item.toString()) ?? 0)
          .toList();
    }

    if (rawValue is String && rawValue.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawValue);
        if (decoded is List) {
          return decoded
              .map((item) => double.tryParse(item.toString()) ?? 0)
              .toList();
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  Future<void> _initializeInterpreter() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
  }

  Future<_FaceCropResult> _extractFaceCrop(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _fileFaceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      return const _FaceCropResult(
        success: false,
        message:
            'No face was detected. Keep your face inside the circle and try again.',
      );
    }

    final sourceFile = File(imagePath);
    final originalBytes = await sourceFile.readAsBytes();
    final decodedImage = img.decodeImage(originalBytes);
    if (decodedImage == null) {
      return const _FaceCropResult(
        success: false,
        message: 'Could not read the captured image.',
      );
    }

    final bakedImage = img.bakeOrientation(decodedImage);
    final face = _largestFace(faces);
    final croppedFace = _cropFaceImage(
      source: bakedImage,
      boundingBox: face.boundingBox,
    );

    if (croppedFace == null) {
      return const _FaceCropResult(
        success: false,
        message: 'Face crop failed. Please retry with better lighting.',
      );
    }

    return _FaceCropResult(
      success: true,
      message: 'Face crop ready.',
      faceImage: croppedFace,
    );
  }

  List<List<List<List<double>>>> _imageToModelInput(img.Image sourceImage) {
    final image = img.copyResizeCropSquare(sourceImage, size: 112);
    final input = List.generate(
      1,
      (_) => List.generate(
        112,
        (y) => List.generate(
          112,
          (x) {
            final pixel = image.getPixel(x, y);
            return <double>[
              (pixel.r - 128.0) / 128.0,
              (pixel.g - 128.0) / 128.0,
              (pixel.b - 128.0) / 128.0,
            ];
          },
        ),
      ),
    );
    return input;
  }

  img.Image? _cropFaceImage({
    required img.Image source,
    required Rect boundingBox,
  }) {
    final centerX = boundingBox.left + (boundingBox.width / 2);
    final centerY = boundingBox.top + (boundingBox.height / 2);
    final int side =
        ((math.max(boundingBox.width, boundingBox.height) * 1.65).round())
            .clamp(140, math.max(source.width, source.height))
            .toInt();

    final int left = (centerX - (side / 2))
        .round()
        .clamp(0, math.max(source.width - side, 0))
        .toInt();
    final int top = (centerY - (side / 2))
        .round()
        .clamp(0, math.max(source.height - side, 0))
        .toInt();

    final int width = math.min(side, source.width - left);
    final int height = math.min(side, source.height - top);
    if (width <= 0 || height <= 0) {
      return null;
    }

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: width,
      height: height,
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

  List<double> _normalizeEmbedding(List<double> embedding) {
    var sum = 0.0;
    for (final value in embedding) {
      sum += value * value;
    }
    final norm = math.sqrt(sum);
    if (norm == 0) {
      return embedding;
    }
    return embedding.map((value) => value / norm).toList();
  }

  double _euclideanDistance(List<double> first, List<double> second) {
    var sum = 0.0;
    final length = math.min(first.length, second.length);
    for (var index = 0; index < length; index++) {
      sum += math.pow(first[index] - second[index], 2).toDouble();
    }
    return math.sqrt(sum);
  }

  @visibleForTesting
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _initializationFuture = null;
    await _fileFaceDetector.close();
  }
}

class _FaceCropResult {
  final bool success;
  final String message;
  final img.Image? faceImage;

  const _FaceCropResult({
    required this.success,
    required this.message,
    this.faceImage,
  });
}
