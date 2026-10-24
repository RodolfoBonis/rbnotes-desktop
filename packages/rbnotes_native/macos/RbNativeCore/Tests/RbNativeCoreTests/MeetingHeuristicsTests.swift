import XCTest

@testable import RbNativeCore

final class MeetingHeuristicsTests: XCTestCase {
  func testClassifiesDedicatedConferencingApps() {
    XCTAssertEqual(
      MeetingHeuristics.classify(bundleId: "us.zoom.xos"),
      .conferencing(app: "zoom.us"))
    XCTAssertEqual(
      MeetingHeuristics.classify(bundleId: "com.microsoft.teams2"),
      .conferencing(app: "Microsoft Teams"))
    XCTAssertEqual(
      MeetingHeuristics.classify(bundleId: "com.apple.FaceTime"),
      .conferencing(app: "FaceTime"))
  }

  func testClassifiesBrowsers() {
    XCTAssertEqual(
      MeetingHeuristics.classify(bundleId: "com.google.Chrome"),
      .browser(app: "Google Chrome"))
    XCTAssertEqual(
      MeetingHeuristics.classify(bundleId: "company.thebrowser.Browser"),
      .browser(app: "Arc"))
  }

  func testUnknownAndNilAreOther() {
    XCTAssertEqual(MeetingHeuristics.classify(bundleId: "com.apple.Notes"), .other)
    XCTAssertEqual(MeetingHeuristics.classify(bundleId: nil), .other)
  }

  func testTitleHeuristic() {
    XCTAssertTrue(
      MeetingHeuristics.titleLooksLikeMeeting("Meet - abc-defg-hij - Google Chrome"))
    XCTAssertTrue(MeetingHeuristics.titleLooksLikeMeeting("Zoom Meeting"))
    XCTAssertFalse(MeetingHeuristics.titleLooksLikeMeeting("Inbox (3) - Gmail"))
    XCTAssertFalse(MeetingHeuristics.titleLooksLikeMeeting(nil))
    XCTAssertFalse(MeetingHeuristics.titleLooksLikeMeeting(""))
  }

  func testMeetingAppDecision() {
    // Dedicated app: always a meeting, regardless of title.
    XCTAssertEqual(
      MeetingHeuristics.meetingApp(for: .conferencing(app: "zoom.us"), browserTitle: nil),
      "zoom.us")
    // Browser with a meeting title: counts.
    XCTAssertEqual(
      MeetingHeuristics.meetingApp(
        for: .browser(app: "Google Chrome"),
        browserTitle: "Meet – standup – Google Chrome"),
      "Google Chrome")
    // Browser without a meeting title: does not count.
    XCTAssertNil(
      MeetingHeuristics.meetingApp(
        for: .browser(app: "Safari"), browserTitle: "Hacker News"))
    // Non-meeting app: never counts.
    XCTAssertNil(MeetingHeuristics.meetingApp(for: .other, browserTitle: nil))
  }
}
