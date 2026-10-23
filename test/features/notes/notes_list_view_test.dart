import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_cubit.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_view.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';

import '../../helpers/test_db.dart';
import '../../helpers/widget_harness.dart';

void main() {
  late WidgetHarness h;

  setUp(() async => h = await WidgetHarness.create());
  tearDown(() => h.dispose());

  Widget subject({String? selectedId}) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => RecordingCubit(
          native: h.native,
          repository: h.repo,
          queue: h.queue,
          settings: h.settings,
          paths: h.paths,
        ),
      ),
      BlocProvider(
        create: (_) => NotesListCubit(repository: h.repo, queue: h.queue),
      ),
    ],
    child: NotesListView(
      selectedId: selectedId,
      tags: const [],
      onSelect: (_) {},
    ),
  );

  testWidgets('mostra estado vazio sem notas', (tester) async {
    // Streams do drift fazem I/O real → fora da zona FakeAsync.
    await tester.runAsync(() async {
      await tester.pumpWidget(h.wrap(subject()));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    });
    expect(find.text('Sem notas ainda'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('lista as notas existentes', (tester) async {
    await tester.runAsync(() async {
      await seedNote(h.db, id: 'a', title: 'Minha primeira nota');
      await tester.pumpWidget(h.wrap(subject()));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    });
    expect(find.text('Minha primeira nota'), findsOneWidget);
  });
}
