import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_buffers.dart';

void main() {
  group('PCM16 framing', () {
    test(
      'keeps split bytes and incomplete windows instead of losing speech',
      () {
        final frames = Pcm16FrameBuffer(windowSize: 2);
        expect(frames.addBytes(Uint8List.fromList([0x00])), isEmpty);
        expect(frames.addBytes(Uint8List.fromList([0x80, 0x00])), isEmpty);
        final complete = frames.addBytes(Uint8List.fromList([0x40])).toList();
        expect(complete, hasLength(1));
        expect(complete.single, orderedEquals([-1.0, 0.5]));
        expect(frames.pendingSamples, 0);
        expect(frames.flushTail(), isNull);
      },
    );

    test('flushes final samples once without inventing silence', () {
      final frames = Pcm16FrameBuffer(windowSize: 4);
      frames.addBytes(Uint8List.fromList([0xff, 0x7f, 0xff, 0xff])).toList();
      expect(frames.flushTail(), orderedEquals([32767 / 32768, -1 / 32768]));
      expect(frames.flushTail(), isNull);
    });

    test(
      'reports malformed odd final byte instead of silently discarding it',
      () {
        final frames = Pcm16FrameBuffer(windowSize: 2);
        frames.addBytes(Uint8List.fromList([0x00])).toList();
        expect(frames.flushTail, throwsFormatException);
      },
    );

    test('emits independent frames when the internal window is reused', () {
      final frames = Pcm16FrameBuffer(windowSize: 1);
      final result = frames
          .addBytes(Uint8List.fromList([0, 0, 0, 0x80]))
          .toList();
      expect(result[0], orderedEquals([0.0]));
      expect(result[1], orderedEquals([-1.0]));
    });
  });

  group('bounded utterance queue', () {
    test(
      'rejects overload atomically and keeps accepted utterances in order',
      () {
        final queue = SpeechWorkQueue<String>(maxItems: 2, maxSamples: 8);
        queue.add('first', samples: 3);
        queue.add('second', samples: 4);
        expect(() => queue.add('rejected', samples: 1), throwsStateError);
        expect(queue.length, 2);
        expect(queue.samples, 7);
        expect(queue.removeFirst(), 'first');
        expect(queue.removeFirst(), 'second');
        expect(queue.samples, 0);
      },
    );

    test('bounds audio duration as well as the number of utterances', () {
      final queue = SpeechWorkQueue<String>(maxItems: 10, maxSamples: 8);
      queue.add('first', samples: 6);
      expect(() => queue.add('too long', samples: 3), throwsStateError);
      expect(queue.length, 1);
      expect(queue.samples, 6);
      expect(queue.removeFirst(), 'first');
      queue.add('fits again', samples: 8);
      expect(queue.removeFirst(), 'fits again');
    });

    test('clear releases queued sample accounting for the next session', () {
      final queue = SpeechWorkQueue<String>(maxItems: 2, maxSamples: 8);
      queue.add('old session', samples: 8);
      queue.clear();
      expect(queue.length, 0);
      expect(queue.samples, 0);
      queue.add('new session', samples: 8);
      expect(queue.removeFirst(), 'new session');
    });
  });
}
