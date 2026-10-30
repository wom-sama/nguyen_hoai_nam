import 'dart:math' as math;
import 'dart:ui';

/// Local framing observations, never evidence of identity or liveness.
class FaceScanObservation {
  const FaceScanObservation({
    required this.bounds,
    this.yaw,
    this.pitch,
    this.roll,
    this.trackingId,
    required this.eyesVisible,
  });
  final Rect bounds;
  final double? yaw, pitch, roll;
  final int? trackingId;
  final bool eyesVisible;
}

enum FaceScanStatus {
  searching,
  multiple,
  tooSmall,
  tooClose,
  offCenter,
  notFrontal,
  unclear,
  moving,
  hold,
  ready,
}

class FaceScanProgress {
  const FaceScanProgress(
    this.status, {
    this.stableFrames = 0,
    this.stableFor = Duration.zero,
  });
  final FaceScanStatus status;
  final int stableFrames;
  final Duration stableFor;
  bool get ready => status == FaceScanStatus.ready;
  double get fraction => math
      .min(stableFrames / 3, stableFor.inMilliseconds / 700)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Conservative photo-framing heuristics. They do not assess identity or certify
/// anti-spoofing; the unchanged server recognizer and email OTP perform login.
class FaceScanGate {
  FaceScanObservation? _anchor;
  Duration? _since, _last;
  Size? _size;
  int _frames = 0;

  void reset() {
    _anchor = null;
    _since = null;
    _last = null;
    _size = null;
    _frames = 0;
  }

  FaceScanProgress _reject(FaceScanStatus status) {
    reset();
    return FaceScanProgress(status);
  }

  FaceScanProgress observe(
    List<FaceScanObservation> faces, {
    required Size size,
    required Duration at,
  }) {
    if (faces.isEmpty) return _reject(FaceScanStatus.searching);
    if (faces.length != 1) return _reject(FaceScanStatus.multiple);
    final face = faces.single, box = face.bounds;
    if (![
          size.width,
          size.height,
          box.left,
          box.top,
          box.width,
          box.height,
        ].every((number) => number.isFinite) ||
        size.width <= 0 ||
        size.height <= 0 ||
        box.width <= 0 ||
        box.height <= 0) {
      return _reject(FaceScanStatus.searching);
    }
    if (box.width < 100 ||
        box.height < 100 ||
        box.width / size.width < .22 ||
        box.height / size.height < .22) {
      return _reject(FaceScanStatus.tooSmall);
    }
    if (box.left < size.width * .02 ||
        box.top < size.height * .02 ||
        box.right > size.width * .98 ||
        box.bottom > size.height * .98 ||
        box.width / size.width > .86 ||
        box.height / size.height > .86) {
      return _reject(FaceScanStatus.tooClose);
    }
    if ((box.center.dx - size.width / 2).abs() > size.width * .12 ||
        (box.center.dy - size.height / 2).abs() > size.height * .14) {
      return _reject(FaceScanStatus.offCenter);
    }
    if (face.yaw == null ||
        face.pitch == null ||
        face.roll == null ||
        ![
          face.yaw!,
          face.pitch!,
          face.roll!,
        ].every((angle) => angle.isFinite) ||
        face.yaw!.abs() > 18 ||
        face.pitch!.abs() > 18 ||
        face.roll!.abs() > 15) {
      return _reject(FaceScanStatus.notFrontal);
    }
    if (!face.eyesVisible) return _reject(FaceScanStatus.unclear);
    final anchor = _anchor;
    final moved =
        anchor != null &&
        ((face.trackingId != null &&
                anchor.trackingId != null &&
                face.trackingId != anchor.trackingId) ||
            (box.center - anchor.bounds.center).distance >
                math.min(size.width, size.height) * .035 ||
            (box.width / anchor.bounds.width - 1).abs() > .1 ||
            (box.height / anchor.bounds.height - 1).abs() > .1);
    if (_size != size ||
        (_last != null &&
            (at < _last! ||
                at - _last! > const Duration(milliseconds: 1400)))) {
      reset();
    }
    if (moved) {
      reset();
      // The moved frame starts a new hold; previous accepted frames cannot count.
      _anchor = face;
      _since = at;
      _last = at;
      _size = size;
      _frames = 1;
      return const FaceScanProgress(FaceScanStatus.moving, stableFrames: 1);
    }
    _anchor ??= face;
    _since ??= at;
    _last = at;
    _size = size;
    _frames++;
    final elapsed = at - _since!;
    return FaceScanProgress(
      _frames >= 3 && elapsed >= const Duration(milliseconds: 700)
          ? FaceScanStatus.ready
          : FaceScanStatus.hold,
      stableFrames: _frames,
      stableFor: elapsed,
    );
  }
}
