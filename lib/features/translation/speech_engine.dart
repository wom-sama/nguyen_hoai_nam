import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_buffers.dart';
import 'speech_models.dart';

part 'speech_workers.dart';

class SpeechEngineSnapshot {
  const SpeechEngineSnapshot({
    this.phase = 'idle',
    this.progress = 0,
    this.queuedSegments = 0,
    this.error,
    this.lastDecodeMs,
  });
  final String phase;
  final double progress;

  /// Includes the utterance currently being decoded.
  final int queuedSegments;
  final String? error;
  final double? lastDecodeMs;
}

class SpeechSegment {
  const SpeechSegment({
    required this.id,
    required this.text,
    required this.languageCode,
    required this.startedAt,
    required this.endedAt,
    required this.decodingMs,
  });
  final String id;
  final String text;
  final String languageCode;
  final DateTime startedAt;
  final DateTime endedAt;
  final double decodingMs;
}

class SpeechEngineException implements Exception {
  const SpeechEngineException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

/// Continuous capture with independent native VAD and ASR Dart isolates.
///
/// Recognizers finalize short speech segments, not partial words. Audio stays
/// on device. Only the selected language family's verified models are loaded.
/// Permission is requested separately while idle; start() only checks it.
class ContinuousSpeechEngine {
  static const _sampleRate = 16000;
  static const _maxInFlightSamples = _sampleRate * 3;
  final _states = StreamController<SpeechEngineSnapshot>.broadcast();
  final _segments = StreamController<SpeechSegment>.broadcast();
  AudioRecorder? _recorder;
  final _queue = SpeechWorkQueue<_Utterance>(
    maxItems: 5,
    maxSamples: _sampleRate * 30,
  );

  SpeechEngineSnapshot _snapshot = const SpeechEngineSnapshot();
  SpeechModelStore? _store;
  _NativeSpeechWorker? _vad;
  _NativeSpeechWorker? _asr;
  Future<void>? _preparing;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<bool>? _permissionRequest;
  StreamSubscription<Uint8List>? _microphone;
  StreamSubscription<RecordState>? _recordingState;
  Completer<void>? _microphoneDone;
  Completer<void>? _decodeDrain;
  Pcm16FrameBuffer _frames = Pcm16FrameBuffer();
  _Utterance? _activeUtterance;
  DateTime? _startedAt;
  String _language = 'vi';
  String? _failure;
  double? _lastDecodeMs;
  int _session = 0;
  int _preparationGeneration = 0;
  int _inFlightSamples = 0;
  int _segmentSequence = 0;
  bool _prepared = false;
  String? _preparedFamily;
  bool _decodeFailed = false;
  bool _capturing = false;
  bool _stopRequested = false;
  bool _disposing = false;
  bool _disposed = false;
  bool _foreground = true;

  void setForeground(bool foreground) => _foreground = foreground;

  /// Ask before model/start work so Android's permission-dialog inactive event
  /// can stop an idle engine without cancelling a startup awaiting permission.
  Future<bool> requestMicrophonePermission() {
    _ensureUsable();
    if (_capturing || _starting != null || !_foreground) {
      return Future.error(
        const SpeechEngineException(
          'Hãy mở màn hình dịch trước khi cấp quyền micro.',
        ),
      );
    }
    return _permissionRequest ??= _requestMicrophonePermission().whenComplete(
      () => _permissionRequest = null,
    );
  }

  Future<bool> _requestMicrophonePermission() async {
    final allowed = await (_recorder ??= AudioRecorder()).hasPermission();
    final stopping = _stopping;
    if (stopping != null) await stopping;
    _ensureUsable();
    return allowed;
  }

  /// Every new listener receives the current state before subsequent updates.
  Stream<SpeechEngineSnapshot> get states =>
      Stream<SpeechEngineSnapshot>.multi((controller) {
        controller.add(_snapshot);
        final subscription = _states.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);
  Stream<SpeechSegment> get segments => _segments.stream;

  Future<void> prepare({String languageCode = 'vi'}) {
    _ensureUsable();
    if (!const {'vi', 'en', 'zh'}.contains(languageCode)) {
      return Future.error(
        const SpeechEngineException('Ngôn ngữ nhận dạng chưa được hỗ trợ.'),
      );
    }
    final family = speechModelSetForLanguage(languageCode).cacheName;
    if (_preparing != null && languageCode != _language) {
      return Future.error(
        const SpeechEngineException(
          'Hãy chờ chuẩn bị ngôn ngữ hiện tại kết thúc.',
        ),
      );
    }
    if (_capturing ||
        _stopping != null ||
        _activeUtterance != null ||
        _queue.length > 0) {
      return Future.error(
        const SpeechEngineException(
          'Hãy chờ phiên giọng nói hiện tại kết thúc trước khi chuẩn bị lại.',
        ),
      );
    }
    if (_prepared && _preparedFamily == family) {
      _language = languageCode;
      return Future.value();
    }
    _language = languageCode;
    return _preparing ??= _prepareImpl(languageCode)
        .whenComplete(() => _preparing = null);
  }

  Future<void> _prepareImpl(String languageCode) async {
    final generation = _preparationGeneration;
    final modelSet = speechModelSetForLanguage(languageCode);
    try {
      if (!Platform.isAndroid) {
        throw const SpeechEngineException(
          'Bộ dịch giọng nói này cần chạy trên Android.',
        );
      }
      _failure = null;
      await _closeWorkers();
      _emit('downloading', progress: 0);
      final support = await getApplicationSupportDirectory();
      _checkPreparation(generation);
      final models = Directory(
        '${support.path}/speech-models/${modelSet.cacheName}',
      );
      final store = _store = SpeechModelStore(
        directory: models,
        assets: modelSet.assets,
      );
      await store.prepare(
        onProgress: (progress) {
          if (generation == _preparationGeneration && !_disposing) {
            _emit('downloading', progress: progress);
          }
        },
      );
      _checkPreparation(generation);
      _emit('loading', progress: 1);
      _vad = await _NativeSpeechWorker.spawn(
        role: 'vad',
        modelDirectory: models.path,
        onEvent: _onVadEvent,
        onFailure: _onWorkerFailure,
      );
      _checkPreparation(generation);
      _asr = await _NativeSpeechWorker.spawn(
        role: 'asr',
        modelDirectory: models.path,
        languageCode: languageCode,
        onEvent: (_) {},
        onFailure: _onAsrFailure,
      );
      _checkPreparation(generation);
      _prepared = true;
      _preparedFamily = modelSet.cacheName;
      _emit('idle', progress: 1);
    } on SpeechDownloadCancelled {
      await _closeWorkers();
      if (!_disposing) _emit('idle', progress: 0, clearError: true);
      rethrow;
    } catch (error) {
      await _closeWorkers();
      _failure = error is SpeechEngineException ? error.message : 'Chưa chuẩn bị được gói giọng nói. Kiểm tra kết nối mạng rồi thử lại.';
      _emit('error');
      rethrow;
    } finally {
      _store = null;
    }
  }

  Future<void> start({required String languageCode}) {
    _ensureUsable();
    if (!_foreground) {
      return Future.error(
        const SpeechEngineException(
          'Chờ ứng dụng trở lại màn hình để bắt đầu thu âm.',
        ),
      );
    }
    if (!const {'vi', 'en', 'zh'}.contains(languageCode)) {
      return Future.error(
        const SpeechEngineException(
          'Hãy chọn tiếng Việt, tiếng Anh hoặc tiếng Trung.',
        ),
      );
    }
    if (_capturing ||
        _starting != null ||
        _stopping != null ||
        _activeUtterance != null ||
        _queue.length > 0) {
      return Future.error(
        const SpeechEngineException(
          'Phiên giọng nói đang hoạt động. Hãy dừng phiên hiện tại trước.',
        ),
      );
    }
    return _starting = _startImpl(languageCode)
        .whenComplete(() => _starting = null);
  }

  Future<void> _startImpl(String languageCode) async {
    try {
      await prepare(languageCode: languageCode);
      if (_stopRequested || _disposing) throw const SpeechDownloadCancelled();
      _ensureUsable();
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission(request: false)) {
        throw const SpeechEngineException(
          'Chưa có quyền micro. Hãy cho phép micro để bắt đầu dịch.',
        );
      }
      if (!await recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
        throw const SpeechEngineException(
          'Micro trên thiết bị này không hỗ trợ luồng âm thanh cần thiết.',
        );
      }
      _language = languageCode;
      _failure = null;
      _decodeFailed = false;
      _queue.clear();
      _activeUtterance = null;
      _frames = Pcm16FrameBuffer();
      _inFlightSamples = 0;
      _segmentSequence = 0;
      final session = ++_session;
      _emit('loading', progress: 1);
      await _asr!.request({'command': 'language', 'language': languageCode});
      await _vad!.request({'command': 'begin', 'session': session});
      if (_stopRequested || _disposing || !_foreground) {
        throw const SpeechDownloadCancelled();
      }
      _ensureUsable();
      _startedAt = DateTime.now();
      _microphoneDone = Completer<void>();
      _recordingState = recorder.onStateChanged().listen(
        (state) {
          if (state == RecordState.pause && _capturing && !_stopRequested) {
            _scheduleFailure(
              'Micro bị gián đoạn. Phiên đã dừng để tránh thiếu nội dung; hãy bắt đầu lại.',
            );
          }
        },
        onError: (Object error) {
          _scheduleFailure('Kết nối micro bị gián đoạn. Hãy thử thu âm lại.');
        },
      );
      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          streamBufferSize: 3200,
        ),
      );
      if (_stopRequested || _disposing || !_foreground) {
        await recorder.stop();
        await _recordingState?.cancel();
        _recordingState = null;
        throw const SpeechDownloadCancelled();
      }
      _capturing = true;
      _microphone = audio.listen(
        (bytes) => _acceptAudio(bytes, session),
        onError: (Object error) {
          _completeMicrophone();
          _scheduleFailure(
            'Micro không thể tiếp tục thu âm. Hãy thử thu âm lại.',
          );
        },
        onDone: () {
          _completeMicrophone();
          if (_capturing && !_stopRequested) {
            _scheduleFailure('Micro đã ngắt. Hãy bắt đầu lại phiên dịch.');
          }
        },
        cancelOnError: false,
      );
      _emit('listening', progress: 1);
    } on SpeechDownloadCancelled {
      if (!_disposing) _emit('idle', progress: _prepared ? 1 : 0);
      rethrow;
    } catch (error) {
      _failure = error is SpeechEngineException
          ? error.message
          : 'Chưa bắt đầu được thu âm. Kiểm tra quyền micro rồi thử lại.';
      _emit('error');
      if (_capturing) {
        await stop();
      } else {
        await _recordingState?.cancel();
        _recordingState = null;
      }
      rethrow;
    }
  }

  void _acceptAudio(Uint8List bytes, int session) {
    if (!_capturing || session != _session || _failure != null) return;
    try {
      if (bytes.length > _sampleRate * 2 * 2) {
        throw StateError('Micro delivered more than two seconds at once.');
      }
      for (final frame in _frames.addBytes(bytes)) {
        if (_inFlightSamples + frame.length > _maxInFlightSamples) {
          throw StateError('VAD cannot keep up with microphone capture.');
        }
        _inFlightSamples += frame.length;
        _vad!.send({
          'command': 'pcm',
          'session': session,
          'samples': TransferableTypedData.fromList([
            frame.buffer.asUint8List(),
          ]),
        });
      }
    } catch (error) {
      _scheduleFailure(
        'Thiết bị xử lý âm thanh không kịp nên đã dừng thu âm. Một số nội dung có thể chưa được lưu. Hãy thử câu ngắn hơn.',
      );
    }
  }

  void _onVadEvent(Map<Object?, Object?> event) {
    if (_disposed || event['session'] != _session) return;
    switch (event['event']) {
      case 'consumed':
        _inFlightSamples = math.max(
          0,
          _inFlightSamples - (event['samples'] as int),
        );
      case 'segment':
        if (_decodeFailed) return;
        try {
          final samples = (event['audio'] as TransferableTypedData)
              .materialize()
              .asFloat32List();
          if (samples.isEmpty) return;
          _queue.add(
            _Utterance(
              session: _session,
              sequence: ++_segmentSequence,
              startSample: event['start'] as int,
              samples: samples,
            ),
            samples: samples.length,
          );
          _dispatchNext();
          _emitCurrent();
        } catch (error) {
          _scheduleFailure(
            'Đã dừng thu âm vì thiết bị đang xử lý quá nhiều đoạn. Một số nội dung có thể chưa được lưu; hãy chờ hoàn tất rồi bắt đầu thu âm lại.',
          );
        }
    }
  }

  void _dispatchNext() {
    if (_activeUtterance != null || _queue.length == 0 || _asr == null) {
      _completeDrainIfReady();
      return;
    }
    final utterance = _activeUtterance = _queue.removeFirst();
    unawaited(_decode(utterance));
  }

  Future<void> _decode(_Utterance utterance) async {
    try {
      final result = await _asr!.request({
        'command': 'decode',
        'audio': TransferableTypedData.fromList([
          utterance.samples.buffer.asUint8List(
            utterance.samples.offsetInBytes,
            utterance.samples.lengthInBytes,
          ),
        ]),
      }, timeout: const Duration(seconds: 45));
      if (utterance.session != _session || _disposed) return;
      _lastDecodeMs = (result['milliseconds'] as num).toDouble();
      final text = (result['text'] as String).trim();
      final origin = _startedAt;
      if (text.isNotEmpty && origin != null) {
        final started = origin.add(
          Duration(
            microseconds: (utterance.startSample * 1000000 / _sampleRate)
                .round(),
          ),
        );
        final ended = started.add(
          Duration(
            microseconds: (utterance.samples.length * 1000000 / _sampleRate)
                .round(),
          ),
        );
        _segments.add(
          SpeechSegment(
            id: '${origin.microsecondsSinceEpoch}-${utterance.sequence}',
            text: text,
            languageCode: _language,
            startedAt: started,
            endedAt: ended,
            decodingMs: _lastDecodeMs!,
          ),
        );
      }
    } catch (error) {
      _decodeFailed = true;
      _prepared = false;
      final unprocessed = _queue.length + 1;
      _queue.clear();
      _scheduleFailure(
        'Chưa nhận được nội dung giọng nói. Có $unprocessed đoạn chưa được lưu; hãy thử thu âm lại.',
      );
    } finally {
      _activeUtterance = null;
      _dispatchNext();
      _emitCurrent();
    }
  }

  Future<void> stop() {
    if (_disposed) return Future.value();
    return _stopping ??= _stopImpl().whenComplete(() => _stopping = null);
  }

  Future<void> _stopImpl() async {
    _stopRequested = true;
    try {
      final preparation = _preparing;
      if (preparation != null && !_capturing) {
        _preparationGeneration++;
        _store?.cancel();
        try {
          await preparation;
        } on SpeechDownloadCancelled {
          // Expected: a user-requested stop cancels first-use model preparation.
        }
      }
      final startup = _starting;
      if (startup != null && !_capturing) {
        try {
          await startup;
        } on SpeechDownloadCancelled {
          // Startup observes _stopRequested before opening the microphone.
        }
      }
      if (_capturing) {
        _emit('processing');
        await _recorder!.stop();
        await _microphoneDone?.future.timeout(const Duration(seconds: 5));
        await _microphone?.cancel();
        _microphone = null;
        _capturing = false;
        await _recordingState?.cancel();
        _recordingState = null;
        final tail = _frames.flushTail();
        await _vad!.request({
          'command': 'flush',
          'session': _session,
          if (tail != null)
            'tail': TransferableTypedData.fromList([tail.buffer.asUint8List()]),
        });
      }
      if (_activeUtterance != null || _queue.length > 0) {
        _emit('processing');
        final drain = _decodeDrain ??= Completer<void>();
        _completeDrainIfReady();
        await drain.future.timeout(const Duration(seconds: 75));
      }
      _emit(_failure == null ? 'idle' : 'error', progress: _prepared ? 1 : 0);
    } catch (error) {
      _failure ??= 'Chưa hoàn tất được lần thu âm này. Có nội dung chưa được xử lý; hãy kiểm tra các đoạn đã lưu trước khi thu âm lại.';
      _emit('error');
      rethrow;
    } finally {
      _capturing = false;
      await _microphone?.cancel();
      _microphone = null;
      await _recordingState?.cancel();
      _recordingState = null;
      _stopRequested = false;
      _decodeDrain = null;
    }
  }

  void _completeMicrophone() {
    final done = _microphoneDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _completeDrainIfReady() {
    final drain = _decodeDrain;
    if (_activeUtterance == null &&
        _queue.length == 0 &&
        drain != null &&
        !drain.isCompleted) {
      drain.complete();
    }
  }

  void _onWorkerFailure(String detail) {
    _prepared = false;
    _scheduleFailure('Nhận dạng giọng nói bị gián đoạn. Hãy thử thu âm lại.');
  }

  void _onAsrFailure(String detail) {
    _decodeFailed = true;
    _queue.clear();
    _onWorkerFailure(detail);
  }

  void _scheduleFailure(String message) {
    if (_disposed || _disposing) return;
    final alreadyFailed = _failure != null;
    _failure ??= message;
    _emit('error');
    if (!alreadyFailed && _capturing && _stopping == null) {
      unawaited(() async {
        try {
          await stop();
        } catch (error) {
          _failure ??= 'Chưa dừng được thu âm hoàn toàn. Hãy thử dừng lại hoặc mở lại màn hình dịch.';
          _emit('error');
        }
      }());
    }
  }

  void _emitCurrent() {
    if (_disposed) return;
    final phase = _failure != null
        ? 'error'
        : _capturing && !_stopRequested
        ? 'listening'
        : _activeUtterance != null || _queue.length > 0
        ? 'processing'
        : _snapshot.phase;
    _emit(phase);
  }

  void _emit(String phase, {double? progress, bool clearError = false}) {
    if (_disposed) return;
    if (clearError) _failure = null;
    _snapshot = SpeechEngineSnapshot(
      phase: phase,
      progress: (progress ?? _snapshot.progress).clamp(0.0, 1.0),
      queuedSegments: _queue.length + (_activeUtterance == null ? 0 : 1),
      error: _failure,
      lastDecodeMs: _lastDecodeMs,
    );
    _states.add(_snapshot);
  }

  void _checkPreparation(int generation) {
    if (generation != _preparationGeneration || _disposing || _disposed) {
      throw const SpeechDownloadCancelled();
    }
    if (_failure != null) throw SpeechEngineException(_failure!);
  }

  void _ensureUsable() {
    if (_disposed || _disposing) {
      throw StateError('Speech engine has been disposed.');
    }
  }

  Future<void> _closeWorkers() async {
    _prepared = false;
    _preparedFamily = null;
    final workers = [_vad, _asr];
    _vad = null;
    _asr = null;
    final failures = <Object>[];
    for (final worker in workers) {
      if (worker == null) continue;
      try {
        await worker.close();
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw SpeechEngineException(
        'Không giải phóng được bộ nhận giọng nói.',
        failures.first,
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed || _disposing) return;
    _disposing = true;
    Object? failure;
    try {
      await stop();
    } catch (error) {
      failure = error;
    }
    try {
      await _closeWorkers();
    } catch (error) {
      failure ??= error;
    }
    try {
      await _recorder?.dispose();
    } catch (error) {
      failure ??= error;
    }
    _disposed = true;
    await _states.close();
    await _segments.close();
    if (failure != null) {
      throw SpeechEngineException(
        'Phiên giọng nói đã đóng nhưng có lỗi dọn dẹp.',
        failure,
      );
    }
  }
}

class _Utterance {
  const _Utterance({
    required this.session,
    required this.sequence,
    required this.startSample,
    required this.samples,
  });
  final int session;
  final int sequence;
  final int startSample;
  final Float32List samples;
}
