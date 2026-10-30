import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/face/face_scan_gate.dart';

const size = Size(480, 640);
FaceScanObservation face({
  Rect box = const Rect.fromLTWH(120, 160, 240, 300),
  int? id = 1,
  double yaw = 0,
  bool eyes = true,
}) => FaceScanObservation(
  bounds: box,
  yaw: yaw,
  pitch: 0,
  roll: 0,
  trackingId: id,
  eyesVisible: eyes,
);

void main() {
  test(
    'requires three stable frames across at least 700ms, not one detection',
    () {
      final gate = FaceScanGate();
      expect(
        gate.observe([face()], size: size, at: Duration.zero).status,
        FaceScanStatus.hold,
      );
      expect(
        gate
            .observe(
              [face()],
              size: size,
              at: const Duration(milliseconds: 350),
            )
            .ready,
        false,
      );
      expect(
        gate
            .observe(
              [face()],
              size: size,
              at: const Duration(milliseconds: 699),
            )
            .ready,
        false,
      );
      expect(
        gate
            .observe(
              [face()],
              size: size,
              at: const Duration(milliseconds: 700),
            )
            .ready,
        true,
      );
    },
  );

  test(
    'zero/multiple faces, head turn and movement reset previous stability',
    () {
      for (final rejected in [
        <FaceScanObservation>[],
        [face(), face(id: 2)],
        [face(yaw: 28)],
        [face(box: const Rect.fromLTWH(165, 160, 240, 300))],
        [face(id: 2)],
      ]) {
        final gate = FaceScanGate();
        gate.observe([face()], size: size, at: Duration.zero);
        gate.observe(
          [face()],
          size: size,
          at: const Duration(milliseconds: 350),
        );
        expect(
          gate
              .observe(
                rejected,
                size: size,
                at: const Duration(milliseconds: 700),
              )
              .ready,
          false,
        );
        expect(
          gate
              .observe(
                [face()],
                size: size,
                at: const Duration(milliseconds: 1050),
              )
              .ready,
          false,
        );
      }
    },
  );

  test(
    'rejects small/cut-off/off-centre faces, missing eyes and unknown pose',
    () {
      final gate = FaceScanGate();
      for (final observation in [
        face(box: const Rect.fromLTWH(200, 260, 70, 80)),
        face(box: const Rect.fromLTWH(-5, 100, 300, 400)),
        face(box: const Rect.fromLTWH(15, 150, 160, 240)),
        face(eyes: false),
        const FaceScanObservation(
          bounds: Rect.fromLTWH(120, 160, 240, 300),
          eyesVisible: true,
        ),
      ]) {
        expect(
          gate.observe([observation], size: size, at: Duration.zero).status,
          isNot(FaceScanStatus.hold),
        );
      }
      gate.observe([face()], size: size, at: Duration.zero);
      gate.observe([face()], size: size, at: const Duration(milliseconds: 350));
      gate.reset();
      expect(
        gate
            .observe(
              [face()],
              size: size,
              at: const Duration(milliseconds: 1000),
            )
            .stableFrames,
        1,
      );
    },
  );
}
