import Foundation

/// Pure classification of the frontmost/running app into a meeting app name,
/// used by meeting detection (`RbNative.meetingSignals`). Foundation-only so it
/// is unit-tested via `RbNativeCore`; the live CoreAudio/NSWorkspace plumbing
/// lives in the (untestable) `MeetingDetector`.
public enum MeetingHeuristics {
  /// Dedicated conferencing apps, keyed by bundle identifier → display name.
  /// The display name matches the contract wire values.
  public static let conferencingApps: [String: String] = [
    "us.zoom.xos": "zoom.us",
    "com.microsoft.teams": "Microsoft Teams",
    "com.microsoft.teams2": "Microsoft Teams",
    "com.cisco.webexmeetingsapp": "Webex",
    "com.webex.meetingmanager": "Webex",
    "com.apple.FaceTime": "FaceTime",
    "com.tinyspeck.slackmacgap": "Slack",
  ]

  /// Browsers that can host a meeting in a tab (Meet, Zoom web, Teams web).
  public static let browsers: [String: String] = [
    "com.google.Chrome": "Google Chrome",
    "com.apple.Safari": "Safari",
    "company.thebrowser.Browser": "Arc",
    "com.microsoft.edgemac": "Microsoft Edge",
    "org.mozilla.firefox": "Firefox",
  ]

  /// Substrings in a browser tab/window title that indicate a live meeting.
  public static let meetingTitleHints: [String] = [
    "meet.google.com", "google meet", "meet - ", "meet – ", "zoom",
    "microsoft teams", "teams meeting", "webex", "whereby", "jitsi", "huddle",
    "meeting", "meet.",
  ]

  public enum Kind: Equatable {
    /// A dedicated conferencing app is in focus — a meeting is very likely.
    case conferencing(app: String)
    /// A browser is in focus; only a meeting if the tab title matches.
    case browser(app: String)
    /// Not a meeting app.
    case other
  }

  /// Classifies an app by its bundle identifier.
  public static func classify(bundleId: String?) -> Kind {
    guard let bundleId else { return .other }
    if let app = conferencingApps[bundleId] { return .conferencing(app: app) }
    if let app = browsers[bundleId] { return .browser(app: app) }
    return .other
  }

  /// Whether a browser window title looks like a live meeting (case-insensitive).
  public static func titleLooksLikeMeeting(_ title: String?) -> Bool {
    guard let title = title?.lowercased(), !title.isEmpty else { return false }
    return meetingTitleHints.contains { title.contains($0) }
  }

  /// Decides whether a meeting is in progress given the foreground app's
  /// classification and (for browsers) its window title. A dedicated app
  /// always counts; a browser counts only when its title matches. Returns the
  /// app name to report, or nil when it is not a meeting.
  public static func meetingApp(for kind: Kind, browserTitle: String?) -> String? {
    switch kind {
    case .conferencing(let app):
      return app
    case .browser(let app):
      return titleLooksLikeMeeting(browserTitle) ? app : nil
    case .other:
      return nil
    }
  }
}
