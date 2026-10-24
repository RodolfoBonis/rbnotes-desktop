import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/library/presentation/sidebar.dart';
import 'package:rbnotes/features/sync/data/sync_status.dart';

void main() {
  Future<void> pumpWith(WidgetTester tester, SyncStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RbNotesTheme.light(),
        home: Scaffold(
          body: SyncIndicator(status: Stream.value(status)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mostra "Sincronizado" quando ocioso sem pendências', (
    tester,
  ) async {
    await pumpWith(tester, SyncStatus(lastSyncAt: DateTime.now()));
    expect(find.text('Sincronizado'), findsOneWidget);
  });

  testWidgets('mostra "Sincronizando…" durante o ciclo', (tester) async {
    await pumpWith(tester, const SyncStatus(phase: SyncPhase.syncing));
    expect(find.text('Sincronizando…'), findsOneWidget);
  });

  testWidgets('mostra erro', (tester) async {
    await pumpWith(
      tester,
      const SyncStatus(phase: SyncPhase.error, message: 'Boom'),
    );
    expect(find.text('Erro de sincronização'), findsOneWidget);
  });

  testWidgets('mostra pendências quando há alterações não enviadas', (
    tester,
  ) async {
    await pumpWith(tester, const SyncStatus(pendingCount: 2));
    expect(find.text('2 alterações pendentes'), findsOneWidget);
  });

  testWidgets('mostra "Sem conexão" offline', (tester) async {
    await pumpWith(
      tester,
      const SyncStatus(phase: SyncPhase.offline, pendingCount: 1),
    );
    expect(find.text('Sem conexão'), findsOneWidget);
  });
}
