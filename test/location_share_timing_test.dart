import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/location/share_timing.dart';

void main() {
  final deadline = DateTime.utc(2026, 10, 29, 4, 15);
  test('Refresh never extends beyond the original consent deadline', () {
    expect(renewalMinutes(deadline, DateTime.utc(2026, 10, 29, 4, 0)), 15);
    expect(renewalMinutes(deadline, DateTime.utc(2026, 10, 29, 4, 0, 20)), 14);
    expect(renewalMinutes(deadline, DateTime.utc(2026, 10, 29, 4, 13, 59)), 1);
  });
  test(
    'A refresh is not issued when a one-minute TTL would extend consent',
    () {
      expect(
        renewalMinutes(deadline, DateTime.utc(2026, 10, 29, 4, 14, 1)),
        isNull,
      );
      expect(renewalMinutes(deadline, deadline), isNull);
      expect(
        renewalMinutes(deadline, deadline.add(const Duration(seconds: 1))),
        isNull,
      );
    },
  );
}
