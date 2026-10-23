import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/features/settings/presentation/settings_page.dart';

import '../../helpers/widget_harness.dart';

void main() {
  late WidgetHarness h;

  setUp(() async => h = await WidgetHarness.create());
  tearDown(() => h.dispose());

  testWidgets('renderiza as seções e o status das permissões', (tester) async {
    await tester.pumpWidget(
      h.wrap(
        BlocProvider(
          create: (_) => ThemeModeCubit(h.prefs),
          child: const SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Aparência'.toUpperCase()), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Microfone'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Microfone'), findsOneWidget);
    // Permissões concedidas no fake aparecem com check (sem botão "Permitir").
    expect(find.text('Permitir'), findsNothing);
  });
}
