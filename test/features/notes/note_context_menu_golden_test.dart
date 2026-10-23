import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/ui/rb_menu.dart';

import '../../helpers/golden.dart';

void main() {
  for (final dark in [false, true]) {
    final name = dark ? 'note_context_menu_dark' : 'note_context_menu';
    testWidgets('golden do menu de contexto da nota ($name)', (tester) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            backgroundColor: dark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFFF2F2F7),
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRbMenu<String>(
                  context: context,
                  position: const Offset(130, 130),
                  items: const [
                    RbMenuItem(
                      value: 'rename',
                      label: 'Renomear',
                      icon: Icons.edit_outlined,
                    ),
                    RbMenuItem(
                      value: 'move',
                      label: 'Mover para pasta…',
                      icon: Icons.folder_outlined,
                      trailing: Icon(Icons.chevron_right, size: 16),
                    ),
                    RbMenuItem(
                      value: 'fav',
                      label: 'Favoritar',
                      icon: Icons.star_border,
                    ),
                    RbMenuItem(
                      value: 'dup',
                      label: 'Duplicar',
                      icon: Icons.copy_outlined,
                    ),
                    RbMenuItem(
                      value: 'export',
                      label: 'Exportar…',
                      icon: Icons.ios_share,
                      dividerAbove: true,
                    ),
                    RbMenuItem(
                      value: 'copy',
                      label: 'Copiar transcrição',
                      icon: Icons.content_copy_outlined,
                    ),
                    RbMenuItem(
                      value: 'retryT',
                      label: 'Tentar transcrever de novo',
                      icon: Icons.graphic_eq,
                      dividerAbove: true,
                    ),
                    RbMenuItem(
                      value: 'retryS',
                      label: 'Gerar resumo de novo',
                      icon: Icons.auto_awesome_outlined,
                    ),
                    RbMenuItem(
                      value: 'delete',
                      label: 'Apagar',
                      icon: Icons.delete_outline,
                      destructive: true,
                      dividerAbove: true,
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        size: const Size(420, 460),
        dark: dark,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
