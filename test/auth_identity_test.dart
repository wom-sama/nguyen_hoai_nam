import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/main.dart';

class _Store implements SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession next) async {
    value = next;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
http.Response reply(Object value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object> challenge(String purpose, {int retry = 0}) => {
  'challengeId': 'bound-alice',
  'maskedEmail': 'a***@example.com',
  'expiresAt': '2099-10-29T00:10:00Z',
  'retryAfterSeconds': retry,
  'purpose': purpose,
};
Future<void> showApp(WidgetTester tester, SessionController session) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AttendanceApp(session: session));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'login freezes submitted identity while waiting for its OTP challenge',
    (tester) async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'https://attendance.example.com',
        transport: MockClient((_) => response.future),
      );
      final session = SessionController(api: api, store: _Store());
      try {
        await showApp(tester, session);
        await tester.enterText(field('Tên đăng nhập'), 'alice');
        await tester.enterText(field('Mật khẩu'), 'long-password');
        await tester.tap(find.widgetWithText(FilledButton, 'Tiếp tục'));
        await tester.pump();
        expect(
          tester.widget<TextField>(field('Tên đăng nhập')).enabled,
          isFalse,
        );
        expect(tester.widget<TextField>(field('Mật khẩu')).enabled, isFalse);
        response.complete(reply(challenge('login')));
        await tester.pumpAndSettle();
        expect(find.textContaining('alice'), findsOneWidget);
        expect(find.text('Xác nhận đăng nhập'), findsOneWidget);
        expect(find.textContaining('a***@example.com'), findsOneWidget);
      } finally {
        if (!response.isCompleted) response.complete(reply(challenge('login')));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        session.dispose();
        api.close();
      }
    },
  );

  testWidgets(
    'registration and resend keep account context and server cooldown',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'https://attendance.example.com',
        transport: MockClient((request) async {
          requests.add({
            'path': request.url.path,
            ...jsonDecode(request.body) as Map<String, dynamic>,
          });
          return reply(
            challenge(
              'register',
              retry: request.url.path.endsWith('/resend-otp') ? 120 : 0,
            ),
          );
        }),
      );
      final session = SessionController(api: api, store: _Store());
      try {
        await showApp(tester, session);
        await tester.tap(find.text('Đăng ký tài khoản'));
        await tester.pumpAndSettle();
        await tester.enterText(field('Họ và tên'), 'Alice Kiểm Thử');
        await tester.enterText(field('Email'), 'alice@example.com');
        await tester.enterText(field('Tên đăng nhập'), 'alice');
        await tester.enterText(field('Mật khẩu'), 'long-password');
        await tester.enterText(field('Nhập lại mật khẩu'), 'long-password');
        final create = find.widgetWithText(FilledButton, 'Tạo tài khoản');
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(find.text('Xác nhận đăng ký'), findsOneWidget);
        expect(find.textContaining('alice'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '112233');
        await tester.tap(find.text('Gửi lại mã OTP'));
        await tester.pumpAndSettle();
        expect(requests.last, {
          'path': '/v1/auth/resend-otp',
          'challengeId': 'bound-alice',
        });
        expect(find.textContaining('alice'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        final wait = find.textContaining('Gửi lại sau');
        final seconds = int.parse(
          RegExp(r'\d+').firstMatch(tester.widget<Text>(wait).data!)!.group(0)!,
        );
        expect(seconds, greaterThanOrEqualTo(115));
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        session.dispose();
        api.close();
      }
    },
  );
}
