import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Carregado antes de cada arquivo de teste: configura pt-BR como no bootstrap
/// e carrega as fontes empacotadas (Inter + Newsreader) para os golden tests
/// renderizarem com as fontes reais, de forma determinística.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await _loadFonts();
  _useTolerantGoldens();
  await testMain();
}

/// Diferença máxima de pixels aceita num golden. O anti-aliasing de texto varia
/// entre versões do macOS (máquina local × runner do CI) em ~0,1–0,5%; uma
/// mudança real de layout passa bem de 1%.
const _goldenTolerance = 0.01;

void _useTolerantGoldens() {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = _TolerantGoldenComparator(
      Uri.parse('${current.basedir}flutter_test_config.dart'),
    );
  }
}

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _goldenTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> _loadFonts() async {
  // Registra o Inter também sob o nome da fonte do sistema para os goldens
  // renderizarem o corpo (o app real usa SF Pro via '.AppleSystemUIFont').
  const fonts = <String, List<String>>{
    'Inter': ['assets/fonts/InterVariable.ttf'],
    '.AppleSystemUIFont': ['assets/fonts/InterVariable.ttf'],
    '.SF Pro Text': ['assets/fonts/InterVariable.ttf'],
    'Newsreader': ['assets/fonts/Newsreader-VariableFont.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    try {
      await loader.load();
    } on Object catch (_) {
      // Sem bundle de assets neste teste — os fallbacks cuidam do render.
    }
  }
  // Ícones do Material (play, busca, checks, engrenagem…) nos goldens.
  for (final key in const [
    'fonts/MaterialIcons-Regular.otf',
    'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  ]) {
    try {
      await (FontLoader(
        key.contains('Cupertino') ? 'CupertinoIcons' : 'MaterialIcons',
      )..addFont(rootBundle.load(key))).load();
    } on Object catch (_) {
      // ícone opcional nos goldens.
    }
  }
}
