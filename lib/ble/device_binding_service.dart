import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceBindingService {
  static const String _storageKey = 'amrita_attendance_device_uuid';
  final FlutterSecureStorage _storage;
  final FirebaseFirestore _firestore;

  DeviceBindingService({
    FlutterSecureStorage? storage,
    FirebaseFirestore? firestore,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  static String generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant RFC4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Gets the local device UUID, or generates and stores one if none exists.
  Future<String> getOrCreateDeviceId() async {
    String? id = await _storage.read(key: _storageKey);
    if (id == null || id.isEmpty) {
      id = generateUuidV4();
      await _storage.write(key: _storageKey, value: id);
    }
    return id;
  }

  /// Ensures this device is bound to the student profile in Firestore.
  /// If the profile has no deviceId, sets it (allowed once by rules).
  /// If the profile has a different deviceId, returns false (mismatch).
  Future<bool> ensureDeviceBound(String studentUid, String? remoteDeviceId) async {
    final localId = await getOrCreateDeviceId();

    if (remoteDeviceId == null || remoteDeviceId.isEmpty) {
      // First-time binding: write to users/{uid}.deviceId
      try {
        await _firestore.collection('users').doc(studentUid).update({
          'deviceId': localId,
        });
        return true;
      } catch (_) {
        return false;
      }
    }

    return localId == remoteDeviceId;
  }
}

final deviceBindingServiceProvider = Provider<DeviceBindingService>((ref) {
  return DeviceBindingService();
});
