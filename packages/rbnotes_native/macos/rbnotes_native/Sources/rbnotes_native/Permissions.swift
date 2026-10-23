import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Handles querying and requesting the three permissions RbNotes needs.
///
/// - microphone: `AVCaptureDevice` authorization (system prompt on request).
/// - screenRecording: `CGPreflightScreenCaptureAccess` /
///   `CGRequestScreenCaptureAccess` (opens Settings on first request).
/// - accessibility: `AXIsProcessTrustedWithOptions` with the prompt option.
enum Permission: String {
  case microphone
  case screenRecording
  case accessibility
}

/// Wire status matching the Dart `PermissionStatus` enum.
enum PermissionStatusValue: String {
  case granted
  case denied
  case notDetermined
}

enum Permissions {
  static func status(_ permission: Permission) -> PermissionStatusValue {
    switch permission {
    case .microphone:
      return microphoneStatus()
    case .screenRecording:
      return CGPreflightScreenCaptureAccess() ? .granted : .denied
    case .accessibility:
      return AXIsProcessTrusted() ? .granted : .denied
    }
  }

  /// Requests the permission. For microphone this awaits the system prompt;
  /// for screen recording / accessibility it triggers the system prompt that
  /// deep-links to Settings and returns the status observable at call time
  /// (the user grants asynchronously in Settings).
  static func request(
    _ permission: Permission,
    completion: @escaping (PermissionStatusValue) -> Void
  ) {
    switch permission {
    case .microphone:
      let current = AVCaptureDevice.authorizationStatus(for: .audio)
      if current == .notDetermined {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          completion(granted ? .granted : .denied)
        }
      } else {
        completion(microphoneStatus())
      }

    case .screenRecording:
      // Returns immediately; shows the prompt / Settings deep-link if needed.
      let granted = CGRequestScreenCaptureAccess()
      RbLog.permissions.info("screen recording request → granted=\(granted)")
      completion(granted ? .granted : .denied)

    case .accessibility:
      let options: NSDictionary = [
        kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
      ]
      let trusted = AXIsProcessTrustedWithOptions(options)
      RbLog.permissions.info("accessibility request → trusted=\(trusted)")
      completion(trusted ? .granted : .denied)
    }
  }

  private static func microphoneStatus() -> PermissionStatusValue {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return .granted
    case .notDetermined: return .notDetermined
    case .denied, .restricted: return .denied
    @unknown default: return .denied
    }
  }
}
