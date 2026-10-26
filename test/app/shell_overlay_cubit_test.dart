import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';

void main() {
  test('abre e fecha overlays mutuamente exclusivos', () {
    final cubit = ShellOverlayCubit()..openAsk();
    expect(cubit.state.askOpen, isTrue);
    cubit.closeAsk();
    expect(cubit.state.askOpen, isFalse);
    cubit.toggleAsk();
    expect(cubit.state.askOpen, isTrue);
    unawaited(cubit.close());
  });

  test('closeTop fecha o overlay de topo na ordem de prioridade', () {
    final cubit = ShellOverlayCubit()
      ..openAsk()
      ..openNewCollection()
      ..openFix('Taís');
    expect(cubit.closeTop(), isTrue); // fecha fix
    expect(cubit.state.fixOpen, isFalse);
    expect(cubit.closeTop(), isTrue); // fecha nova coleção
    expect(cubit.state.newCollectionOpen, isFalse);
    expect(cubit.closeTop(), isTrue); // fecha ask
    expect(cubit.state.askOpen, isFalse);
    expect(cubit.closeTop(), isFalse); // nada aberto
    unawaited(cubit.close());
  });

  test('showToast define e depois limpa a mensagem', () async {
    final cubit = ShellOverlayCubit()..showToast('oi');
    expect(cubit.state.toast, 'oi');
    await Future<void>.delayed(const Duration(milliseconds: 2700));
    expect(cubit.state.toast, isNull);
    await cubit.close();
  });
}
