import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/features/reports/report_models.dart';
import 'package:nguyen_hoai_nam/features/manage/resources_screen.dart';

const admin = AppUser(
  id: 'admin',
  fullName: 'Admin kiểm thử',
  username: 'admin',
  email: 'admin@example.com',
  role: 'admin',
  status: 'active',
);
const staff = AppUser(
  id: 'staff',
  fullName: 'Nhân viên kiểm thử',
  username: 'staff',
  email: 'staff@example.com',
  role: 'employee',
  status: 'active',
  branchId: 'branch-a',
);

void main() {
  test('month changes preserve filters, branch changes reset stale personnel selection', () {
    final filter = MonthlyReportFilter(
      month: DateTime(2026, 10, 29),
      branchId: 'branch-a',
      employeeId: 'staff',
    );
    expect(filter.query(admin), {
      'month': '2026-10',
      'branchId': 'branch-a',
      'employeeId': 'staff',
    });
    expect(filter.forMonth(DateTime(2027, 1)).query(admin)['month'], '2027-01');
    expect(filter.forMonth(DateTime(2027, 1)).employeeId, 'staff');
    expect(filter.forBranch('branch-b').employeeId, isNull);
    expect(filter.forBranch('branch-b').branchId, 'branch-b');
  });
  test('employee report filter cannot request another identity or branch', () {
    expect(
      () => MonthlyReportFilter(
        month: DateTime(2026, 10),
        employeeId: 'other',
      ).query(staff),
      throwsFormatException,
    );
    expect(
      () => MonthlyReportFilter(
        month: DateTime(2026, 10),
        branchId: 'branch-b',
      ).query(staff),
      throwsFormatException,
    );
    expect(MonthlyReportFilter(month: DateTime(2026, 10)).query(staff), {
      'month': '2026-10',
    });
  });
  test(
    'shift patch omits server-managed status and unchanged plan metadata',
    () {
      final original = <String, dynamic>{
        'id': 's1',
        'title': 'Ca sáng',
        'status': 'in_progress',
        'branchId': 'b1',
        'employeeId': 'u1',
        'startsAt': '2026-10-29T01:00:00Z',
        'endsAt': '2026-10-29T10:00:00Z',
        'planLocked': true,
        'hasAttendance': true,
      };
      expect(
        resourceMutation('shifts', {
          ...original,
          'title': 'Ca sáng A',
        }, initial: original),
        {'title': 'Ca sáng A'},
      );
      expect(
        () => resourceMutation('shifts', {
          ...original,
          'employeeId': 'u2',
        }, initial: original),
        throwsFormatException,
      );
      expect(
        resourceMutation('shifts', {
          'title': 'Ca mới',
          'status': 'completed',
          'id': 'unexpected',
        }),
        {'title': 'Ca mới'},
      );
    },
  );
  test('branch policy mutation preserves all four integers but skips an unchanged snapshot', () {
    final policy = <String, dynamic>{
      'checkInEarlyMinutes': 30,
      'lateGraceMinutes': 10,
      'earlyLeaveGraceMinutes': 10,
      'checkOutLateMinutes': 120,
    };
    final original = <String, dynamic>{
      'id': 'b1',
      'name': 'Chi nhánh A',
      'timePolicy': policy,
    };
    expect(
      resourceMutation('branches', {
        'name': 'Chi nhánh A',
        'timePolicy': Map<String, dynamic>.from(policy),
      }, initial: original),
      isEmpty,
    );
    final changed = {...policy, 'lateGraceMinutes': 15};
    expect(
      resourceMutation('branches', {
        'name': 'Chi nhánh A',
        'timePolicy': changed,
      }, initial: original),
      {'timePolicy': changed},
    );
  });
}
