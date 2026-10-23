import FlutterMacOS
import Foundation

/// Generic `FlutterStreamHandler` backed by closures, so the plugin can wire
/// each EventChannel inline.
final class ClosureStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenCb: (Any?, @escaping FlutterEventSink) -> FlutterError?
  private let onCancelCb: (Any?) -> FlutterError?

  init(
    onListen: @escaping (Any?, @escaping FlutterEventSink) -> FlutterError?,
    onCancel: @escaping (Any?) -> FlutterError?
  ) {
    self.onListenCb = onListen
    self.onCancelCb = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    onListenCb(arguments, events)
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelCb(arguments)
  }
}

/// Dispatches an event sink call onto the main thread (Flutter requires sinks
/// to be invoked on the platform thread).
func emit(_ sink: @escaping FlutterEventSink, _ value: Any?) {
  if Thread.isMainThread {
    sink(value)
  } else {
    DispatchQueue.main.async { sink(value) }
  }
}
