import Foundation
import XCTest

@testable import RbNativeCore

final class OverlayStateMachineTests: XCTestCase {
  func testApplyOnlyChangesProvidedFields() {
    let start = OverlayState(
      mode: .recording, phase: .live, liveText: "olá", message: "keep me")
    let next = OverlayLogic.apply(
      OverlayUpdate(liveText: "olá mundo"), to: start)
    XCTAssertEqual(next.liveText, "olá mundo")
    // Untouched fields are preserved.
    XCTAssertEqual(next.phase, .live)
    XCTAssertEqual(next.message, "keep me")
    XCTAssertEqual(next.mode, .recording)
  }

  func testApplyClampsLevelsAndProgress() {
    let start = OverlayState(mode: .recording)
    let next = OverlayLogic.apply(
      OverlayUpdate(micLevel: 2.0, systemLevel: -0.5, progress: 1.7),
      to: start)
    XCTAssertEqual(next.micLevel, 1.0, accuracy: 0.0001)
    XCTAssertEqual(next.systemLevel, 0.0, accuracy: 0.0001)
    XCTAssertEqual(next.progress, 1.0, accuracy: 0.0001)
  }

  func testClampToleratesNaN() {
    XCTAssertEqual(OverlayLogic.clamp01(.nan), 0)
  }

  func testPhaseTransitionLiveToProcessingToDone() {
    var s = OverlayState(mode: .recording, phase: .live)
    s = OverlayLogic.apply(
      OverlayUpdate(phase: .processing, progress: 0.3, message: "Transcrevendo"),
      to: s)
    XCTAssertEqual(s.phase, .processing)
    XCTAssertEqual(s.message, "Transcrevendo")
    s = OverlayLogic.apply(
      OverlayUpdate(phase: .done, message: "Reunião salva"), to: s)
    XCTAssertEqual(s.phase, .done)
    XCTAssertEqual(s.message, "Reunião salva")
  }

  func testPausedToggle() {
    var s = OverlayState(mode: .recording)
    XCTAssertFalse(s.paused)
    s = OverlayLogic.apply(OverlayUpdate(paused: true), to: s)
    XCTAssertTrue(s.paused)
    s = OverlayLogic.apply(OverlayUpdate(paused: false), to: s)
    XCTAssertFalse(s.paused)
  }

  func testAutoHideOnlyForDone() {
    XCTAssertEqual(OverlayLogic.autoHideDelay(phase: .done), 1.5)
    XCTAssertNil(OverlayLogic.autoHideDelay(phase: .live))
    XCTAssertNil(OverlayLogic.autoHideDelay(phase: .processing))
    // Errors persist so the user can read them.
    XCTAssertNil(OverlayLogic.autoHideDelay(phase: .error))
  }

  func testInitialExpandedWindowIsTwoSeconds() {
    XCTAssertEqual(OverlayLogic.initialExpandedWindow, 2.0, accuracy: 0.0001)
  }

  func testWireRawValuesMatchContract() {
    XCTAssertEqual(OverlayMode.recording.rawValue, "recording")
    XCTAssertEqual(OverlayMode.dictation.rawValue, "dictation")
    XCTAssertEqual(OverlayPhase.live.rawValue, "live")
    XCTAssertEqual(OverlayPhase.processing.rawValue, "processing")
    XCTAssertEqual(OverlayPhase.done.rawValue, "done")
    XCTAssertEqual(OverlayPhase.error.rawValue, "error")
  }
}
