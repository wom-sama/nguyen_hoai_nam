part of 'speech_engine.dart';

/// Windows are acknowledged separately so capture can bound its PCM backlog.
class _NativeSpeechWorker {
  _NativeSpeechWorker(this._onEvent, this._onFailure);
  final void Function(Map<Object?, Object?>) _onEvent;
  final void Function(String) _onFailure;
  final _messages = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _requests = <int, Completer<Map<Object?, Object?>>>{};
  Isolate? _isolate;
  SendPort? _commands;
  int _requestId = 0;
  bool _closing = false;
  bool _closed = false;

  static Future<_NativeSpeechWorker> spawn({
    required String role,
    required String modelDirectory,
    String languageCode = 'vi',
    required void Function(Map<Object?, Object?>) onEvent,
    required void Function(String) onFailure,
  }) async {
    final worker = _NativeSpeechWorker(onEvent, onFailure);
    worker._messages.listen(worker._receive);
    worker._errors.listen((Object? error) => worker._failed('$role: $error'));
    worker._exits.listen((_) {
      if (!worker._exited.isCompleted) worker._exited.complete();
      if (!worker._closing) {
        worker._failed('$role worker stopped unexpectedly.');
      }
    });
    try {
      final launch =
          Isolate.spawn(
            role == 'vad' ? _runVadWorker : _runAsrWorker,
            <String, Object>{
              'parent': worker._messages.sendPort,
              'directory': modelDirectory,
              'language': languageCode,
            },
            onError: worker._errors.sendPort,
            onExit: worker._exits.sendPort,
            errorsAreFatal: true,
            debugName: 'nhom8-speech-$role',
          ).then((isolate) {
            worker._isolate = isolate;
            if (worker._closing) isolate.kill(priority: Isolate.immediate);
          });
      await Future.wait<void>([
        launch,
        worker._ready.future.timeout(const Duration(seconds: 60)),
      ], eagerError: true);
      return worker;
    } catch (_) {
      worker._closing = true;
      worker._isolate?.kill(priority: Isolate.immediate);
      worker._closePorts();
      rethrow;
    }
  }

  void _receive(Object? raw) {
    if (_closed || raw is! Map) return;
    final message = Map<Object?, Object?>.from(raw);
    if (message['event'] == 'ready') {
      _commands = message['port'] as SendPort;
      if (!_ready.isCompleted) _ready.complete();
    } else if (message['reply'] is int) {
      final pending = _requests.remove(message['reply']);
      if (pending == null) return;
      if (message['error'] != null) {
        pending.completeError(
          SpeechEngineException(
            'Chưa xử lý được giọng nói. Hãy thử thu âm lại.',
            message['error'],
          ),
        );
      } else {
        pending.complete(message);
      }
    } else if (message['event'] == 'fatal') {
      _failed('${message['detail']}');
    } else {
      _onEvent(message);
    }
  }

  void _failed(String message) {
    if (!_ready.isCompleted) {
      _ready.completeError(
        SpeechEngineException(
          'Chưa chuẩn bị được giọng nói trên thiết bị này. Hãy thử lại.',
          message,
        ),
      );
    }
    for (final pending in _requests.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          SpeechEngineException(
            'Nhận dạng giọng nói bị gián đoạn. Hãy thử thu âm lại.',
            message,
          ),
        );
      }
    }
    _requests.clear();
    if (!_closing && !_closed) _onFailure(message);
  }

  void send(Map<String, Object> command) {
    if (_commands == null || _closed) {
      throw StateError('Speech worker is not ready.');
    }
    _commands!.send(command);
  }

  Future<Map<Object?, Object?>> request(
    Map<String, Object> command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = ++_requestId;
    final completion = Completer<Map<Object?, Object?>>();
    _requests[id] = completion;
    try {
      send({...command, 'id': id});
      return await completion.future.timeout(timeout);
    } finally {
      _requests.remove(id);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closing = true;
    try {
      if (!_exited.isCompleted && _commands != null) {
        await request({'command': 'close'});
        await _exited.future.timeout(const Duration(seconds: 10));
      }
    } catch (error) {
      _isolate?.kill(priority: Isolate.immediate);
      throw SpeechEngineException(
        'Chưa dừng được xử lý giọng nói. Hãy mở lại màn hình dịch.',
        error,
      );
    } finally {
      _closePorts();
    }
  }

  void _closePorts() {
    _closed = true;
    _messages.close();
    _errors.close();
    _exits.close();
    for (final pending in _requests.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Speech worker closed.'));
      }
    }
    _requests.clear();
  }
}

Future<void> _runVadWorker(Map<String, Object> init) async {
  final parent = init['parent'] as SendPort;
  final directory = init['directory'] as String;
  final commands = ReceivePort();
  sherpa.VoiceActivityDetector? detector;
  var session = 0;
  var receivedSamples = 0;

  void drainSegments() {
    final vad = detector!;
    while (!vad.isEmpty()) {
      final segment = vad.front();
      final count = math.min(
        segment.samples.length,
        receivedSamples - segment.start,
      );
      if (count > 0) {
        final samples = Float32List.fromList(segment.samples.sublist(0, count));
        parent.send({
          'event': 'segment',
          'session': session,
          'start': segment.start,
          'audio': TransferableTypedData.fromList([
            samples.buffer.asUint8List(),
          ]),
        });
      }
      vad.pop();
    }
  }

  try {
    await sherpa.initBindingsAsync();
    detector = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: '$directory/silero_vad.onnx',
          threshold: 0.5,
          minSilenceDuration: 0.6,
          minSpeechDuration: 0.25,
          windowSize: 512,
          maxSpeechDuration: 8,
        ),
        sampleRate: 16000,
        numThreads: 1,
        debug: false,
      ),
      bufferSizeInSeconds: 30,
    );
    parent.send({'event': 'ready', 'port': commands.sendPort});
    await for (final raw in commands) {
      final message = raw as Map;
      final id = message['id'];
      try {
        final vad = detector!;
        switch (message['command']) {
          case 'begin':
            vad.reset();
            session = message['session'] as int;
            receivedSamples = 0;
          case 'pcm':
            if (message['session'] != session) continue;
            final samples = (message['samples'] as TransferableTypedData)
                .materialize()
                .asFloat32List();
            receivedSamples += samples.length;
            vad.acceptWaveform(samples);
            drainSegments();
            parent.send({
              'event': 'consumed',
              'session': session,
              'samples': samples.length,
            });
          case 'flush':
            if (message['session'] != session) {
              throw StateError('Stale speech session.');
            }
            final tail = message['tail'] as TransferableTypedData?;
            if (tail != null) {
              final samples = tail.materialize().asFloat32List();
              receivedSamples += samples.length;
              final padded = Float32List(512)
                ..setRange(0, samples.length, samples);
              vad.acceptWaveform(padded);
            }
            vad.flush();
            drainSegments();
          case 'close':
            vad.free();
            detector = null;
            parent.send({'reply': id});
            return;
          default:
            throw StateError('Unsupported VAD command.');
        }
        if (id is int) parent.send({'reply': id});
      } catch (error) {
        if (id is int) {
          parent.send({'reply': id, 'error': error.toString()});
        } else {
          rethrow;
        }
      }
    }
  } catch (error) {
    parent.send({'event': 'fatal', 'detail': 'VAD: $error'});
  } finally {
    detector?.free();
    commands.close();
  }
}

Future<void> _runAsrWorker(Map<String, Object> init) async {
  final parent = init['parent'] as SendPort;
  final directory = init['directory'] as String;
  final commands = ReceivePort();
  sherpa.OfflineRecognizer? recognizer;
  var language = init['language'] as String? ?? 'vi';

  sherpa.OfflineRecognizer createRecognizer(String sourceLanguage) =>
      sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
          model: sourceLanguage == 'vi'
              ? sherpa.OfflineModelConfig(
                  transducer: sherpa.OfflineTransducerModelConfig(
                    encoder: '$directory/encoder.int8.onnx',
                    decoder: '$directory/decoder.onnx',
                    joiner: '$directory/joiner.int8.onnx',
                  ),
                  tokens: '$directory/tokens.txt',
                  numThreads: 1,
                  debug: false,
                )
              : sherpa.OfflineModelConfig(
                  paraformer: sherpa.OfflineParaformerModelConfig(
                    model: '$directory/model.int8.onnx',
                  ),
                  tokens: '$directory/tokens.txt',
                  numThreads: 1,
                  debug: false,
                ),
          decodingMethod: 'greedy_search',
        ),
      );

  try {
    await sherpa.initBindingsAsync();
    recognizer = createRecognizer(language);
    parent.send({'event': 'ready', 'port': commands.sendPort});
    await for (final raw in commands) {
      final message = raw as Map;
      final id = message['id'];
      try {
        switch (message['command']) {
          case 'language':
            final requested = message['language'] as String;
            if (!const {'vi', 'en', 'zh'}.contains(requested)) {
              throw ArgumentError('Unsupported speech language.');
            }
            if (requested != language) {
              if ((requested == 'vi') != (language == 'vi')) {
                throw StateError(
                  'The language family changed; prepare its model first.',
                );
              }
              language = requested;
            }
          case 'decode':
            final samples = (message['audio'] as TransferableTypedData)
                .materialize()
                .asFloat32List();
            final stream = recognizer!.createStream();
            final watch = Stopwatch()..start();
            try {
              stream.acceptWaveform(samples: samples, sampleRate: 16000);
              recognizer.decode(stream);
              parent.send({
                'reply': id,
                'text': recognizer.getResult(stream).text,
                'milliseconds': watch.elapsedMicroseconds / 1000.0,
              });
            } finally {
              stream.free();
            }
            continue;
          case 'close':
            recognizer?.free();
            recognizer = null;
            parent.send({'reply': id});
            return;
          default:
            throw StateError('Unsupported ASR command.');
        }
        parent.send({'reply': id});
      } catch (error) {
        parent.send({'reply': id, 'error': error.toString()});
      }
    }
  } catch (error) {
    parent.send({'event': 'fatal', 'detail': 'ASR: $error'});
  } finally {
    recognizer?.free();
    commands.close();
  }
}
