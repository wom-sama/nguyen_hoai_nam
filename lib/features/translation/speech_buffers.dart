import 'dart:collection';
import 'dart:typed_data';

/// Bounded PCM framing shared by microphone capture and its unit tests.
class Pcm16FrameBuffer {
  Pcm16FrameBuffer({this.windowSize = 512})
    : _window = Float32List(windowSize) {
    if (windowSize <= 0) throw ArgumentError.value(windowSize, 'windowSize');
  }

  final int windowSize;
  final Float32List _window;
  int _length = 0;
  int? _lowByte;

  int get pendingSamples => _length;

  /// PCM callbacks may split both an int16 sample and a VAD window.
  ///
  /// Consume the iterable fully before supplying another chunk. Only one
  /// window and at most one incomplete byte are retained between callbacks.
  Iterable<Float32List> addBytes(Uint8List bytes) sync* {
    for (final byte in bytes) {
      final low = _lowByte;
      if (low == null) {
        _lowByte = byte;
        continue;
      }
      final unsigned = low | (byte << 8);
      final signed = unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
      _lowByte = null;
      _window[_length++] = signed / 32768.0;
      if (_length == windowSize) {
        _length = 0;
        yield Float32List.fromList(_window);
      }
    }
  }

  Float32List? flushTail() {
    if (_lowByte != null) {
      throw const FormatException(
        'The microphone ended inside a PCM16 sample.',
      );
    }
    if (_length == 0) return null;
    final tail = Float32List.fromList(_window.sublist(0, _length));
    _length = 0;
    return tail;
  }
}

/// A queue bounded by both the number and duration of pending utterances.
class SpeechWorkQueue<T> {
  SpeechWorkQueue({required this.maxItems, required this.maxSamples}) {
    if (maxItems <= 0 || maxSamples <= 0) {
      throw ArgumentError('Speech queue limits must be positive.');
    }
  }

  final int maxItems;
  final int maxSamples;
  final Queue<(T, int)> _items = Queue<(T, int)>();
  int _samples = 0;

  int get length => _items.length;
  int get samples => _samples;

  void add(T item, {required int samples}) {
    if (samples <= 0) throw ArgumentError.value(samples, 'samples');
    if (_items.length >= maxItems || _samples + samples > maxSamples) {
      throw StateError('Speech processing cannot keep up with the microphone.');
    }
    _items.addLast((item, samples));
    _samples += samples;
  }

  T removeFirst() {
    final (item, samples) = _items.removeFirst();
    _samples -= samples;
    return item;
  }

  void clear() {
    _items.clear();
    _samples = 0;
  }
}
