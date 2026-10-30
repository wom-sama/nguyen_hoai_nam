import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';

Json person(String name) => {
  'id': name,
  'fullName': name,
  'username': name,
  'email': '$name@example.com',
  'role': 'employee',
  'status': 'active',
  'branchId': 'branch-test',
};
http.Response data(Object? value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response rejected() => http.Response(
  jsonEncode({
    'error': {'code': 'UNAUTHORIZED', 'message': 'Phiên đã hết hạn.'},
  }),
  401,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json challenge(String name) => {
  'challengeId': name,
  'maskedEmail': '$name***@example.com',
  'expiresAt': '2099-10-29T00:10:00Z',
  'retryAfterSeconds': 60,
  'purpose': 'login',
};
Json tokens(String name) => {
  'accessToken': 'access-$name',
  'refreshToken': 'refresh-$name',
  'user': person(name),
};

class _Store implements SessionStore {
  StoredSession? value;
  Completer<void>? aliceWrite;
  final aliceStarted = Completer<void>();
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession next) async {
    if (next.accessToken == 'access-alice' && aliceWrite != null) {
      if (!aliceStarted.isCompleted) aliceStarted.complete();
      await aliceWrite!.future;
    }
    value = next;
  }
}

void main() {
  test(
    'canceled OTP write cannot overwrite the next account in secure storage',
    () async {
      final store = _Store()..aliceWrite = Completer<void>();
      final bobRequested = Completer<void>();
      final api = ApiClient(
        baseUrl: 'https://attendance.example.com',
        transport: MockClient((request) async {
          final body = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Map;
          if (request.url.path.endsWith('/login')) {
            return data(challenge(body['username'] as String));
          }
          if (request.url.path.endsWith('/verify-otp')) {
            final name = body['challengeId'] as String;
            if (name == 'bob') bobRequested.complete();
            return data(tokens(name));
          }
          if (request.url.path.endsWith('/me')) {
            return data(
              person(
                request.headers['authorization'] == 'Bearer access-bob'
                    ? 'bob'
                    : 'alice',
              ),
            );
          }
          return data(null);
        }),
      );
      final session = SessionController(api: api, store: store);
      await session.login('alice', 'long-password');
      final alice = session.verifyOtp('123456');
      await store.aliceStarted.future;
      session.cancelChallenge();
      await session.login('bob', 'long-password');
      final bob = session.verifyOtp('123456');
      await bobRequested.future;
      // Let Bob's response reach storage before releasing Alice's older write.
      await Future<void>.delayed(Duration.zero);
      store.aliceWrite!.complete();
      await Future.wait([alice, bob]);
      expect(session.user?.id, 'bob');
      expect(store.value?.accessToken, 'access-bob');
      final restored = SessionController(api: api, store: store);
      await restored.restore();
      expect(restored.user?.id, 'bob');
      restored.dispose();
      session.dispose();
      api.close();
    },
  );

  test(
    'late rejected refresh from the previous account cannot clear a new login',
    () async {
      final refreshStarted = Completer<void>(),
          refreshReply = Completer<http.Response>();
      final store = _Store()
        ..value = const StoredSession(
          baseUrl: 'https://attendance.example.com/v1',
          accessToken: 'access-alice',
          refreshToken: 'refresh-alice',
        );
      final api = ApiClient(
        baseUrl: 'https://attendance.example.com',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/protected')) return rejected();
          if (request.url.path.endsWith('/refresh')) {
            refreshStarted.complete();
            return refreshReply.future;
          }
          if (request.url.path.endsWith('/login')) {
            return data(challenge('bob'));
          }
          if (request.url.path.endsWith('/verify-otp')) {
            return data(tokens('bob'));
          }
          return data(null);
        }),
      )..accessToken = 'access-alice';
      final session = SessionController(api: api, store: store)
        ..user = AppUser.fromJson(person('alice'));
      final request = api
          .get('/protected')
          .then<Object?>((value) => value, onError: (Object error) => error);
      await refreshStarted.future;
      await session.logout();
      await session.login('bob', 'long-password');
      await session.verifyOtp('123456');
      refreshReply.complete(rejected());
      expect(await request, isA<ApiException>());
      expect(session.user?.id, 'bob');
      expect(api.accessToken, 'access-bob');
      expect(store.value?.refreshToken, 'refresh-bob');
      session.dispose();
      api.close();
    },
  );

  test(
    'late restore profile cannot replace the account established after logout',
    () async {
      final profileStarted = Completer<void>(),
          profileReply = Completer<http.Response>();
      final store = _Store()
        ..value = const StoredSession(
          baseUrl: 'https://attendance.example.com/v1',
          accessToken: 'access-alice',
          refreshToken: 'refresh-alice',
        );
      final api = ApiClient(
        baseUrl: 'https://attendance.example.com',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/me')) {
            profileStarted.complete();
            return profileReply.future;
          }
          if (request.url.path.endsWith('/login')) {
            return data(challenge('bob'));
          }
          if (request.url.path.endsWith('/verify-otp')) {
            return data(tokens('bob'));
          }
          return data(null);
        }),
      );
      final session = SessionController(api: api, store: store);
      final restore = session.restore();
      await profileStarted.future;
      await session.logout();
      await session.login('bob', 'long-password');
      await session.verifyOtp('123456');
      profileReply.complete(data(person('alice')));
      await restore;
      expect(session.user?.id, 'bob');
      expect(store.value?.accessToken, 'access-bob');
      expect(session.restoring, isFalse);
      session.dispose();
      api.close();
    },
  );
}
