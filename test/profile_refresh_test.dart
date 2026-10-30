import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/main.dart';
import 'package:nguyen_hoai_nam/features/auth/auth_screen.dart';
import 'package:nguyen_hoai_nam/features/manage/resources_screen.dart';

class _Store implements SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession next) async {
    value = next;
  }
}

class _Fixture {
  String role = 'employee', branch = 'A', status = 'active';
  bool failProfile = false;
  Completer<http.Response>? profileReply;
  int profileReads = 0;
  Map<String, dynamic> get person => {
    'id': 'alice',
    'username': 'alice',
    'fullName': 'Alice',
    'email': 'alice@example.com',
    'role': role,
    'status': status,
    'branchId': branch,
  };
  late final api = ApiClient(
    baseUrl: 'https://attendance.example.com',
    transport: MockClient((request) async {
      Object data = [];
      if (request.url.path.endsWith('/me')) {
        profileReads++;
        if (profileReply != null) return profileReply!.future;
        if (failProfile) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY',
                'message': 'Tạm thời chưa kết nối được.',
              },
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        data = person;
      }
      if (request.url.path.endsWith('/face/status')) {
        data = {'enrolled': false, 'enrolledAt': null};
      }
      if (request.url.path.endsWith('/branches')) {
        data = [
          {'id': branch, 'name': 'Chi nhánh $branch', 'radiusMeters': 100},
        ];
      }
      if (request.url.path.endsWith('/shifts')) {
        data = [
          {
            'id': 'shift-$branch',
            'employeeId': 'alice',
            'branchId': branch,
            'title': 'Ca chi nhánh $branch',
            'startsAt': DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'endsAt': DateTime.now()
                .add(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
            'status': 'scheduled',
          },
        ];
      }
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  late final session = SessionController(api: api, store: _Store())
    ..user = AppUser.fromJson(person);
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AttendanceApp(session: session));
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
  setUpAll(() async {
    await initializeDateFormatting('vi');
  });
  testWidgets(
    'manual account refresh applies a newly granted admin role immediately',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        await tester.tap(find.text('Tài khoản'));
        await tester.pumpAndSettle();
        fixture.role = 'admin';
        final refresh = find.text('Kiểm tra quyền và trạng thái');
        expect(refresh, findsOneWidget);
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 1);
        expect(find.text('Quản trị'), findsOneWidget);
        expect(find.text('Quản lý'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  testWidgets(
    'returning from background refreshes role without a new OTP flow',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        fixture.role = 'manager';
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 1);
        expect(find.text('Điều phối ca'), findsOneWidget);
        expect(find.byType(OtpScreen), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  testWidgets(
    'branch reassignment discards cached data from the previous branch',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        expect(find.text('Ca chi nhánh A'), findsWidgets);
        fixture.branch = 'B';
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Ca chi nhánh B'), findsWidgets);
        expect(find.text('Ca chi nhánh A'), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  testWidgets(
    'foreground polling coalesces slow reads and stops while backgrounded',
    (tester) async {
      final fixture = _Fixture(), pending = Completer<http.Response>();
      fixture.profileReply = pending;
      try {
        await fixture.open(tester);
        await tester.pump(const Duration(seconds: 10));
        expect(fixture.profileReads, 1);
        await tester.pump(const Duration(seconds: 30));
        expect(fixture.profileReads, 1);
        fixture.profileReply = null;
        pending.complete(
          http.Response(
            jsonEncode({'data': fixture.person}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(seconds: 30));
        expect(fixture.profileReads, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(fixture.profileReads, 2);
      } finally {
        if (!pending.isCompleted) {
          pending.complete(
            http.Response(
              jsonEncode({'data': fixture.person}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          );
        }
        await fixture.close(tester);
      }
    },
  );
  testWidgets(
    'a temporary profile sync failure keeps login and shows stale account state',
    (tester) async {
      final fixture = _Fixture()..failProfile = true;
      try {
        await fixture.open(tester);
        await tester.tap(find.text('Tài khoản'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(fixture.session.user?.id, 'alice');
        expect(
          find.textContaining('Thông tin đang hiển thị là lần tải gần nhất.'),
          findsOneWidget,
        );
        expect(find.text('Đăng nhập'), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  testWidgets(
    'a pending account learns approval through polling without another login',
    (tester) async {
      final fixture = _Fixture()..status = 'pending';
      try {
        await fixture.open(tester);
        expect(find.text('Chờ duyệt tài khoản'), findsOneWidget);
        fixture.status = 'active';
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('Chờ duyệt tài khoản'), findsNothing);
        expect(fixture.profileReads, 1);
      } finally {
        await fixture.close(tester);
      }
    },
  );
  for (final status in [429, 503]) {
    testWidgets(
      'retryable restore $status reuses saved session without login or OTP',
      (tester) async {
        final store = _Store()
          ..value = const StoredSession(
            baseUrl: 'https://attendance.example.com/v1',
            accessToken: 'stored-access',
            refreshToken: 'stored-refresh',
          );
        final paths = <String>[];
        var attempts = 0;
        final api = ApiClient(
          baseUrl: 'https://attendance.example.com',
          transport: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path.endsWith('/me')) {
              attempts++;
              if (attempts == 1) {
                return http.Response(
                  jsonEncode({
                    'error': {
                      'code': 'TEMPORARY',
                      'message': 'Dịch vụ đang khởi động.',
                    },
                  }),
                  status,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }
              return http.Response(
                jsonEncode({
                  'data': {
                    'id': 'alice',
                    'fullName': 'Alice',
                    'username': 'alice',
                    'email': 'alice@example.com',
                    'role': 'employee',
                    'status': 'active',
                    'branchId': 'A',
                  },
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response(
              jsonEncode({'data': []}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final session = SessionController(api: api, store: store);
        try {
          await session.restore();
          await tester.pumpWidget(AttendanceApp(session: session));
          await tester.pumpAndSettle();
          expect(find.text('Thử kết nối lại'), findsOneWidget);
          expect(find.text('Tiếp tục'), findsNothing);
          expect(store.value?.accessToken, 'stored-access');
          await tester.tap(find.text('Thử kết nối lại'));
          await tester.pumpAndSettle();
          expect(session.user?.id, 'alice');
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(paths.where((path) => path.contains('/auth/')), isEmpty);
          expect(attempts, 2);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          session.dispose();
          api.close();
        }
      },
    );
  }
  testWidgets(
    'a branch change discards routes opened under the previous branch',
    (tester) async {
      final fixture = _Fixture()..role = 'manager';
      try {
        await fixture.open(tester);
        await tester.tap(find.text('Nhân viên chi nhánh'));
        await tester.pumpAndSettle();
        expect(find.byType(ResourceScreen), findsOneWidget);
        fixture.branch = 'B';
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expect(find.byType(ResourceScreen), findsNothing);
        expect(find.text('Điều phối ca'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
