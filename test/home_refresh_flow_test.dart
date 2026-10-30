import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/auth/auth_screen.dart';
import 'package:nguyen_hoai_nam/features/home/home_screen.dart';
import 'package:nguyen_hoai_nam/features/notifications/messaging_gateway.dart';
import 'package:nguyen_hoai_nam/features/notifications/notification_controller.dart';
import 'package:nguyen_hoai_nam/main.dart';

class _Store implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession value) async {}
}

// Exercise the existing banner boundary without starting Firebase native code.
class _Notifications extends NotificationController {
  _Notifications(SessionController session)
    : super(session: session, gateway: FirebaseMessagingGateway()) {
    enabled = true;
  }
  final hints = StreamController<PushHint>.broadcast(sync: true);
  @override
  Stream<PushHint> get banners => hints.stream;
  @override
  Future<void> refresh() async {}
  void openHome() {
    navigation = NotificationNavigation(
      const PushHint(
        recipientId: 'alice',
        destination: NotificationDestination.home,
      ),
      1,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(hints.close());
    super.dispose();
  }
}

class _Location extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    longitude: 106,
    latitude: 10,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _Fixture {
  bool hasShift = false, failShifts = false;
  int shiftReads = 0, attendanceReads = 0, branchReads = 0, correctionReads = 0;
  final authPaths = <String>[];
  Completer<http.Response>? shiftReply, punchReply;
  final person = <String, dynamic>{
    'id': 'alice',
    'username': 'alice',
    'fullName': 'Alice',
    'email': 'alice@example.com',
    'role': 'employee',
    'status': 'active',
    'branchId': 'branch',
  };
  List<Map<String, dynamic>> get shifts => [
    if (hasShift)
      {
        'id': 'new-shift',
        'employeeId': 'alice',
        'branchId': 'branch',
        'title': 'Ca vừa phân công',
        'startsAt': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'endsAt': DateTime.now()
            .add(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
        'status': 'scheduled',
      },
  ];
  http.Response reply(Object data) => http.Response(
    jsonEncode({'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  late final api = ApiClient(
    baseUrl: 'https://attendance.example.com',
    transport: MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/auth/')) authPaths.add(path);
      if (path.endsWith('/me')) return reply(person);
      if (path.endsWith('/shifts')) {
        shiftReads++;
        if (shiftReply != null) return shiftReply!.future;
        if (failShifts) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY',
                'message': 'Chưa tải được ca làm.',
              },
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return reply(shifts);
      }
      if (path.endsWith('/attendance/check-in')) return punchReply!.future;
      if (path.endsWith('/attendance')) attendanceReads++;
      if (path.endsWith('/corrections')) correctionReads++;
      if (path.endsWith('/branches')) {
        branchReads++;
        return reply([
          {'id': 'branch', 'name': 'Chi nhánh hiện tại', 'radiusMeters': 100},
        ]);
      }
      if (path.endsWith('/face/status')) return reply({'enrolled': false});
      return reply([]);
    }),
  );
  late final session = SessionController(api: api, store: _Store())
    ..user = AppUser.fromJson(person);
  late final notifications = _Notifications(session);
  void hint(NotificationDestination destination, {String recipient = 'alice'}) {
    notifications.hints.add(
      PushHint(recipientId: recipient, destination: destination),
    );
  }

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AttendanceApp(session: session, notifications: notifications),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    if (shiftReply != null && !shiftReply!.isCompleted) {
      shiftReply!.complete(reply(shifts));
    }
    if (punchReply != null && !punchReply!.isCompleted) {
      punchReply!.complete(
        reply({'checkInAt': DateTime.now().toUtc().toIso8601String()}),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    notifications.dispose();
    session.dispose();
    api.close();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('vi'));

  for (final hideHome in [false, true]) {
    testWidgets(
      'an own hint during an old initial snapshot queues one fresh batch, hidden=$hideHome',
      (tester) async {
        final fixture = _Fixture();
        final oldSnapshot = Completer<http.Response>();
        fixture.shiftReply = oldSnapshot;
        try {
          await fixture.open(tester, settle: false);
          expect(fixture.shiftReads, 1);
          fixture.hasShift = true;
          fixture.hint(NotificationDestination.home);
          fixture.hint(NotificationDestination.corrections);
          if (hideHome) {
            await tester.tap(find.text('Tài khoản'));
          }
          await tester.pump();
          expect(fixture.shiftReads, 1);
          fixture.shiftReply = null;
          oldSnapshot.complete(fixture.reply([]));
          await tester.pumpAndSettle();
          if (hideHome) {
            expect(fixture.shiftReads, 1);
            await tester.tap(find.text('Ca làm'));
            await tester.pumpAndSettle();
          }
          expect(find.text('Ca vừa phân công'), findsWidgets);
          expect(fixture.shiftReads, 2);
          expect(fixture.attendanceReads, 2);
          expect(fixture.branchReads, 2);
          expect(fixture.correctionReads, 2);
          expect(fixture.authPaths, isEmpty);
          await tester.pump(const Duration(seconds: 1));
          expect(fixture.shiftReads, 2);
        } finally {
          if (!oldSnapshot.isCompleted) {
            oldSnapshot.complete(fixture.reply([]));
          }
          await fixture.close(tester);
        }
      },
    );
  }

  testWidgets(
    'returning to Home loads a newly assigned shift without offscreen polling or OTP',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        expect(find.text('Hôm nay chưa có ca cần chấm công'), findsOneWidget);
        await tester.tap(find.text('Tài khoản'));
        await tester.pumpAndSettle();
        fixture.hasShift = true;
        fixture.hint(NotificationDestination.home);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(seconds: 30));
        await tester.pumpAndSettle();
        expect(fixture.shiftReads, 1);
        await tester.tap(find.text('Ca làm'));
        await tester.pumpAndSettle();
        expect(find.text('Ca vừa phân công'), findsWidgets);
        expect(fixture.shiftReads, 2);
        expect(fixture.attendanceReads, 2);
        expect(fixture.branchReads, 2);
        expect(fixture.correctionReads, 2);
        expect(fixture.authPaths, isEmpty);
        expect(find.byType(OtpScreen), findsNothing);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('resuming while Home is active reloads a newly assigned shift', (
    tester,
  ) async {
    final fixture = _Fixture();
    try {
      await fixture.open(tester);
      fixture.hasShift = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(fixture.shiftReads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Ca vừa phân công'), findsWidgets);
      expect(fixture.shiftReads, 2);
      expect(fixture.authPaths, isEmpty);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'a route covering Home defers refresh until the route is closed',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        final corrections = find.text('Điều chỉnh công');
        await tester.ensureVisible(corrections);
        await tester.tap(corrections);
        await tester.pumpAndSettle();
        fixture.hasShift = true;
        fixture.hint(NotificationDestination.corrections);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(fixture.shiftReads, 1);
        Navigator.of(tester.element(find.byType(AppBar))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Ca vừa phân công'), findsWidgets);
        expect(fixture.shiftReads, 2);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  for (final destination in [
    NotificationDestination.home,
    NotificationDestination.corrections,
  ]) {
    testWidgets(
      'own $destination foreground hint refreshes Home while preserving its banner and route',
      (tester) async {
        final fixture = _Fixture();
        try {
          await fixture.open(tester);
          fixture.hasShift = true;
          fixture.hint(destination, recipient: 'someone-else');
          fixture.hint(NotificationDestination.handovers);
          await tester.pumpAndSettle();
          expect(fixture.shiftReads, 1);
          fixture.hint(destination);
          await tester.pumpAndSettle();
          expect(find.text('Ca vừa phân công'), findsWidgets);
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(find.byType(MaterialBanner), findsOneWidget);
          expect(fixture.notifications.navigation, isNull);
          expect(fixture.shiftReads, 2);
          expect(fixture.authPaths, isEmpty);
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }

  testWidgets(
    'refresh bursts share one pending load and disposal leaves no callback error',
    (tester) async {
      final fixture = _Fixture();
      final pending = Completer<http.Response>();
      try {
        await fixture.open(tester);
        fixture.shiftReply = pending;
        fixture.hint(NotificationDestination.home);
        await tester.pump();
        fixture.hint(NotificationDestination.corrections);
        fixture.hint(NotificationDestination.home);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(fixture.shiftReads, 2);
        expect(fixture.attendanceReads, 2);
        expect(fixture.branchReads, 2);
        expect(fixture.correctionReads, 2);
        await tester.pumpWidget(const SizedBox());
        fixture.hasShift = true;
        pending.complete(fixture.reply(fixture.shifts));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'the compact refresh action keeps failures visible and retry reloads data',
    (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.open(tester);
        fixture.failShifts = true;
        await tester.tap(find.byTooltip('Làm mới ca làm'));
        await tester.pumpAndSettle();
        expect(find.text('Chưa tải được ca làm.'), findsOneWidget);
        expect(find.text('Thử lại'), findsOneWidget);
        fixture.failShifts = false;
        fixture.hasShift = true;
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.text('Ca vừa phân công'), findsWidgets);
        expect(fixture.shiftReads, 3);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'notification navigation during a punch preserves the pending punch and receipt',
    (tester) async {
      final location = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = _Location();
      addTearDown(() => GeolocatorPlatform.instance = location);
      final fixture = _Fixture()..hasShift = true;
      final pending = Completer<http.Response>();
      fixture.punchReply = pending;
      try {
        await fixture.open(tester);
        await tester.tap(find.text('Chấm công vào'));
        await tester.pump();
        expect(find.text('Đang xác định vị trí…'), findsOneWidget);
        fixture.hint(NotificationDestination.home);
        fixture.notifications.openHome();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(fixture.shiftReads, 1);
        expect(find.text('Đang xác định vị trí…'), findsOneWidget);
        pending.complete(
          fixture.reply({
            'checkInAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Đóng biên nhận'), findsOneWidget);
        expect(fixture.shiftReads, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
