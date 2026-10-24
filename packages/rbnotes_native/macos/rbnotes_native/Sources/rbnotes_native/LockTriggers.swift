import AppKit
import Foundation

/// Observes the system events that should make the app lock itself (Phase 3,
/// Touch ID): the screen being locked, the screen saver starting and the
/// display/machine going to sleep. Emits a wire trigger name on `onTrigger`,
/// debounced so a burst of related notifications (e.g. screen-lock + display
/// sleep) only fires once per short window.
///
/// Screen lock / screen saver come from `DistributedNotificationCenter`
/// (`com.apple.screenIsLocked` / `com.apple.screensaver.didstart`); sleep comes
/// from `NSWorkspace` (`screensDidSleepNotification` / `willSleepNotification`).
final class LockTriggerManager {
  /// Called on the main thread with a wire trigger name
  /// (`screenLocked`/`systemSleep`/`screensaver`).
  var onTrigger: ((String) -> Void)?

  private var observers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private let debounceInterval: TimeInterval
  private var lastFired: [String: Date] = [:]

  init(debounceInterval: TimeInterval = 1.0) {
    self.debounceInterval = debounceInterval
  }

  /// Starts observing. Safe to call once; a second call is a no-op.
  func start() {
    guard observers.isEmpty, distributedObservers.isEmpty else { return }

    let dnc = DistributedNotificationCenter.default()
    distributedObservers.append(
      dnc.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
      ) { [weak self] _ in self?.fire("screenLocked") })
    distributedObservers.append(
      dnc.addObserver(
        forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main
      ) { [weak self] _ in self?.fire("screensaver") })

    let wsnc = NSWorkspace.shared.notificationCenter
    observers.append(
      wsnc.addObserver(
        forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.fire("systemSleep") })
    observers.append(
      wsnc.addObserver(
        forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.fire("systemSleep") })

    RbLog.lock.info("lock triggers observing")
  }

  func stop() {
    let dnc = DistributedNotificationCenter.default()
    distributedObservers.forEach { dnc.removeObserver($0) }
    distributedObservers.removeAll()
    let wsnc = NSWorkspace.shared.notificationCenter
    observers.forEach { wsnc.removeObserver($0) }
    observers.removeAll()
  }

  deinit { stop() }

  private func fire(_ name: String) {
    let now = Date()
    if let last = lastFired[name], now.timeIntervalSince(last) < debounceInterval {
      return
    }
    lastFired[name] = now
    RbLog.lock.info("lock trigger: \(name, privacy: .public)")
    onTrigger?(name)
  }
}
