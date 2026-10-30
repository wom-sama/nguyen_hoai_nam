import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/manage/resources_screen.dart';

class _Store implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession value) async {}
}

class _Fixture {
  final branches = <Json>[
    {'id': 'branch-a', 'name': 'Chi nhánh A'},
    {'id': 'branch-b', 'name': 'Chi nhánh B'},
  ];
  final employees = <Json>[
    {
      'id': 'one',
      'fullName': 'Nguyễn Văn A',
      'username': 'staff_one',
      'email': 'one@example.test',
      'emailVerified': true,
      'role': 'employee',
      'status': 'active',
      'branchId': 'branch-a',
    },
    {
      'id': 'two',
      'fullName': 'Nguyễn Văn A',
      'username': 'staff_two',
      'email': 'two@example.test',
      'emailVerified': true,
      'role': 'employee',
      'status': 'active',
      'branchId': 'branch-b',
    },
    {
      'id': 'new',
      'fullName': 'Nhân viên mới',
      'username': 'new_staff',
      'email': 'new@example.test',
      'emailVerified': true,
      'role': 'employee',
      'status': 'pending',
      'branchId': null,
    },
    {
      'id': 'unverified',
      'fullName': 'Chưa xác thực',
      'username': 'not_verified',
      'email': 'unverified@example.test',
      'emailVerified': false,
      'role': 'employee',
      'status': 'active',
      'branchId': 'branch-b',
    },
  ];
  final requests = <http.Request>[];
  bool failBranches = false, stalePatch = false;
  late final api = ApiClient(
    baseUrl: 'https://attendance.example.test',
    transport: MockClient((request) async {
      requests.add(request);
      Object data;
      if (request.method == 'GET' && request.url.path == '/v1/branches') {
        if (failBranches) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'DATABASE_UNAVAILABLE',
                'message': 'Chưa tải được chi nhánh.',
              },
            }),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        data = branches;
      } else if (request.method == 'GET' &&
          request.url.path == '/v1/employees') {
        data = employees;
      } else if (request.method == 'PATCH' &&
          request.url.path.startsWith('/v1/employees/')) {
        final row = employees.singleWhere(
          (row) => row['id'] == request.url.pathSegments.last,
        );
        if (!stalePatch) row.addAll(jsonDecode(request.body) as Json);
        data = row;
      } else {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  )..accessToken = 'fixture-access';
  late final session = SessionController(api: api, store: _Store())
    ..user = const AppUser(
      id: 'admin',
      fullName: 'Quản trị',
      username: 'admin',
      email: 'admin@example.test',
      role: 'admin',
      status: 'active',
    );
  void close() {
    session.dispose();
    api.close();
  }
}

Future<void> _open(WidgetTester tester, _Fixture f, Widget page) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: f.session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => page),
              ),
              child: const Text('Mở kiểm thử'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở kiểm thử'));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, int index, String label) async {
  final field = find.byType(DropdownButtonFormField<String>).at(index);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Lưu thay đổi'));
  await tester.tap(find.text('Lưu thay đổi'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'approval requires a branch for staff, sends all grants, and confirms the saved values',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      await _open(
        tester,
        f,
        ResourceEditor(resource: 'employees', initial: Map.of(f.employees[2])),
      );
      expect(f.requests.map((r) => r.url.path), ['/v1/branches']);
      await _select(tester, 0, 'Quản lý');
      await _select(tester, 1, 'Đang hoạt động');
      await _save(tester);
      expect(find.text('Vui lòng chọn chi nhánh.'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'PATCH'), isEmpty);
      await _select(tester, 2, 'Chi nhánh B');
      await _save(tester);
      expect(find.text('Mở kiểm thử'), findsOneWidget);
      expect(
        jsonDecode(f.requests.singleWhere((r) => r.method == 'PATCH').body),
        {'role': 'manager', 'status': 'active', 'branchId': 'branch-b'},
      );
      expect(f.employees[2]['branchId'], 'branch-b');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'duplicate names remain distinguishable and pending/unassigned filters remain reachable',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      await _open(tester, f, const ResourceScreen(resource: 'employees'));
      expect(find.text('@staff_one'), findsOneWidget);
      expect(find.text('@staff_two'), findsOneWidget);
      expect(find.text('Chi nhánh A'), findsOneWidget);
      expect(find.byTooltip('Cập nhật danh sách'), findsOneWidget);
      await tester.tap(find.text('Chờ duyệt (1)'));
      await tester.pumpAndSettle();
      expect(find.text('@new_staff'), findsOneWidget);
      expect(find.text('@staff_one'), findsNothing);
      expect(find.text('Phân quyền & chi nhánh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'assignment explains the chosen branch and reloads members after assigning one',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      await _open(tester, f, const ResourceEditor(resource: 'shifts'));
      await _select(tester, 0, 'Chi nhánh B');
      expect(
        find.text('Có 1 nhân viên sẵn sàng tại chi nhánh đã chọn.'),
        findsOneWidget,
      );
      await _select(tester, 1, 'Nguyễn Văn A · @staff_two');
      expect(find.text('Nguyễn Văn A · @staff_one'), findsNothing);
      await tester.ensureVisible(find.text('Gán nhân viên vào chi nhánh'));
      await tester.tap(find.text('Gán nhân viên vào chi nhánh'));
      await tester.pumpAndSettle();
      f.employees[2].addAll({'status': 'active', 'branchId': 'branch-b'});
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(
        find.text('Có 2 nhân viên sẵn sàng tại chi nhánh đã chọn.'),
        findsOneWidget,
      );
      expect(
        f.requests.where((r) => r.url.path == '/v1/employees').length,
        greaterThan(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed branch loading cannot expose an incomplete grant form and can be retried',
    (tester) async {
      final f = _Fixture()..failBranches = true;
      addTearDown(f.close);
      await _open(
        tester,
        f,
        ResourceEditor(resource: 'employees', initial: Map.of(f.employees[2])),
      );
      expect(find.text('Tải lại dữ liệu'), findsOneWidget);
      expect(find.text('Lưu thay đổi'), findsNothing);
      f.failBranches = false;
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.text('Vai trò'), findsOneWidget);
      expect(find.text('Lưu thay đổi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a stale successful response does not falsely confirm a role change',
    (tester) async {
      final f = _Fixture()..stalePatch = true;
      addTearDown(f.close);
      await _open(
        tester,
        f,
        ResourceEditor(resource: 'employees', initial: Map.of(f.employees[2])),
      );
      await _select(tester, 0, 'Quản trị viên');
      await _save(tester);
      expect(
        find.widgetWithText(
          SnackBar,
          'Chưa xác nhận được thay đổi. Hãy tải lại dữ liệu trước khi thử lại.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lưu thay đổi'), findsOneWidget);
      expect(f.employees[2]['role'], 'employee');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
