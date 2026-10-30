import 'dart:convert';

import 'package:biometric_signature/biometric_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/features/auth/device_biometrics.dart';

/// Platform fixtures validate orchestration only, never native biometrics.
class _Biometric extends BiometricSignature {
  bool supported = true, cancel = false;
  final keys = <String, KeyInfo>{};
  final deleted = <String>[];
  int creates = 0, signs = 0;
  @override
  Future<BiometricAvailability> biometricAuthAvailable({
    BiometricStrength biometricStrength = BiometricStrength.strong,
  }) async => BiometricAvailability(
    canAuthenticate: supported,
    hasEnrolledBiometrics: supported,
    availableBiometrics: supported ? [BiometricType.fingerprint] : [],
  );
  @override
  Future<KeyInfo> getKeyInfo({
    String? keyAlias,
    bool checkValidity = false,
    KeyFormat keyFormat = KeyFormat.base64,
  }) async => keys[keyAlias] ?? KeyInfo(exists: false);
  @override
  Future<KeyCreationResult> createKeys({
    String? keyAlias,
    CreateKeysConfig? config,
    KeyFormat keyFormat = KeyFormat.base64,
    String? promptMessage,
  }) async {
    expect(config!.requireAuthentication, isTrue);
    expect(config.useDeviceCredentials, isFalse);
    expect(config.failIfExists, isTrue);
    creates++;
    keys[keyAlias!] = KeyInfo(
      exists: true,
      isValid: true,
      publicKey: 'PUBLIC TEST KEY $keyAlias',
      requiresAuthentication: true,
      allowsDeviceCredentials: false,
      invalidatedByBiometricEnrollment: true,
    );
    return KeyCreationResult(
      code: BiometricError.success,
      publicKey: keys[keyAlias]!.publicKey,
    );
  }

  @override
  Future<SignatureResult> createSignature({
    required String payload,
    String? keyAlias,
    CreateSignatureConfig? config,
    SignatureFormat signatureFormat = SignatureFormat.base64,
    KeyFormat keyFormat = KeyFormat.base64,
    String? promptMessage,
  }) async {
    expect(config!.allowDeviceCredentials, isFalse);
    signs++;
    return cancel
        ? SignatureResult(code: BiometricError.userCanceled)
        : SignatureResult(
            code: BiometricError.success,
            signature: base64Encode(List.filled(256, 7)),
            authenticationType: AuthenticationType.biometric,
          );
  }

  @override
  Future<bool> deleteKeys({String? keyAlias}) async {
    deleted.add(keyAlias!);
    keys.remove(keyAlias);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Biometric biometric;
  late DeviceBiometrics device;
  late ApiClient api;
  late Map<String, String> metadata;
  late List<String> calls;
  bool canEnroll = true;
  bool registered = true;
  String account = 'nam';
  const challengeId = 'd7af7dd6-a476-4c9e-b6d3-ff8e024ff972';
  setUp(() {
    biometric = _Biometric();
    metadata = {};
    calls = [];
    canEnroll = true;
    registered = true;
    account = 'nam';
    device = DeviceBiometrics(
      biometric: biometric,
      readMetadata: (key) async => metadata[key],
      writeMetadata: (key, value) async {
        metadata[key] = value;
      },
      deleteMetadata: (key) async {
        metadata.remove(key);
      },
    );
    api = ApiClient(
      baseUrl: 'https://api.example.test',
      transport: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        Object data;
        if (request.url.path.endsWith('/fingerprint/status')) {
          data = {
            'registered': registered,
            'canEnroll': canEnroll,
            'username': account,
            'device': {'id': challengeId},
          };
        } else if (request.url.path.endsWith('/fingerprint/enroll')) {
          data = {'id': challengeId, 'deviceId': body['deviceId']};
        } else if (request.url.path.endsWith('/fingerprint/challenge')) {
          data = {
            'challengeId': challengeId,
            'payload':
                'HN-FINGERPRINT-V1\nserver\n$challengeId\nuser\n${body['deviceId']}\nnonce',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 2))
                .toIso8601String(),
          };
        } else if (request.url.path.endsWith('/fingerprint/verify')) {
          data = {
            'accessToken': 'direct-access',
            'refreshToken': 'direct-refresh',
            'user': {'username': account},
          };
        } else {
          data = {'revoked': true};
        }
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() => api.close());
  test(
    'unsupported devices never create keys or send an enrollment request',
    () async {
      biometric.supported = false;
      expect(await device.isSupported(), isFalse);
      await expectLater(
        device.enroll(api, 'nam'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, isEmpty);
      expect(biometric.creates, 0);
    },
  );
  test(
    'fresh password-OTP preflight happens before creating a biometric key',
    () async {
      canEnroll = false;
      await expectLater(
        device.enroll(api, 'nam'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'FINGERPRINT_REAUTH_REQUIRED',
          ),
        ),
      );
      expect(biometric.creates, 0);
    },
  );
  test(
    'canceling the OS prompt never sends verify or fabricates a session',
    () async {
      await device.enroll(api, ' Nam ');
      biometric.cancel = true;
      await expectLater(
        device.login(api, 'NAM'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'BIOMETRIC_CANCELED',
          ),
        ),
      );
      expect(
        calls.where((value) => value.endsWith('/fingerprint/verify')),
        isEmpty,
      );
    },
  );
  test(
    'signature login returns a direct session without an OTP endpoint',
    () async {
      await device.enroll(api, 'nam');
      final session = await device.login(api, 'nam');
      expect(session['accessToken'], 'direct-access');
      expect(session['challengeId'], isNull);
      expect(calls.any((value) => value.contains('otp')), isFalse);
      expect(biometric.signs, 1);
    },
  );
  test(
    'server revocation and a replaced local key invalidate setup readiness',
    () async {
      await device.enroll(api, 'nam');
      expect(await device.isRegistered(api, 'nam'), isTrue);
      registered = false;
      expect(await device.isRegistered(api, 'nam'), isFalse);
      registered = true;
      final key = biometric.keys.values.single;
      key.publicKey = 'REPLACED PUBLIC KEY';
      expect(await device.hasRegistration('nam'), isFalse);
    },
  );
  test('per-account aliases preserve other keys and re-enrollment never overwrites a valid key', () async {
    await device.enroll(api, 'nam');
    final first = biometric.keys.keys.single;
    await device.enroll(api, 'nam');
    expect(biometric.creates, 1);
    account = 'other';
    await device.enroll(api, 'other');
    expect(biometric.keys, hasLength(2));
    await device.revoke(api, 'other');
    expect(biometric.keys.keys, [first]);
    expect(await device.hasRegistration('nam'), isTrue);
    expect(await device.hasRegistration('other'), isFalse);
  });
}
