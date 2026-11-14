import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/ble/challenge_crypto.dart';
import 'package:amrita_ble_attendance/ble/ble_constants.dart';

void main() {
  group('Cryptographic Cross-Platform Test Vectors between Python and Flutter', () {
    final testVectors = [
      {
        'secret': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        'sessionId': '550e8400-e29b-41d4-a716-446655440000',
        'step': 58000000,
        'expectedChallenge': '3a7bb516e37fe7d07c3d9d400e404434',
        'expectedUuid': '3a7bb516-e37f-e7d0-7c3d-9d400e404434',
      },
      {
        'secret': 'a7f92b4c81d3e5f60123456789abcdefa7f92b4c81d3e5f60123456789abcdef',
        'sessionId': 'e2e00000-0000-0000-0000-000000000001',
        'step': 100000000,
        'expectedChallenge': 'a5ff3c823f09f3eee7d34ea41b13c80c',
        'expectedUuid': 'a5ff3c82-3f09-f3ee-e7d3-4ea41b13c80c',
      },
      {
        'secret': 'deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef',
        'sessionId': '77777777-8888-9999-aaaa-bbbbccccdddd',
        'step': 999999999,
        'expectedChallenge': '323214f238d073724db658924c7142e2',
        'expectedUuid': '323214f2-38d0-7372-4db6-58924c7142e2',
      },
    ];

    for (var i = 0; i < testVectors.length; i++) {
      test('Test Vector ${i + 1} matches Python backend bit-for-bit', () {
        final vec = testVectors[i];
        final derived = ChallengeCrypto.computeChallenge(
          sessionSecret: vec['secret'] as String,
          sessionId: vec['sessionId'] as String,
          step: vec['step'] as int,
        );

        // 1. Verify 128-bit challenge hex output
        expect(derived, vec['expectedChallenge']);
        expect(derived.length, 32);

        // 2. Verify UUID formatting
        final formattedUuid = ChallengeCrypto.formatAsUuid(derived);
        expect(formattedUuid, vec['expectedUuid']);

        // 3. Verify BleConstants extraction
        final extracted = BleConstants.extractChallenge(formattedUuid);
        expect(extracted, vec['expectedChallenge']);
      });
    }
  });
}
