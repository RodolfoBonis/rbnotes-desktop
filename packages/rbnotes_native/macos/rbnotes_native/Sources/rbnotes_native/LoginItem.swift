import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` to implement the "open at login" setting
/// (Phase 3, option F). Registration can require the user to approve the item
/// in System Settings → General → Login Items; in that case `isEnabled` stays
/// false until they do, and `setEnabled(true)` throws `login_item_failed` with
/// a message that tells the app to ask the user to approve it.
enum LoginItem {
  /// Whether RbNotes is currently registered and enabled as a login item.
  static func isEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Registers (enabled == true) or unregisters RbNotes as a login item.
  /// Throws `RbNativeError.loginItemFailed` on failure or when approval is
  /// still pending.
  static func setEnabled(_ enabled: Bool) throws {
    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status == .enabled { return }
        try service.register()
        // After register, macOS may hold the item for the user to approve.
        if service.status == .requiresApproval {
          throw RbNativeError.loginItemFailed(
            "O macOS pediu aprovação em Ajustes → Geral → Itens de login para "
              + "abrir o RbNotes ao iniciar sessão.")
        }
      } else {
        if service.status == .notRegistered || service.status == .notFound { return }
        try service.unregister()
      }
      RbLog.loginItem.info(
        "login item set to \(enabled ? "enabled" : "disabled", privacy: .public)")
    } catch let error as RbNativeError {
      throw error
    } catch {
      RbLog.loginItem.error("login item change failed: \(error.localizedDescription)")
      throw RbNativeError.loginItemFailed(error.localizedDescription)
    }
  }
}
