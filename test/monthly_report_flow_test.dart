import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/manage/resources_screen.dart';
import 'package:nguyen_hoai_nam/features/reports/monthly_report_screen.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

final branches = <Json>[
  {
    'id': 'branch-a',
    'name': 'Chi nhánh A',
    'address': 'Địa chỉ kiểm thử A',
    'latitude': 10,
    'longitude': 106,
    'radiusMeters': 100,
    'timePolicy': branchTimePolicyDefaults,
  },
  {
    'id': 'branch-b',
    'name': 'Chi nhánh B',
    'address': 'Địa chỉ kiểm thử B',
    'latitude': 11,
    'longitude': 107,
    'radiusMeters': 200,
    'timePolicy': branchTimePolicyDefaults,
  },
];
final people = <Json>[
  {
    'id': 'staff-a',
    'fullName': 'Nhân viên A',
    'username': 'staffa',
    'branchId': 'branch-a',
    'status': 'active',
  },
  {
    'id': 'staff-b',
    'fullName': 'Nhân viên B',
    'username': 'staffb',
    'branchId': 'branch-b',
    'status': 'active',
  },
];
http.Response dataReply(dynamic value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

SessionController reportSession(http.Client client) =>
    SessionController(
        api: ApiClient(baseUrl: 'https://api.example.com', transport: client),
      )
      ..user = const AppUser(
        id: 'admin-test',
        fullName: 'Quản trị kiểm thử',
        username: 'admin',
        email: 'admin@example.com',
        role: 'admin',
        status: 'active',
      );

Json reportFixture(Uri uri) => {
  'month': uri.queryParameters['month'],
  'timeZone': 'Asia/Bangkok',
  'rows': <Json>[],
  'totals': {
    for (final key in [
      'shiftCount',
      'completedCount',
      'inProgressCount',
      'upcomingCount',
      'notCheckedInCount',
      'missingCheckInCount',
      'missingCheckOutCount',
      'lateCount',
      'earlyLeaveCount',
      'rawSpanMinutes',
      'recordedSpanMinutes',
    ])
      key: 0,
  },
};

Future<void> visibleTap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> pumpReportPage(
  WidgetTester tester,
  SessionController session,
  Widget page,
) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(theme: appTheme(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpEditor(
  WidgetTester tester,
  SessionController session,
  Widget editor,
) => pumpReportPage(
  tester,
  session,
  Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => editor),
          ),
          child: const Text('Mở biên tập'),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final font = FontLoader('BeVietnamPro');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora-Variable.ttf'))).load();
  });

  testWidgets(
    'overnight ledger preserves server work-date and separates corrected from original times',
    (tester) async {
      final row = <String, dynamic>{
        'shiftId': 'overnight',
        'title': 'Ca đêm cuối tháng',
        'employeeId': 'staff-a',
        'employeeName': 'Nhân viên A',
        'branchId': 'branch-a',
        'branchName': 'Chi nhánh A',
        'workDate': '2026-10-31',
        'status': 'completed',
        'source': 'correction',
        'startsAt': '2026-10-31T15:00:00Z',
        'endsAt': '2026-10-31T23:00:00Z',
        'checkInAt': '2026-10-31T15:00:00Z',
        'checkOutAt': '2026-10-31T23:00:00Z',
        'recordedCheckInAt': '2026-10-31T15:04:00Z',
        'recordedCheckOutAt': '2026-10-31T22:58:00Z',
        'timePolicySnapshot': branchTimePolicyDefaults,
        'localTimes': {
          'startsAt': '2026-10-31 22:00',
          'endsAt': '2026-11-01 06:00',
          'checkInAt': '2026-10-31 22:00',
          'checkOutAt': '2026-11-01 06:00',
          'recordedCheckInAt': '2026-10-31 22:04',
          'recordedCheckOutAt': '2026-11-01 05:58',
        },
        'timing': {
          'state': 'completed',
          'late': false,
          'earlyLeave': false,
          'arrivalDelayMinutes': 0,
          'earlyLeaveMinutes': 0,
          'missingCheckOut': false,
          'rawSpanMinutes': 480,
          'recordedSpanMinutes': 474,
        },
      };
      final session = reportSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/employees')) return dataReply(people);
          if (request.url.path.endsWith('/branches')) {
            return dataReply(branches);
          }
          final data = reportFixture(request.url);
          data['rows'] = [row];
          data['totals'] = {
            ...data['totals'] as Map,
            'shiftCount': 1,
            'completedCount': 1,
            'rawSpanMinutes': 480,
            'recordedSpanMinutes': 474,
          };
          return dataReply(data);
        }),
      );
      await pumpReportPage(
        tester,
        session,
        MonthlyReportScreen(initialMonth: DateTime(2026, 10)),
      );
      expect(
        find.text('Khoảng giờ sau điều chỉnh: 8 giờ 00 phút'),
        findsOneWidget,
      );
      expect(find.text('Khoảng giờ chấm gốc: 7 giờ 54 phút'), findsOneWidget);
      await visibleTap(tester, find.text('Ca đêm cuối tháng'));
      expect(find.text('2026-10-31'), findsOneWidget);
      expect(find.text('2026-11-01 06:00'), findsNWidgets(2));
      expect(find.text('2026-10-31 22:04'), findsOneWidget);
      expect(find.text('2026-11-01 05:58'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );

  testWidgets(
    'monthly report resets person when branch changes and preserves branch while changing month',
    (tester) async {
      final requests = <Uri>[];
      final session = reportSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/employees')) return dataReply(people);
          if (request.url.path.endsWith('/branches')) {
            return dataReply(branches);
          }
          requests.add(request.url);
          return dataReply(reportFixture(request.url));
        }),
      );
      await pumpReportPage(
        tester,
        session,
        MonthlyReportScreen(initialMonth: DateTime(2026, 10)),
      );
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await visibleTap(tester, dropdowns.last);
      await tester.tap(find.text('Nhân viên A · staffa').last);
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters, {
        'month': '2026-10',
        'employeeId': 'staff-a',
      });
      await visibleTap(tester, dropdowns.first);
      await tester.tap(find.text('Chi nhánh B').last);
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters, {
        'month': '2026-10',
        'branchId': 'branch-b',
      });
      await visibleTap(tester, find.byTooltip('Tháng trước'));
      expect(requests.last.queryParameters, {
        'month': '2026-09',
        'branchId': 'branch-b',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );

  testWidgets(
    'locked shift editor sends only changed title without server-managed status or plan fields',
    (tester) async {
      final patches = <Json>[];
      final original = <String, dynamic>{
        'id': 'shift-a',
        'title': 'Ca sáng',
        'branchId': 'branch-a',
        'employeeId': 'staff-a',
        'employeeName': 'Nhân viên A',
        'branchName': 'Chi nhánh A',
        'startsAt': '2026-10-29T01:00:00Z',
        'endsAt': '2026-10-29T10:00:00Z',
        'status': 'in_progress',
        'planLocked': true,
        'hasAttendance': true,
        'timePolicySnapshot': branchTimePolicyDefaults,
      };
      final session = reportSession(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            patches.add(jsonDecode(request.body) as Json);
            return dataReply({...original, ...patches.last});
          }
          if (request.url.path.endsWith('/employees')) return dataReply(people);
          if (request.url.path.endsWith('/branches')) {
            return dataReply(branches);
          }
          return dataReply(<Json>[]);
        }),
      );
      await pumpEditor(
        tester,
        session,
        ResourceEditor(resource: 'shifts', initial: original),
      );
      await tester.tap(find.text('Mở biên tập'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .where((field) => field.enabled == false)
            .length,
        4,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên ca làm'),
        'Ca sáng đã sửa tên',
      );
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Lưu thay đổi'),
      );
      expect(patches.single, {'title': 'Ca sáng đã sửa tên'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );

  testWidgets(
    'branch editor sends one complete integer policy and preserves unchanged branch fields',
    (tester) async {
      final patches = <Json>[];
      final session = reportSession(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            patches.add(jsonDecode(request.body) as Json);
            return dataReply({...branches.first, ...patches.last});
          }
          if (request.url.path.endsWith('/employees')) return dataReply(people);
          if (request.url.path.endsWith('/branches')) {
            return dataReply(branches);
          }
          return dataReply(<Json>[]);
        }),
      );
      await pumpEditor(
        tester,
        session,
        ResourceEditor(resource: 'branches', initial: branches.first),
      );
      await tester.tap(find.text('Mở biên tập'));
      await tester.pumpAndSettle();
      final grace = find.widgetWithText(TextFormField, 'Ân hạn đi muộn (phút)');
      await tester.ensureVisible(grace);
      await tester.pumpAndSettle();
      await tester.enterText(grace, '15');
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Lưu thay đổi'),
      );
      expect(patches.single, {
        'timePolicy': {...branchTimePolicyDefaults, 'lateGraceMinutes': 15},
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
}
