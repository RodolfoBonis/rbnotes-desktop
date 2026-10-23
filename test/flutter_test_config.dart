import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Carregado antes de cada arquivo de teste: configura pt-BR como no bootstrap.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await testMain();
}
