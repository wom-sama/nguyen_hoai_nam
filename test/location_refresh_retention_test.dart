import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/features/location/location_screen.dart';
import 'package:nguyen_hoai_nam/ui/components.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.value);
  final int value;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  var count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('value ${widget.value}, count $count'),
  );
}

void main() {
  testWidgets(
    'opted-in async child retains state through pending and successful refresh',
    (tester) async {
      final source = ValueNotifier<Future<int>>(Future.value(1));
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: source,
              builder: (_, future, child) => AsyncPanel<int>(
                future: future,
                keepDataWhileLoading: true,
                onRetry: () {},
                builder: _Probe.new,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('value 1, count 0'));
      await tester.pump();
      final state = tester.state(find.byType(_Probe));
      final pending = Completer<int>();
      source.value = pending.future;
      await tester.pump();
      expect(find.text('value 1, count 1'), findsOneWidget);
      expect(tester.state(find.byType(_Probe)), same(state));
      pending.complete(2);
      await tester.pumpAndSettle();
      expect(find.text('value 2, count 1'), findsOneWidget);
      expect(tester.state(find.byType(_Probe)), same(state));
    },
  );

  testWidgets('retained data never masks fetch errors or retry recovery', (
    tester,
  ) async {
    final source = ValueNotifier<Future<int>>(Future.value(1));
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: source,
            builder: (_, future, child) => AsyncPanel<int>(
              future: future,
              keepDataWhileLoading: true,
              onRetry: () => source.value = Future.value(3),
              builder: _Probe.new,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pending = Completer<int>();
    source.value = pending.future;
    await tester.pump();
    pending.completeError(
      const ApiException('NETWORK', 'Mất kết nối kiểm thử.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối kiểm thử.'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('value 3, count 0'), findsOneWidget);
    expect(find.text('Mất kết nối kiểm thử.'), findsNothing);
  });

  testWidgets(
    'ordinary async panels still replace data with progress by default',
    (tester) async {
      final source = ValueNotifier<Future<int>>(Future.value(1));
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: source,
              builder: (_, future, child) => AsyncPanel<int>(
                future: future,
                onRetry: () {},
                builder: _Probe.new,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      source.value = Completer<int>().future;
      await tester.pump();
      expect(find.byType(_Probe), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('stopped or consent-expired point cannot return through cached or late data', () {
    final now = DateTime.utc(2026, 10, 29, 10);
    final expiry = LocationShareExpiry(now: () => now, onExpire: () {});
    addTearDown(expiry.dispose);
    final row = <String, dynamic>{
      'id': 'own',
      'expiresAt': now.add(const Duration(minutes: 1)).toIso8601String(),
    };
    expect(expiry.visibleRows([row]), hasLength(1));
    expiry.forget('own');
    expect(expiry.visibleRows([row]), isEmpty);
    expiry.restore('own');
    expect(expiry.visibleRows([row]), hasLength(1));
  });

  testWidgets(
    'expiry removes retained points exactly on deadline even while the next fetch stalls',
    (tester) async {
      var now = DateTime.utc(2026, 10, 29, 10);
      var expirations = 0;
      final changes = ValueNotifier<int>(0);
      final expiry = LocationShareExpiry(
        now: () => now,
        onExpire: () {
          expirations++;
          changes.value++;
        },
      );
      addTearDown(expiry.dispose);
      addTearDown(changes.dispose);
      final rows = <Json>[
        {
          'id': 'own',
          'expiresAt': now.add(const Duration(seconds: 1)).toIso8601String(),
        },
        {
          'id': 'colleague',
          'expiresAt': now.add(const Duration(seconds: 2)).toIso8601String(),
        },
        {'id': 'invalid', 'expiresAt': 'invalid'},
      ];
      expiry.schedule(
        rows,
        consentExpiresAt: now.add(const Duration(seconds: 1)),
      );
      final source = ValueNotifier<Future<List<Json>>>(Future.value(rows));
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: source,
              builder: (_, future, child) => AsyncPanel<List<Json>>(
                future: future,
                keepDataWhileLoading: true,
                onRetry: () {},
                builder: (loaded) => ValueListenableBuilder(
                  valueListenable: changes,
                  builder: (_, value, child) => Column(
                    children: [
                      for (final row in expiry.visibleRows(loaded))
                        Text('point ${row['id']}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      source.value = Completer<List<Json>>().future;
      await tester.pump();
      expect(find.text('point own'), findsOneWidget);
      expect(find.text('point invalid'), findsNothing);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('point own'), findsNothing);
      expect(find.text('point colleague'), findsOneWidget);
      expect(expirations, 1);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('point colleague'), findsNothing);
      expect(expirations, 2);
      expiry.schedule([
        {'expiresAt': now.add(const Duration(seconds: 1)).toIso8601String()},
      ]);
      expiry.dispose();
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(expirations, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
