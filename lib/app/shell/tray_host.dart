import 'package:tray_manager/tray_manager.dart';

/// Seam fino sobre o `tray_manager` para o `TrayController` ser testável sem o
/// canal de plataforma. A implementação real delega ao `trayManager`; os testes
/// injetam um fake que registra as chamadas.
abstract class TrayHost {
  void addListener(TrayListener listener);
  void removeListener(TrayListener listener);
  Future<void> setIcon(String path, {bool isTemplate = false});
  Future<void> setToolTip(String tooltip);
  Future<void> setContextMenu(Menu menu);
  Future<void> popUpContextMenu();
  Future<void> destroy();
}

/// Implementação de produção: delega ao singleton `trayManager`.
class RealTrayHost implements TrayHost {
  const RealTrayHost();

  @override
  void addListener(TrayListener listener) => trayManager.addListener(listener);

  @override
  void removeListener(TrayListener listener) =>
      trayManager.removeListener(listener);

  @override
  Future<void> setIcon(String path, {bool isTemplate = false}) =>
      trayManager.setIcon(path, isTemplate: isTemplate);

  @override
  Future<void> setToolTip(String tooltip) => trayManager.setToolTip(tooltip);

  @override
  Future<void> setContextMenu(Menu menu) => trayManager.setContextMenu(menu);

  @override
  Future<void> popUpContextMenu() => trayManager.popUpContextMenu();

  @override
  Future<void> destroy() => trayManager.destroy();
}
