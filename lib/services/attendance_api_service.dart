import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AttendanceApiResponse {
  final bool isSuccess;
  final String attendanceId;
  final String sessionId;
  final String studentId;
  final String status;
  final String method;
  final DateTime verifiedAt;
  final bool alreadyMarked;
  final bool signatureVerified;
  final String message;
  final String? errorMessage;
  final int? statusCode;

  AttendanceApiResponse({
    required this.isSuccess,
    this.attendanceId = '',
    this.sessionId = '',
    this.studentId = '',
    this.status = '',
    this.method = '',
    DateTime? verifiedAt,
    this.alreadyMarked = false,
    this.signatureVerified = false,
    this.message = '',
    this.errorMessage,
    this.statusCode,
  }) : verifiedAt = verifiedAt ?? DateTime.now();

  factory AttendanceApiResponse.fromJson(Map<String, dynamic> json) {
    return AttendanceApiResponse(
      isSuccess: true,
      attendanceId: json['attendance_id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      studentId: json['student_id'] as String? ?? '',
      status: json['status'] as String? ?? 'present',
      method: json['method'] as String? ?? 'ble_signed_nonce',
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      alreadyMarked: json['already_marked'] as bool? ?? false,
      signatureVerified: json['signature_verified'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }

  factory AttendanceApiResponse.failure(String message, {int? statusCode}) {
    return AttendanceApiResponse(
      isSuccess: false,
      errorMessage: message,
      statusCode: statusCode,
    );
  }
}

class AttendanceApiService {
  final String _baseUrl;
  final FirebaseAuth _auth;
  final HttpClient _client;

  AttendanceApiService({
    String? baseUrl,
    FirebaseAuth? auth,
    HttpClient? client,
  })  : _baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
        _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? HttpClient();

  static String _resolveDefaultBaseUrl() {
    // Android emulator loops back to host 10.0.2.2; real device/web uses localhost or LAN IP
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  Future<AttendanceApiResponse> submitProximityCheckIn({
    required String sessionId,
    required String ephemeralNonce,
    required int observedRssi,
    String? signature,
    String? publicKeyFingerprint,
    int? clientTimestamp,
  }) async {
    final timestamp = clientTimestamp ?? DateTime.now().millisecondsSinceEpoch;
    final token = await _auth.currentUser?.getIdToken();

    final url = Uri.parse('$_baseUrl/api/v1/attendance/check-in');

    try {
      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final payload = {
        'session_id': sessionId,
        'ephemeral_nonce': ephemeralNonce,
        'observed_rssi': observedRssi,
        'client_timestamp': timestamp,
        if (signature != null) 'signature': signature,
        if (publicKeyFingerprint != null) 'public_key_fingerprint': publicKeyFingerprint,
      };

      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(const Duration(seconds: 12));

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        return AttendanceApiResponse.fromJson(decoded);
      } else {
        String detailMessage = 'Server returned HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(responseBody);
          if (errJson is Map && errJson.containsKey('detail')) {
            detailMessage = errJson['detail'].toString();
          }
        } catch (_) {}
        return AttendanceApiResponse.failure(detailMessage, statusCode: response.statusCode);
      }
    } on SocketException catch (e) {
      return AttendanceApiResponse.failure('Network connection failed: ${e.message}');
    } on HandshakeException catch (e) {
      return AttendanceApiResponse.failure('Secure handshake failed: ${e.message}');
    } catch (e) {
      return AttendanceApiResponse.failure('Check-in communication failed: $e');
    }
  }
}

final attendanceApiServiceProvider = Provider<AttendanceApiService>((ref) {
  return AttendanceApiService();
});
