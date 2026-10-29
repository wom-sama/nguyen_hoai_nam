import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late SpeechModelAsset asset;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('speech-model-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    asset = SpeechModelAsset(
      fileName: 'tiny-fixture.bin',
      url: 'http://127.0.0.1:${server.port}/model',
      bytes: 3,
      sha256:
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  tearDown(() async {
    await server.close(force: true);
    if (directory.parent.absolute.path != Directory.systemTemp.absolute.path ||
        !directory.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('speech-model-test-')) {
      throw StateError('Refusing to delete a directory outside this test.');
    }
    await directory.delete(recursive: true);
  });

  test(
    'publishes only a complete verified model and reuses a verified cache',
    () async {
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.contentLength = 3;
        request.response.add([97, 98, 99]);
        await request.response.close();
      });
      final store = SpeechModelStore(directory: directory, assets: [asset]);
      await store.prepare();
      expect(await File('${directory.path}/${asset.fileName}').readAsBytes(), [
        97,
        98,
        99,
      ]);
      expect(
        await File('${directory.path}/${asset.fileName}.part').exists(),
        isFalse,
      );
      await SpeechModelStore(directory: directory, assets: [asset]).prepare();
      expect(requests, 1);
    },
  );

  test('rejects a corrupt download without leaving a usable model', () async {
    server.listen((request) async {
      request.response.contentLength = 3;
      request.response.add([97, 98, 100]);
      await request.response.close();
    });
    final store = SpeechModelStore(directory: directory, assets: [asset]);
    await expectLater(
      store.prepare(),
      throwsA(isA<SpeechModelDownloadException>()),
    );
    expect(await File('${directory.path}/${asset.fileName}').exists(), isFalse);
    expect(
      await File('${directory.path}/${asset.fileName}.part').exists(),
      isFalse,
    );
  });
}
