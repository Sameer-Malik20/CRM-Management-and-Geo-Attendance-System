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

class FaceDetectionMatch {
  final String employeeId;
  final String employeeName;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  FaceDetectionMatch({
    required this.employeeId,
    required this.employeeName,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class GroupFaceApiResponse {
  final bool success;
  final String message;
  final List<FaceDetectionMatch> matches;

  GroupFaceApiResponse({
    required this.success,
    required this.message,
    required this.matches,
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

      return FaceBackendWarmupInfo(
        state: FaceBackendWarmupState.unavailable,
        message: 'Face backend unavailable (${response.statusCode}).',
      );
    } on TimeoutException {
      return FaceBackendWarmupInfo(
        state: usesRender
            ? FaceBackendWarmupState.warmingUp
            : FaceBackendWarmupState.unavailable,
        message: usesRender
            ? 'Render server is warming up...'
            : 'Face backend request timed out.',
      );
    } catch (_) {
      return FaceBackendWarmupInfo(
        state: usesRender
            ? FaceBackendWarmupState.warmingUp
            : FaceBackendWarmupState.unavailable,
        message: usesRender
            ? 'Render server is warming up...'
            : 'Face backend unavailable.',
      );
    }
  }

  static Future<FaceApiResponse> registerFace({
    required String imagePath,
    required String employeeId,
    required String employeeName,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/register'),
      )
        ..fields['empId'] = employeeId
        ..fields['name'] = employeeName
        ..files.add(
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
    required String expectedEmployeeId,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/recognize'),
      )
        ..files.add(
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
        if (matchedEmployeeId != expectedEmployeeId) {
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

  static Future<GroupFaceApiResponse> recognizeGroup({
    required String imagePath,
    List<String> expectedEmployeeIds = const [],
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/recognize-group'),
      )
        ..fields['expectedEmpIds'] = expectedEmployeeIds.join(',')
        ..files.add(
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
      final matches = <FaceDetectionMatch>[];

      if (rawMatches is List) {
        for (final item in rawMatches) {
          if (item is Map) {
            matches.add(
              FaceDetectionMatch(
                employeeId: item['empId']?.toString() ?? '',
                employeeName: item['name']?.toString() ?? '',
                confidence:
                    double.tryParse(item['confidence']?.toString() ?? '') ?? 0,
                x: double.tryParse(item['x']?.toString() ?? '') ?? 0,
                y: double.tryParse(item['y']?.toString() ?? '') ?? 0,
                width: double.tryParse(item['w']?.toString() ?? '') ?? 0,
                height: double.tryParse(item['h']?.toString() ?? '') ?? 0,
              ),
            );
          }
        }
      }

      return GroupFaceApiResponse(
        success: response.statusCode == 200,
        message: _extractMessage(
          payload,
          response.statusCode == 200
              ? 'Faces detected successfully.'
              : 'Group recognition failed.',
        ),
        matches: matches,
      );
    } catch (_) {
      return GroupFaceApiResponse(
        success: false,
        message:
            'Could not connect to the face server. Please check the backend URL and server status.',
        matches: const [],
      );
    }
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
