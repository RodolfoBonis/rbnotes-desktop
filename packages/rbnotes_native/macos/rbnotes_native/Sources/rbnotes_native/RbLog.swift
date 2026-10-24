import Foundation
import os

/// Centralized `os.Logger` instances for the plugin. Subsystem matches the
/// bundle id convention `br.com.rodolfodebonis.rbnotes` so logs can be
/// filtered in Console.app and `log stream`.
enum RbLog {
  static let subsystem = "br.com.rodolfodebonis.rbnotes"

  static let permissions = Logger(subsystem: subsystem, category: "permissions")
  static let recording = Logger(subsystem: subsystem, category: "recording")
  static let systemAudio = Logger(subsystem: subsystem, category: "system-audio")
  static let whisper = Logger(subsystem: subsystem, category: "whisper")
  static let dictation = Logger(subsystem: subsystem, category: "dictation")
  static let plugin = Logger(subsystem: subsystem, category: "plugin")
  static let lock = Logger(subsystem: subsystem, category: "lock")
  static let meeting = Logger(subsystem: subsystem, category: "meeting")
  static let diarization = Logger(subsystem: subsystem, category: "diarization")
  static let loginItem = Logger(subsystem: subsystem, category: "login-item")
}
