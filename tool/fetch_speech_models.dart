import 'dart:io';

import 'package:nguyen_hoai_nam/features/translation/speech_models.dart';

/// Host-side prefetch uses exactly the same pinned manifest and hash checks as
/// first-use downloading on Android. Supply an explicit scratch directory.
/// Example: dart run tool/fetch_speech_models.dart C:/path/to/work/speech-models
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/fetch_speech_models.dart <model-directory> [vi|en|zh]',
    );
    exitCode = 64;
    return;
  }
  final destination = Directory(arguments.first).absolute;
  final modelSet = speechModelSetForLanguage(
    arguments.length == 2 ? arguments[1] : 'vi',
  );
  final store = SpeechModelStore(
    directory: destination,
    assets: modelSet.assets,
  );
  var lastPercent = -1;
  try {
    await store.prepare(
      onProgress: (progress) {
        final percent = (progress * 100).floor();
        if (percent != lastPercent) {
          stdout.writeln('Speech models: $percent%');
          lastPercent = percent;
        }
      },
    );
    stdout.writeln('Verified speech models: ${destination.path}');
  } catch (error) {
    stderr.writeln('Speech model preparation failed: $error');
    exitCode = 1;
  }
}
