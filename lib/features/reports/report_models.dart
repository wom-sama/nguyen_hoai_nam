import '../../core/models.dart';

class MonthlyReportFilter {
  const MonthlyReportFilter({
    required this.month,
    this.employeeId,
    this.branchId,
  });
  final DateTime month;
  final String? employeeId, branchId;
  String get monthKey =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
  MonthlyReportFilter forMonth(DateTime value) => MonthlyReportFilter(
    month: value,
    employeeId: employeeId,
    branchId: branchId,
  );
  MonthlyReportFilter forBranch(String? value) =>
      MonthlyReportFilter(month: month, branchId: value);
  MonthlyReportFilter forEmployee(String? value) =>
      MonthlyReportFilter(month: month, branchId: branchId, employeeId: value);
  Map<String, String> query(AppUser viewer) {
    if ((!viewer.canManage && employeeId != null && employeeId != viewer.id) ||
        (!viewer.isAdmin && branchId != null && branchId != viewer.branchId)) {
      throw const FormatException('Bộ lọc nằm ngoài phạm vi được xem.');
    }
    return {
      'month': monthKey,
      'employeeId': ?employeeId,
      'branchId': ?branchId,
    };
  }
}

String reportDuration(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '—';
  final minutes = value.floor();
  return '${minutes ~/ 60} giờ ${(minutes % 60).toString().padLeft(2, '0')} phút';
}

String reportLocalTime(Json row, String key, {bool clockOnly = false}) {
  final local = row['localTimes'] is Map
      ? row['localTimes'][key]?.toString()
      : null;
  if (local != null && local.length >= 16) {
    return clockOnly ? local.substring(11, 16) : local;
  }
  final parsed = DateTime.tryParse(row[key]?.toString() ?? '');
  if (parsed == null) return '—';
  final utc = parsed.toUtc().toIso8601String();
  return '${utc.substring(0, 10)} ${utc.substring(11, 16)} UTC';
}

String reportStateLabel(String state) => switch (state) {
  'upcoming' => 'Sắp đến ca',
  'not_checked_in' => 'Chưa vào ca',
  'missing_check_in' => 'Thiếu giờ vào',
  'in_progress' => 'Đang trong ca',
  'missing_check_out' => 'Thiếu giờ ra',
  'completed' => 'Đã ra ca',
  _ => 'Chưa xác định',
};
