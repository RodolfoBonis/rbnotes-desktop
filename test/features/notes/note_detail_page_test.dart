import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_page.dart';

import '../../helpers/test_db.dart';
import '../../helpers/widget_harness.dart';

void main() {
  late WidgetHarness h;

  setUp(() async => h = await WidgetHarness.create());
  tearDown(() => h.dispose());

  testWidgets('renderiza título, segmentos e permite tocar no segmento', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedNote(h.db, id: 'a', title: 'Conversa importante');
      await seedSegment(
        h.db,
        noteId: 'a',
        content: 'primeiro trecho falado',
        endMs: 2000,
      );
      await tester.pumpWidget(h.wrap(const NoteDetailPage(noteId: 'a')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    });

    expect(find.text('Conversa importante'), findsOneWidget);
    expect(find.text('primeiro trecho falado'), findsOneWidget);
    expect(find.text('Eu'), findsOneWidget);

    await tester.tap(find.text('primeiro trecho falado'));
    await tester.pump();
  });

  testWidgets('estado vazio quando a nota não existe', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(h.wrap(const NoteDetailPage(noteId: 'missing')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    });
    expect(find.text('Selecione uma nota'), findsOneWidget);
  });
}
