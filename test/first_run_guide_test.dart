import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/ui/first_run_guide.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Guide completion persists independently of the authenticated session',
    () async {
      final first = FirstRunController();
      await first.load();
      expect(first.completed, isFalse);
      await first.complete();
      final next = FirstRunController();
      await next.load();
      expect(next.completed, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'attendance_session'),
        isNull,
      );
      first.dispose();
      next.dispose();
    },
  );

  testWidgets('All three steps remain usable at 320px and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var completed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: QuickGuideScreen(
          onComplete: () async {
            completed++;
          },
        ),
      ),
    );
    for (int step = 0; step < 2; step++) {
      await tester.scrollUntilVisible(find.text('Tiếp theo'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếp theo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(find.text('Bắt đầu'), 150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skip opens the app and the guide can be replayed', (
    tester,
  ) async {
    final controller = FirstRunController();
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: FirstRunGate(
          controller: controller,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuickGuide(context),
                child: const Text('Xem hướng dẫn'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();
    expect(find.text('Xem hướng dẫn'), findsOneWidget);
    await tester.tap(find.text('Xem hướng dẫn'));
    await tester.pumpAndSettle();
    expect(find.text('Đóng'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Xem hướng dẫn'), findsOneWidget);
    controller.dispose();
  });
}
