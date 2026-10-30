import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/auth/biometric_setup.dart';
import 'package:nguyen_hoai_nam/features/auth/auth_screen.dart';
import 'package:nguyen_hoai_nam/features/account/account_screen.dart';
import 'package:nguyen_hoai_nam/features/settings/settings_screen.dart';
import 'package:nguyen_hoai_nam/main.dart';

class _Store implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession value) async {}
}

class _Fixture {
  bool faceEnrolled = true, failFace = false;
  int version = 1, profileReads = 0, faceReads = 0;
  double fontScale = 1.2;
  String primary = '#246B4A';
  final paths = <String>[];
  Json get user => {
    'id': 'alice',
    'fullName': 'Alice',
    'username': 'alice',
    'email': 'alice@example.test',
    'role': 'employee',
    'status': 'active',
    'branchId': 'branch',
    'profileVersion': version,
  };
  http.Response reply(Object? data) => http.Response(
    jsonEncode({'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  late final api = ApiClient(
    baseUrl: 'https://attendance.example.test',
    transport: MockClient((request) async {
      final path = request.url.path;
      paths.add(path);
      if (path.endsWith('/me')) return reply(user);
      if (path.endsWith('/me/profile')) {
        profileReads++;
        return reply({
          ...user,
          'phone': '',
          'address': '',
          'avatarBase64': null,
          'appearance': {
            'fontScale': fontScale,
            'textColor': '#213547',
            'primaryColor': primary,
            'backgroundBase64': null,
          },
        });
      }
      if (path.endsWith('/face/status')) {
        faceReads++;
        if (failFace) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY',
                'message': 'Chưa kiểm tra được đăng ký khuôn mặt.',
              },
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return reply({'enrolled': faceEnrolled, 'enrolledAt': null});
      }
      return reply([]);
    }),
  )..accessToken = 'fixture-access';
  late final session = SessionController(api: api, store: _Store())
    ..user = AppUser.fromJson(user);
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AttendanceApp(session: session, enableAccountSettings: true),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    session.dispose();
    api.close();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('vi'));

  testWidgets(
    'production settings mode passes a registered face and applies saved appearance to real app routes',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        expect(find.byType(BiometricSetupGate), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('Đăng ký đăng nhập nhanh'), findsNothing);
        final navigationContext = tester.element(find.byType(NavigationBar));
        expect(
          Theme.of(navigationContext).colorScheme.primary,
          const Color(0xFF246B4A),
        );
        expect(
          MediaQuery.textScalerOf(navigationContext).scale(10),
          closeTo(12, .001),
        );
        expect(fixture.profileReads, 1);
        expect(fixture.faceReads, 1);
        await tester.tap(find.text('Tài khoản'));
        await tester.pumpAndSettle();
        final settings = find.text('Cài đặt và hồ sơ');
        final accountScroll = find
            .descendant(
              of: find.byType(AccountScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          settings.hitTestable(),
          180,
          scrollable: accountScroll,
        );
        await tester.tap(settings.hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(SettingsHubScreen), findsOneWidget);
        expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
        expect(find.text('Giao diện'), findsOneWidget);
        expect(fixture.profileReads, 1);
        expect(fixture.paths.where((path) => path.contains('/auth/')), isEmpty);
        expect(find.byType(OtpScreen), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'production gate blocks unregistered users until server confirms enrollment without native camera calls',
    (tester) async {
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      var storageReads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (
        call,
      ) async {
        if (call.method == 'read') storageReads++;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          storage,
          null,
        ),
      );
      final fixture = _Fixture()..faceEnrolled = false;
      try {
        await fixture.open(tester);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('Đăng ký đăng nhập nhanh'), findsOneWidget);
        expect(find.text('Đăng ký khuôn mặt'), findsOneWidget);
        expect(find.text('Đăng ký vân tay thiết bị'), findsOneWidget);
        expect(storageReads, 1);
        fixture.faceEnrolled = true;
        await tester.tap(find.text('Kiểm tra lại'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(fixture.faceReads, 2);
        expect(
          fixture.paths.where((path) => path.endsWith('/face/enroll')),
          isEmpty,
        );
        expect(
          fixture.paths.where((path) => path.contains('/fingerprint/')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'production gate shows a failed status check and retries without sending a new OTP',
    (tester) async {
      final fixture = _Fixture()..failFace = true;
      try {
        await fixture.open(tester);
        expect(
          find.text('Chưa kiểm tra được đăng ký khuôn mặt.'),
          findsOneWidget,
        );
        expect(find.byType(NavigationBar), findsNothing);
        fixture.failFace = false;
        await tester.tap(find.text('Kiểm tra lại'));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(fixture.paths.where((path) => path.contains('/auth/')), isEmpty);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'profile version changes refresh full appearance once without fetching images on every profile poll',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        expect(fixture.profileReads, 1);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 1);
        fixture.version = 2;
        fixture.fontScale = .9;
        fixture.primary = '#61419C';
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 2);
        final navigationContext = tester.element(find.byType(NavigationBar));
        expect(
          Theme.of(navigationContext).colorScheme.primary,
          const Color(0xFF61419C),
        );
        expect(
          MediaQuery.textScalerOf(navigationContext).scale(10),
          closeTo(9, .001),
        );
        await tester.pump(const Duration(seconds: 20));
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 2);
        expect(fixture.faceReads, 1);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
