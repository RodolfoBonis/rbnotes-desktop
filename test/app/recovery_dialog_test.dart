import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rbnotes/app/shell/recovery_dialog.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

class _MockRecoveryCubit extends MockCubit<RecoveryState>
    implements RecoveryCubit {}

const _rec = RecoverableRecording(
  id: 'r1',
  micWavPath: '/tmp/r1.mic.wav',
  systemWavPath: null,
  duration: Duration(seconds: 19),
);

/// Regressão: com o tema real do app (sem extensões do Forma) o diálogo
/// quebrava num null check e deixava só a barreira cinza na tela.
void main() {
  late _MockRecoveryCubit cubit;
  late StreamController<RecoveryState> states;

  setUp(() {
    cubit = _MockRecoveryCubit();
    states = StreamController<RecoveryState>.broadcast();
    when(
      () => cubit.state,
    ).thenReturn(const RecoveryState(recoverable: [_rec]));
    whenListen(
      cubit,
      states.stream,
      initialState: const RecoveryState(recoverable: [_rec]),
    );
  });

  tearDown(() => states.close());

  Future<void> open(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRecoveryDialog(context, cubit),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  for (final entry in {
    'claro': RbNotesTheme.light(),
    'escuro': RbNotesTheme.dark(),
  }.entries) {
    testWidgets('renderiza com o tema ${entry.key} do app', (tester) async {
      await open(tester, entry.value);
      expect(tester.takeException(), isNull);
      expect(find.text('Gravações interrompidas'), findsOneWidget);
      expect(find.text('Recuperar'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
    });
  }

  testWidgets('fecha sozinho quando não sobra nada para recuperar', (
    tester,
  ) async {
    await open(tester, RbNotesTheme.light());
    expect(find.byType(AlertDialog), findsOneWidget);

    when(() => cubit.state).thenReturn(const RecoveryState());
    states.add(const RecoveryState());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
