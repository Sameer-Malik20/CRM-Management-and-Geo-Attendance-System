import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class FaceApiResponse {
  final bool success;
  final String message;
  final String? employeeId;
  final String? employeeName;
  final String? timestamp;

  FaceApiResponse({
    required this.success,
    required this.message,
    this.employeeId,
    this.employeeName,
    this.timestamp,
  });
}

class FaceApiGroupMatch {
  final String employeeId;
  final String employeeName;
  final double? confidence;
  final bool matched;
  final Map<String, double> box;

  const FaceApiGroupMatch({
    required this.employeeId,
    required this.employeeName,
    this.confidence,
    required this.matched,
    required this.box,
  });
}

class FaceApiGroupResponse {
  final bool success;
  final String message;
  final List<FaceApiGroupMatch> matches;
  final List<FaceApiGroupMatch> detections;

  const FaceApiGroupResponse({
    required this.success,
    required this.message,
    required this.matches,
    required this.detections,
  });
}

enum FaceBackendWarmupState { checking, warmingUp, ready, unavailable }

class FaceBackendWarmupInfo {
  final FaceBackendWarmupState state;
  final String message;

  const FaceBackendWarmupInfo({
    required this.state,
    required this.message,
  });
}

class FaceAttendanceApi {
  static const String baseUrl = String.fromEnvironment(
    'FACE_API_BASE_URL',
    defaultValue: 'https://susageo-face-backend.onrender.com',
  );

  static const FaceBackendWarmupInfo initialWarmupInfo = FaceBackendWarmupInfo(
    state: FaceBackendWarmupState.checking,
    message: 'Checking face backend...',
  );

  static bool get usesRender => baseUrl.contains('onrender.com');

  static Future<FaceBackendWarmupInfo> checkServerWarmup() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return const FaceBackendWarmupInfo(
          state: FaceBackendWarmupState.ready,
          message: 'Face backend ready',
        );
      }

      if (usesRender &&
          <int>{408, 429, 500, 502, 503, 504}.contains(response.statusCode)) {
        return const FaceBackendWarmupInfo(
          state: FaceBackendWarmupState.warmingUp,
          message: 'Render server is warming up...',
        );
      }

      if (!usesRender &&
          <int>{408, 429, 500, 502, 503, 504}.contains(response.statusCode)) {
        return const FaceBackendWarmupInfo(
          state: FaceBackendWarmupState.warmingUp,
          message: 'Face backend is starting...',
        );
      }

      return FaceBackendWarmupInfo(
        state: FaceBackendWarmupState.unavailable,
        message: 'Face backend unavailable (${response.statusCode}).',
      );
    } on TimeoutException {
      return FaceBackendWarmupInfo(
        state: FaceBackendWarmupState.warmingUp,
        message: usesRender
            ? 'Render server is warming up...'
            : 'Face backend is starting...',
      );
    } catch (_) {
      return FaceBackendWarmupInfo(
        state: usesRender
            ? FaceBackendWarmupState.warmingUp
            : FaceBackendWarmupState.warmingUp,
        message: usesRender
            ? 'Render server is warming up...'
            : 'Face backend is starting...',
      );
    }
  }

  static Future<FaceApiResponse> registerFace({
    required String imagePath,
    required String employeeId,
    required String employeeName,
    String? sampleKey,
    bool replaceExisting = false,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/register'),
      )
        ..fields['empId'] = employeeId
        ..fields['name'] = employeeName
        ..fields['replaceExisting'] = replaceExisting.toString()
        ..files.add(
          await http.MultipartFile.fromPath(
            'image',
            imagePath,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      if (sampleKey != null && sampleKey.trim().isNotEmpty) {
        request.fields['sampleKey'] = sampleKey.trim();
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final payload = _decodePayload(body);

      if (response.statusCode == 200) {
        return FaceApiResponse(
          success: true,
          message: _extractMessage(
            payload,
            'Face registered successfully.',
          ),
          employeeId: employeeId,
          employeeName: employeeName,
        );
      }

      return FaceApiResponse(
        success: false,
        message: _extractMessage(
          payload,
          'Face registration failed.',
        ),
      );
    } catch (_) {
      return FaceApiResponse(
        success: false,
        message:
            'Could not connect to the face server. Please check the backend URL and server status.',
      );
    }
  }

  static Future<FaceApiResponse> verifyFace({
    required String imagePath,
    String? expectedEmployeeId,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/recognize'),
      )..files.add(
          await http.MultipartFile.fromPath(
            'image',
            imagePath,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final payload = _decodePayload(body);

      if (response.statusCode == 200) {
        final matchedEmployeeId = payload['empId']?.toString();
        final trimmedExpectedEmployeeId = expectedEmployeeId?.trim() ?? '';
        if (trimmedExpectedEmployeeId.isNotEmpty &&
            matchedEmployeeId != trimmedExpectedEmployeeId) {
          return FaceApiResponse(
            success: false,
            employeeId: matchedEmployeeId,
            employeeName: payload['name']?.toString(),
            timestamp: payload['timestamp']?.toString(),
            message:
                'This selfie matched a different employee. Please retry with the correct user.',
          );
        }

        return FaceApiResponse(
          success: true,
          employeeId: matchedEmployeeId,
          employeeName: payload['name']?.toString(),
          timestamp: payload['timestamp']?.toString(),
          message: _extractMessage(
            payload,
            'Face verified successfully.',
          ),
        );
      }

      return FaceApiResponse(
        success: false,
        message: _extractMessage(
          payload,
          'Face verification failed.',
        ),
      );
    } catch (_) {
      return FaceApiResponse(
        success: false,
        message:
            'Could not connect to the face server. Please check the backend URL and server status.',
      );
    }
  }

  static Future<FaceApiGroupResponse> verifyGroupFaces({
    required String imagePath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/recognize-group'),
      )..files.add(
          await http.MultipartFile.fromPath(
            'image',
            imagePath,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final payload = _decodePayload(body);
      final rawMatches = payload['matches'];
      final rawDetections = payload['detections'];
      final matches = rawMatches is List
          ? rawMatches
              .whereType<Map>()
              .map(
                (rawMatch) => FaceApiGroupMatch(
                  employeeId: rawMatch['empId']?.toString() ?? '',
                  employeeName: rawMatch['name']?.toString() ?? '',
                  confidence: double.tryParse(
                    rawMatch['confidence']?.toString() ?? '',
                  ),
                  matched: rawMatch['matched'] == true ||
                      (rawMatch['empId']?.toString().isNotEmpty ?? false),
                  box: _parseBox(rawMatch['box']),
                ),
              )
              .where((match) => match.employeeId.isNotEmpty)
              .toList()
          : <FaceApiGroupMatch>[];
      final detections = rawDetections is List
          ? rawDetections
              .whereType<Map>()
              .map(
                (rawMatch) => FaceApiGroupMatch(
                  employeeId: rawMatch['empId']?.toString() ?? '',
                  employeeName: rawMatch['name']?.toString() ?? '',
                  confidence: double.tryParse(
                    rawMatch['confidence']?.toString() ?? '',
                  ),
                  matched: rawMatch['matched'] == true ||
                      (rawMatch['empId']?.toString().isNotEmpty ?? false),
                  box: _parseBox(rawMatch['box']),
                ),
              )
              .toList()
          : matches;

      if (response.statusCode == 200) {
        return FaceApiGroupResponse(
          success: true,
          message: _extractMessage(
            payload,
            'Face group verified successfully.',
          ),
          matches: matches,
          detections: detections,
        );
      }

      return FaceApiGroupResponse(
        success: false,
        message: _extractMessage(
          payload,
          'Group face verification failed.',
        ),
        matches: matches,
        detections: detections,
      );
    } catch (_) {
      return const FaceApiGroupResponse(
        success: false,
        message:
            'Could not connect to the face server. Please check the backend URL and server status.',
        matches: <FaceApiGroupMatch>[],
        detections: <FaceApiGroupMatch>[],
      );
    }
  }

  static Map<String, double> _parseBox(dynamic rawBox) {
    if (rawBox is Map) {
      return {
        'x': double.tryParse(rawBox['x']?.toString() ?? '') ?? 0,
        'y': double.tryParse(rawBox['y']?.toString() ?? '') ?? 0,
        'width': double.tryParse(rawBox['width']?.toString() ?? '') ?? 0,
        'height': double.tryParse(rawBox['height']?.toString() ?? '') ?? 0,
      };
    }
    return const {
      'x': 0,
      'y': 0,
      'width': 0,
      'height': 0,
    };
  }

  static Map<String, dynamic> _decodePayload(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{'message': body};
  }

  static String _extractMessage(
    Map<String, dynamic> payload,
    String fallback,
  ) {
    final dynamic message = payload['message'] ?? payload['error'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
    return fallback;
  }
}
