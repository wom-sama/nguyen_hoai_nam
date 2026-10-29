import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/main.dart';

class _MemoryStore implements SessionStore {
  StoredSession? data;
  @override
  Future<StoredSession?> read() async => data;
  @override
  Future<void> write(StoredSession value) async {
    data = value;
  }
}

SessionController fixture({
  String role = 'employee',
  String status = 'active',
  bool withShift = false,
}) {
  return SessionController(
    store: _MemoryStore(),
    api: ApiClient(
      baseUrl: 'https://api.example.com',
      transport: MockClient((req) async {
        dynamic data;
        if (req.url.path == '/v1/auth/login') {
          data = {
            'challengeId': 'challenge-test',
            'maskedEmail': 't***@example.com',
            'expiresAt': '2099-10-29T00:10:00Z',
            'retryAfterSeconds': 60,
            'purpose': 'login',
          };
        } else if (req.url.path == '/v1/auth/verify-otp') {
          data = {
            'accessToken': 'test-access',
            'refreshToken': 'test-refresh',
            'user': {
              'id': 'staff-test',
              'fullName': 'Nhân viên kiểm thử',
              'username': 'nhanvien',
              'email': 'test@example.com',
              'role': role,
              'status': status,
              'branchId': 'branch-test',
              'createdAt': '2026-10-29T00:00:00Z',
            },
          };
        } else if (withShift && req.url.path == '/v1/shifts') {
          final start = DateTime.now().subtract(const Duration(hours: 1));
          final end = start.add(const Duration(hours: 8));
          data = [
            {
              'id': 'shift-fixture-001',
              'employeeId': 'staff-test',
              'branchId': 'branch-test',
              'title': 'Ca vận hành A',
              'startsAt': start.toUtc().toIso8601String(),
              'endsAt': end.toUtc().toIso8601String(),
              'status': 'scheduled',
              'timeWindow': {
                'checkInOpensAt': start
                    .subtract(const Duration(minutes: 30))
                    .toUtc()
                    .toIso8601String(),
                'checkInClosesAt': end.toUtc().toIso8601String(),
                'checkOutClosesAt': end
                    .add(const Duration(hours: 2))
                    .toUtc()
                    .toIso8601String(),
              },
            },
          ];
        } else if (withShift && req.url.path == '/v1/branches') {
          data = [
            {
              'id': 'branch-test',
              'name': 'Chi nhánh kiểm thử',
              'radiusMeters': 150,
            },
          ];
        } else if (req.url.path == '/v1/face/status') {
          data = {'enrolled': false, 'enrolledAt': null};
        } else {
          data = <dynamic>[];
        }
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  );
}

Future<void> pumpApp(
  WidgetTester tester,
  SessionController session,
  GlobalKey boundary,
) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: AttendanceApp(session: session),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../preview_test_$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('vi');
    final loader = FontLoader('BeVietnamPro');
    for (final file in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$file.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora-Variable.ttf'))).load();
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
  });
  testWidgets(
    'Assigned shift renders its server punch window and monthly report entry on a narrow screen',
    (tester) async {
      final session = fixture(withShift: true), boundary = GlobalKey();
      await session.login('nhanvien', 'long-password-test');
      await session.verifyOtp('123456');
      await pumpApp(tester, session, boundary);
      expect(find.text('Chấm công vào'), findsOneWidget);
      expect(find.textContaining('Nhận giờ vào'), findsOneWidget);
      expect(find.text('Chi nhánh kiểm thử'), findsOneWidget);
      await capture(tester, boundary, 'assigned_shift');
      tester.view.physicalSize = const Size(320, 760);
      await tester.pumpAndSettle();
      expect(find.text('Bảng công tháng'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
  testWidgets(
    'An employee reaches own dashboard only after OTP and never gets management navigation',
    (tester) async {
      final session = fixture(), boundary = GlobalKey();
      await pumpApp(tester, session, boundary);
      await capture(tester, boundary, 'login');
      expect(find.text('Kết nối máy chủ'), findsNothing);
      expect(find.textContaining('onrender.com'), findsNothing);
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu cần ít nhất 10 ký tự.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'nhanvien');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'long-password-test',
      );
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận và tiếp tục'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.tap(find.text('Xác nhận và tiếp tục'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Quản lý'), findsNothing);
      expect(find.text('Hôm nay chưa có ca cần chấm công'), findsOneWidget);
      await capture(tester, boundary, 'employee_home');
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Hướng dẫn sử dụng'), findsOneWidget);
      expect(find.text('Kết nối máy chủ'), findsNothing);
      expect(find.textContaining('onrender.com'), findsNothing);
      await capture(tester, boundary, 'employee_account');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
  testWidgets(
    'A pending account sees approval state rather than attendance or administrative tools',
    (tester) async {
      final session = fixture(status: 'pending'), boundary = GlobalKey();
      await session.login('nhanvien', 'long-password-test');
      await session.verifyOtp('123456');
      await pumpApp(tester, session, boundary);
      expect(find.text('Kiểm tra trạng thái'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Chấm công vào'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'pending');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
  testWidgets(
    'An admin enters management immediately after OTP without overflow',
    (tester) async {
      final session = fixture(role: 'admin'), boundary = GlobalKey();
      await session.login('admin', 'long-password-test');
      await session.verifyOtp('123456');
      await pumpApp(tester, session, boundary);
      expect(find.text('Nhân viên'), findsOneWidget);
      expect(find.text('Chi nhánh'), findsOneWidget);
      expect(find.text('Điều chỉnh công'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'admin_management');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
  testWidgets(
    'Changing tabs preserves a translation draft when reduced motion is enabled',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final session = fixture(), boundary = GlobalKey();
      await session.login('nhanvien', 'long-password-test');
      await session.verifyOtp('123456');
      await pumpApp(tester, session, boundary);
      await tester.tap(find.text('Dịch'));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Nhập nội dung cần dịch',
      );
      await tester.enterText(input, 'Bàn giao lúc 22:00');
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dịch'));
      await tester.pumpAndSettle();
      expect(find.text('Bàn giao lúc 22:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
}
