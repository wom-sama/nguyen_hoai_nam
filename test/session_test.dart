import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';

class MemoryStore implements SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession next) async {
    value = next;
  }
}

final userJson = <String, dynamic>{
  'id': 'employee-1',
  'fullName': 'Nhân viên kiểm thử',
  'username': 'nhanvien',
  'email': 'staff@example.com',
  'role': 'employee',
  'status': 'active',
  'branchId': 'branch-1',
  'createdAt': '2026-10-29T00:00:00Z',
};
http.Response reply(dynamic data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test('Password alone never authenticates; OTP failure keeps credentials out of storage', () async {
    final store = MemoryStore();
    final api = ApiClient(
      baseUrl: 'https://attendance.example.com',
      transport: MockClient((req) async {
        if (req.url.path == '/v1/auth/login') {
          return reply({
            'challengeId': 'challenge-1',
            'maskedEmail': 's***@example.com',
            'expiresAt': '2099-10-29T00:10:00Z',
            'retryAfterSeconds': 60,
            'purpose': 'login',
          });
        }
        if (req.url.path == '/v1/auth/verify-otp') {
          final body = jsonDecode(req.body) as Map;
          if (body['code'] != '123456') {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 'OTP_INVALID',
                  'message': 'Mã OTP không đúng.',
                },
              }),
              400,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return reply({
            'accessToken': 'access-after-otp',
            'refreshToken': 'refresh-after-otp',
            'user': userJson,
          });
        }
        return http.Response('{}', 404);
      }),
    );
    final session = SessionController(api: api, store: store);
    expect(await session.login('nhanvien', 'a-real-long-password'), isTrue);
    expect(session.user, isNull);
    expect(session.challenge?.id, 'challenge-1');
    expect(api.accessToken, isNull);
    expect(store.value?.accessToken, isNull);
    expect(await session.verifyOtp('000000'), isFalse);
    expect(session.error, contains('OTP'));
    expect(session.user, isNull);
    expect(session.challenge?.id, 'challenge-1');
    expect(store.value?.refreshToken, isNull);
    expect(await session.verifyOtp('123456'), isTrue);
    expect(session.user?.id, 'employee-1');
    expect(api.accessToken, 'access-after-otp');
    expect(store.value?.refreshToken, 'refresh-after-otp');
    expect(session.challenge, isNull);
    session.dispose();
    api.close();
  });

  test('Expired access and rejected refresh clear stored credentials and keep server configuration', () async {
    final store = MemoryStore()
      ..value = const StoredSession(
        baseUrl: 'https://attendance.example.com/v1',
        accessToken: 'expired',
        refreshToken: 'revoked',
      );
    final api = ApiClient(
      transport: MockClient(
        (req) async => http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHORIZED', 'message': 'Phiên đã hết hạn.'},
          }),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final session = SessionController(api: api, store: store);
    await session.restore();
    expect(session.user, isNull);
    expect(api.accessToken, isNull);
    expect(store.value?.refreshToken, isNull);
    expect(store.value?.baseUrl, 'https://attendance.example.com/v1');
    expect(session.restoring, isFalse);
    session.dispose();
    api.close();
  });

  test('API configuration rejects local addresses and credentials in URLs', () {
    for (final value in [
      'http://public.example.com',
      'https://localhost',
      'https://127.0.0.1',
      'https://10.0.2.2',
      'https://192.168.1.3',
      'https://172.20.0.1',
      'https://[::1]',
      'https://[fc00::1]',
      'https://user:password@public.example.com',
    ]) {
      expect(
        () => ApiClient.validateUrl(value),
        throwsA(isA<ApiException>()),
        reason: value,
      );
    }
    expect(
      ApiClient.validateUrl('https://ca-lam.onrender.com/'),
      'https://ca-lam.onrender.com/v1',
    );
  });
}
