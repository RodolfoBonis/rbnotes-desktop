import 'dart:async';

import 'package:rbnotes/app/shell/tray_host.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:tray_manager/tray_manager.dart';

/// Ícone da menu bar: Gravar/Parar, status e "Abrir RbNotes".
///
/// A presença do ícone segue "Mostrar na barra de menus" (aba Geral) e pode ser
/// alternada ao vivo por [setVisible]. O menu é reconstruído quando o estado de
/// gravação muda. Enquanto visível, o menu nunca expõe o título de uma nota —
/// só "RbNotes" e o estado da gravação —, então continua seguro com o app
/// travado por Touch ID.
class TrayController with TrayListener {
  TrayController({
    required this.recording,
    required this.onOpen,
    required SettingsStore settings,
    TrayHost host = const RealTrayHost(),
  }) : _settings = settings,
       _host = host;

  final RecordingCubit recording;
  final Future<void> Function() onOpen;
  final SettingsStore _settings;
  final TrayHost _host;

  StreamSubscription<RecordingState>? _sub;
  bool _visible = false;
  bool _listening = false;

  /// `true` quando o ícone está presente na barra de menus.
  bool get isVisible => _visible;

  /// Liga a tray conforme a preferência salva.
  Future<void> init() => setVisible(enabled: _settings.showInMenuBar);

  /// Mostra ou remove o ícone ao vivo (toggle "Mostrar na barra de menus").
  ///
  /// Idempotente: ligar quando já visível (ou desligar quando já ausente) é
  /// no-op. A barra é opcional — sem o plugin (testes) ou se o sistema recusar
  /// o ícone, o app segue sem a tray.
  Future<void> setVisible({required bool enabled}) async {
    if (enabled == _visible) return;
    try {
      if (enabled) {
        if (!_listening) {
          _host.addListener(this);
          _listening = true;
        }
        // Ícone template (mono): o macOS ajusta a cor ao tema da barra.
        await _host.setIcon('assets/brand/tray_icon.png', isTemplate: true);
        await _host.setToolTip('RbNotes');
        _visible = true;
        await _rebuildMenu(recording.state);
        _sub ??= recording.stream.listen(_rebuildMenu);
      } else {
        await _sub?.cancel();
        _sub = null;
        await _host.destroy();
        _visible = false;
      }
    } on Object catch (e) {
      AppLogger.warning('tray setVisible failed', category: 'tray', error: e);
    }
  }

  Future<void> _rebuildMenu(RecordingState state) async {
    if (!_visible) return;
    final recordingNow = state.isActive;
    final menu = Menu(
      items: [
        MenuItem(
          key: 'toggle',
          label: recordingNow ? 'Parar gravação' : 'Gravar',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'status',
          disabled: true,
          label: recordingNow ? 'Gravando…' : 'Ocioso',
        ),
        MenuItem.separator(),
        MenuItem(key: 'open', label: 'Abrir RbNotes'),
      ],
    );
    await _host.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() => unawaited(_host.popUpContextMenu());

  @override
  void onTrayIconRightMouseDown() => unawaited(_host.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        unawaited(recording.isActive ? recording.stop() : recording.start());
      case 'open':
        unawaited(onOpen());
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
    if (_listening) {
      _host.removeListener(this);
      // Sem o plugin (testes) ou se a barra nunca apareceu, destroy pode
      // falhar; engolimos para não virar um erro assíncrono não tratado.
      unawaited(_host.destroy().catchError((Object _) {}));
    }
  }
}

extension on RecordingCubit {
  bool get isActive => state.isActive;
}
