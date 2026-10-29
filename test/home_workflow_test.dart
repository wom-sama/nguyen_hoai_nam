import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/home/home_screen.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

class _Store implements SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession next) async {
    value = next;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('vi'));
  testWidgets(
    'An expired overnight checkout directs the worker to correction, without inventing a punch',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day - 1, 22);
      final end = start.add(const Duration(hours: 8));
      final session = SessionController(
        store: _Store(),
        api: ApiClient(
          baseUrl: 'https://api.example.com',
          transport: MockClient((request) async {
            final dynamic data = switch (request.url.path) {
              '/v1/auth/login' => {
                'challengeId': 'fixture',
                'maskedEmail': 't***@example.com',
                'expiresAt': '2099-01-01T00:00:00Z',
                'retryAfterSeconds': 60,
                'purpose': 'login',
              },
              '/v1/auth/verify-otp' => {
                'accessToken': 'fixture-access',
                'refreshToken': 'fixture-refresh',
                'user': {
                  'id': 'worker',
                  'username': 'worker',
                  'fullName': 'Nhân viên kiểm thử',
                  'email': 'worker@example.com',
                  'role': 'employee',
                  'status': 'active',
                  'branchId': 'branch',
                  'createdAt': '2026-01-01T00:00:00Z',
                },
              },
              '/v1/shifts' => [
                {
                  'id': 'night-shift',
                  'employeeId': 'worker',
                  'branchId': 'branch',
                  'title': 'Ca trực đêm',
                  'startsAt': start.toUtc().toIso8601String(),
                  'endsAt': end.toUtc().toIso8601String(),
                  'status': 'in_progress',
                },
              ],
              '/v1/attendance' => [
                {
                  'id': 'receipt-night',
                  'employeeId': 'worker',
                  'shiftId': 'night-shift',
                  'checkInAt': start.toUtc().toIso8601String(),
                  'checkOutAt': null,
                  'timing': {
                    'missingCheckOut': true,
                    'state': 'missing_check_out',
                  },
                },
              ],
              '/v1/branches' => [
                {
                  'id': 'branch',
                  'name': 'Chi nhánh kiểm thử',
                  'radiusMeters': 150,
                },
              ],
              _ => [],
            };
            return http.Response(
              jsonEncode({'data': data}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      await session.login('worker', 'fixture-password');
      await session.verifyOtp('123456');
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ca qua đêm'), findsOneWidget);
      expect(find.text('Gửi đơn bổ sung giờ ra'), findsOneWidget);
      expect(find.text('Chấm công ra'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
}
