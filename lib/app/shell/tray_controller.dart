import 'dart:async';

import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:tray_manager/tray_manager.dart';

/// Ícone da menu bar: Gravar/Parar, status e "Abrir RbNotes".
///
/// O menu é reconstruído quando o estado de gravação muda.
class TrayController with TrayListener {
  TrayController({required this.recording, required this.onOpen});

  final RecordingCubit recording;
  final Future<void> Function() onOpen;

  StreamSubscription<RecordingState>? _sub;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/brand/app_icon_1024.png');
    await trayManager.setToolTip('RbNotes');
    await _rebuildMenu(recording.state);
    _sub = recording.stream.listen(_rebuildMenu);
  }

  Future<void> _rebuildMenu(RecordingState state) async {
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
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

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
    trayManager.removeListener(this);
    unawaited(trayManager.destroy());
  }
}

extension on RecordingCubit {
  bool get isActive => state.isActive;
}
