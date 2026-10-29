import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/ui/paper_backdrop.dart';

void main() {
  testWidgets(
    'Ambient paint stops with reduced motion, hidden tabs and paused app',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      Widget scene({bool enabled = true, bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: enabled,
            child: const SizedBox.expand(child: PaperBackdrop()),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(scene(enabled: false));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(scene(reduced: true));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(scene());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
