import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Business-flow assertions use the supported reduced-motion setting so an
// ambient repeating watermark does not prevent pumpAndSettle from finishing.
// paper_backdrop_test.dart explicitly enables motion and checks its lifecycle.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    // Do not create a widget binding in pure Dart tests: that would replace
    // their real local-fixture HttpClient with the widget-test HTTP override.
    if (BindingBase.debugBindingType() != null) {
      TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
    }
  });
  await testMain();
}
