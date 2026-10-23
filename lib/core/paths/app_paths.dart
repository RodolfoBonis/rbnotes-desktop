import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Diretórios do app em Application Support/RbNotes.
///
/// `recordings/` guarda os `.m4a`/`.wav`; `models/` os modelos whisper.
class AppPaths {
  AppPaths._(this.root);

  /// Para testes: usa [root] diretamente, sem depender do path_provider.
  @visibleForTesting
  AppPaths.forTesting(this.root);

  final Directory root;

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'RbNotes'));
    await root.create(recursive: true);
    final paths = AppPaths._(root);
    await Directory(paths.recordingsDir).create(recursive: true);
    await Directory(paths.modelsDir).create(recursive: true);
    return paths;
  }

  String get recordingsDir => p.join(root.path, 'recordings');

  String get modelsDir => p.join(root.path, 'models');
}
