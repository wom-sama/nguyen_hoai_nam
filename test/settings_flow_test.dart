import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/settings/appearance_controller.dart';
import 'package:nguyen_hoai_nam/features/settings/settings_screen.dart';
import 'package:nguyen_hoai_nam/features/settings/email_change_screen.dart';
import 'package:nguyen_hoai_nam/features/settings/settings_image.dart';

http.Response _reply(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json _profile(String name) => {
  'fullName': name,
  'username': name.toLowerCase(),
  'email': '${name.toLowerCase()}@example.test',
  'phone': '',
  'address': '',
  'avatarBase64': null,
  'profileVersion': 1,
  'appearance': const AppearancePreferences().toJson(),
};

class _Store implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession value) async {}
}

class _Fixture {
  Json profile = _profile('Alice');
  final requests = <http.Request>[];
  Json? emailChange;
  final reviews = <Json>[];
  late final api = ApiClient(
    baseUrl: 'https://attendance.example.test',
    transport: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/me/profile')) {
        if (request.method == 'PATCH') {
          profile.addAll(jsonDecode(request.body) as Json);
        }
        return _reply(profile);
      }
      if (path.endsWith('/me/appearance')) {
        profile['appearance'] = jsonDecode(request.body);
        return _reply(profile);
      }
      if (path.endsWith('/me/email-change')) {
        if (request.method == 'POST') {
          emailChange = {
            'requestId': 'request-one',
            'maskedOldEmail': 'a***@example.test',
            'maskedNewEmail': 'n***@example.test',
            'status': 'pending_verification',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String(),
            'retryAfterSeconds': 60,
          };
        }
        return _reply(emailChange);
      }
      if (path.endsWith('/verify')) {
        emailChange!['status'] = 'pending_approval';
        return _reply(emailChange);
      }
      if (path.endsWith('/email-change-requests')) return _reply(reviews);
      if (path.endsWith('/review')) {
        final id =
            request.url.pathSegments[request.url.pathSegments.length - 2];
        final row = reviews.singleWhere((row) => row['requestId'] == id);
        reviews.remove(row);
        return _reply({...row, 'status': 'approved'});
      }
      return _reply([]);
    }),
  );
  late final session = SessionController(api: api, store: _Store())
    ..user = const AppUser(
      id: 'alice',
      fullName: 'Alice',
      username: 'alice',
      email: 'alice@example.test',
      role: 'admin',
      status: 'active',
    );
  final settings = AppearanceController();
  Future<void> open(WidgetTester tester, Widget screen) async {
    await settings.load(api: api, userId: 'alice');
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(theme: settings.themeData, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    settings.dispose();
    session.dispose();
    api.close();
  }
}

void main() {
  testWidgets(
    'gallery image processing bounds avatar dimensions and encoded bytes',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 1600, 800),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final source = await picture.toImage(1600, 800);
        final data = await source.toByteData(format: ui.ImageByteFormat.png);
        source.dispose();
        picture.dispose();
        final encoded = await prepareSettingsImage(
          data!.buffer.asUint8List(),
          avatar: true,
        );
        final bytes = base64Decode(encoded);
        expect(bytes.length, lessThanOrEqualTo(300 * 1024));
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 512);
        expect(image.height, 256);
        image.dispose();
        codec.dispose();
      });
    },
  );

  test(
    'appearance saves to the account and reloads with the same theme and scale',
    () async {
      final f = _Fixture();
      try {
        await f.settings.load(api: f.api, userId: 'alice');
        final saved = await f.settings.saveAppearance(
          const AppearancePreferences(
            fontScale: 1.3,
            textColor: '#213547',
            primaryColor: '#246B4A',
          ),
        );
        expect(saved, isTrue);
        final patch = f.requests.singleWhere((r) => r.method == 'PATCH');
        expect(patch.url.path, '/v1/me/appearance');
        expect(jsonDecode(patch.body), {
          'fontScale': 1.3,
          'textColor': '#213547',
          'primaryColor': '#246B4A',
          'backgroundBase64': null,
        });
        final cold = AppearanceController();
        await cold.load(api: f.api, userId: 'alice');
        expect(cold.textScaler.scale(20), 26);
        expect(cold.themeData.colorScheme.primary, const Color(0xFF246B4A));
        expect(
          cold.themeData.textTheme.bodyMedium?.color,
          const Color(0xFF213547),
        );
        cold.dispose();
      } finally {
        f.settings.dispose();
        f.api.close();
      }
    },
  );

  test(
    'switching accounts discards old appearance and ignores a late old profile',
    () async {
      final pending = Completer<http.Response>();
      var reads = 0;
      final api = ApiClient(
        baseUrl: 'https://attendance.example.test',
        transport: MockClient((request) async {
          if (++reads == 1) return pending.future;
          return _reply(_profile('Bob'));
        }),
      );
      final controller = AppearanceController();
      try {
        final alice = controller.load(api: api, userId: 'alice');
        await controller.load(api: api, userId: 'bob');
        pending.complete(
          _reply({
            ..._profile('Alice'),
            'appearance': const AppearancePreferences(
              fontScale: 1.6,
              primaryColor: '#FF0000',
            ).toJson(),
          }),
        );
        await alice;
        expect(controller.userId, 'bob');
        expect(controller.profile?.fullName, 'Bob');
        expect(controller.preferences.fontScale, 1);
        controller.reset();
        expect(controller.profile, isNull);
        expect(controller.backgroundBytes, isNull);
        expect(controller.preferences.primaryColor, '#AA496C');
      } finally {
        controller.dispose();
        api.close();
      }
    },
  );

  test('profile writes contain only editable own-profile fields', () async {
    final f = _Fixture();
    try {
      await f.settings.load(api: f.api, userId: 'alice');
      expect(
        await f.settings.saveProfile(
          fullName: ' Alice Nguyen ',
          phone: ' 0901234567 ',
          address: ' Hanoi ',
          avatarBase64: null,
        ),
        isTrue,
      );
      expect(
        jsonDecode(f.requests.singleWhere((r) => r.method == 'PATCH').body),
        {
          'fullName': 'Alice Nguyen',
          'phone': '0901234567',
          'address': 'Hanoi',
          'avatarBase64': null,
        },
      );
      expect(f.settings.profile?.username, 'alice');
      expect(f.settings.profile?.email, 'alice@example.test');
    } finally {
      f.settings.dispose();
      f.api.close();
    }
  });

  test(
    'a failed appearance save keeps saved preferences and exposes the failure',
    () async {
      final api = ApiClient(
        baseUrl: 'https://attendance.example.test',
        transport: MockClient((request) async {
          if (request.method == 'GET') return _reply(_profile('Alice'));
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'TEMPORARY',
                'message': 'Chưa lưu được giao diện.',
              },
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final controller = AppearanceController();
      try {
        await controller.load(api: api, userId: 'alice');
        expect(
          await controller.saveAppearance(
            const AppearancePreferences(fontScale: 1.5),
          ),
          isFalse,
        );
        expect(controller.preferences.fontScale, 1);
        expect(controller.error, 'Chưa lưu được giao diện.');
        expect(controller.saving, isFalse);
      } finally {
        controller.dispose();
        api.close();
      }
    },
  );

  testWidgets(
    'slider edits remain local until Save and the response applies appearance',
    (tester) async {
      final f = _Fixture();
      try {
        await f.open(tester, const AppearanceSettingsScreen());
        tester.widget<Slider>(find.byType(Slider)).onChanged!(1.4);
        await tester.pump();
        expect(f.requests.where((r) => r.method == 'PATCH'), isEmpty);
        expect(f.settings.preferences.fontScale, 1);
        await tester.ensureVisible(find.text('Lưu giao diện'));
        await tester.tap(find.text('Lưu giao diện'));
        await tester.pumpAndSettle();
        expect(f.settings.preferences.fontScale, 1.4);
        expect(f.requests.where((r) => r.method == 'PATCH').length, 1);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'email change sends separate old and new OTPs then waits for another admin',
    (tester) async {
      final f = _Fixture();
      try {
        await f.open(tester, const EmailChangeScreen());
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email mới'),
          'new@example.test',
        );
        await tester.tap(find.text('Gửi mã đến hai email'));
        await tester.pumpAndSettle();
        expect(find.text('a***@example.test'), findsOneWidget);
        expect(find.text('n***@example.test'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mã từ email hiện tại'),
          '123456',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mã từ email mới'),
          '654321',
        );
        await tester.ensureVisible(find.text('Xác nhận hai mã'));
        await tester.tap(find.text('Xác nhận hai mã'));
        await tester.pumpAndSettle();
        final verify = f.requests.singleWhere(
          (r) => r.url.path.endsWith('/verify'),
        );
        expect(jsonDecode(verify.body), {
          'oldCode': '123456',
          'newCode': '654321',
        });
        expect(find.text('Chờ quản trị viên khác duyệt'), findsOneWidget);
        expect(find.text('Xác nhận hai mã'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'admin can review another account but cannot review their own request',
    (tester) async {
      final f = _Fixture();
      f.reviews.addAll([
        {
          'requestId': 'own',
          'userId': 'alice',
          'fullName': 'Alice',
          'username': 'alice',
          'oldEmail': 'alice@example.test',
          'newEmail': 'alice-new@example.test',
        },
        {
          'requestId': 'other',
          'userId': 'bob',
          'fullName': 'Bob',
          'username': 'bob',
          'oldEmail': 'bob@example.test',
          'newEmail': 'bob-new@example.test',
        },
      ]);
      try {
        await f.open(tester, const EmailChangeReviewScreen());
        expect(
          find.text('Cần quản trị viên khác duyệt yêu cầu của bạn.'),
          findsOneWidget,
        );
        expect(find.text('Duyệt'), findsOneWidget);
        await tester.ensureVisible(find.text('Duyệt'));
        await tester.tap(find.text('Duyệt'));
        await tester.pumpAndSettle();
        final review = f.requests.singleWhere(
          (r) => r.url.path.endsWith('/review'),
        );
        expect(review.url.path, '/v1/email-change-requests/other/review');
        expect(jsonDecode(review.body), {'decision': 'approved'});
      } finally {
        await f.close(tester);
      }
    },
  );
}
