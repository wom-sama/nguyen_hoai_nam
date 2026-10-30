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
import 'package:nguyen_hoai_nam/features/notifications/messaging_gateway.dart';
import 'package:nguyen_hoai_nam/features/notifications/notification_controller.dart';
import 'package:nguyen_hoai_nam/features/manage/resources_screen.dart';
import 'package:nguyen_hoai_nam/main.dart';

class MemoryConsent implements NotificationConsentStore {
  final values = <String, bool>{};
  @override
  Future<bool> read(String scope) async => values[scope] ?? false;
  @override
  Future<void> write(String scope, bool enabled) async {
    values[scope] = enabled;
  }
}

class MemorySession implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession value) async {}
}

class FakeMessaging implements MessagingGateway {
  final ids = StreamController<String>.broadcast(sync: true);
  final messages = StreamController<PushHint>.broadcast(sync: true);
  final taps = StreamController<PushHint>.broadcast(sync: true);
  bool permission = true, autoInit = false;
  int requests = 0, registrationsCount = 0, unregisterCount = 0;
  Object? failure;
  Object? unregisterFailure;
  PushHint? initial;
  @override
  Future<String> initialize() async {
    if (failure != null) throw failure!;
    return 'project-test';
  }

  @override
  Stream<String> get registrations => ids.stream;
  @override
  Stream<PushHint> get foreground => messages.stream;
  @override
  Stream<PushHint> get opened => taps.stream;
  @override
  Future<PushHint?> initialMessage() async => initial;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<void> setAutoInit(bool enabled) async {
    autoInit = enabled;
  }

  @override
  Future<String> register() async {
    registrationsCount++;
    ids.add('fid-test');
    return 'fid-test';
  }

  @override
  Future<void> unregister() async {
    unregisterCount++;
    if (unregisterFailure != null) throw unregisterFailure!;
  }

  Future<void> close() async {
    await ids.close();
    await messages.close();
    await taps.close();
  }
}

Map<String, dynamic> userData(String id, {String status = 'active'}) => {
  'id': id,
  'username': id,
  'fullName': id,
  'email': '$id@example.com',
  'role': 'employee',
  'status': status,
  'branchId': null,
};
http.Response reply(Object data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  Fixture({
    String? user = 'alice',
    Future<http.Response> Function(http.Request)? intercept,
  }) {
    api = ApiClient(
      baseUrl: 'https://api.example.com',
      transport: MockClient((request) async {
        requests.add(request);
        if (intercept != null) return intercept(request);
        if (request.url.path.endsWith('/notifications/status')) {
          return reply({
            'enabled': true,
            'provider': 'fcm',
            'firebaseProjectId': 'project-test',
          });
        }
        if (request.url.path.endsWith('/face/status')) {
          return reply({'enrolled': false});
        }
        if (request.url.path.endsWith('/me')) {
          return reply(nextProfile ?? userData(session.user!.id));
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map;
          return reply({
            'id': 'device-test',
            'recipientId': session.user!.id,
            'installationId': body['installationId'],
            'platform': 'android',
          });
        }
        return reply(request.method == 'DELETE' ? {'deleted': true} : []);
      }),
    );
    api.accessToken = user == null ? null : 'access-$user';
    session = SessionController(api: api, store: MemorySession());
    if (user != null) session.user = AppUser.fromJson(userData(user));
    controller = NotificationController(
      session: session,
      gateway: messaging,
      consentStore: consent,
    );
  }
  late ApiClient api;
  late SessionController session;
  late NotificationController controller;
  final messaging = FakeMessaging();
  final consent = MemoryConsent();
  final requests = <http.Request>[];
  Map<String, dynamic>? nextProfile;
  Future<void> close() async {
    controller.dispose();
    session.dispose();
    api.close();
    await messaging.close();
  }
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 15));

void main() {
  setUpAll(() => initializeDateFormatting('vi'));
  test(
    'profile pushes require the recipient to match the changed identity',
    () {
      expect(
        PushHint.parse({
          'eventType': 'profile_updated',
          'recipientId': 'alice',
          'entityId': 'alice',
        })?.destination,
        NotificationDestination.profile,
      );
      expect(
        PushHint.parse({
          'eventType': 'profile_updated',
          'recipientId': 'alice',
          'entityId': 'bob',
        }),
        isNull,
      );
    },
  );
  test(
    'own profile push refreshes permissions without navigation, banner or OTP',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      await f.controller.enable();
      final banners = <PushHint>[];
      final subscription = f.controller.banners.listen(banners.add);
      addTearDown(subscription.cancel);
      f.nextProfile = {
        ...userData('alice'),
        'role': 'manager',
        'branchId': 'branch-new',
      };
      f.messaging.messages.add(
        PushHint.parse({
          'eventType': 'profile_updated',
          'recipientId': 'alice',
          'entityId': 'alice',
          'role': 'admin',
        })!,
      );
      await flush();
      expect(f.session.user!.role, 'manager');
      expect(f.session.user!.branchId, 'branch-new');
      expect(f.controller.navigation, isNull);
      expect(banners, isEmpty);
      expect(f.requests.where((r) => r.url.path.contains('/auth/')), isEmpty);
      expect(f.requests.where((r) => r.url.path.endsWith('/me')).length, 1);
    },
  );
  test('a profile push for another account cannot refresh or replace this identity', () async {
    final f = Fixture();
    addTearDown(f.close);
    f.nextProfile = {...userData('bob'), 'role': 'admin'};
    await f.controller.open(
      const PushHint(
        recipientId: 'bob',
        destination: NotificationDestination.profile,
      ),
    );
    expect(f.session.user!.id, 'alice');
    expect(f.requests, isEmpty);
    expect(f.controller.navigation, isNull);
  });
  test(
    'initialization never requests permission or registers before opt-in',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      expect(f.messaging.requests, 0);
      expect(f.messaging.registrationsCount, 0);
      expect(f.controller.enabled, isFalse);
      expect(f.messaging.unregisterCount, greaterThan(0));
    },
  );

  test('denied permission cannot bind a device or claim enabled', () async {
    final f = Fixture();
    addTearDown(f.close);
    f.messaging.permission = false;
    await f.controller.initialize();
    await f.controller.enable();
    expect(f.messaging.requests, 1);
    expect(f.controller.enabled, isFalse);
    expect(f.controller.status, contains('quyền'));
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test(
    'enabled only after authenticated FID binding; refresh replaces binding',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      await f.controller.enable();
      expect(f.controller.enabled, isTrue);
      final first = f.requests.singleWhere((r) => r.method == 'POST');
      expect(first.headers['authorization'], 'Bearer access-alice');
      expect(jsonDecode(first.body), {
        'installationId': 'fid-test',
        'firebaseProjectId': 'project-test',
        'platform': 'android',
      });
      f.messaging.ids.add('fid-refreshed');
      await flush();
      expect(
        jsonDecode(f.requests.last.body)['installationId'],
        'fid-refreshed',
      );
      expect(f.controller.enabled, isTrue);
    },
  );

  test('opt-out wins over a binding already in flight', () async {
    final posted = Completer<void>(), response = Completer<http.Response>();
    final f = Fixture(
      intercept: (r) async {
        if (r.method == 'POST') {
          posted.complete();
          return response.future;
        }
        return reply(
          r.method == 'DELETE'
              ? {'deleted': true}
              : {
                  'enabled': true,
                  'provider': 'fcm',
                  'firebaseProjectId': 'project-test',
                },
        );
      },
    );
    addTearDown(f.close);
    await f.controller.initialize();
    final enabling = f.controller.enable();
    await posted.future;
    final disabling = f.controller.disable();
    response.complete(
      reply({
        'id': 'device-test',
        'recipientId': 'alice',
        'installationId': 'fid-test',
      }),
    );
    await Future.wait([enabling, disabling]);
    expect(f.controller.enabled, isFalse);
    expect(f.messaging.autoInit, isFalse);
    expect(f.requests.last.method, 'DELETE');
  });

  test(
    'tap waits for correct active recipient and fetches authorized list',
    () async {
      final f = Fixture(user: null);
      addTearDown(f.close);
      await f.controller.initialize();
      const hint = PushHint(
        recipientId: 'alice',
        destination: NotificationDestination.corrections,
      );
      await f.controller.open(hint);
      expect(f.controller.navigation, isNull);
      f.session.user = AppUser.fromJson(userData('bob'));
      f.api.accessToken = 'access-bob';
      await f.controller.refresh();
      expect(f.controller.navigation, isNull);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/corrections')),
        isEmpty,
      );
      f.session.user = AppUser.fromJson(userData('alice', status: 'pending'));
      await f.controller.refresh();
      expect(f.controller.navigation, isNull);
      f.session.user = AppUser.fromJson(userData('alice'));
      f.api.accessToken = 'access-alice';
      await f.controller.refresh();
      expect(f.requests.last.url.path, '/v1/corrections');
      expect(f.requests.last.headers['authorization'], 'Bearer access-alice');
      expect(f.controller.navigation?.hint.recipientId, 'alice');
    },
  );

  test(
    'stale authorized fetch cannot navigate after identity changes',
    () async {
      final fetched = Completer<void>(), response = Completer<http.Response>();
      final f = Fixture(
        intercept: (r) async {
          if (r.url.path.endsWith('/handovers')) {
            fetched.complete();
            return response.future;
          }
          return reply({
            'enabled': true,
            'provider': 'fcm',
            'firebaseProjectId': 'project-test',
          });
        },
      );
      addTearDown(f.close);
      await f.controller.initialize();
      final opening = f.controller.open(
        const PushHint(
          recipientId: 'alice',
          destination: NotificationDestination.handovers,
        ),
      );
      await fetched.future;
      f.session.user = AppUser.fromJson(userData('bob'));
      f.api.accessToken = 'access-bob';
      response.complete(reply([]));
      await opening;
      expect(f.controller.navigation, isNull);
    },
  );

  test('unknown events and malformed recipients cannot select routes', () {
    expect(
      PushHint.parse({
        'eventType': 'open_url',
        'recipientId': 'alice',
        'url': 'https://evil.example',
      }),
      isNull,
    );
    expect(
      PushHint.parse({
        'eventType': 'shift_assigned',
        'recipientId': '../alice',
      }),
      isNull,
    );
    expect(
      PushHint.parse({
        'eventType': 'shift_assigned',
        'recipientId': 'alice',
        'entityId': 'ignored',
      })?.destination,
      NotificationDestination.home,
    );
  });

  test(
    'unconfigured backend never asks permission or registers the installation',
    () async {
      final f = Fixture(
        intercept: (_) async => reply({
          'enabled': false,
          'provider': 'fcm',
          'firebaseProjectId': null,
        }),
      );
      addTearDown(f.close);
      await f.controller.initialize();
      await f.controller.enable();
      expect(f.controller.enabled, isFalse);
      expect(
        f.controller.status,
        'Thông báo đang tạm ngừng. Vui lòng thử lại sau.',
      );
      expect(f.messaging.requests, 0);
      expect(f.messaging.registrationsCount, 0);
    },
  );

  test(
    'backend recipient mismatch never reports successful enrollment',
    () async {
      final f = Fixture(
        intercept: (r) async => reply(
          r.method == 'POST'
              ? {
                  'id': 'device-test',
                  'recipientId': 'bob',
                  'installationId': 'fid-test',
                }
              : {
                  'enabled': true,
                  'provider': 'fcm',
                  'firebaseProjectId': 'project-test',
                },
        ),
      );
      addTearDown(f.close);
      await f.controller.initialize();
      await f.controller.enable();
      await flush();
      expect(f.controller.enabled, isFalse);
      expect(f.controller.status, isNot(contains('Đã bật.')));
    },
  );

  test(
    'foreground banner only receives hints for current opted-in recipient',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final banners = <PushHint>[];
      final subscription = f.controller.banners.listen(banners.add);
      addTearDown(subscription.cancel);
      await f.controller.initialize();
      const alice = PushHint(
        recipientId: 'alice',
        destination: NotificationDestination.home,
      );
      const bob = PushHint(
        recipientId: 'bob',
        destination: NotificationDestination.home,
      );
      f.messaging.messages.add(alice);
      await flush();
      expect(banners, isEmpty);
      await f.controller.enable();
      f.messaging.messages.add(bob);
      f.messaging.messages.add(alice);
      await flush();
      expect(banners, [alice]);
      f.controller.suspendForLogout();
      f.messaging.messages.add(alice);
      await flush();
      expect(banners, [alice]);
    },
  );

  test(
    'failed SDK unregister still deletes backend binding and permits retry',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      await f.controller.enable();
      f.messaging.unregisterFailure = StateError(
        'native temporarily unavailable',
      );
      await f.controller.disable();
      expect(f.controller.enabled, isFalse);
      expect(f.controller.cleanupIncomplete, isTrue);
      expect(f.requests.last.method, 'DELETE');
      expect(
        f.controller.status,
        'Đã ngừng nhận thông báo trong ứng dụng. Kết nối mạng rồi bấm tắt lại để hoàn tất.',
      );
      f.messaging.unregisterFailure = null;
      await f.controller.disable();
      expect(f.controller.cleanupIncomplete, isFalse);
      expect(f.controller.status, 'Đã tắt thông báo trên thiết bị này.');
    },
  );

  test('unavailable Firebase does not change authenticated session', () async {
    final f = Fixture();
    addTearDown(f.close);
    f.messaging.failure = StateError('No Google Play services');
    await f.controller.initialize();
    expect(f.controller.enabled, isFalse);
    expect(f.controller.status, contains('chưa sẵn sàng'));
    expect(f.session.user?.id, 'alice');
    expect(f.api.accessToken, 'access-alice');
  });

  testWidgets(
    'Account button explicitly opts in, and foreground banner uses generic copy',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      await tester.pumpWidget(
        AttendanceApp(session: f.session, notifications: f.controller),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      expect(f.messaging.requests, 0);
      final button = find.text('Bật thông báo');
      await Scrollable.ensureVisible(tester.element(button), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(f.messaging.requests, 1);
      expect(find.text('ĐANG BẬT'), findsOneWidget);
      f.messaging.messages.add(
        const PushHint(
          recipientId: 'bob',
          destination: NotificationDestination.home,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      f.messaging.messages.add(
        const PushHint(
          recipientId: 'alice',
          destination: NotificationDestination.home,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Bạn có cập nhật mới. Mở ứng dụng để xem.'),
        findsOneWidget,
      );
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'notification navigation waits behind an open draft then opens authorized corrections',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final f = Fixture();
      addTearDown(f.close);
      await f.controller.initialize();
      await tester.pumpWidget(
        AttendanceApp(session: f.session, notifications: f.controller),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final draftRoute = navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Bản nháp đang mở')),
        ),
      );
      await tester.pumpAndSettle();
      await f.controller.open(
        const PushHint(
          recipientId: 'alice',
          destination: NotificationDestination.corrections,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp đang mở'), findsOneWidget);
      expect(find.byType(ResourceScreen), findsNothing);
      navigator.pop();
      await draftRoute;
      await tester.pumpAndSettle();
      expect(find.byType(ResourceScreen), findsOneWidget);
      expect(
        f.requests
            .where((request) => request.url.path == '/v1/corrections')
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
