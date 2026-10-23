import Foundation
import XCTest

@testable import RbNativeCore

final class LiveTranscriptAccumulatorTests: XCTestCase {
  func testFirstChunkIsKeptVerbatim() {
    var acc = LiveTranscriptAccumulator()
    acc.append("olá mundo")
    XCTAssertEqual(acc.text, "olá mundo")
  }

  func testOverlapIsDeduplicated() {
    var acc = LiveTranscriptAccumulator()
    acc.append("o rato roeu a")
    // Next window overlaps on "roeu a" and adds "roupa do rei".
    acc.append("roeu a roupa do rei")
    XCTAssertEqual(acc.text, "o rato roeu a roupa do rei")
  }

  func testOverlapMatchesIgnoringCaseAndPunctuation() {
    var acc = LiveTranscriptAccumulator()
    acc.append("bom dia, pessoal")
    acc.append("Pessoal! vamos começar")
    XCTAssertEqual(acc.text, "bom dia, pessoal Pessoal! vamos começar".replacingOccurrences(
      of: "pessoal Pessoal!", with: "pessoal"))
    // Spelled out explicitly for clarity:
    XCTAssertEqual(acc.text, "bom dia, pessoal vamos começar")
  }

  func testNoOverlapAppendsEverything() {
    var acc = LiveTranscriptAccumulator()
    acc.append("primeira parte")
    acc.append("conteúdo totalmente novo")
    XCTAssertEqual(acc.text, "primeira parte conteúdo totalmente novo")
  }

  func testFullyRepeatedChunkAddsNothing() {
    var acc = LiveTranscriptAccumulator()
    acc.append("mesma frase aqui")
    acc.append("mesma frase aqui")
    XCTAssertEqual(acc.text, "mesma frase aqui")
  }

  func testEmptyChunkIsIgnored() {
    var acc = LiveTranscriptAccumulator()
    acc.append("texto")
    acc.append("   ")
    XCTAssertEqual(acc.text, "texto")
  }

  func testOverlapLengthPrefersLongestMatch() {
    // tail ends with "a b c"; head starts with "b c" and also "a b c".
    let tail = ["x", "a", "b", "c"]
    let head = ["a", "b", "c", "d"]
    XCTAssertEqual(
      LiveTranscriptAccumulator.overlapLength(tail: tail, head: head, maxWindow: 40), 3)
  }
}
